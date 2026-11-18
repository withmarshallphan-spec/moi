import AppKit
import CoreLocation
import ImageIO
import Photos
import Vision

/// Finds photos by what's in them (on-device Vision), where they were taken, and when.
/// Photos library results can become an album (photos themselves are never changed);
/// files in folders can be moved into a folder, with Put back.
@MainActor
final class PhotoFinder: ObservableObject {
    static let shared = PhotoFinder()
    enum Source: Hashable { case asset(String), file(URL) }
    struct Hit: Identifiable, Hashable { var id: Source; var date: Date? }

    /// One result group per thing asked for ("flowers and my trips" → Flower, Italy · Mar 2025, …).
    struct Group: Identifiable { var id = UUID(); var title: String; var hits: [Hit] }
    /// Something that could be a photo, read once per search: where it is, when and where it was taken.
    private struct Item { var id: Source; var key: String; var date: Date?; var location: CLLocation?; var width: Int; var height: Int }
    struct WallpaperPick: Identifiable { var hit: Hit; var score: Double; var reason: String; var id: Source { hit.id } }
    @Published private(set) var wallpaperPicks: [WallpaperPick] = []
    private var oldWallpaper: [NSScreen: URL] = [:]
    @Published private(set) var canRestoreWallpaper = false
    /// The pick that's on the desktop right now.
    @Published private(set) var applied: Source?

    @Published private(set) var request = ""
    @Published private(set) var groups: [Group] = []
    var hits: [Hit] { groups.flatMap(\.hits) }
    @Published private(set) var progress: String?
    @Published var message = ""
    @Published var error: String?
    @Published var chosen = Set<Source>()
    private var job: Task<Void, Never>?
    private var generation = UUID()
    private var assets: [String: PHAsset] = [:]
    /// What Vision saw in each photo (labels only), so a second search is instant. Kept on this Mac.
    private var labels: [String: [String]]
    private let cacheURL = MoiPaths.root.appendingPathComponent("photo-labels.json")
    private var countryCache: [String: String] = [:]

    private init() { labels = (try? LocalStorage.load([String: [String]].self, from: cacheURL, default: [:])) ?? [:] }

    static var folders: [URL] {
        if let dirs = ProcessInfo.processInfo.environment["MOI_PHOTO_DIRS"] { return dirs.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) } } // development: synthetic folders only
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Pictures", "Desktop", "Downloads"].map { home.appendingPathComponent($0, isDirectory: true) }
    }

    func cancel() { generation = UUID(); job?.cancel(); job = nil; progress = nil }

    /// Finds everything asked for, as one group each. `then` runs once the results are in.
    func search(_ text: String, then: ((PhotoFinder) -> Void)? = nil) {
        cancel()
        let queries = PhotoQuery.parseAll(text)
        request = text; groups = []; wallpaperPicks = []; chosen = []; error = nil; message = ""
        guard !queries.isEmpty else { error = "Tell me what to look for, like “flowers”, “my trips”, “trip in Italy” or “2019”."; return }
        let requestID = generation
        job = Task {
            defer { if generation == requestID { progress = nil } }
            do {
                let items = try await collect()
                var found: [Group] = []
                for q in queries {
                    if q.trips { let t = try await trips(q, items); found += t.isEmpty ? [Group(title: q.title, hits: [])] : t }
                    else { found.append(Group(title: q.title, hits: try await matching(q, items, region: try await placeRegion(q.place)))) }
                }
                try Task.checkCancellation()
                guard generation == requestID else { return }
                try? LocalStorage.save(labels, to: cacheURL)
                groups = found.filter { !$0.hits.isEmpty }
                chosen = Set(hits.map(\.id))
                if MoiPaths.isDevelopment, ProcessInfo.processInfo.environment["MOI_PHOTO_DIRS"] != nil {
                    for g in found { NSLog("PHOTOS %@ → %@", g.title, g.hits.compactMap { if case let .file(u) = $0.id { return u.lastPathComponent } else { return nil } }.joined(separator: ", ")) }
                }
                let missing = found.filter(\.hits.isEmpty).map { $0.title.lowercased() }
                message = groups.isEmpty ? "I couldn't find any \(queries.map { $0.title.lowercased() }.joined(separator: " or ")) photos." + (queries.contains(where: \.trips) ? " Trips need photos with a location, taken at least 100 km from where most of yours are." : "")
                    : "Found \(Set(hits.map(\.id)).count) \(Set(hits.map(\.id)).count == 1 ? "photo" : "photos") in \(groups.count == 1 ? "“\(groups[0].title)”" : "\(groups.count) groups")." + (missing.isEmpty ? "" : " None for \(missing.joined(separator: ", ")).")
                then?(self)
            } catch is CancellationError {
            } catch { if generation == requestID { self.error = error.localizedDescription } }
        }
    }


    /// Native image assessment, not a language model guessing from a filename or a random pick.
    func recommendWallpaper(_ text: String, then: ((PhotoFinder) -> Void)? = nil) {
        cancel(); request = text; groups = []; wallpaperPicks = []; chosen = []; error = nil; message = ""
        let subject = WallpaperJudgment.wantsRecommendation(text) ? WallpaperJudgment.subject(text) : text
        let screen = NSScreen.main.map { CGSize(width: $0.frame.width * $0.backingScaleFactor, height: $0.frame.height * $0.backingScaleFactor) } ?? CGSize(width: 1920, height: 1080)
        let requestID = generation
        job = Task {
            defer { if generation == requestID { progress = nil } }
            do {
                let items = try await collect()
                let wanted: Set<Source>?
                if let subject, !subject.isEmpty {
                    let q = PhotoQuery.parse(subject)
                    wanted = Set(try await matching(q, items, region: try await placeRegion(q.place)).map(\.id))
                } else { wanted = nil }
                // shortcut: assess at most 80 resolution/shape candidates, use an incremental index for larger libraries.
                let candidates = items.filter { wanted?.contains($0.id) ?? true }.sorted {
                    WallpaperJudgment.score(width: $0.width, height: $0.height, screen: screen, aesthetics: nil, utility: false) > WallpaperJudgment.score(width: $1.width, height: $1.height, screen: screen, aesthetics: nil, utility: false)
                }.prefix(80)
                var picks: [WallpaperPick] = []
                for (index, item) in candidates.enumerated() {
                    try Task.checkCancellation(); progress = "Looking at your photos · \(index + 1) of \(candidates.count)"
                    let image: CGImage?
                    switch item.id {
                    case let .asset(id): if let asset = assets[id] { image = await thumbnail(asset, size: 512) } else { image = nil }
                    case let .file(url):
                        image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) }
                    }
                    guard let image else { continue }
                    let assessment = await Task.detached(priority: .utility) { Self.aesthetics(image) }.value
                    try Task.checkCancellation()
                    let score = WallpaperJudgment.score(width: item.width, height: item.height, screen: screen, aesthetics: assessment.score, utility: assessment.utility)
                    // Plain reasons, from the same numbers that ranked it.
                    let ratio = Double(item.width) / Double(max(1, item.height)), screenRatio = Double(screen.width / screen.height)
                    var bits = [assessment.score.map { $0 > 0.3 ? "Beautifully composed" : $0 > 0 ? "Nicely composed" : "Simple composition" } ?? "Good fit"]
                    if abs(ratio - screenRatio) < 0.15 { bits.append("fits your screen") } else if ratio < 1 { bits.append("will be cropped to fit") }
                    if Double(item.width * item.height) >= Double(screen.width * screen.height) * 0.9 { bits.append("sharp at full size") }
                    if assessment.utility { bits.append("looks like a screenshot or document") }
                    let reason = bits.joined(separator: ", ")
                    picks.append(WallpaperPick(hit: Hit(id: item.id, date: item.date), score: score, reason: reason))
                }
                try Task.checkCancellation()
                guard generation == requestID else { return }
                wallpaperPicks = Array(picks.sorted { $0.score > $1.score }.prefix(5))
                message = picks.isEmpty ? "I couldn't find a photo for that. Try something like “flowers” or “beach”." : "My top \(wallpaperPicks.count) of \(picks.count) photos, judged on composition, sharpness and how well they fit your screen."
                then?(self)
            } catch is CancellationError { } catch { if generation == requestID { self.error = error.localizedDescription } }
        }
    }

    nonisolated static func aesthetics(_ image: CGImage) -> (score: Double?, utility: Bool) {
        if #available(macOS 15, *) {
            let request = VNCalculateImageAestheticsScoresRequest()
            if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil, let value = request.results?.first { return (Double(value.overallScore), value.isUtility) }
        }
        return (nil, false)
    }

    func applyWallpaper(_ pick: WallpaperPick) async {
        do {
            // moi carries the photo up and hangs it.
            var before: [NSScreen: URL] = [:]
            try await TidyShow.shared.hang(await preview(of: pick.id)) { before = try await setWallpaper(pick.id) }
            if oldWallpaper.isEmpty { oldWallpaper = before } // switching between picks still goes back to the original
            canRestoreWallpaper = !oldWallpaper.isEmpty; applied = pick.id
            message = "That's your wallpaper now. The photo itself isn't changed."
            Intelligence.shared.record("wallpaper", "Completed", pick.reason)
        }
        catch { self.error = error.localizedDescription }
    }
    /// A screen-sized preview of a photo, for moi to carry.
    private func preview(of source: Source) async -> NSImage? {
        switch source {
        case let .file(url):
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        case let .asset(id):
            guard let asset = assets[id] ?? PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject, let cg = await thumbnail(asset, size: 1800) else { return nil }
            return NSImage(cgImage: cg, size: .zero)
        }
    }

    func restoreWallpaper() {
        let failures = MacControl.restoreWallpaper(oldWallpaper)
        if failures.isEmpty { oldWallpaper = [:]; canRestoreWallpaper = false; applied = nil; message = "Your old wallpaper is back." }
        else { error = "Some wallpapers could not be restored: " + failures.joined(separator: "; ") }
    }

    // MARK: Reading what's there

    private func collect() async throws -> [Item] {
        var items: [Item] = []
        if ProcessInfo.processInfo.environment["MOI_PHOTO_DIRS"] == nil { // development runs never read the real library
            progress = "Opening your Photos library…"
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            if status == .authorized || status == .limited {
                let options = PHFetchOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.fetchLimit = 20_000
                assets = [:]
                PHAsset.fetchAssets(with: .image, options: options).enumerateObjects { asset, _, _ in
                    self.assets[asset.localIdentifier] = asset
                    items.append(Item(id: .asset(asset.localIdentifier), key: "asset:" + asset.localIdentifier, date: asset.creationDate, location: asset.location, width: asset.pixelWidth, height: asset.pixelHeight))
                }
            }
        }
        progress = "Looking through Pictures, Desktop and Downloads…"
        let folders = Self.folders
        let task = Task.detached(priority: .utility) { try Self.fileItems(in: folders) }
        items += try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        return items
    }

    nonisolated private static func fileItems(in folders: [URL]) throws -> [Item] {
        var items: [Item] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey]
        for folder in folders {
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var seen = 0
            while let url = walker.nextObject() as? URL {
                try Task.checkCancellation()
                if walker.level > 3 { walker.skipDescendants(); continue }
                guard ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "webp"].contains(url.pathExtension.lowercased()) else { continue }
                seen += 1; if seen > 4_000 { break }
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
                let meta = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let values = try? url.resourceValues(forKeys: Set(keys))
                let date = (meta[kCGImagePropertyExifDictionary] as? [CFString: Any]).flatMap { ($0[kCGImagePropertyExifDateTimeOriginal] as? String).flatMap(Self.exifDate) } ?? values?.creationDate
                let size = WallpaperJudgment.orientedSize(width: meta[kCGImagePropertyPixelWidth] as? Int ?? 0, height: meta[kCGImagePropertyPixelHeight] as? Int ?? 0, orientation: meta[kCGImagePropertyOrientation] as? Int ?? 1)
                items.append(Item(id: .file(url), key: "file:\(url.path)#\(Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0))", date: date, location: Self.gps(meta), width: size.width, height: size.height))
            }
        }
        return items
    }

    /// What Vision sees in one photo, worked out once and remembered.
    private func labels(for item: Item) async -> [String] {
        if let known = labels[item.key] { return known }
        var image: CGImage?
        switch item.id {
        case let .asset(id): if let asset = assets[id] { image = await thumbnail(asset) }
        case let .file(url):
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 299, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
            }
        }
        guard let image else { return [] }
        let found = await Task.detached { Self.classify(image) }.value
        labels[item.key] = found
        return found
    }

    private func matching(_ q: PhotoQuery, _ items: [Item], region: Region?) async throws -> [Hit] {
        var hits: [Hit] = []
        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            if index % 100 == 0 { progress = "Looking for \(q.title.lowercased())… \(index * 100 / max(1, items.count))%" }
            guard yearOK(q, item.date), await inside(item.location, region) else { continue }
            if !q.subjects.isEmpty { guard matches(q, labels: await labels(for: item)) else { continue } }
            hits.append(Hit(id: item.id, date: item.date))
        }
        return hits.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// Every trip away from home, newest first, each named after where it was ("Italy · Mar 2025").
    private func trips(_ q: PhotoQuery, _ items: [Item]) async throws -> [Group] {
        progress = "Working out your trips from where your photos were taken…"
        let located = items.filter { $0.location != nil && $0.date != nil && yearOK(q, $0.date) }
        let points = located.map { Trips.Point(date: $0.date!, lat: $0.location!.coordinate.latitude, lon: $0.location!.coordinate.longitude) }
        guard let home = Trips.home(points) else { return [] }
        let homeCountry = await country(at: CLLocation(latitude: home.lat, longitude: home.lon))
        var groups: [Group] = []
        for trip in Trips.group(points, home: home).reversed() {
            try Task.checkCancellation()
            var members = trip.map { located[$0] }
            if !q.subjects.isEmpty {
                var kept: [Item] = []
                for item in members where matches(q, labels: await labels(for: item)) { kept.append(item) }
                members = kept
            }
            guard let middle = members[safe: members.count / 2], let first = members.first?.date else { continue }
            let mark = try? await CLGeocoder().reverseGeocodeLocation(middle.location!).first
            let place = mark.flatMap { m in m.isoCountryCode == homeCountry ? [m.locality, m.administrativeArea].compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: ", ") : (m.country ?? m.administrativeArea) }
            let title = [q.subjects.isEmpty ? nil : q.title, place ?? "Trip", first.formatted(.dateTime.month(.abbreviated).year())].compactMap { $0 }.joined(separator: " · ")
            groups.append(Group(title: title, hits: members.map { Hit(id: $0.id, date: $0.date) }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }))
        }
        return groups
    }

    private func country(at location: CLLocation) async -> String {
        (try? await CLGeocoder().reverseGeocodeLocation(location))?.first?.isoCountryCode ?? ""
    }

    // MARK: Matching

    private struct Region { var center: CLLocation; var radius: CLLocationDistance; var country: String? }

    /// "Italy" → Italy's country code and rough extent (asks Apple's geocoder for the place name only).
    private func placeRegion(_ place: String?) async throws -> Region? {
        guard let place else { return nil }
        let marks = try await CLGeocoder().geocodeAddressString(place)
        guard let mark = marks.first, let location = mark.location else { throw MoiError.message("I don't know where “\(place)” is.") }
        let radius = (mark.region as? CLCircularRegion)?.radius ?? 50_000
        let isCountry = mark.locality == nil && mark.administrativeArea == nil
        return Region(center: location, radius: max(radius * 1.3, 20_000), country: isCountry ? mark.isoCountryCode : nil)
    }

    /// Countries are checked properly (borders aren't circles): nearby spots are reverse-geocoded once per ~50 km cell.
    private func inside(_ location: CLLocation?, _ region: Region?) async -> Bool {
        guard let region else { return true }
        guard let location, location.distance(from: region.center) <= region.radius else { return false }
        guard let country = region.country else { return true }
        let cell = String(format: "%.1f,%.1f", (location.coordinate.latitude * 2).rounded() / 2, (location.coordinate.longitude * 2).rounded() / 2)
        if let cached = countryCache[cell] { return cached == country }
        let code = (try? await CLGeocoder().reverseGeocodeLocation(location))?.first?.isoCountryCode ?? ""
        countryCache[cell] = code
        return code == country
    }

    private func matches(_ q: PhotoQuery, labels: [String]) -> Bool { q.subjects.allSatisfy { PhotoQuery.matches(subject: $0, labels: labels) } }
    private func yearOK(_ q: PhotoQuery, _ date: Date?) -> Bool { q.year.map { y in date.map { Calendar.current.component(.year, from: $0) == y } ?? false } ?? true }

    nonisolated private static func classify(_ image: CGImage) -> [String] {
        let request = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).filter { $0.confidence > 0.3 }.prefix(12).map(\.identifier)
    }

    // MARK: Photos library

    func thumbnail(_ asset: PHAsset, size: CGFloat = 299) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat; options.isNetworkAccessAllowed = false; options.isSynchronous = false; options.resizeMode = .fast
            var resumed = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: size, height: size), contentMode: .aspectFit, options: options) { image, _ in
                guard !resumed else { return }; resumed = true
                continuation.resume(returning: image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            }
        }
    }

    /// Makes an album of the chosen library photos in a group. Nothing in the library is changed or deleted.
    func makeAlbum(_ group: Group) async throws -> String {
        let ids = group.hits.compactMap { hit -> String? in if case let .asset(id) = hit.id, chosen.contains(hit.id) { return id } else { return nil } }
        guard !ids.isEmpty else { throw MoiError.message("Pick some photos from your library first.") }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: group.title).addAssets(assets)
        }
        return group.title
    }

    // MARK: Folders

    nonisolated static func exifDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy:MM:dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); return f.date(from: s)
    }

    nonisolated static func gps(_ meta: [CFString: Any]) -> CLLocation? {
        guard let g = meta[kCGImagePropertyGPSDictionary] as? [CFString: Any], var lat = g[kCGImagePropertyGPSLatitude] as? Double, var lon = g[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        if (g[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (g[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        return CLLocation(latitude: lat, longitude: lon)
    }

    /// A move plan for a group's chosen files: into a folder named after it, beside the first one.
    /// Files with the same name from different folders get " 2", " 3"; files already there stay.
    func folderPlan(_ group: Group) -> DesktopTidy.Plan? {
        let files = group.hits.compactMap { hit -> URL? in if case let .file(url) = hit.id, chosen.contains(hit.id) { return url } else { return nil } }.sorted { $0.path < $1.path }
        guard let first = files.first else { return nil }
        let name = group.title.replacingOccurrences(of: " · ", with: " ").replacingOccurrences(of: "/", with: "-")
        let parent = first.deletingLastPathComponent().lastPathComponent == name ? first.deletingLastPathComponent().deletingLastPathComponent() : first.deletingLastPathComponent()
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        var taken = Set<String>(), moves: [DesktopTidy.Move] = []
        for file in files where file.deletingLastPathComponent() != folder {
            let free = FreeName.pick(file.lastPathComponent, taken: taken) { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
            taken.insert(free)
            moves.append(.init(from: file.path, to: folder.appendingPathComponent(free).path))
        }
        return moves.isEmpty ? nil : DesktopTidy.Plan(folder: folder, moves: moves, left: [])
    }

    /// Sets a photo as the wallpaper on every screen. Library photos are copied out first
    /// (into moi's folder); the photo itself isn't changed. Returns the old wallpapers for undo.
    func setWallpaper(_ source: Source) async throws -> [NSScreen: URL] {
        let url: URL
        switch source {
        case let .file(file): url = file
        case let .asset(id):
            guard let asset = assets[id] ?? PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { throw MoiError.message("I couldn't find that photo any more.") }
            let data: Data? = await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions(); options.isNetworkAccessAllowed = true; options.deliveryMode = .highQualityFormat
                PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in continuation.resume(returning: data) }
            }
            guard let data else { throw MoiError.message("Photos didn't hand over that picture.") }
            let folder = MoiPaths.root.appendingPathComponent("Wallpapers", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            url = folder.appendingPathComponent(id.replacingOccurrences(of: "/", with: "-") + ".heic")
            try data.write(to: url, options: .atomic)
        }
        return try MacControl.setWallpaper(url)
    }
}

extension Array { subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil } }
