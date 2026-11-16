import Foundation

struct QuotaBucket: Decodable {
    let bucketId: String?
    let displayName: String?
    let window: String?
    let remainingFraction: Double?
    let resetTime: String?
    let description: String?
    let disabled: Bool?

    enum CodingKeys: String, CodingKey {
        case bucketId, bucket_id
        case displayName, display_name
        case window
        case remainingFraction, remaining_fraction
        case resetTime, reset_time
        case description
        case disabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bucketId = try container.decodeIfPresent(String.self, forKey: .bucketId) ?? container.decodeIfPresent(String.self, forKey: .bucket_id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? container.decodeIfPresent(String.self, forKey: .display_name)
        window = try container.decodeIfPresent(String.self, forKey: .window)
        
        // remainingFraction can be Double, Float, Int, or String
        if let d = try? container.decodeIfPresent(Double.self, forKey: .remainingFraction) {
            remainingFraction = d
        } else if let d = try? container.decodeIfPresent(Double.self, forKey: .remaining_fraction) {
            remainingFraction = d
        } else if let s = try? container.decodeIfPresent(String.self, forKey: .remainingFraction), let d = Double(s) {
            remainingFraction = d
        } else if let s = try? container.decodeIfPresent(String.self, forKey: .remaining_fraction), let d = Double(s) {
            remainingFraction = d
        } else {
            remainingFraction = nil
        }
        
        resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime) ?? container.decodeIfPresent(String.self, forKey: .reset_time)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
    }
}

struct QuotaGroup: Decodable {
    let displayName: String?
    let description: String?
    let buckets: [QuotaBucket]?

    enum CodingKeys: String, CodingKey {
        case displayName, display_name
        case description
        case buckets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? container.decodeIfPresent(String.self, forKey: .display_name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        buckets = try container.decodeIfPresent([QuotaBucket].self, forKey: .buckets)
    }
}

struct QuotaResponseEnvelope: Decodable {
    let response: QuotaResponseData?
    let groups: [QuotaGroup]?
    
    enum CodingKeys: String, CodingKey {
        case response, groups
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decodeIfPresent(QuotaResponseData.self, forKey: .response)
        groups = try container.decodeIfPresent([QuotaGroup].self, forKey: .groups)
    }
}

struct QuotaResponseData: Decodable {
    let groups: [QuotaGroup]?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case groups, description
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groups = try container.decodeIfPresent([QuotaGroup].self, forKey: .groups)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

struct ModelBucketInfo: Codable {
    let id: String
    let displayName: String
    let window: String
    let percent: Int
    let resetTime: String
    let description: String
}

struct ModelGroupInfo: Codable {
    let displayName: String
    let description: String
    var buckets: [ModelBucketInfo]
}

struct GeminiQuota {
    // Primary Gemini metrics
    var fiveHourPercent: Int = 100
    var weeklyPercent: Int = 100
    var fiveHourResetTime: String = ""
    var weeklyResetTime: String = ""
    var fiveHourDescription: String = ""
    var weeklyDescription: String = ""
    var lastUpdated: Date = Date()
    
    // Claude & GPT metrics
    var claudeFiveHourPercent: Int?
    var claudeWeeklyPercent: Int?
    var claudeWeeklyDescription: String?
    
    // Gemini 4 Argon metrics (New Model!)
    var argonWeeklyPercent: Int?
    var argonDescription: String?
    var argonResetTime: String?

    // All dynamic groups returned by the server
    var allGroups: [ModelGroupInfo] = []
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
    private var cachedScheme: String?
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
                let scheme = self.cachedScheme ?? "http"
                if let quota = self.querySchemePort(scheme: scheme, port: port, token: token) {
                    DispatchQueue.main.async {
                        completion(.success(quota))
                    }
                    return
                }
            }
            
            // 2. Discover running processes
            let servers = self.findLanguageServerProcesses()
            if servers.isEmpty {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "QuotaFetcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Antigravity IDE is not running"])))
                }
                return
            }
            
            for server in servers {
                var candidatePorts: [Int] = []
                if let p = server.port {
                    candidatePorts.append(p)
                }
                
                let lsofPorts = self.findListeningPorts(pid: server.pid)
                for lp in lsofPorts {
                    if !candidatePorts.contains(lp) {
                        candidatePorts.append(lp)
                    }
                }
                
                for port in candidatePorts {
                    for scheme in ["http", "https"] {
                        if let quota = self.querySchemePort(scheme: scheme, port: port, token: server.token) {
                            self.cachedPort = port
                            self.cachedScheme = scheme
                            self.cachedToken = server.token
                            DispatchQueue.main.async {
                                completion(.success(quota))
                            }
                            return
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "QuotaFetcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not connect to the Antigravity endpoint"])))
            }
        }
    }
    
    private func querySchemePort(scheme: String, port: Int, token: String) -> GeminiQuota? {
        let endpoints = [
            "/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary",
            "/exa.language_server_pb.PredictionService/RetrieveUserQuotaSummary"
        ]
        
        for path in endpoints {
            guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)\(path)") else { continue }
            
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
                resultQuota = Self.parseQuota(from: data)
            }
            
            task.resume()
            _ = semaphore.wait(timeout: .now() + 1.5)
            
            if let quota = resultQuota {
                return quota
            }
        }
        
        return nil
    }

    static func parseQuota(from data: Data) -> GeminiQuota? {
        guard let decoded = try? JSONDecoder().decode(QuotaResponseEnvelope.self, from: data),
              let groups = decoded.groups ?? decoded.response?.groups,
              !groups.isEmpty else {
            return nil
        }

        var quota = GeminiQuota()
        var groupInfos: [ModelGroupInfo] = []

        for group in groups {
            guard let gName = group.displayName, !gName.isEmpty else { continue }
            var bucketInfos: [ModelBucketInfo] = []

            for bucket in group.buckets ?? [] {
                let fraction = bucket.remainingFraction ?? 1.0
                let percent = Int(round(fraction * 100))
                let bId = bucket.bucketId ?? ""
                let bWindow = bucket.window ?? ""
                let bReset = bucket.resetTime ?? ""
                let bDesc = bucket.description ?? ""

                var defaultName = "Limit"
                if bWindow == "5h" || bId.contains("5h") || bWindow.contains("session") {
                    defaultName = "5h Limit"
                } else if bWindow == "weekly" || bId.contains("weekly") {
                    defaultName = "Weekly Limit"
                }
                let bDisplayName = (bucket.displayName?.isEmpty == false) ? bucket.displayName! : defaultName

                let bInfo = ModelBucketInfo(
                    id: bId,
                    displayName: bDisplayName,
                    window: bWindow,
                    percent: percent,
                    resetTime: bReset,
                    description: bDesc
                )
                bucketInfos.append(bInfo)

                if gName.contains("Gemini") && !gName.contains("Argon") {
                    if bWindow == "5h" || bId.contains("5h") {
                        quota.fiveHourPercent = percent
                        quota.fiveHourResetTime = bReset
                        quota.fiveHourDescription = bDesc
                    } else if bWindow == "weekly" || bId.contains("weekly") {
                        quota.weeklyPercent = percent
                        quota.weeklyResetTime = bReset
                        quota.weeklyDescription = bDesc
                    }
                } else if gName.contains("Claude") || gName.contains("GPT") {
                    if bWindow == "weekly" || bId.contains("weekly") {
                        quota.claudeWeeklyPercent = percent
                        quota.claudeWeeklyDescription = bDesc
                    } else if bWindow == "5h" || bId.contains("5h") {
                        quota.claudeFiveHourPercent = percent
                    }
                } else if gName.contains("Argon") {
                    quota.argonWeeklyPercent = percent
                    quota.argonDescription = bDesc
                    quota.argonResetTime = bReset
                }
            }

            groupInfos.append(ModelGroupInfo(
                displayName: gName,
                description: group.description ?? "",
                buckets: bucketInfos
            ))
        }

        quota.allGroups = groupInfos
        quota.lastUpdated = Date()
        return quota
    }
    
    func findLanguageServerProcesses() -> [(pid: String, token: String, port: Int?)] {
        var results: [(pid: String, token: String, port: Int?)] = []
        
        // 1. Try pgrep for agy, language_server, or language-server
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-fl", "agy|language_server|language-server"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        var output = ""
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            output = String(data: data, encoding: .utf8) ?? ""
        } catch {}
        
        // 2. Fallback to ps if pgrep gave no lines with tokens
        if !output.contains("csrf") {
            let psTask = Process()
            psTask.executableURL = URL(fileURLWithPath: "/bin/ps")
            psTask.arguments = ["-axo", "pid,command"]
            let psPipe = Pipe()
            psTask.standardOutput = psPipe
            do {
                try psTask.run()
                let data = psPipe.fileHandleForReading.readDataToEndOfFile()
                psTask.waitUntilExit()
                output = String(data: data, encoding: .utf8) ?? ""
            } catch {}
        }
        
        for line in output.components(separatedBy: "\n") {
            guard line.contains("csrf_token") || line.contains("csrf-token") else { continue }
            
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard let first = parts.first, let _ = Int(first) else { continue }
            let pid = String(first)
            
            // Extract Token
            var token = ""
            if let tokenRegex = try? NSRegularExpression(pattern: #"--csrf[-_]token[=\s]+([^\s"']+)"#) {
                let nsLine = line as NSString
                if let match = tokenRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                   match.numberOfRanges > 1 {
                    token = nsLine.substring(with: match.range(at: 1))
                }
            }
            
            if token.isEmpty {
                for key in ["--csrf_token", "--csrf-token"] {
                    if let range = line.range(of: key) {
                        var sub = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if sub.hasPrefix("=") {
                            sub = String(sub.dropFirst()).trimmingCharacters(in: .whitespaces)
                        }
                        token = sub.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespaces.union(.init(charactersIn: "\"'"))) ?? ""
                        if !token.isEmpty { break }
                    }
                }
            }
            
            guard !token.isEmpty else { continue }
            
            // Extract Port from command line if present (--hub-port=49203, --https_server_port=..., --port=...)
            var cmdPort: Int?
            if let portRegex = try? NSRegularExpression(pattern: #"--(?:hub-port|https_server_port|port)[=\s]+(\d+)"#) {
                let nsLine = line as NSString
                if let match = portRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
                   match.numberOfRanges > 1 {
                    cmdPort = Int(nsLine.substring(with: match.range(at: 1)))
                }
            }
            
            results.append((pid: pid, token: token, port: cmdPort))
        }
        
        return results
    }
    
    func findListeningPorts(pid: String) -> [Int] {
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

    // MARK: - Cloud Code API (Multi-Account)

    struct CloudAccountQuota {
        let email: String
        let quota: GeminiQuota
        let subscriptionTier: String?
        let credits: Int?
        let projectId: String?
    }

    private let cloudBaseURLs = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]
    private let cloudUserAgent = "antigravity/2.32.1 (aidev_client; os_type=darwin; arch=arm64; cl=1003475615)"
    private let loadCodeAssistUserAgent = "antigravity/2.32.1 darwin/arm64 google-api-nodejs-client/10.3.0"

    func fetchAllCloudQuotas(accounts: [StoredAccount], completion: @escaping ([String: Result<CloudAccountQuota, Error>]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [String: Result<CloudAccountQuota, Error>] = [:]

        for account in accounts {
            group.enter()
            fetchCloudQuota(for: account) { result in
                lock.lock()
                results[account.key] = result
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results)
        }
    }

    func fetchCloudQuota(for account: StoredAccount, completion: @escaping (Result<CloudAccountQuota, Error>) -> Void) {
        AccountManager.shared.validAccessToken(for: account.email) { [weak self] tokenResult in
            guard let self = self else { return }
            switch tokenResult {
            case .failure(let err):
                completion(.failure(err))
            case .success(let accessToken):
                self.loadCodeAssist(accessToken: accessToken, preferredProjectId: account.projectId) { meta in
                    let effectiveProjectId = meta.projectId ?? account.projectId
                    self.retrieveCloudQuotaSummary(
                        accessToken: accessToken,
                        projectId: effectiveProjectId,
                        baseURLIndex: 0
                    ) { quotaResult in
                        switch quotaResult {
                        case .success(let quota):
                            AccountManager.shared.updateAccountMetadata(
                                email: account.email,
                                tier: meta.tier,
                                credits: meta.credits,
                                projectId: effectiveProjectId
                            )
                            completion(.success(CloudAccountQuota(
                                email: account.email,
                                quota: quota,
                                subscriptionTier: meta.tier ?? account.subscriptionTier,
                                credits: meta.credits ?? account.credits,
                                projectId: effectiveProjectId
                            )))
                        case .failure(let err):
                            completion(.failure(err))
                        }
                    }
                }
            }
        }
    }

    private func loadCodeAssist(
        accessToken: String,
        preferredProjectId: String?,
        completion: @escaping ((projectId: String?, tier: String?, credits: Int?)) -> Void
    ) {
        guard let url = URL(string: "\(cloudBaseURLs[0])/v1internal:loadCodeAssist") else {
            completion((preferredProjectId, nil, nil))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 6.0
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(loadCodeAssistUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("gl-node/22.21.1", forHTTPHeaderField: "x-goog-api-client")

        var metadata: [String: Any] = [
            "ideType": "ANTIGRAVITY",
            "platform": "DARWIN",
            "pluginType": "GEMINI"
        ]
        var body: [String: Any] = ["mode": "FULL_ELIGIBILITY_CHECK"]
        if let pid = preferredProjectId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pid.isEmpty, pid != "aicode-consumers" {
            metadata["duetProject"] = pid
            body["cloudaicompanionProject"] = pid
        }
        body["metadata"] = metadata
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion((preferredProjectId, nil, nil))
                return
            }

            var projectId: String? = preferredProjectId
            if let pStr = json["cloudaicompanionProject"] as? String, !pStr.isEmpty {
                projectId = pStr
            } else if let pObj = json["cloudaicompanionProject"] as? [String: Any],
                      let pId = pObj["id"] as? String, !pId.isEmpty {
                projectId = pId
            }

            let paidTier = json["paidTier"] as? [String: Any]
            let currentTier = json["currentTier"] as? [String: Any]
            let rawTier = (paidTier?["name"] as? String)
                ?? (paidTier?["id"] as? String)
                ?? (currentTier?["name"] as? String)
                ?? (currentTier?["id"] as? String)
            let tier = Self.formatTierName(rawTier)

            var totalCredits: Int?
            if let creditsArr = (paidTier?["availableCredits"] as? [[String: Any]])
                ?? (currentTier?["availableCredits"] as? [[String: Any]])
                ?? (json["availableCredits"] as? [[String: Any]]) {
                var sum = 0
                var found = false
                for item in creditsArr {
                    if let amtStr = item["creditAmount"] as? String, let amt = Int(amtStr) {
                        sum += amt
                        found = true
                    } else if let amt = item["creditAmount"] as? Int {
                        sum += amt
                        found = true
                    }
                }
                if found { totalCredits = sum }
            }

            completion((projectId, tier, totalCredits))
        }.resume()
    }

    private func retrieveCloudQuotaSummary(
        accessToken: String,
        projectId: String?,
        baseURLIndex: Int,
        completion: @escaping (Result<GeminiQuota, Error>) -> Void
    ) {
        guard baseURLIndex < cloudBaseURLs.count else {
            completion(.failure(NSError(domain: "QuotaFetcher", code: 500, userInfo: [NSLocalizedDescriptionKey: "All Cloud Code endpoints failed"])))
            return
        }
        guard let url = URL(string: "\(cloudBaseURLs[baseURLIndex])/v1internal:retrieveUserQuotaSummary") else {
            retrieveCloudQuotaSummary(accessToken: accessToken, projectId: projectId, baseURLIndex: baseURLIndex + 1, completion: completion)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8.0
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cloudUserAgent, forHTTPHeaderField: "User-Agent")

        var payload: [String: Any] = [:]
        if let pid = projectId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pid.isEmpty, pid != "aicode-consumers" {
            payload["project"] = pid
        }
        req.httpBody = (try? JSONSerialization.data(withJSONObject: payload)) ?? "{}".data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data = data, error == nil, (200..<300).contains(status),
               let quota = Self.parseQuota(from: data) {
                completion(.success(quota))
                return
            }
            if baseURLIndex + 1 < self.cloudBaseURLs.count {
                self.retrieveCloudQuotaSummary(accessToken: accessToken, projectId: projectId, baseURLIndex: baseURLIndex + 1, completion: completion)
            } else {
                let msg = error?.localizedDescription ?? "HTTP \(status)"
                completion(.failure(NSError(domain: "QuotaFetcher", code: status, userInfo: [NSLocalizedDescriptionKey: msg])))
            }
        }.resume()
    }

    private static func formatTierName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let lower = raw.lowercased()
        if lower.contains("ultra") { return "Ultra" }
        if lower.contains("pro") { return "Pro" }
        if lower.contains("free") || lower.contains("standard") { return "Free" }
        return raw
    }
}
