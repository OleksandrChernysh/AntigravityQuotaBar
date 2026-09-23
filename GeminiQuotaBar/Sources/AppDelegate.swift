import Cocoa

enum DisplayFormat: Int {
    case standard = 0      // ♊ 5h: 97% · Sem: 100%
    case descriptive = 1   // Gemini: 97% (5h) · 100% (Sem)
    case compact = 2       // ♊ 97% | 100%
    case icons = 3         // ⚡97% · 📅100%
    case fiveHourOnly = 4  // ♊ 5h: 97%
    case weeklyOnly = 5    // ♊ Sem: 100%
    
    func format(fiveHour: Int, weekly: Int) -> String {
        switch self {
        case .standard:
            return "♊ 5h: \(fiveHour)% · Sem: \(weekly)%"
        case .descriptive:
            return "Gemini: \(fiveHour)% (5h) · \(weekly)% (Sem)"
        case .compact:
            return "♊ \(fiveHour)% | \(weekly)%"
        case .icons:
            return "⚡\(fiveHour)% · 📅\(weekly)%"
        case .fiveHourOnly:
            return "♊ 5h: \(fiveHour)%"
        case .weeklyOnly:
            return "♊ Sem: \(weekly)%"
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var refreshInterval: TimeInterval = 60.0 // 1 minute default
    var currentFormat: DisplayFormat = .standard
    var latestQuota: GeminiQuota?
    var isFetching = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load saved preferences
        if let savedFormat = UserDefaults.standard.value(forKey: "DisplayFormat") as? Int,
           let format = DisplayFormat(rawValue: savedFormat) {
            currentFormat = format
        }
        if let savedInterval = UserDefaults.standard.value(forKey: "RefreshInterval") as? Double,
           savedInterval >= 15.0 {
            refreshInterval = savedInterval
        }
        
        // Initialize Status Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let savedLast5h = UserDefaults.standard.value(forKey: "Last5h") as? Int,
           let savedLastWk = UserDefaults.standard.value(forKey: "LastWeekly") as? Int {
            if let button = statusItem.button {
                button.title = currentFormat.format(fiveHour: savedLast5h, weekly: savedLastWk)
            }
        } else if let button = statusItem.button {
            button.title = "♊ Conectando..."
        }
        
        buildMenu()
        fetchData()
        startTimer()
    }
    
    func startTimer(interval: TimeInterval? = nil) {
        timer?.invalidate()
        let intv = interval ?? refreshInterval
        timer = Timer.scheduledTimer(withTimeInterval: intv, repeats: true) { [weak self] _ in
            self?.fetchData()
        }
    }
    
    @objc func fetchData() {
        guard !isFetching else { return }
        isFetching = true
        
        QuotaFetcher.shared.fetchQuota { [weak self] result in
            guard let self = self else { return }
            self.isFetching = false
            switch result {
            case .success(let quota):
                self.latestQuota = quota
                // Cache last values so they show instantly on next reboot
                UserDefaults.standard.setValue(quota.fiveHourPercent, forKey: "Last5h")
                UserDefaults.standard.setValue(quota.weeklyPercent, forKey: "LastWeekly")
                self.updateStatusBarTitle(quota: quota)
                self.buildMenu()
                self.startTimer(interval: self.refreshInterval)
            case .failure(let error):
                if self.latestQuota == nil {
                    if let button = self.statusItem.button {
                        button.title = "♊ (Esperando IDE...)"
                    }
                    self.buildErrorMenu(error: error.localizedDescription)
                }
                // When disconnected, retry more frequently (every 5 seconds) until Antigravity starts
                self.startTimer(interval: 5.0)
            }
        }
    }
    
    func updateStatusBarTitle(quota: GeminiQuota) {
        guard let button = statusItem.button else { return }
        button.title = currentFormat.format(fiveHour: quota.fiveHourPercent, weekly: quota.weeklyPercent)
    }
    
    func getStatusEmoji(percent: Int) -> String {
        if percent >= 50 { return "🟢" }
        if percent >= 20 { return "🟡" }
        return "🔴"
    }
    
    func buildMenu() {
        let menu = NSMenu()
        
        if let quota = latestQuota {
            // Header
            let headerItem = NSMenuItem(title: "Google Gemini Quota", action: nil, keyEquivalent: "")
            headerItem.attributedTitle = NSAttributedString(
                string: "♊ Google Gemini Quota",
                attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
            )
            menu.addItem(headerItem)
            menu.addItem(NSMenuItem.separator())
            
            // 5-Hour Limit
            let fiveHourItem = NSMenuItem(
                title: "\(getStatusEmoji(percent: quota.fiveHourPercent)) Límite 5 Horas: \(quota.fiveHourPercent)%",
                action: nil,
                keyEquivalent: ""
            )
            fiveHourItem.attributedTitle = NSAttributedString(
                string: "\(getStatusEmoji(percent: quota.fiveHourPercent)) Límite 5 Horas: \(quota.fiveHourPercent)%",
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
            )
            menu.addItem(fiveHourItem)
            
            if !quota.fiveHourDescription.isEmpty {
                let descItem = NSMenuItem(title: "    " + quota.fiveHourDescription, action: nil, keyEquivalent: "")
                descItem.attributedTitle = NSAttributedString(
                    string: "    " + quota.fiveHourDescription,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                menu.addItem(descItem)
            }
            
            menu.addItem(NSMenuItem.separator())
            
            // Weekly Limit
            let weeklyItem = NSMenuItem(
                title: "\(getStatusEmoji(percent: quota.weeklyPercent)) Límite Semanal: \(quota.weeklyPercent)%",
                action: nil,
                keyEquivalent: ""
            )
            weeklyItem.attributedTitle = NSAttributedString(
                string: "\(getStatusEmoji(percent: quota.weeklyPercent)) Límite Semanal: \(quota.weeklyPercent)%",
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
            )
            menu.addItem(weeklyItem)
            
            if !quota.weeklyDescription.isEmpty {
                let descItem = NSMenuItem(title: "    " + quota.weeklyDescription, action: nil, keyEquivalent: "")
                descItem.attributedTitle = NSAttributedString(
                    string: "    " + quota.weeklyDescription,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                menu.addItem(descItem)
            }
            
            // Claude info if available
            if let claudeW = quota.claudeWeeklyPercent {
                menu.addItem(NSMenuItem.separator())
                let claudeHeader = NSMenuItem(title: "Otros Modelos (Claude / GPT)", action: nil, keyEquivalent: "")
                claudeHeader.attributedTitle = NSAttributedString(
                    string: "🤖 Claude & GPT: \(claudeW)% restante",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                menu.addItem(claudeHeader)
                if let claudeDesc = quota.claudeWeeklyDescription, !claudeDesc.isEmpty {
                    let cDescItem = NSMenuItem(title: "    " + claudeDesc, action: nil, keyEquivalent: "")
                    cDescItem.attributedTitle = NSAttributedString(
                        string: "    " + claudeDesc,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 10),
                            .foregroundColor: NSColor.tertiaryLabelColor
                        ]
                    )
                    menu.addItem(cDescItem)
                }
            }
            
        } else {
            menu.addItem(NSMenuItem(title: "Cargando información de cuota...", action: nil, keyEquivalent: ""))
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Format submenu
        let formatMenu = NSMenu()
        let formats: [(DisplayFormat, String)] = [
            (.standard, "♊ 5h: 97% · Sem: 100% (Recomendado)"),
            (.descriptive, "Gemini: 97% (5h) · 100% (Sem)"),
            (.compact, "♊ 97% | 100%"),
            (.icons, "⚡97% · 📅100%"),
            (.fiveHourOnly, "♊ 5h: 97% (Solo 5 horas)"),
            (.weeklyOnly, "♊ Sem: 100% (Solo Semanal)")
        ]
        
        for (fmt, title) in formats {
            let item = NSMenuItem(title: title, action: #selector(changeFormat(_:)), keyEquivalent: "")
            item.tag = fmt.rawValue
            item.state = (fmt == currentFormat) ? .on : .off
            formatMenu.addItem(item)
        }
        
        let formatSubmenuItem = NSMenuItem(title: "Estilo en la Barra de Menús", action: nil, keyEquivalent: "")
        formatSubmenuItem.submenu = formatMenu
        menu.addItem(formatSubmenuItem)
        
        // Refresh interval submenu
        let intervalMenu = NSMenu()
        let intervals: [(TimeInterval, String)] = [
            (30.0, "Cada 30 segundos"),
            (60.0, "Cada 1 minuto (Por defecto)"),
            (300.0, "Cada 5 minutos")
        ]
        for (sec, title) in intervals {
            let item = NSMenuItem(title: title, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.representedObject = sec
            item.state = (abs(refreshInterval - sec) < 1.0) ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalSubmenuItem = NSMenuItem(title: "Frecuencia de Actualización", action: nil, keyEquivalent: "")
        intervalSubmenuItem.submenu = intervalMenu
        menu.addItem(intervalSubmenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Refresh now item
        let refreshItem = NSMenuItem(title: "Actualizar Ahora", action: #selector(fetchData), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = .command
        menu.addItem(refreshItem)
        
        // Last updated time
        if let quota = latestQuota {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeStr = formatter.string(from: quota.lastUpdated)
            let timeItem = NSMenuItem(title: "Actualizado: \(timeStr)", action: nil, keyEquivalent: "")
            timeItem.isEnabled = false
            menu.addItem(timeItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at Login
        let launchItem = NSMenuItem(title: "Iniciar al encender la Mac", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)
        
        // Quit item
        let quitItem = NSMenuItem(title: "Salir de Gemini Quota", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    func buildErrorMenu(error: String) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "♊ Gemini Quota Bar", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(string: "♊ Gemini Quota Bar", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())
        
        let errItem = NSMenuItem(title: "Estado: Desconectado", action: nil, keyEquivalent: "")
        errItem.attributedTitle = NSAttributedString(
            string: "⚠️ Estado: \(error)",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        menu.addItem(errItem)
        
        let tipItem = NSMenuItem(title: "Asegúrate de que Antigravity IDE esté abierto.", action: nil, keyEquivalent: "")
        tipItem.isEnabled = false
        menu.addItem(tipItem)
        
        menu.addItem(NSMenuItem.separator())
        let refreshItem = NSMenuItem(title: "Reintentar Conexión", action: #selector(fetchData), keyEquivalent: "r")
        refreshItem.keyEquivalentModifierMask = .command
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    @objc func changeFormat(_ sender: NSMenuItem) {
        guard let format = DisplayFormat(rawValue: sender.tag) else { return }
        currentFormat = format
        UserDefaults.standard.setValue(format.rawValue, forKey: "DisplayFormat")
        if let quota = latestQuota {
            updateStatusBarTitle(quota: quota)
        }
        buildMenu()
    }
    
    @objc func changeInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        refreshInterval = interval
        UserDefaults.standard.setValue(interval, forKey: "RefreshInterval")
        startTimer()
        buildMenu()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Launch at Login Helper
    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.antigravity.geminiquotabar.plist")
    }
    
    func isLaunchAtLoginEnabled() -> Bool {
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }
    
    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let enabled = isLaunchAtLoginEnabled()
        let fm = FileManager.default
        if enabled {
            try? fm.removeItem(at: launchAgentPlistURL)
        } else {
            guard let appBundlePath = Bundle.main.bundlePath as String? else { return }
            let execPath = (appBundlePath as NSString).appendingPathComponent("Contents/MacOS/GeminiQuotaBar")
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.antigravity.geminiquotabar</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <false/>
            </dict>
            </plist>
            """
            let launchAgentsDir = launchAgentPlistURL.deletingLastPathComponent()
            try? fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            try? plistContent.write(to: launchAgentPlistURL, atomically: true, encoding: .utf8)
        }
        buildMenu()
    }
}
