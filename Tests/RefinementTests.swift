import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import MoiApp

@main struct RefinementTests {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); count += 1; print("PASS: " + message)
        }
        check(MoiCommand.intent(from: "clean up my home screen") == .cleanUp("screen"), "home screen is the desktop environment")
        check(MoiCommand.intent(from: "clean it up") == .cleanUp("screen"), "a general cleanup starts a desktop review, never a recursive home-folder mutation")
        check(MoiCommand.intent(from: "clean up my home folder") == .cleanUp("home folder"), "explicit home folder retains its meaning")
        check(MoiCommand.intent(from: "sort my downloads") == .cleanUp("downloads"), "existing folder routing retained")
        check(MoiCommand.freeModelCandidates(provider:"groq", available:["openai/gpt-oss-120b","canopylabs/orpheus-v1-english","whisper-large-v3"]) == ["openai/gpt-oss-120b"], "speech models never appear as ready conversation models")
        check(MoiCommand.intent(from: "change my wallpaper to what you think is the best image I have") == .wallpaper("what you think is the best image I have"), "wallpaper request preserves the user's actual ranking request")
        check(MoiCommand.intent(from: "choose my best image for wallpaper") == .wallpaper("best image"), "the guided wallpaper example uses the native planner")
        check(WallpaperJudgment.subject("what you think is the best image I have") == nil, "generic best does not search for a literal favorite")
        check(WallpaperJudgment.subject("my best flower photo") == "flower", "subject constraints remain")
        let rotated = WallpaperJudgment.orientedSize(width:4000,height:3000,orientation:6)
        check(rotated.width == 3000 && rotated.height == 4000, "rotated photo metadata uses the displayed shape")
        let screen = CGSize(width: 1920, height: 1080)
        check(WallpaperJudgment.score(width: 3840, height: 2160, screen: screen, aesthetics: 0, utility: false) > WallpaperJudgment.score(width: 300, height: 500, screen: screen, aesthetics: 0, utility: false), "wallpaper ranking rewards resolution and screen fit")
        check(WallpaperJudgment.score(width: 3840, height: 2160, screen: screen, aesthetics: 0.9, utility: false) > WallpaperJudgment.score(width: 3840, height: 2160, screen: screen, aesthetics: 0.9, utility: true), "utility images are penalized")
        check(WallpaperJudgment.score(width: Int.max, height: Int.max, screen: screen, aesthetics: 0, utility: false).isFinite, "extreme dimensions do not overflow")
        let headers = ["X-RateLimit-Limit-Requests":"1000", "x-ratelimit-remaining-requests":"750", "x-ratelimit-limit-tokens":"100", "x-ratelimit-remaining-tokens":"20"]
        let quotas = BrainQuota.read(provider: "groq", headers: headers)
        let oldLedger = try JSONDecoder().decode(BrainEntry.self, from: Data(#"{"day":"2026-11-18","requests":3,"remaining":{}}"#.utf8))
        check(oldLedger.requests == 3 && oldLedger.quotaHeaders == nil, "existing brain usage records remain readable")
        check(quotas.count == 2 && quotas[0].usedFraction == 0.25 && quotas[0].label == "Requests today" && quotas[1].label == "Tokens per minute", "Groq daily requests and minute tokens have distinct windows")
        check(BrainQuota.read(provider: "other", headers: ["x-ratelimit-remaining-requests":"5"]).isEmpty, "missing denominator never fabricates a percentage")
        for pair in [("0","0"),("100","101"),("nan","10"),("inf","10"),("1e100","10")] {
            check(BrainQuota.read(provider: "other", headers: ["x-ratelimit-limit-requests":pair.0,"x-ratelimit-remaining-requests":pair.1]).isEmpty, "invalid provider limit rejected: " + pair.0)
        }
        let size = NotchLayout.size(.expanded, notch: CGSize(width:185,height:32), parts: [.music,.tasks,.files,.calendar,.weather], showsNow:true, recentHeight:74)
        check(size.width == 600 && size.height <= 244, "all notch widgets remain in a bounded side-by-side layout")
        check(NotchLayout.size(.collapsed, notch: CGSize(width:185,height:32), parts: [.music]) == CGSize(width:185,height:32), "idle notch retains hardware geometry")
        check(Set(SidebarSection.allCases.map { PageGuide(section:$0).seenKey }).count == SidebarSection.allCases.count, "guide progress is separate for every destination")
        check(SidebarSection.allCases.allSatisfy { PageGuide(section:$0).steps.count >= 3 }, "every page has a step-by-step guide")
        check(Set(TidyStore.Tab.allCases.map { PageGuide(section:.clean, mode:$0.rawValue).seenKey }).count == TidyStore.Tab.allCases.count, "cleanup modes each have their own first-visit guide")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("moi-refinement-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let context = CGContext(data:nil,width:800,height:450,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0.15,green:0.45,blue:0.8,alpha:1)); context.fill(CGRect(x:0,y:0,width:800,height:450))
        let image = context.makeImage()!, picture = root.appendingPathComponent("synthetic.png")
        let dest = CGImageDestinationCreateWithURL(picture as CFURL,UTType.png.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(dest,image,nil); precondition(CGImageDestinationFinalize(dest))
        let before = try Data(contentsOf:picture)
        setenv("MOI_DATA_DIR",root.appendingPathComponent("state").path,1)
        setenv("MOI_PHOTO_DIRS",root.path,1);setenv("MOI_TIDY_DESKTOP",root.path,1)
        defer { unsetenv("MOI_PHOTO_DIRS");unsetenv("MOI_TIDY_DESKTOP");unsetenv("MOI_DATA_DIR") }
        let finder = PhotoFinder.shared
        finder.recommendWallpaper("what you think is the best image I have")
        for _ in 0..<150 {
            if !finder.wallpaperPicks.isEmpty || finder.error != nil { break }
            try await Task.sleep(for:.milliseconds(100))
        }
        check(finder.error == nil && finder.wallpaperPicks.count == 1, "real native image recommendation completes on a synthetic folder")
        let actual: URL? = finder.wallpaperPicks.first.flatMap { if case let .file(url) = $0.id { return url } else { return nil } }
        check(actual?.resolvingSymlinksInPath() == picture.resolvingSymlinksInPath(), "recommendation points to its actual source")
        let after = try Data(contentsOf:picture)
        check(after == before, "recommendation does not modify image bytes")
        if #available(macOS 15, *) { check(PhotoFinder.aesthetics(image).score?.isFinite == true, "native Vision aesthetics returns a real score") }
        for name in ["essay.txt","personal.jpg","video.mp4","Screenshot-test.png"] {
            let path = root.appendingPathComponent(name);try Data("synthetic".utf8).write(to:path)
            try FileManager.default.setAttributes([.modificationDate:Date().addingTimeInterval(-3600)],ofItemAtPath:path.path)
        }
        ScreenTidyStore.shared.preview()
        let planned = Set(ScreenTidyStore.shared.plan?.moves.map { URL(fileURLWithPath:$0.from).lastPathComponent } ?? [])
        check(planned == ["essay.txt", "personal.jpg", "video.mp4", "Screenshot-test.png"], "desktop clean-up sorts every loose file, photos included (moved, never changed)")
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        check(!ScreenTidyStore.shared.apps.contains { $0.bundleID == front && ScreenTidyStore.shared.quitting.contains($0.id) }, "the app you're using is never picked to quit")
        check(FileManager.default.fileExists(atPath:root.appendingPathComponent("essay.txt").path), "desktop preview does not move files")
        print("PASS: \(count) refinement assertions")
    }
}
