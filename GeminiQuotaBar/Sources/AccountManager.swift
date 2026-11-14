import Cocoa
import Network
import Security

enum ClientKind: String, Codable {
    case ide
    case app

    var badge: String {
        switch self {
        case .ide: return "IDE"
        case .app: return "App"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .ide: return "com.google.antigravity-ide"
        case .app: return "com.google.antigravity"
        }
    }
}

enum FocusMode: Equatable {
    case auto
    case pinned(String)

    var storageValue: String {
        switch self {
        case .auto: return "auto"
        case .pinned(let email): return "pin:\(email.lowercased())"
        }
    }

    init(storageValue: String?) {
        guard let v = storageValue else { self = .auto; return }
        if v.hasPrefix("pin:") {
            let email = String(v.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !email.isEmpty {
                self = .pinned(email)
                return
            }
        }
        self = .auto
    }
}

struct StoredAccount: Codable, Equatable {
    let email: String
    var subscriptionTier: String?
    var credits: Int?
    var projectId: String?

    var key: String { email.lowercased() }
}

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: TimeInterval
}

final class AccountManager {
    static let shared = AccountManager()

    private var clientId: String {
        Self.loadOAuthClientConfig()?.clientId
            ?? ProcessInfo.processInfo.environment["ANTIGRAVITY_OAUTH_CLIENT_ID"]
            ?? ""
    }
    private var clientSecret: String {
        Self.loadOAuthClientConfig()?.clientSecret
            ?? ProcessInfo.processInfo.environment["ANTIGRAVITY_OAUTH_CLIENT_SECRET"]
            ?? ""
    }

    private struct OAuthClientConfig: Decodable {
        let clientId: String
        let clientSecret: String
        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case clientSecret = "client_secret"
        }
    }

    private static func loadOAuthClientConfig() -> OAuthClientConfig? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AntigravityQuotaBar/oauth_client.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(OAuthClientConfig.self, from: data)
    }
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let userInfoURL = "https://www.googleapis.com/oauth2/v2/userinfo"
    private let keychainService = "com.antigravity.antigravityquotabar.oauth"

    private let accountsDefaultsKey = "StoredAccountsV1"
    private let focusModeDefaultsKey = "AccountFocusMode"
    private let showBadgeDefaultsKey = "ShowAccountBadgeInMenuBar"

    private(set) var accounts: [StoredAccount] = []
    private(set) var focusMode: FocusMode = .auto
    private(set) var showBadgeInMenuBar: Bool = true
    private(set) var lastActiveClient: ClientKind = .ide
    private(set) var clientEmails: [ClientKind: String] = [:]

    var onFocusOrAccountsChanged: (() -> Void)?

    private var oauthListener: NWListener?
    private var workspaceObserver: NSObjectProtocol?
    private var tokenCache: [String: OAuthTokens] = [:]

    private init() {
        loadPreferences()
        seedInitialClientFromRunningApps()
        startWorkspaceObserver()
    }

    private func loadPreferences() {
        if let data = UserDefaults.standard.data(forKey: accountsDefaultsKey),
           let decoded = try? JSONDecoder().decode([StoredAccount].self, from: data) {
            accounts = decoded
        }
        focusMode = FocusMode(storageValue: UserDefaults.standard.string(forKey: focusModeDefaultsKey))
        if UserDefaults.standard.object(forKey: showBadgeDefaultsKey) != nil {
            showBadgeInMenuBar = UserDefaults.standard.bool(forKey: showBadgeDefaultsKey)
        }
    }

    private func saveAccounts() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: accountsDefaultsKey)
        }
    }

    func setFocusMode(_ mode: FocusMode) {
        focusMode = mode
        UserDefaults.standard.set(mode.storageValue, forKey: focusModeDefaultsKey)
        onFocusOrAccountsChanged?()
    }

    func setShowBadgeInMenuBar(_ show: Bool) {
        showBadgeInMenuBar = show
        UserDefaults.standard.set(show, forKey: showBadgeDefaultsKey)
        onFocusOrAccountsChanged?()
    }

    func updateAccountMetadata(email: String, tier: String?, credits: Int?, projectId: String?) {
        let key = email.lowercased()
        guard let idx = accounts.firstIndex(where: { $0.key == key }) else { return }
        if let tier = tier { accounts[idx].subscriptionTier = tier }
        if let credits = credits { accounts[idx].credits = credits }
        if let projectId = projectId { accounts[idx].projectId = projectId }
        saveAccounts()
    }

    func removeAccount(email: String) {
        let key = email.lowercased()
        accounts.removeAll { $0.key == key }
        deleteTokens(for: key)
        if case .pinned(let pinnedEmail) = focusMode, pinnedEmail.lowercased() == key {
            focusMode = .auto
            UserDefaults.standard.set(focusMode.storageValue, forKey: focusModeDefaultsKey)
        }
        saveAccounts()
        onFocusOrAccountsChanged?()
    }

    /// Short 1-2 char badge for an account (e.g. "P" / "W", or "A1" / "A2" if initials collide).
    func shortBadge(for email: String) -> String {
        let key = email.lowercased()
        let firstChar = email.split(separator: "@").first?.first.map { String($0).uppercased() } ?? "A"
        let collisions = accounts.filter {
            ($0.email.split(separator: "@").first?.first.map { String($0).uppercased() } ?? "") == firstChar
        }
        if collisions.count <= 1 {
            return firstChar
        }
        if let idx = accounts.firstIndex(where: { $0.key == key }) {
            return "\(firstChar)\(idx + 1)"
        }
        return firstChar
    }

    /// Which client(s) currently hold this account email, if detected locally.
    func clientBadges(for email: String) -> [ClientKind] {
        let key = email.lowercased()
        var kinds: [ClientKind] = []
        if clientEmails[.ide]?.lowercased() == key { kinds.append(.ide) }
        if clientEmails[.app]?.lowercased() == key { kinds.append(.app) }
        return kinds
    }

    func activeAccountEmail() -> String? {
        guard !accounts.isEmpty else { return nil }
        switch focusMode {
        case .pinned(let pinnedEmail):
            if let match = accounts.first(where: { $0.key == pinnedEmail.lowercased() }) {
                return match.email
            }
            return accounts.first?.email
        case .auto:
            if let clientEmail = clientEmails[lastActiveClient]?.lowercased(),
               let match = accounts.first(where: { $0.key == clientEmail }) {
                return match.email
            }
            let other: ClientKind = (lastActiveClient == .ide) ? .app : .ide
            if let otherEmail = clientEmails[other]?.lowercased(),
               let match = accounts.first(where: { $0.key == otherEmail }) {
                return match.email
            }
            return accounts.first?.email
        }
    }

    // MARK: - NSWorkspace Active App / IDE Tracking

    private func seedInitialClientFromRunningApps() {
        if let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            if front == ClientKind.app.bundleIdentifier { lastActiveClient = .app; return }
            if front == ClientKind.ide.bundleIdentifier { lastActiveClient = .ide; return }
        }
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        if running.contains(ClientKind.ide.bundleIdentifier) {
            lastActiveClient = .ide
        } else if running.contains(ClientKind.app.bundleIdentifier) {
            lastActiveClient = .app
        }
    }

    private func startWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier else { return }
            let newClient: ClientKind?
            if bundleId == ClientKind.app.bundleIdentifier {
                newClient = .app
            } else if bundleId == ClientKind.ide.bundleIdentifier {
                newClient = .ide
            } else {
                newClient = nil
            }
            if let client = newClient, client != self.lastActiveClient {
                self.lastActiveClient = client
                if self.focusMode == .auto {
                    self.onFocusOrAccountsChanged?()
                }
            }
        }
    }

    /// Detects which account email is currently logged into Antigravity IDE / App
    /// by querying `GetUserStatus` on each running `language_server` / `agy` process.
    func refreshDetectedClientEmails(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .utility).async {
            var detected: [ClientKind: String] = [:]
            let processes = self.findClientLanguageServers()

            for proc in processes {
                if detected[proc.client] != nil { continue }
                var candidatePorts: [Int] = []
                if let p = proc.port { candidatePorts.append(p) }
                for p in QuotaFetcher.shared.findListeningPorts(pid: proc.pid) {
                    if !candidatePorts.contains(p) { candidatePorts.append(p) }
                }
                if let email = self.queryEmailFromServer(ports: candidatePorts, token: proc.token) {
                    detected[proc.client] = email
                }
            }

            DispatchQueue.main.async {
                let changed = detected != self.clientEmails
                self.clientEmails = detected
                if changed {
                    self.onFocusOrAccountsChanged?()
                }
                completion?()
            }
        }
    }

    private func findClientLanguageServers() -> [(client: ClientKind, pid: String, token: String, port: Int?)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid,ppid,command"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        var output = ""
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            output = String(data: data, encoding: .utf8) ?? ""
        } catch {
            return []
        }

        // Map PID -> command to trace parent app when needed
        var cmdByPid: [String: String] = [:]
        var ppidByPid: [String: String] = [:]
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3 else { continue }
            let pid = String(parts[0])
            let ppid = String(parts[1])
            let cmd = String(parts[2])
            cmdByPid[pid] = cmd
            ppidByPid[pid] = ppid
        }

        func resolveClient(pid: String, cmd: String) -> ClientKind? {
            if cmd.contains("Antigravity IDE.app") { return .ide }
            if cmd.contains("/Applications/Antigravity.app/") || cmd.contains("--subclient_type hub") { return .app }
            var cur = pid
            for _ in 0..<5 {
                guard let p = ppidByPid[cur], p != "0", p != "1", let pCmd = cmdByPid[p] else { break }
                if pCmd.contains("Antigravity IDE") { return .ide }
                if pCmd.contains("Antigravity.app") { return .app }
                cur = p
            }
            if cmd.contains("/bin/agy") && cmd.contains("--hub") { return .ide }
            return nil
        }

        var results: [(client: ClientKind, pid: String, token: String, port: Int?)] = []
        for (pid, cmd) in cmdByPid {
            guard cmd.contains("csrf_token") || cmd.contains("csrf-token") else { continue }
            guard let client = resolveClient(pid: pid, cmd: cmd) else { continue }

            var token = ""
            if let regex = try? NSRegularExpression(pattern: #"--csrf[-_]token[=\s]+([^\s"']+)"#) {
                let ns = cmd as NSString
                if let match = regex.firstMatch(in: cmd, range: NSRange(location: 0, length: ns.length)),
                   match.numberOfRanges > 1 {
                    token = ns.substring(with: match.range(at: 1))
                }
            }
            guard !token.isEmpty else { continue }

            var cmdPort: Int?
            if let regex = try? NSRegularExpression(pattern: #"--(?:hub-port|https_server_port|port)[=\s]+(\d+)"#) {
                let ns = cmd as NSString
                if let match = regex.firstMatch(in: cmd, range: NSRange(location: 0, length: ns.length)),
                   match.numberOfRanges > 1,
                   let p = Int(ns.substring(with: match.range(at: 1))), p > 0 {
                    cmdPort = p
                }
            }

            results.append((client: client, pid: pid, token: token, port: cmdPort))
        }
        return results
    }

    private func queryEmailFromServer(ports: [Int], token: String) -> String? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.5
        config.timeoutIntervalForResource = 1.5
        let session = URLSession(configuration: config, delegate: SelfSignedSessionDelegate(), delegateQueue: nil)

        for port in ports {
            for scheme in ["https", "http"] {
                guard let url = URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else { continue }
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
                req.httpBody = "{}".data(using: .utf8)

                let sem = DispatchSemaphore(value: 0)
                var foundEmail: String?
                session.dataTask(with: req) { data, _, error in
                    defer { sem.signal() }
                    guard let data = data, error == nil,
                          let text = String(data: data, encoding: .utf8),
                          let regex = try? NSRegularExpression(pattern: #""email"\s*:\s*"([^"]+@[^"]+)""#),
                          let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
                          match.numberOfRanges > 1 else { return }
                    foundEmail = (text as NSString).substring(with: match.range(at: 1))
                }.resume()
                _ = sem.wait(timeout: .now() + 1.5)
                if let email = foundEmail { return email }
            }
        }
        return nil
    }

    // MARK: - Keychain Token Storage

    private func saveTokens(_ tokens: OAuthTokens, for emailKey: String) {
        tokenCache[emailKey] = tokens
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: emailKey
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func loadTokens(for email: String) -> OAuthTokens? {
        let key = email.lowercased()
        if let cached = tokenCache[key] {
            return cached
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let decoded = try? JSONDecoder().decode(OAuthTokens.self, from: data) else {
            return nil
        }
        tokenCache[key] = decoded
        return decoded
    }

    private func deleteTokens(for emailKey: String) {
        tokenCache.removeValue(forKey: emailKey)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: emailKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Token Refresh

    func validAccessToken(for email: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let tokens = loadTokens(for: email) else {
            completion(.failure(NSError(domain: "AccountManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "Missing OAuth token for \(email)"])))
            return
        }
        if tokens.expiresAt > Date().timeIntervalSince1970 + 300 {
            completion(.success(tokens.accessToken))
            return
        }
        refreshAccessToken(refreshToken: tokens.refreshToken) { [weak self] result in
            switch result {
            case .success(let newTokens):
                self?.saveTokens(newTokens, for: email.lowercased())
                completion(.success(newTokens.accessToken))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func refreshAccessToken(refreshToken: String, completion: @escaping (Result<OAuthTokens, Error>) -> Void) {
        guard let url = URL(string: tokenURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyParts = [
            "client_id=\(urlEncode(clientId))",
            "client_secret=\(urlEncode(clientSecret))",
            "refresh_token=\(urlEncode(refreshToken))",
            "grant_type=refresh_token"
        ]
        req.httpBody = bodyParts.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Token refresh failed"
                completion(.failure(NSError(domain: "AccountManager", code: 401, userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }
            let expiresIn = (json["expires_in"] as? Double) ?? 3600
            let newRefresh = (json["refresh_token"] as? String) ?? refreshToken
            let tokens = OAuthTokens(
                accessToken: accessToken,
                refreshToken: newRefresh,
                expiresAt: Date().timeIntervalSince1970 + expiresIn
            )
            completion(.success(tokens))
        }.resume()
    }

    // MARK: - Google OAuth Loopback Sign-In

    func startOAuthLogin(completion: @escaping (Result<StoredAccount, Error>) -> Void) {
        oauthListener?.cancel()
        oauthListener = nil

        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .any)
            self.oauthListener = listener

            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                if case .ready = state, let port = listener.port?.rawValue {
                    let redirectURI = "http://127.0.0.1:\(port)/oauth2callback"
                    let scopes = [
                        "openid",
                        "https://www.googleapis.com/auth/cloud-platform",
                        "https://www.googleapis.com/auth/userinfo.email",
                        "https://www.googleapis.com/auth/userinfo.profile",
                        "https://www.googleapis.com/auth/cclog",
                        "https://www.googleapis.com/auth/experimentsandconfigs",
                        "https://www.googleapis.com/auth/aicode"
                    ].joined(separator: " ")
                    var comp = URLComponents(string: self.authURL)!
                    comp.queryItems = [
                        URLQueryItem(name: "client_id", value: self.clientId),
                        URLQueryItem(name: "redirect_uri", value: redirectURI),
                        URLQueryItem(name: "response_type", value: "code"),
                        URLQueryItem(name: "scope", value: scopes),
                        URLQueryItem(name: "access_type", value: "offline"),
                        URLQueryItem(name: "prompt", value: "consent")
                    ]
                    if let url = comp.url {
                        DispatchQueue.main.async {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } else if case .failed(let err) = state {
                    DispatchQueue.main.async {
                        completion(.failure(err))
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { return }
                connection.start(queue: .global(qos: .userInitiated))
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, _, _ in
                    guard let data = data, let requestText = String(data: data, encoding: .utf8) else {
                        connection.cancel()
                        return
                    }
                    let firstLine = requestText.components(separatedBy: "\r\n").first ?? ""
                    let parts = firstLine.split(separator: " ")
                    let targetPath = parts.count >= 2 ? String(parts[1]) : "/"
                    guard targetPath.hasPrefix("/oauth2callback"),
                          let port = listener.port?.rawValue,
                          let comps = URLComponents(string: "http://127.0.0.1:\(port)\(targetPath)"),
                          let code = comps.queryItems?.first(where: { $0.name == "code" })?.value else {
                        self.sendHTTPResponse(connection: connection, html: "<h3>Authorization cancelled or failed.</h3>")
                        return
                    }

                    let redirectURI = "http://127.0.0.1:\(port)/oauth2callback"
                    self.sendHTTPResponse(
                        connection: connection,
                        html: "<html><body style='font-family:-apple-system,sans-serif;padding:40px;text-align:center;'><h2>Signed in to AntigravityQuotaBar</h2><p>You can close this tab and return to the menu bar app.</p></body></html>"
                    )
                    listener.cancel()
                    self.oauthListener = nil

                    self.exchangeCodeForAccount(code: code, redirectURI: redirectURI, completion: completion)
                }
            }

            listener.start(queue: .global(qos: .userInitiated))
        } catch {
            completion(.failure(error))
        }
    }

    private func sendHTTPResponse(connection: NWConnection, html: String) {
        let bodyData = html.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(bodyData)
        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func exchangeCodeForAccount(code: String, redirectURI: String, completion: @escaping (Result<StoredAccount, Error>) -> Void) {
        guard let url = URL(string: tokenURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let bodyParts = [
            "client_id=\(urlEncode(clientId))",
            "client_secret=\(urlEncode(clientSecret))",
            "code=\(urlEncode(code))",
            "redirect_uri=\(urlEncode(redirectURI))",
            "grant_type=authorization_code"
        ]
        req.httpBody = bodyParts.joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let refreshToken = json["refresh_token"] as? String else {
                let msg = data.flatMap { String(data: $0, encoding: .utf8) } ?? "OAuth exchange failed"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AccountManager", code: 400, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
                return
            }
            let expiresIn = (json["expires_in"] as? Double) ?? 3600
            let tokens = OAuthTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date().timeIntervalSince1970 + expiresIn
            )
            self.fetchUserEmail(accessToken: accessToken) { emailResult in
                switch emailResult {
                case .success(let email):
                    self.saveTokens(tokens, for: email.lowercased())
                    DispatchQueue.main.async {
                        let account = StoredAccount(email: email, subscriptionTier: nil, credits: nil, projectId: nil)
                        if let idx = self.accounts.firstIndex(where: { $0.key == account.key }) {
                            self.accounts[idx] = account
                        } else {
                            self.accounts.append(account)
                        }
                        self.saveAccounts()
                        self.onFocusOrAccountsChanged?()
                        completion(.success(account))
                    }
                case .failure(let err):
                    DispatchQueue.main.async { completion(.failure(err)) }
                }
            }
        }.resume()
    }

    private func fetchUserEmail(accessToken: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: userInfoURL) else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let email = json["email"] as? String else {
                completion(.failure(NSError(domain: "AccountManager", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch user email"])))
                return
            }
            completion(.success(email))
        }.resume()
    }

    private func urlEncode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
