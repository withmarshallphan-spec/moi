import Foundation

/// Percentages require a matching provider-reported numerator and denominator.
struct BrainQuota: Identifiable, Equatable {
    var id: String
    var label: String
    var limit: Double
    var remaining: Double
    var reset: String?
    var usedFraction: Double { min(1, max(0, (limit - remaining) / limit)) }
    var summary: String { "\(Int((usedFraction * 100).rounded()))% used · \(Int(remaining)) / \(Int(limit)) left" }
    static func read(provider: String, headers: [String: String]) -> [Self] {
        let h = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        return ["requests", "tokens"].compactMap { unit in
            let prefix = "x-ratelimit-"
            guard let rawLimit = h[prefix + "limit-" + unit], let limit = Double(rawLimit), limit.isFinite, limit > 0, limit < Double(Int.max),
                  let rawLeft = h[prefix + "remaining-" + unit], let left = Double(rawLeft), left.isFinite, left >= 0, left <= limit else { return nil }
            let window = provider == "groq" ? (unit == "requests" ? "Requests today" : "Tokens per minute") : unit.capitalized + " · provider window"
            return Self(id: unit, label: window, limit: limit, remaining: left, reset: h[prefix + "reset-" + unit])
        }
    }
}

enum WallpaperJudgment {
    static func orientedSize(width: Int, height: Int, orientation: Int) -> (width: Int, height: Int) {
        (5...8).contains(orientation) ? (height, width) : (width, height)
    }
    static func wantsRecommendation(_ text: String) -> Bool {
        text.range(of: #"\b(best|nicest|beautiful|choose|pick|recommend|favorite|favourite)\b|you think|surprise me"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    /// Ranking words describe how to choose, not objects to find in an image.
    static func subject(_ text: String) -> String? {
        let clean = text.lowercased().replacingOccurrences(of: #"\b(what|you|think|is|the|best|nicest|most|beautiful|image|images|photo|photos|picture|pictures|i|have|my|a|an|one|of|choose|pick|recommend|favorite|favourite|wallpaper|please|for|me)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
    /// An explainable wallpaper fit score; Vision aesthetics is optional on older macOS.
    static func score(width: Int, height: Int, screen: CGSize, aesthetics: Double?, utility: Bool) -> Double {
        guard width > 0, height > 0, screen.width > 0, screen.height > 0 else { return -.infinity }
        let fit = min(Double(width) / Double(height), Double(screen.width / screen.height)) / max(Double(width) / Double(height), Double(screen.width / screen.height))
        let resolution = min(1, (Double(width) * Double(height)) / max(1, Double(screen.width * screen.height)))
        let beauty = aesthetics.map { min(1, max(0, ($0 + 1) / 2)) } ?? 0.5
        return 0.6 * beauty + 0.25 * fit + 0.15 * resolution - (utility ? 0.65 : 0)
    }
}
