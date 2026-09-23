import Foundation

struct QuotaBucket: Codable {
    let bucketId: String?
    let displayName: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?
    let description: String?
    let disabled: Bool?
}

struct QuotaGroup: Codable {
    let displayName: String?
    let description: String?
    let buckets: [QuotaBucket]?
}

struct QuotaResponseEnvelope: Codable {
    let response: QuotaResponseData?
}

struct QuotaResponseData: Codable {
    let groups: [QuotaGroup]?
    let description: String?
}

struct GeminiQuota {
    var fiveHourPercent: Int = 100
    var weeklyPercent: Int = 100
    var fiveHourResetTime: String = ""
    var weeklyResetTime: String = ""
    var fiveHourDescription: String = ""
    var weeklyDescription: String = ""
    var lastUpdated: Date = Date()
    
    var claudeWeeklyPercent: Int?
    var claudeWeeklyDescription: String?
}

class SelfSignedSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

class QuotaFetcher {
    static let shared = QuotaFetcher()
    
    private var cachedPort: Int?
    private var cachedToken: String?
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        self.session = URLSession(configuration: config, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)
    }
    
    func fetchQuota(completion: @escaping (Result<GeminiQuota, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1. Try cached credentials first
            if let port = self.cachedPort, let token = self.cachedToken {
                if let quota = self.queryPort(port: port, token: token) {
                    DispatchQueue.main.async {
                        completion(.success(quota))
                    }
                    return
                }
            }
            
            // 2. Discover running language servers
            let servers = self.findLanguageServerProcesses()
            if servers.isEmpty {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "QuotaFetcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Antigravity IDE no está en ejecución"])))
                }
                return
            }
            
            for (pid, token) in servers {
                let ports = self.findListeningPorts(pid: pid)
                for port in ports {
                    if let quota = self.queryPort(port: port, token: token) {
                        self.cachedPort = port
                        self.cachedToken = token
                        DispatchQueue.main.async {
                            completion(.success(quota))
                        }
                        return
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "QuotaFetcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo conectar al endpoint de Antigravity"])))
            }
        }
    }
    
    private func queryPort(port: Int, token: String) -> GeminiQuota? {
        guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = "{}".data(using: .utf8)
        
        let semaphore = DispatchSemaphore(value: 0)
        var resultQuota: GeminiQuota?
        
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            guard let data = data, error == nil else { return }
            do {
                let decoded = try JSONDecoder().decode(QuotaResponseEnvelope.self, from: data)
                if let groups = decoded.response?.groups {
                    var quota = GeminiQuota()
                    for group in groups {
                        if group.displayName?.contains("Gemini") == true {
                            for bucket in group.buckets ?? [] {
                                let fraction = bucket.remainingFraction ?? 1.0
                                let percent = Int(round(fraction * 100))
                                if bucket.window == "5h" || bucket.bucketId?.contains("5h") == true {
                                    quota.fiveHourPercent = percent
                                    quota.fiveHourResetTime = bucket.resetTime ?? ""
                                    quota.fiveHourDescription = bucket.description ?? ""
                                } else if bucket.window == "weekly" || bucket.bucketId?.contains("weekly") == true {
                                    quota.weeklyPercent = percent
                                    quota.weeklyResetTime = bucket.resetTime ?? ""
                                    quota.weeklyDescription = bucket.description ?? ""
                                }
                            }
                        } else if group.displayName?.contains("Claude") == true {
                            for bucket in group.buckets ?? [] {
                                if bucket.window == "weekly" || bucket.bucketId?.contains("weekly") == true {
                                    let fraction = bucket.remainingFraction ?? 0.0
                                    quota.claudeWeeklyPercent = Int(round(fraction * 100))
                                    quota.claudeWeeklyDescription = bucket.description
                                }
                            }
                        }
                    }
                    quota.lastUpdated = Date()
                    resultQuota = quota
                }
            } catch {
                // Ignore port parse errors
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2.0)
        return resultQuota
    }
    
    private func findLanguageServerProcesses() -> [(pid: String, token: String)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "language_server_macos_arm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            var results: [(pid: String, token: String)] = []
            for line in output.components(separatedBy: "\n") {
                if line.contains("--csrf_token") {
                    let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                    guard let first = parts.first else { continue }
                    let pid = String(first)
                    
                    if let range = line.range(of: "--csrf_token") {
                        let sub = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                        let token = sub.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespaces) ?? ""
                        if !token.isEmpty {
                            results.append((pid, token))
                        }
                    }
                }
            }
            return results
        } catch {
            return []
        }
    }
    
    private func findListeningPorts(pid: String) -> [Int] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-a", "-p", pid, "-iTCP", "-sTCP:LISTEN", "-P", "-n"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            
            var ports: [Int] = []
            guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
            let nsOutput = output as NSString
            let matches = regex.matches(in: output, range: NSRange(location: 0, length: nsOutput.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let portStr = nsOutput.substring(with: match.range(at: 1))
                    if let p = Int(portStr) {
                        ports.append(p)
                    }
                }
            }
            return ports
        } catch {
            return []
        }
    }
}
