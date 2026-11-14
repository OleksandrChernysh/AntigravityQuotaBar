import Foundation

struct LocalSavingsData {
    let localOutputTokens: Int
    let cloudOutputTokens: Int
    let totalOutputTokens: Int
    let savedPercent: Int
}

final class LocalSavingsManager {
    static let shared = LocalSavingsManager()

    private let enabledKey = "LocalSavingsEnabled"
    private var cachedData: LocalSavingsData?
    private var lastCalculationTime: Date?

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return isOllamaAvailable
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    var isOllamaAvailable: Bool {
        let localLog = ("~/.gemini/antigravity/local_tokens.jsonl" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: localLog) { return true }
        if FileManager.default.fileExists(atPath: "/Applications/Ollama.app") { return true }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/ollama") { return true }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama") { return true }
        return false
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    func currentSavings() -> LocalSavingsData {
        if let cached = cachedData, let lastTime = lastCalculationTime, Date().timeIntervalSince(lastTime) < 15.0 {
            return cached
        }

        let today = todayString()
        var localOut = 0

        // 1. Read local tokens generated today from local_tokens.jsonl
        let localLogPath = ("~/.gemini/antigravity/local_tokens.jsonl" as NSString).expandingTildeInPath
        if let localContent = try? String(contentsOfFile: localLogPath, encoding: .utf8) {
            for line in localContent.split(separator: "\n") {
                if line.contains(today) {
                    if let data = line.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let out = obj["output_tokens"] as? Int {
                        localOut += out
                    }
                }
            }
        }

        // 2. Read cloud tokens used today from transcripts modified in last 24h
        var cloudOut = 0
        let brainPath = ("~/.gemini/antigravity/brain" as NSString).expandingTildeInPath
        let fm = FileManager.default
        if let convs = try? fm.contentsOfDirectory(atPath: brainPath) {
            let cutoff = Date().addingTimeInterval(-86400)
            for conv in convs {
                let transcriptPath = "\(brainPath)/\(conv)/.system_generated/logs/transcript.jsonl"
                if let attrs = try? fm.attributesOfItem(atPath: transcriptPath),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate > cutoff {
                    if let content = try? String(contentsOfFile: transcriptPath, encoding: .utf8) {
                        for line in content.split(separator: "\n") {
                            if line.contains(today) {
                                if let data = line.data(using: .utf8),
                                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let out = obj["output_tokens"] as? Int {
                                    cloudOut += out
                                }
                            }
                        }
                    }
                }
            }
        }

        let total = localOut + cloudOut
        let pct = total > 0 ? Int(round(Double(localOut) / Double(total) * 100.0)) : 0
        let result = LocalSavingsData(
            localOutputTokens: localOut,
            cloudOutputTokens: cloudOut,
            totalOutputTokens: total,
            savedPercent: pct
        )
        self.cachedData = result
        self.lastCalculationTime = Date()
        return result
    }

    /// Formatted badge for menu row (e.g. " (+85% saved)")
    func savingsBadge(for groupDisplayName: String) -> String? {
        guard isEnabled else { return nil }
        let savings = currentSavings()
        guard savings.localOutputTokens > 0 else { return nil }

        let activeKind = ModelTracker.shared.currentKind ?? .gemini
        let thisKind = groupKind(groupDisplayName)
        if thisKind == activeKind || (activeKind == .other && thisKind == .gemini) {
            let pctStr = savings.savedPercent > 0 ? "\(savings.savedPercent)%" : "<1%"
            return " (+\(pctStr) saved)"
        }
        return nil
    }

    /// Detailed tooltip text
    func tooltipText(for groupDisplayName: String) -> String? {
        guard isEnabled else { return nil }
        let savings = currentSavings()
        guard savings.localOutputTokens > 0 else {
            return nil
        }
        let activeKind = ModelTracker.shared.currentKind ?? .gemini
        let thisKind = groupKind(groupDisplayName)
        guard thisKind == activeKind || (activeKind == .other && thisKind == .gemini) else {
            return nil
        }

        let locK = formatK(savings.localOutputTokens)
        let cldK = formatK(savings.cloudOutputTokens)
        let pctStr = savings.savedPercent > 0 ? "\(savings.savedPercent)%" : "<1%"
        return "Ollama saved: \(pctStr) of output tokens today (\(locK) local vs \(cldK) cloud)"
    }

    private func formatK(_ val: Int) -> String {
        if val >= 1_000_000 {
            return String(format: "%.1fM", Double(val) / 1_000_000.0)
        } else if val >= 1_000 {
            return String(format: "%.1fk", Double(val) / 1_000.0)
        }
        return "\(val)"
    }
}
