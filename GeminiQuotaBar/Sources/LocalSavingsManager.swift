import Foundation

struct LocalSavingsData {
    let localOutputTokens: Int
    let freeCloudOutputTokens: Int
    let cloudOutputTokens: Int
    let totalOutputTokens: Int
    let savedPercent: Int
    let activeProviders: Set<String>

    var savedOutputTokens: Int {
        localOutputTokens + freeCloudOutputTokens
    }

    var localPercent: Int {
        totalOutputTokens > 0 ? Int(round(Double(localOutputTokens) / Double(totalOutputTokens) * 100.0)) : 0
    }

    var freeCloudPercent: Int {
        totalOutputTokens > 0 ? Int(round(Double(freeCloudOutputTokens) / Double(totalOutputTokens) * 100.0)) : 0
    }
}

final class LocalSavingsManager {
    static let shared = LocalSavingsManager()

    private let enabledKey = "LocalSavingsEnabled"
    private let cacheLock = NSLock()
    private var cachedData: LocalSavingsData?
    private var lastCalculationTime: Date?

    private let localLogPath = ("~/.gemini/antigravity/local_tokens.jsonl" as NSString).expandingTildeInPath
    private let bridgeScriptPaths = [
        ("~/.gemini/config/plugins-optional/dev-suite/savings-bridge/local_bridge.py" as NSString).expandingTildeInPath,
        ("~/.gemini/config/plugins/dev-suite/savings-bridge/local_bridge.py" as NSString).expandingTildeInPath
    ]

    var isEnabled: Bool {
        get {
            guard isConfigured else { return false }
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    /// True only when savings tracking is actually configured (log file or bridge script exists).
    var isConfigured: Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: localLogPath) { return true }
        return bridgeScriptPaths.contains { fm.fileExists(atPath: $0) }
    }

    /// Providers detected from the savings-bridge script and/or local_tokens.jsonl.
    func configuredProviders() -> [String] {
        var providers: [String] = []
        func add(_ name: String) {
            if !providers.contains(name) { providers.append(name) }
        }

        for path in bridgeScriptPaths {
            if let script = try? String(contentsOfFile: path, encoding: .utf8) {
                if script.contains("query_ollama") || script.contains("OLLAMA_API") { add("Ollama") }
                if script.contains("\"opencode/\"") || script.contains("query_opencode") { add("OpenCode") }
                if script.contains("\"nvidia/\"") || script.contains("query_nvidia_nim") { add("Nvidia") }
                break
            }
        }

        if let log = try? String(contentsOfFile: localLogPath, encoding: .utf8) {
            for line in log.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let model = obj["model"] as? String else { continue }
                if let slash = model.firstIndex(of: "/") {
                    let prefix = String(model[..<slash]).lowercased()
                    switch prefix {
                    case "opencode": add("OpenCode")
                    case "nvidia": add("Nvidia")
                    default:
                        if !prefix.isEmpty { add(prefix.capitalized) }
                    }
                } else if !model.isEmpty {
                    add("Ollama")
                }
            }
        }

        return providers
    }

    private static let todayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()

    private func todayString() -> String {
        Self.todayFormatter.string(from: Date())
    }

    private func isEntryToday(
        _ obj: [String: Any],
        todayPrefix: String,
        iso: ISO8601DateFormatter,
        isoFrac: ISO8601DateFormatter
    ) -> Bool {
        guard let raw = (obj["timestamp"] as? String) ?? (obj["created_at"] as? String) else {
            return false
        }
        if let date = isoFrac.date(from: raw) ?? iso.date(from: raw) {
            return Calendar.current.isDateInToday(date)
        }
        return raw.hasPrefix(todayPrefix)
    }

    func currentSavings() -> LocalSavingsData {
        cacheLock.lock()
        if let cached = cachedData, let lastTime = lastCalculationTime, Date().timeIntervalSince(lastTime) < 15.0 {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let today = todayString()
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var localOut = 0
        var freeCloudOut = 0
        var activeProviders: Set<String> = []

        // 1. Read local & free-cloud tokens generated today from local_tokens.jsonl
        if let localContent = try? String(contentsOfFile: localLogPath, encoding: .utf8) {
            for line in localContent.split(separator: "\n") {
                if let data = line.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   isEntryToday(obj, todayPrefix: today, iso: iso, isoFrac: isoFrac),
                   let rawOut = obj["output_tokens"] as? NSNumber {
                    let out = rawOut.intValue
                    guard out > 0 else { continue }
                    let model = ((obj["model"] as? String) ?? "").lowercased()
                    if model.hasPrefix("opencode/") {
                        freeCloudOut += out
                        activeProviders.insert("OpenCode")
                    } else if model.hasPrefix("nvidia/") {
                        freeCloudOut += out
                        activeProviders.insert("Nvidia")
                    } else {
                        localOut += out
                        activeProviders.insert("Ollama")
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
                            if let data = line.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               isEntryToday(obj, todayPrefix: today, iso: iso, isoFrac: isoFrac),
                               let rawOut = obj["output_tokens"] as? NSNumber {
                                let out = rawOut.intValue
                                if out > 0 {
                                    cloudOut += out
                                }
                            }
                        }
                    }
                }
            }
        }

        let savedOut = localOut + freeCloudOut
        let total = savedOut + cloudOut
        let pct = total > 0 ? Int(round(Double(savedOut) / Double(total) * 100.0)) : 0
        let result = LocalSavingsData(
            localOutputTokens: localOut,
            freeCloudOutputTokens: freeCloudOut,
            cloudOutputTokens: cloudOut,
            totalOutputTokens: total,
            savedPercent: pct,
            activeProviders: activeProviders
        )
        cacheLock.lock()
        self.cachedData = result
        self.lastCalculationTime = Date()
        cacheLock.unlock()
        return result
    }

    /// Compact badge for the top menu bar (e.g. "(+42%)")
    func topMenuBadge() -> String? {
        guard isEnabled else { return nil }
        let savings = currentSavings()
        guard savings.savedOutputTokens > 0 else { return nil }
        let pctStr = savings.savedPercent > 0 ? "\(savings.savedPercent)%" : "<1%"
        return "(+\(pctStr))"
    }

    /// Detailed tooltip text for the Local and Free section
    func summaryTooltip(for savings: LocalSavingsData) -> String {
        guard savings.totalOutputTokens > 0 else {
            return "No output tokens recorded today"
        }
        let locK = formatK(savings.localOutputTokens)
        let freeK = formatK(savings.freeCloudOutputTokens)
        let cldK = formatK(savings.cloudOutputTokens)
        let pctStr = savings.savedPercent > 0 ? "\(savings.savedPercent)%" : (savings.savedOutputTokens > 0 ? "<1%" : "0%")

        var parts: [String] = []
        if savings.localOutputTokens > 0 { parts.append("\(locK) local") }
        if savings.freeCloudOutputTokens > 0 { parts.append("\(freeK) free cloud") }
        let savedDesc = parts.isEmpty ? "0 saved" : parts.joined(separator: " + ")
        return "Saved today: \(pctStr) of output tokens (\(savedDesc) vs \(cldK) paid)"
    }

    func formatK(_ val: Int) -> String {
        if val >= 1_000_000 {
            return String(format: "%.1fM", Double(val) / 1_000_000.0)
        } else if val >= 1_000 {
            return String(format: "%.1fk", Double(val) / 1_000.0)
        }
        return "\(val)"
    }
}
