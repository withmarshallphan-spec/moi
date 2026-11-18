import Foundation

/// Which brains moi tries, in what order, and how long to leave one alone after it fails.
/// Kept free of networking so the rules are tested directly.
enum BrainChain {
    /// Free tiers that work with the person's own key, most capable first.
    static let free = ["gemini", "groq", "openrouter", "nvidia", "mistral"]
    /// Bill the person's account. Only ever used when chosen as the main brain, or with an explicit OK.
    static let paid: Set<String> = ["openai", "anthropic", "deepseek", "xai", "together", "custom"]
    static let local = ["ollama", "lmstudio"]

    /// The main brain first, then free backups, then models on this Mac, then Apple's on-device model.
    /// Brains that are resting (out of quota, refused, unreachable) are skipped until they wake.
    /// "moi" means the person chose no AI at all, so nothing is tried.
    static func order(primary: String, ready: Set<String>, allowPaid: Bool, resting: [String: Date], now: Date) -> [String] {
        guard primary != "moi" else { return [] }
        var seen = Set<String>(), list: [String] = []
        for id in [primary] + free + local + paid.sorted() + ["apple"] where !seen.contains(id) {
            seen.insert(id)
            guard ready.contains(id), id == primary || !paid.contains(id) || allowPaid else { continue }
            if let until = resting[id], until > now { continue }
            list.append(id)
        }
        return list
    }

    /// When to try a brain again after a failure.
    static func rest(status: Int?, retryAfter: Double?, daily: Bool, now: Date) -> Date {
        if status == 401 || status == 403 { return now.addingTimeInterval(86_400) } // a refused key waits for the person
        if daily { return nextPacificMidnight(after: now) }                      // free daily quotas reset at midnight, US Pacific
        if let retryAfter { return now.addingTimeInterval(min(max(retryAfter, 5), 86_400)) }
        switch status {
        case 429?: return now.addingTimeInterval(60)
        case let s? where s >= 500: return now.addingTimeInterval(30)
        default: return now.addingTimeInterval(15)                               // network trouble
        }
    }

    static func nextPacificMidnight(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
    }

    /// Which provider a pasted key belongs to, from its shape. nil = can't tell (ask).
    static func detect(key raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes: [(String, String)] = [("AIza", "gemini"), ("gsk_", "groq"), ("sk-or-", "openrouter"), ("nvapi-", "nvidia"), ("sk-ant-", "anthropic"), ("xai-", "xai"), ("sk-proj-", "openai")]
        return prefixes.first { key.hasPrefix($0.0) }?.1
    }

    /// From a provider's error body: how long it asked us to wait, and whether a daily quota ran out.
    static func readLimit(body: String, retryAfterHeader: String?) -> (retryAfter: Double?, daily: Bool) {
        var retry = retryAfterHeader.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if retry == nil, let r = body.range(of: #""retryDelay"\s*:\s*"(\d+(?:\.\d+)?)s""#, options: .regularExpression) {
            retry = Double(body[r].filter { $0.isNumber || $0 == "." })
        }
        let lower = body.lowercased()
        let daily = lower.contains("perday") || lower.contains("per day") || lower.contains("requests per day") || lower.contains("daily")
        return (retry, daily)
    }
}
