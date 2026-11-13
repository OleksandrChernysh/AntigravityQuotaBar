import Foundation

struct DiscoveredModelInfo {
    let code: String
    let displayName: String
    let kind: GroupKind
}

/// Tracks the model currently selected in the Antigravity App.
///
/// Discovers model definitions directly from Antigravity's local language server
/// via `GetAvailableModels`, so model codes (like `MODEL_PLACEHOLDER_M404`) are
/// automatically mapped to real names ("Claude Sonnet 5.5") and their respective
/// quota group without any manual mapping by the user.
final class ModelTracker {
    static let shared = ModelTracker()

    var onChange: (() -> Void)?

    private(set) var currentCode: String?
    private(set) var currentDisplayName: String?
    private(set) var currentKind: GroupKind?

    private var discoveredModels: [String: DiscoveredModelInfo] = [:]
    private var lastModified: Date?
    private var timer: Timer?

    private var stateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/antigravity_state.pbtxt")
    }

    func start() {
        refreshModelCatalog()
        check()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    /// Queries `GetAvailableModels` from the running language_server.
    func refreshModelCatalog() {
        QuotaFetcher.shared.fetchQuota { [weak self] _ in
            self?.queryAvailableModels()
        }
    }

    private func queryAvailableModels() {
        // Find credentials from QuotaFetcher-discovered servers
        let servers = QuotaFetcher.shared.findLanguageServerProcesses()
        guard let server = servers.first else { return }

        var candidatePorts: [Int] = []
        if let p = server.port { candidatePorts.append(p) }
        for p in QuotaFetcher.shared.findListeningPorts(pid: server.pid) {
            if !candidatePorts.contains(p) { candidatePorts.append(p) }
        }

        for port in candidatePorts {
            for scheme in ["https", "http"] {
                guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetAvailableModels") else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(server.token, forHTTPHeaderField: "x-codeium-csrf-token")
                request.httpBody = "{}".data(using: .utf8)

                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 2.0
                let session = URLSession(configuration: config, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)

                let sem = DispatchSemaphore(value: 0)
                let task = session.dataTask(with: request) { [weak self] data, _, error in
                    defer { sem.signal() }
                    guard let data = data, error == nil,
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let response = json["response"] as? [String: Any],
                          let models = response["models"] as? [String: Any] else { return }

                    var dict: [String: DiscoveredModelInfo] = [:]
                    for (k, val) in models {
                        guard let info = val as? [String: Any] else { continue }
                        let code = (info["model"] as? String) ?? k
                        let displayName = (info["displayName"] as? String) ?? k
                        let provider = (info["modelProvider"] as? String) ?? ""

                        let kind: GroupKind
                        let lower = displayName.lowercased()
                        if lower.contains("argon") {
                            kind = .argon
                        } else if lower.contains("gemini") {
                            kind = .gemini
                        } else if lower.contains("claude") || lower.contains("gpt") || provider.contains("ANTHROPIC") || provider.contains("OPENAI") {
                            kind = .claudeGPT
                        } else {
                            kind = .other
                        }
                        dict[code] = DiscoveredModelInfo(code: code, displayName: displayName, kind: kind)
                    }

                    DispatchQueue.main.async {
                        self?.discoveredModels = dict
                        self?.resolveCurrentModel()
                    }
                }
                task.resume()
                _ = sem.wait(timeout: .now() + 1.5)
                if !self.discoveredModels.isEmpty { return }
            }
        }
    }

    private func check() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: stateURL.path)
        let modified = attrs?[.modificationDate] as? Date
        guard modified != lastModified || currentCode == nil else { return }
        lastModified = modified

        if let code = readCode(), code != currentCode {
            currentCode = code
            resolveCurrentModel()
            onChange?()
        }
    }

    private func resolveCurrentModel() {
        guard let code = currentCode else { return }
        if let info = discoveredModels[code] {
            currentDisplayName = info.displayName
            currentKind = info.kind
        } else {
            // Fallback for known codes if GetAvailableModels is still loading
            let lower = code.lowercased()
            if lower.contains("argon") {
                currentKind = .argon
            } else if lower.contains("gemini") {
                currentKind = .gemini
            } else if lower.contains("claude") || lower.contains("gpt") {
                currentKind = .claudeGPT
            } else {
                currentKind = nil
            }
            currentDisplayName = nil
        }
    }

    private func readCode() -> String? {
        guard let text = try? String(contentsOf: stateURL, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"last_selected_agent_model:\s*"?([A-Za-z0-9_\-\.]+)"?"#)
        else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
