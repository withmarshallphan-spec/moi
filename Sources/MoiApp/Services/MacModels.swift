import Foundation

/// Pure helpers behind moi's Mac actions, kept free of AppKit so they're tested directly.
enum Web {
    /// "youtube" → https://www.youtube.com, "pornhub.com" → https://pornhub.com, "example.org/a" → https://example.org/a.
    static func url(for target: String) -> URL? {
        var t = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        t = t.replacingOccurrences(of: #"^(?:the\s+)?(?:website|site|page)\s+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+(?:website|site|dot com)$"#, with: "", options: .regularExpression)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("http://") || t.hasPrefix("https://") { return URL(string: t) }
        if t.contains("."), !t.contains(" ") { return URL(string: "https://" + t) }
        let host = t.replacingOccurrences(of: " ", with: "")
        guard host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return URL(string: "https://www.\(host).com")
    }

    static func search(_ query: String) -> URL? {
        var parts = URLComponents(string: "https://www.google.com/search")
        parts?.queryItems = [URLQueryItem(name: "q", value: query)]
        return parts?.url
    }

    /// Command-line flag each browser uses for a private window (Safari has none; moi scripts it).
    static func privateFlag(forBrowser name: String) -> String? {
        switch name.lowercased() {
        case let n where n.contains("chrome") || n.contains("brave") || n.contains("chromium") || n.contains("vivaldi") || n.contains("opera"): "--incognito"
        case let n where n.contains("edge"): "--inprivate"
        case let n where n.contains("firefox"): "--private-window"
        default: nil
        }
    }
}

/// What someone is looking for in their photos: things in them, a place, a year.
struct PhotoQuery: Equatable {
    var subjects: [String] = []
    var place: String?
    var year: Int?
    /// "my trips", "holidays": every trip away from home, found from where and when photos were taken.
    var trips = false
    var title: String {
        if trips && subjects.isEmpty && year == nil { return "Trips" }
        let parts = subjects.map { $0.prefix(1).uppercased() + $0.dropFirst() } + [place.map { $0.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }].compactMap { $0 } + [year.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? "Photos" : parts.joined(separator: " · ")
    }

    /// Scene words are things to look for, not places ("photos at the beach").
    static let scenes: Set<String> = ["beach", "park", "mountain", "mountains", "snow", "forest", "lake", "sea", "ocean", "city", "garden", "sunset", "sunrise", "night", "restaurant", "concert", "wedding", "party", "pool", "desert", "river", "waterfall", "zoo", "museum", "church", "street", "office", "home", "school", "gym"]
    static let filler: Set<String> = ["my", "all", "the", "a", "an", "of", "and", "with", "some", "every", "photos", "photo", "pictures", "picture", "pics", "pic", "images", "image", "shots", "trip", "holiday", "vacation", "from", "in", "at", "to", "on", "that", "i", "took", "me", "our", "into", "album", "folder", "one", "sort", "find", "show", "gather", "collect", "organise", "organize", "group", "put", "make", "search", "look", "for", "get", "them", "together", "can", "you", "please"]

    static func parse(_ text: String) -> PhotoQuery {
        var t = " " + text.lowercased().replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression) + " "
        var q = PhotoQuery()
        if let r = t.range(of: #"\b(19|20)\d\d\b"#, options: .regularExpression) { q.year = Int(t[r]); t.replaceSubrange(r, with: " ") }
        if let r = t.range(of: #"\b(?:trip|holiday|vacation|travels?)?\s*(?:in|to|from|at)\s+([a-z][a-z ]*)$"#, options: .regularExpression) {
            let words = t[r].split(separator: " ").map(String.init).filter { !filler.contains($0) && !["trip", "holiday", "vacation", "travel", "travels"].contains($0) }
            if !words.isEmpty, !words.allSatisfy(scenes.contains) {
                q.place = words.joined(separator: " ")
                t.replaceSubrange(r, with: " ")
            }
        }
        if q.place == nil, let r = t.range(of: #"\b(?:trips?|travels?|travelling|traveling|holidays?|vacations?)\b"#, options: .regularExpression) { q.trips = true; t.replaceSubrange(r, with: " ") }
        q.subjects = t.split(separator: " ").map(String.init).filter { !filler.contains($0) && $0.count > 1 && !["trips", "travels", "holidays", "vacations"].contains($0) }.map { $0.hasSuffix("s") && $0.count > 3 && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0 }
        return q
    }

    /// "flowers and my trips", "dogs, cats" → one search each. Empty pieces are dropped.
    static func parseAll(_ text: String) -> [PhotoQuery] {
        text.lowercased().components(separatedBy: try! NSRegularExpression(pattern: #"\s*(?:,|&|\band also\b|\band\b|\bplus\b)\s*"#)).map(parse).filter { !$0.subjects.isEmpty || $0.place != nil || $0.year != nil || $0.trips }
    }

    /// Vision labels that count as a match for one subject word.
    static let synonyms: [String: [String]] = [
        "flower": ["flower", "rose", "tulip", "daisy", "sunflower", "orchid", "lily", "blossom", "bouquet", "flowerbed", "lavender", "peony", "dandelion", "hibiscus"],
        "dog": ["dog", "puppy", "canine", "retriever", "terrier", "poodle", "bulldog", "spaniel", "shepherd_dog", "husky", "beagle", "corgi"],
        "cat": ["cat", "kitten", "feline", "tabby"],
        "bird": ["bird", "parrot", "owl", "eagle", "penguin", "pigeon", "duck", "swan", "seagull", "songbird", "raptor", "hummingbird", "flamingo"],
        "food": ["food", "meal", "dish", "dessert", "cake", "pizza", "pasta", "burger", "sushi", "salad", "bread", "baked_goods", "fruit", "noodles", "breakfast"],
        "car": ["car", "automobile", "vehicle", "sports_car", "convertible", "suv", "sedan"],
        "baby": ["baby", "infant", "toddler", "child"],
        "people": ["people", "person", "adult", "child", "selfie", "portrait", "crowd"],
        "selfie": ["selfie", "portrait"],
        "screenshot": ["screenshot", "document", "text", "computer_screen"],
        "receipt": ["receipt", "document", "paper", "text"],
        "document": ["document", "paper", "text", "printed_page"],
    ]

    static func matches(subject: String, labels: [String]) -> Bool {
        let wanted = synonyms[subject] ?? [subject]
        return labels.contains { label in wanted.contains { label == $0 || label.hasPrefix($0 + "_") || label.hasSuffix("_" + $0) } }
    }
}

extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        var parts: [String] = [], start = startIndex
        for m in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
            guard let r = Range(m.range, in: self) else { continue }
            parts.append(String(self[start..<r.lowerBound])); start = r.upperBound
        }
        return parts + [String(self[start...])]
    }
}

/// Trips, worked out from where and when photos were taken: "home" is where most of them are,
/// and photos far from it are split into trips wherever a couple of days pass without one.
enum Trips {
    struct Point { var date: Date; var lat: Double; var lon: Double }

    static func km(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let r = Double.pi / 180, dLat = (b.lat - a.lat) * r, dLon = (b.lon - a.lon) * r
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * r) * cos(b.lat * r) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// The ~50 km cell with the most photos, as the average spot in it.
    static func home(_ points: [Point]) -> (lat: Double, lon: Double)? {
        let cells = Dictionary(grouping: points) { "\(Int(($0.lat * 2).rounded())),\(Int(($0.lon * 2).rounded()))" }
        guard let best = cells.values.max(by: { $0.count < $1.count }) else { return nil }
        return (best.map(\.lat).reduce(0, +) / Double(best.count), best.map(\.lon).reduce(0, +) / Double(best.count))
    }

    /// Indices of `points` per trip, oldest trip first.
    static func group(_ points: [Point], home: (lat: Double, lon: Double), minKm: Double = 100, gapDays: Double = 2, minPhotos: Int = 3) -> [[Int]] {
        let away = points.indices.filter { km(home, (points[$0].lat, points[$0].lon)) > minKm }.sorted { points[$0].date < points[$1].date }
        var trips: [[Int]] = []
        for i in away {
            if let last = trips.last?.last, points[i].date.timeIntervalSince(points[last].date) <= gapDays * 86_400 { trips[trips.count - 1].append(i) }
            else { trips.append([i]) }
        }
        return trips.filter { $0.count >= minPhotos }
    }
}

/// A free name in a folder: "front.png" → "front 2.png" when taken (by a file or by `taken`).
enum FreeName {
    static func pick(_ name: String, taken: Set<String>, exists: (String) -> Bool) -> String {
        guard taken.contains(name) || exists(name) else { return name }
        let ext = (name as NSString).pathExtension, base = (name as NSString).deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !taken.contains(candidate) && !exists(candidate) { return candidate }
            n += 1
        }
    }
}

/// The Dock's app list as stored in com.apple.dock "persistent-apps". Edits are made on a copy.
enum DockLayout {
    typealias Item = [String: Any]

    static func label(_ item: Item) -> String { ((item["tile-data"] as? Item)?["file-label"] as? String) ?? "" }
    static func path(_ item: Item) -> String? {
        guard let data = (item["tile-data"] as? Item)?["file-data"] as? Item, let raw = data["_CFURLString"] as? String else { return nil }
        return URL(string: raw)?.path ?? raw
    }

    /// Removes apps whose name matches any of `names` (case-insensitive, whole name or prefix).
    static func removing(_ names: [String], from items: [Item]) -> (items: [Item], removed: [String]) {
        let wanted = names.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var removed: [String] = []
        let kept = items.filter { item in
            let name = label(item).lowercased()
            let hit = wanted.contains { name == $0 || name.hasPrefix($0) }
            if hit { removed.append(label(item)) }
            return !hit
        }
        return (kept, removed)
    }

    static func adding(appAt url: URL, bundleID: String?, to items: [Item]) -> [Item] {
        guard !items.contains(where: { path($0) == url.path }) else { return items }
        var tile: Item = ["file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15], "file-label": url.deletingPathExtension().lastPathComponent, "file-type": 41]
        if let bundleID { tile["bundle-identifier"] = bundleID }
        return items + [["tile-data": tile, "tile-type": "file-tile"]]
    }
}
