import Cocoa

enum DisplayFormat: Int {
    case standardWithTime = 0 // ♊ 5h: 78% (1h 28m) · Sem: 38% (2d 2h)
    case standard = 1         // ♊ 5h: 78% · Sem: 38%
    case compactWithTime = 2  // ♊ 78% (1h) | 38% (2d)
    case compact = 3          // ♊ 78% | 38%
    case icons = 4            // ⚡78% · 📅38% (2d 2h)
    case weeklyOnly = 5       // ♊ Sem: 38% · ⏳ 2d 2h
    case fiveHourOnly = 6     // ♊ 5h: 78% · ⏳ 1h 28m
    case argonOnly = 7        // 🪐 Argon: 1% · ⏳ 5d 17h
    case lowest = 8           // ⚠️ Mín: 1% (5d 17h)
    case descriptive = 9      // Gemini: 78% (5h) · 38% (Sem)
    
    func format(quota: GeminiQuota) -> String {
        let fiveHourCd = formatShortCountdown(from: quota.fiveHourResetTime)
        let weeklyCd = formatShortCountdown(from: quota.weeklyResetTime)
        let argonCd = formatShortCountdown(from: quota.argonResetTime ?? "")
        
        switch self {
        case .standardWithTime:
            let hStr = fiveHourCd.isEmpty ? "" : " (\(fiveHourCd))"
            let wStr = weeklyCd.isEmpty ? "" : " (\(weeklyCd))"
            return "♊ 5h: \(quota.fiveHourPercent)%\(hStr) · Sem: \(quota.weeklyPercent)%\(wStr)"
        case .standard:
            return "♊ 5h: \(quota.fiveHourPercent)% · Sem: \(quota.weeklyPercent)%"
        case .compactWithTime:
            let hStr = fiveHourCd.isEmpty ? "" : " (\(fiveHourCd))"
            let wStr = weeklyCd.isEmpty ? "" : " (\(weeklyCd))"
            return "♊ \(quota.fiveHourPercent)%\(hStr) | \(quota.weeklyPercent)%\(wStr)"
        case .compact:
            return "♊ \(quota.fiveHourPercent)% | \(quota.weeklyPercent)%"
        case .icons:
            let wStr = weeklyCd.isEmpty ? "" : " (\(weeklyCd))"
            return "⚡\(quota.fiveHourPercent)% · 📅\(quota.weeklyPercent)%\(wStr)"
        case .weeklyOnly:
            let wStr = weeklyCd.isEmpty ? "" : " · ⏳ \(weeklyCd)"
            return "♊ Sem: \(quota.weeklyPercent)%\(wStr)"
        case .fiveHourOnly:
            let hStr = fiveHourCd.isEmpty ? "" : " · ⏳ \(fiveHourCd)"
            return "♊ 5h: \(quota.fiveHourPercent)%\(hStr)"
        case .argonOnly:
            if let argon = quota.argonWeeklyPercent {
                let aStr = argonCd.isEmpty ? "" : " · ⏳ \(argonCd)"
                return "🪐 Argon: \(argon)%\(aStr)"
            } else {
                let wStr = weeklyCd.isEmpty ? "" : " · ⏳ \(weeklyCd)"
                return "♊ Sem: \(quota.weeklyPercent)%\(wStr)"
            }
        case .lowest:
            var minP = min(quota.fiveHourPercent, quota.weeklyPercent)
            var cd = (quota.fiveHourPercent <= quota.weeklyPercent) ? fiveHourCd : weeklyCd
            if let a = quota.argonWeeklyPercent, a < minP {
                minP = a
                cd = argonCd
            }
            if let c = quota.claudeWeeklyPercent, c < minP {
                minP = c
            }
            let cdStr = cd.isEmpty ? "" : " (\(cd))"
            return "⚠️ Mín: \(minP)%\(cdStr)"
        case .descriptive:
            return "Gemini: \(quota.fiveHourPercent)% (5h) · \(quota.weeklyPercent)% (Sem)"
        }
    }
}

func formatShortCountdown(from isoString: String) -> String {
    guard !isoString.isEmpty else { return "" }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: isoString)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: isoString)
    }
    guard let targetDate = date else { return "" }
    
    let diff = targetDate.timeIntervalSince(Date())
    if diff <= 0 { return "0h" }
    
    let totalMinutes = Int(diff) / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60
    
    if days > 0 {
        return "\(days)d \(hours)h"
    } else if hours > 0 {
        return "\(hours)h \(minutes)m"
    } else {
        return "\(minutes)m"
    }
}

func formatFullCountdown(from isoString: String) -> (short: String, detailed: String, absolute: String)? {
    guard !isoString.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: isoString)
    if date == nil {
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: isoString)
    }
    guard let targetDate = date else { return nil }
    
    let diff = targetDate.timeIntervalSince(Date())
    if diff <= 0 {
        return (short: "0h", detailed: "Inminente", absolute: "Ahora")
    }
    
    let totalMinutes = Int(diff) / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60
    
    let short: String
    let detailed: String
    if days > 0 {
        short = "\(days)d \(hours)h"
        detailed = "\(days) día\(days == 1 ? "" : "s"), \(hours) hora\(hours == 1 ? "" : "s")"
    } else if hours > 0 {
        short = "\(hours)h \(minutes)m"
        detailed = "\(hours) hora\(hours == 1 ? "" : "s"), \(minutes) min"
    } else {
        short = "\(minutes)m"
        detailed = "\(minutes) minuto\(minutes == 1 ? "" : "s")"
    }
    
    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "es_ES")
    timeFormatter.dateFormat = "EEE d MMM, HH:mm"
    let absolute = timeFormatter.string(from: targetDate)
    
    return (short: short, detailed: detailed, absolute: absolute)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var refreshInterval: TimeInterval = 60.0 // 1 minute default
    var currentFormat: DisplayFormat = .standardWithTime
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
            var cached = GeminiQuota()
            cached.fiveHourPercent = savedLast5h
            cached.weeklyPercent = savedLastWk
            cached.fiveHourResetTime = UserDefaults.standard.string(forKey: "Last5hReset") ?? ""
            cached.weeklyResetTime = UserDefaults.standard.string(forKey: "LastWeeklyReset") ?? ""
            if let savedArgon = UserDefaults.standard.value(forKey: "LastArgon") as? Int {
                cached.argonWeeklyPercent = savedArgon
                cached.argonResetTime = UserDefaults.standard.string(forKey: "LastArgonReset")
            }
            if let button = statusItem.button {
                button.title = currentFormat.format(quota: cached)
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
                UserDefaults.standard.setValue(quota.fiveHourResetTime, forKey: "Last5hReset")
                UserDefaults.standard.setValue(quota.weeklyResetTime, forKey: "LastWeeklyReset")
                if let argon = quota.argonWeeklyPercent {
                    UserDefaults.standard.setValue(argon, forKey: "LastArgon")
                    UserDefaults.standard.setValue(quota.argonResetTime, forKey: "LastArgonReset")
                }
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
                self.startTimer(interval: 5.0)
            }
        }
    }
    
    func updateStatusBarTitle(quota: GeminiQuota) {
        guard let button = statusItem.button else { return }
        button.title = currentFormat.format(quota: quota)
    }
    
    func getStatusEmoji(percent: Int) -> String {
        if percent >= 50 { return "🟢" }
        if percent >= 20 { return "🟡" }
        return "🔴"
    }
    
    func buildMenu() {
        let menu = NSMenu()
        
        if let quota = latestQuota {
            if !quota.allGroups.isEmpty {
                for group in quota.allGroups {
                    var icon = "✨ "
                    if group.displayName.contains("Argon") {
                        icon = "🪐 "
                    } else if group.displayName.contains("Gemini") {
                        icon = "♊ "
                    } else if group.displayName.contains("Claude") || group.displayName.contains("GPT") {
                        icon = "🤖 "
                    }
                    
                    let headerItem = NSMenuItem(title: "\(icon)\(group.displayName)", action: nil, keyEquivalent: "")
                    headerItem.attributedTitle = NSAttributedString(
                        string: "\(icon)\(group.displayName)",
                        attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
                    )
                    menu.addItem(headerItem)
                    
                    if !group.description.isEmpty {
                        let descItem = NSMenuItem(title: "    " + group.description, action: nil, keyEquivalent: "")
                        descItem.attributedTitle = NSAttributedString(
                            string: "    " + group.description,
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 10),
                                .foregroundColor: NSColor.secondaryLabelColor
                            ]
                        )
                        menu.addItem(descItem)
                    }
                    
                    for bucket in group.buckets {
                        let emoji = getStatusEmoji(percent: bucket.percent)
                        let countdown = formatFullCountdown(from: bucket.resetTime)
                        
                        var itemTitle = "\(emoji) \(bucket.displayName): \(bucket.percent)%"
                        if let cd = countdown {
                            itemTitle += "  ⏳ \(cd.short)"
                        }
                        
                        let bucketItem = NSMenuItem(
                            title: itemTitle,
                            action: nil,
                            keyEquivalent: ""
                        )
                        bucketItem.attributedTitle = NSAttributedString(
                            string: itemTitle,
                            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]
                        )
                        menu.addItem(bucketItem)
                        
                        // Exact countdown detail line: days and hours
                        if let cd = countdown {
                            let resetDetail = "      ⏳ Reset: en \(cd.detailed)  (\(cd.absolute))"
                            let detailItem = NSMenuItem(title: resetDetail, action: nil, keyEquivalent: "")
                            detailItem.attributedTitle = NSAttributedString(
                                string: resetDetail,
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                                    .foregroundColor: NSColor.systemBlue
                                ]
                            )
                            menu.addItem(detailItem)
                        } else if !bucket.description.isEmpty {
                            let descItem = NSMenuItem(title: "      " + bucket.description, action: nil, keyEquivalent: "")
                            descItem.attributedTitle = NSAttributedString(
                                string: "      " + bucket.description,
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 10),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                ]
                            )
                            menu.addItem(descItem)
                        }
                    }
                    
                    menu.addItem(NSMenuItem.separator())
                }
            } else {
                // Fallback rendering
                let headerItem = NSMenuItem(title: "♊ Google Gemini Quota", action: nil, keyEquivalent: "")
                headerItem.attributedTitle = NSAttributedString(
                    string: "♊ Google Gemini Quota",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
                )
                menu.addItem(headerItem)
                menu.addItem(NSMenuItem.separator())
                
                let cd5h = formatFullCountdown(from: quota.fiveHourResetTime)
                var title5h = "\(getStatusEmoji(percent: quota.fiveHourPercent)) Límite 5 Horas: \(quota.fiveHourPercent)%"
                if let cd = cd5h { title5h += "  ⏳ \(cd.short)" }
                menu.addItem(NSMenuItem(title: title5h, action: nil, keyEquivalent: ""))
                if let cd = cd5h {
                    menu.addItem(NSMenuItem(title: "      ⏳ Reset: en \(cd.detailed)", action: nil, keyEquivalent: ""))
                }
                
                let cdWk = formatFullCountdown(from: quota.weeklyResetTime)
                var titleWk = "\(getStatusEmoji(percent: quota.weeklyPercent)) Límite Semanal: \(quota.weeklyPercent)%"
                if let cd = cdWk { titleWk += "  ⏳ \(cd.short)" }
                menu.addItem(NSMenuItem(title: titleWk, action: nil, keyEquivalent: ""))
                if let cd = cdWk {
                    menu.addItem(NSMenuItem(title: "      ⏳ Reset: en \(cd.detailed)", action: nil, keyEquivalent: ""))
                }
                menu.addItem(NSMenuItem.separator())
            }
        } else {
            menu.addItem(NSMenuItem(title: "Cargando información de cuota...", action: nil, keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        }
        
        // Format submenu
        let formatMenu = NSMenu()
        let formats: [(DisplayFormat, String)] = [
            (.standardWithTime, "♊ 5h: 78% (1h 28m) · Sem: 38% (2d 2h)  [Recomendado]"),
            (.standard, "♊ 5h: 78% · Sem: 38%  [Solo porcentajes]"),
            (.compactWithTime, "♊ 78% (1h) | 38% (2d)  [Compacto con tiempo]"),
            (.compact, "♊ 78% | 38%  [Compacto simple]"),
            (.icons, "⚡78% · 📅38% (2d)  [Iconos]"),
            (.weeklyOnly, "♊ Sem: 38% · ⏳ 2d 2h  [Solo Semanal]"),
            (.fiveHourOnly, "♊ 5h: 78% · ⏳ 1h 28m  [Solo 5 Horas]"),
            (.argonOnly, "🪐 Argon: 1% · ⏳ 5d 17h  [Gemini 4 Argon]"),
            (.lowest, "⚠️ Mín: 1% (5d 17h)  [Mínimo de todos]"),
            (.descriptive, "Gemini: 78% (5h) · 38% (Sem)")
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
