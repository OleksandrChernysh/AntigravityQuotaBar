import Cocoa

// MARK: - SF Symbols helpers

/// Returns an SF Symbol image. Without a color it stays a template image, so it
/// adapts automatically to light/dark mode and menu highlight states.
func symbol(_ name: String,
            _ description: String? = nil,
            size: CGFloat = 13,
            weight: NSFont.Weight = .regular,
            color: NSColor? = nil) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: description) else { return nil }
    var config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
    if let color = color {
        config = config.applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    }
    return base.withSymbolConfiguration(config)
}

/// System health color for a remaining-quota percentage.
func healthColor(percent: Int) -> NSColor {
    if percent >= 50 { return .systemGreen }
    if percent >= 20 { return .systemYellow }
    return .systemRed
}

/// An icon is either a system SF Symbol (for generic concepts like time, refresh, quit)
/// or one or more official brand logos bundled in Contents/Resources (for products).
enum Icon {
    case sf(String)
    case brand(String)       // antigravity, gemini, claude, openai
    case brands([String])    // several logos side by side, e.g. Claude + OpenAI

    static let antigravity = Icon.brand("antigravity")
    static let gemini = Icon.brand("gemini")
}

/// Loads a bundled monochrome brand logo (SVG) as a template image.
func brandImage(_ name: String, size: CGFloat) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "svg"),
          let img = NSImage(contentsOf: url) else { return nil }
    img.size = NSSize(width: size, height: size)
    img.isTemplate = true
    img.accessibilityDescription = name.capitalized
    return img
}

/// Renders an Icon. Brand logos and uncolored symbols are template images,
/// so they follow light/dark mode exactly like native SF Symbols.
func iconImage(_ icon: Icon, size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor? = nil) -> NSImage? {
    // Brand logos are drawn edge-to-edge, so they need a slightly larger box
    // than an SF Symbol of the same point size to look optically equal.
    let brandSize = round(size * 1.15)
    switch icon {
    case .sf(let name):
        return symbol(name, nil, size: size, weight: weight, color: color)
    case .brand(let name):
        return brandImage(name, size: brandSize) ?? symbol("questionmark.square.dashed", nil, size: size)
    case .brands(let names):
        let images = names.compactMap { brandImage($0, size: brandSize) }
        guard !images.isEmpty else { return nil }
        let gap: CGFloat = 3
        let width = CGFloat(images.count) * brandSize + CGFloat(images.count - 1) * gap
        let composite = NSImage(size: NSSize(width: width, height: brandSize), flipped: false) { _ in
            for (i, img) in images.enumerated() {
                img.draw(in: NSRect(x: CGFloat(i) * (brandSize + gap), y: 0, width: brandSize, height: brandSize))
            }
            return true
        }
        composite.isTemplate = true
        return composite
    }
}

/// Icon for a model group returned by the server.
func groupIcon(_ groupName: String) -> Icon {
    // Gemini 4 Argon is a Gemini model, so it uses the Gemini mark too.
    if groupName.contains("Gemini") || groupName.contains("Argon") { return .gemini }
    let hasClaude = groupName.contains("Claude")
    let hasGPT = groupName.contains("GPT") || groupName.contains("OpenAI")
    if hasClaude && hasGPT { return .brands(["claude", "openai"]) }
    if hasClaude { return .brand("claude") }
    if hasGPT { return .brand("openai") }
    return .antigravity
}

enum DisplayFormat: Int, CaseIterable {
    case standardWithTime = 0 // [Antigravity] 5h: 78% (1h 28m) · Wk: 38% (2d 2h)
    case standard = 1         // [Antigravity] 5h: 78% · Wk: 38%
    case compactWithTime = 2  // [Antigravity] 78% (1h) | 38% (2d)
    case compact = 3          // [Antigravity] 78% | 38%
    case icons = 4            // [gauge] 78% · 38% (2d 2h)
    case weeklyOnly = 5       // [calendar] Wk: 38% · 2d 2h
    case fiveHourOnly = 6     // [clock] 5h: 78% · 1h 28m
    case argonOnly = 7        // [Gemini] Argon: 1% · 5d 17h
    case lowest = 8           // [triangle] Min: 1% (5d 17h)
    case descriptive = 9      // [Gemini] Gemini: 78% (5h) · 38% (Wk)

    /// Icon shown in the menu bar, to the left of the text.
    /// The app itself is identified by the Antigravity logo; formats focused on
    /// a single metric use the SF Symbol that describes that metric.
    func icon(quota: GeminiQuota?) -> Icon {
        switch self {
        case .icons: return .sf("gauge.with.dots.needle.50percent") // remaining quota = fuel gauge
        case .weeklyOnly: return .sf("calendar")                     // weekly window
        case .fiveHourOnly: return .sf("clock")                      // 5-hour window
        case .argonOnly: return (quota == nil || quota?.argonWeeklyPercent != nil) ? .gemini : .sf("calendar")
        case .lowest: return .sf("exclamationmark.triangle")         // warning: lowest quota
        case .descriptive: return .gemini
        default: return .antigravity
        }
    }

    /// Label used in the "Menu Bar Style" submenu.
    var menuLabel: String {
        switch self {
        case .standardWithTime: return "5h: 78% (1h 28m) · Wk: 38% (2d 2h)  — Recommended"
        case .standard: return "5h: 78% · Wk: 38%  — Percentages only"
        case .compactWithTime: return "78% (1h) | 38% (2d)  — Compact with time"
        case .compact: return "78% | 38%  — Compact"
        case .icons: return "78% · 38% (2d)  — Gauge"
        case .weeklyOnly: return "Wk: 38% · 2d 2h  — Weekly only"
        case .fiveHourOnly: return "5h: 78% · 1h 28m  — 5-hour only"
        case .argonOnly: return "Argon: 1% · 5d 17h  — Gemini 4 Argon"
        case .lowest: return "Min: 1% (5d 17h)  — Lowest of all"
        case .descriptive: return "Gemini: 78% (5h) · 38% (Wk)"
        }
    }

    func format(quota: GeminiQuota) -> String {
        let fiveHourCd = formatShortCountdown(from: quota.fiveHourResetTime)
        let weeklyCd = formatShortCountdown(from: quota.weeklyResetTime)
        let argonCd = formatShortCountdown(from: quota.argonResetTime ?? "")

        switch self {
        case .standardWithTime:
            let hStr = fiveHourCd.isEmpty ? "" : " (\(fiveHourCd))"
            let wStr = weeklyCd.isEmpty ? "" : " (\(weeklyCd))"
            return "5h: \(quota.fiveHourPercent)%\(hStr) · Wk: \(quota.weeklyPercent)%\(wStr)"
        case .standard:
            return "5h: \(quota.fiveHourPercent)% · Wk: \(quota.weeklyPercent)%"
        case .compactWithTime:
            let hStr = fiveHourCd.isEmpty ? "" : " (\(fiveHourCd))"
            let wStr = weeklyCd.isEmpty ? "" : " (\(weeklyCd))"
            return "\(quota.fiveHourPercent)%\(hStr) | \(quota.weeklyPercent)%\(wStr)"
        case .compact:
            return "\(quota.fiveHourPercent)% | \(quota.weeklyPercent)%"
        case .icons:
            let wStr = weeklyCd.isEmpty ? "" : " (\(weeklyCd))"
            return "\(quota.fiveHourPercent)% · \(quota.weeklyPercent)%\(wStr)"
        case .weeklyOnly:
            let wStr = weeklyCd.isEmpty ? "" : " · \(weeklyCd)"
            return "Wk: \(quota.weeklyPercent)%\(wStr)"
        case .fiveHourOnly:
            let hStr = fiveHourCd.isEmpty ? "" : " · \(fiveHourCd)"
            return "5h: \(quota.fiveHourPercent)%\(hStr)"
        case .argonOnly:
            if let argon = quota.argonWeeklyPercent {
                let aStr = argonCd.isEmpty ? "" : " · \(argonCd)"
                return "Argon: \(argon)%\(aStr)"
            } else {
                let wStr = weeklyCd.isEmpty ? "" : " · \(weeklyCd)"
                return "Wk: \(quota.weeklyPercent)%\(wStr)"
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
            return "Min: \(minP)%\(cdStr)"
        case .descriptive:
            return "Gemini: \(quota.fiveHourPercent)% (5h) · \(quota.weeklyPercent)% (Wk)"
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
        return (short: "0h", detailed: "Imminent", absolute: "Now")
    }

    let totalMinutes = Int(diff) / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60

    let short: String
    let detailed: String
    if days > 0 {
        short = "\(days)d \(hours)h"
        detailed = "\(days) day\(days == 1 ? "" : "s"), \(hours) hour\(hours == 1 ? "" : "s")"
    } else if hours > 0 {
        short = "\(hours)h \(minutes)m"
        detailed = "\(hours) hour\(hours == 1 ? "" : "s"), \(minutes) min"
    } else {
        short = "\(minutes)m"
        detailed = "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }

    let timeFormatter = DateFormatter()
    timeFormatter.locale = Locale(identifier: "en_US")
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
        statusItem.button?.imagePosition = .imageLeading
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
            updateStatusBarTitle(quota: cached)
        } else {
            setStatusBar(icon: .antigravity, text: "Connecting…")
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
                    self.setStatusBar(icon: .antigravity, text: "Waiting for IDE…")
                    self.buildErrorMenu(error: error.localizedDescription)
                }
                self.startTimer(interval: 5.0)
            }
        }
    }

    /// Sets the menu bar icon (template image, adapts to light/dark) and text.
    func setStatusBar(icon: Icon, text: String) {
        guard let button = statusItem.button else { return }
        button.image = iconImage(icon, size: 14, weight: .medium)
        button.title = text.isEmpty ? "" : " " + text
    }

    func updateStatusBarTitle(quota: GeminiQuota) {
        setStatusBar(icon: currentFormat.icon(quota: quota), text: currentFormat.format(quota: quota))
    }

    /// Creates a menu item with an optional icon (SF Symbol or brand logo).
    func makeItem(_ title: String,
                  icon: Icon? = nil,
                  symbolColor: NSColor? = nil,
                  symbolSize: CGFloat = 13,
                  action: Selector? = nil,
                  key: String = "",
                  indent: Int = 0,
                  attributes: [NSAttributedString.Key: Any]? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if let icon = icon {
            item.image = iconImage(icon, size: symbolSize, color: symbolColor)
        }
        if let attrs = attributes {
            item.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        }
        item.indentationLevel = indent
        return item
    }

    func addBucketItems(to menu: NSMenu, name: String, percent: Int, resetTime: String, description: String) {
        let countdown = formatFullCountdown(from: resetTime)

        // Shorten "Five Hour" / "5-Hour" / "5 Hours" to "5h"
        let shortName = name.replacingOccurrences(of: #"(?i)\b(five|5)[ -]hours?\b"#,
                                                  with: "5h",
                                                  options: .regularExpression)
        var itemTitle = "\(shortName): \(percent)%"
        if let cd = countdown {
            itemTitle += "  ·  \(cd.short)"
        }
        // Colored dot = health indicator (green > 50%, yellow 20–50%, red < 20%)
        menu.addItem(makeItem(itemTitle,
                              icon: .sf("circle.fill"),
                              symbolColor: healthColor(percent: percent),
                              symbolSize: 9,
                              indent: 1,
                              attributes: [.font: NSFont.menuFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))

        // Exact countdown detail line: days and hours
        if let cd = countdown {
            let resetDetail = "Resets in \(cd.detailed)  (\(cd.absolute))"
            menu.addItem(makeItem(resetDetail,
                                  indent: 2,
                                  attributes: [
                                    .font: NSFont.systemFont(ofSize: 12),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                  ]))
        } else if !description.isEmpty {
            menu.addItem(makeItem(description,
                                  indent: 2,
                                  attributes: [
                                    .font: NSFont.systemFont(ofSize: 12),
                                    .foregroundColor: NSColor.secondaryLabelColor
                                  ]))
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        // Info rows have no action; without this AppKit draws them as disabled (faded gray).
        menu.autoenablesItems = false

        if let quota = latestQuota {
            if !quota.allGroups.isEmpty {
                for group in quota.allGroups {
                    menu.addItem(makeItem(group.displayName,
                                          icon: groupIcon(group.displayName),
                                          attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))

                    // Skip the Argon plan note ("...available on Ultra plans")
                    if !group.description.isEmpty && !group.displayName.contains("Argon") {
                        menu.addItem(makeItem(group.description,
                                              indent: 1,
                                              attributes: [
                                                .font: NSFont.systemFont(ofSize: 12),
                                                .foregroundColor: NSColor.secondaryLabelColor
                                              ]))
                    }

                    for bucket in group.buckets {
                        addBucketItems(to: menu,
                                       name: bucket.displayName,
                                       percent: bucket.percent,
                                       resetTime: bucket.resetTime,
                                       description: bucket.description)
                    }

                    menu.addItem(NSMenuItem.separator())
                }
            } else {
                // Fallback rendering
                menu.addItem(makeItem("Google Gemini Quota",
                                      icon: .gemini,
                                      attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
                addBucketItems(to: menu, name: "5h Limit", percent: quota.fiveHourPercent,
                               resetTime: quota.fiveHourResetTime, description: "")
                addBucketItems(to: menu, name: "Weekly Limit", percent: quota.weeklyPercent,
                               resetTime: quota.weeklyResetTime, description: "")
                menu.addItem(NSMenuItem.separator())
            }
        } else {
            menu.addItem(makeItem("Loading quota information…", icon: .sf("hourglass")))
            menu.addItem(NSMenuItem.separator())
        }

        // Format submenu
        let formatMenu = NSMenu()
        for fmt in DisplayFormat.allCases {
            let item = makeItem(fmt.menuLabel,
                                icon: fmt.icon(quota: nil),
                                action: #selector(changeFormat(_:)))
            item.tag = fmt.rawValue
            item.state = (fmt == currentFormat) ? .on : .off
            formatMenu.addItem(item)
        }

        let formatSubmenuItem = makeItem("Menu Bar Style", icon: .sf("menubar.rectangle"))
        formatSubmenuItem.submenu = formatMenu
        menu.addItem(formatSubmenuItem)

        // Refresh interval submenu
        let intervalMenu = NSMenu()
        let intervals: [(TimeInterval, String)] = [
            (30.0, "Every 30 seconds"),
            (60.0, "Every 1 minute (Default)"),
            (300.0, "Every 5 minutes")
        ]
        for (sec, title) in intervals {
            let item = NSMenuItem(title: title, action: #selector(changeInterval(_:)), keyEquivalent: "")
            item.representedObject = sec
            item.state = (abs(refreshInterval - sec) < 1.0) ? .on : .off
            intervalMenu.addItem(item)
        }
        let intervalSubmenuItem = makeItem("Refresh Interval", icon: .sf("timer"))
        intervalSubmenuItem.submenu = intervalMenu
        menu.addItem(intervalSubmenuItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh now item
        let refreshItem = makeItem("Refresh Now", icon: .sf("arrow.clockwise"), action: #selector(fetchData), key: "r")
        refreshItem.keyEquivalentModifierMask = .command
        menu.addItem(refreshItem)

        // Last updated time
        if let quota = latestQuota {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timeStr = formatter.string(from: quota.lastUpdated)
            let timeItem = makeItem("Updated: \(timeStr)", icon: .sf("clock.arrow.circlepath"))
            menu.addItem(timeItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let launchItem = makeItem("Launch at Login", icon: .sf("power"), action: #selector(toggleLaunchAtLogin(_:)))
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        // Quit item
        let quitItem = makeItem("Quit Gemini Quota", icon: .sf("xmark.circle"), action: #selector(quitApp), key: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func buildErrorMenu(error: String) {
        let menu = NSMenu()
        // Info rows have no action; without this AppKit draws them as disabled (faded gray).
        menu.autoenablesItems = false
        menu.addItem(makeItem("Gemini Quota Bar",
                              icon: .antigravity,
                              attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeItem("Status: \(error)",
                              icon: .sf("exclamationmark.triangle.fill"),
                              symbolColor: .systemOrange,
                              attributes: [.foregroundColor: NSColor.systemRed]))

        let tipItem = makeItem("Make sure Antigravity IDE is open.", icon: .sf("info.circle"))
        menu.addItem(tipItem)

        menu.addItem(NSMenuItem.separator())
        let refreshItem = makeItem("Retry Connection", icon: .sf("arrow.clockwise"), action: #selector(fetchData), key: "r")
        refreshItem.keyEquivalentModifierMask = .command
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = makeItem("Quit", icon: .sf("xmark.circle"), action: #selector(quitApp), key: "q")
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
