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
    if hasClaude { return .brand("claude") }
    if hasGPT { return .brand("openai") }
    return .antigravity
}

/// "Gemini Models" -> "Gemini", "Claude and GPT models" -> "Claude", "Gemini 4 Argon" -> "Argon".
func shortGroupName(_ name: String) -> String {
    if name.contains("Argon") { return "Argon" }
    if name.contains("Gemini") { return "Gemini" }
    if name.contains("Claude") { return "Claude" }
    if name.contains("GPT") { return "GPT" }
    return name.split(separator: " ").first.map(String.init) ?? name
}

/// "5h" / "Wk" label for a bucket's time window.
func windowLabel(_ b: ModelBucketInfo) -> String {
    let w = b.window.lowercased(), id = b.id.lowercased(), n = b.displayName.lowercased()
    if w == "5h" || w.contains("session") || id.contains("5h") || n.contains("5h") || n.contains("five") { return "5h" }
    if w.contains("week") || id.contains("weekly") || n.contains("week") { return "Wk" }
    return String(b.displayName.prefix(2))
}

/// Which product a server group belongs to.
enum GroupKind { case gemini, claudeGPT, argon, other }

func groupKind(_ name: String) -> GroupKind {
    if name.contains("Argon") { return .argon }
    if name.contains("Gemini") { return .gemini }
    if name.contains("Claude") || name.contains("GPT") { return .claudeGPT }
    return .other
}

/// Groups to show in the menu bar: live groups from the server, or a minimal
/// set rebuilt from the flat cached fields.
func statusGroups(_ q: GeminiQuota) -> [ModelGroupInfo] {
    if !q.allGroups.isEmpty { return q.allGroups }
    var groups = [ModelGroupInfo(displayName: "Gemini Models", description: "", buckets: [
        ModelBucketInfo(id: "5h", displayName: "5h Limit", window: "5h",
                        percent: q.fiveHourPercent, resetTime: q.fiveHourResetTime, description: ""),
        ModelBucketInfo(id: "weekly", displayName: "Weekly Limit", window: "weekly",
                        percent: q.weeklyPercent, resetTime: q.weeklyResetTime, description: "")
    ])]
    if let a = q.argonWeeklyPercent {
        groups.append(ModelGroupInfo(displayName: "Gemini 4 Argon", description: "", buckets: [
            ModelBucketInfo(id: "weekly", displayName: "Argon Weekly Limit", window: "weekly",
                            percent: a, resetTime: q.argonResetTime ?? "", description: "")
        ]))
    }
    return groups
}

/// "1h 18m" -> "1h", "6d 20h" -> "6d", "45m" -> "45m".
func firstUnit(_ countdown: String) -> String {
    String(countdown.split(separator: " ").first ?? "")
}

/// Compact value for one group, 5h first then weekly:
/// "88% | 96%"  or, with time, "88% (1h) | 96% (6d)".
func compactValue(_ group: ModelGroupInfo, withTime: Bool) -> String {
    let order: (ModelBucketInfo) -> Int = { b in
        switch windowLabel(b) { case "5h": return 0; case "Wk": return 1; default: return 2 }
    }
    return group.buckets.sorted { order($0) < order($1) }.map { b in
        let cd = withTime ? firstUnit(formatShortCountdown(from: b.resetTime)) : ""
        return "\(b.percent)%" + (cd.isEmpty ? "" : " (\(cd))")
    }.joined(separator: " | ")
}

/// One logo + text pair in the menu bar.
struct StatusSegment {
    let icon: Icon
    let text: String
}

enum DisplayFormat: Int, CaseIterable {
    case allCompact = 0   // [Gemini] 88% | 96%  [Claude] 100% | 100%  [Gemini] Ar 100%
    case gemini = 2       // [Gemini] 88% (1h) | 96% (6d)
    case claudeGPT = 3    // [Claude] 100% (4h) | 100% (6d)
    case argon = 4        // [Gemini] Argon 100% (6d)

    /// Label used in the "Style" submenu (a live preview image is shown next to it).
    var title: String {
        switch self {
        case .allCompact: return "All, compact"
        case .gemini: return "Gemini"
        case .claudeGPT: return "Claude and GPT Models"
        case .argon: return "Argon"
        }
    }

    func segments(quota: GeminiQuota) -> [StatusSegment] {
        let groups = statusGroups(quota)
        func segment(_ g: ModelGroupInfo, withTime: Bool, argonLabel: String) -> StatusSegment {
            let kind = groupKind(g.displayName)
            let prefix = kind == .argon ? argonLabel + " " : ""
            return StatusSegment(icon: groupIcon(g.displayName), text: prefix + compactValue(g, withTime: withTime))
        }
        func only(_ kind: GroupKind, argonLabel: String = "Argon") -> [StatusSegment] {
            groups.filter { groupKind($0.displayName) == kind }
                  .map { segment($0, withTime: true, argonLabel: argonLabel) }
        }

        switch self {
        case .allCompact:
            return groups.filter { !$0.buckets.isEmpty }.map { segment($0, withTime: false, argonLabel: "Ar") }
        case .gemini:
            return only(.gemini)
        case .claudeGPT:
            return only(.claudeGPT)
        case .argon:
            return only(.argon)
        }
    }
}

/// Draws logo + text segments into one template image, so every logo sits next
/// to its own numbers and the whole thing follows the menu bar's light/dark tint.
func renderSegments(_ segments: [StatusSegment], height: CGFloat, fontSize: CGFloat = 0) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize > 0 ? fontSize : NSFont.systemFontSize, weight: .regular)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let iconGap: CGFloat = 4, segmentGap: CGFloat = 10

    let parts: [(NSImage?, NSString, NSSize)] = segments.map { seg in
        let text = seg.text as NSString
        return (iconImage(seg.icon, size: font.pointSize - 1), text, text.size(withAttributes: attrs))
    }
    var width: CGFloat = 0
    for (i, (img, _, size)) in parts.enumerated() {
        if i > 0 { width += segmentGap }
        if let img = img { width += img.size.width + iconGap }
        width += ceil(size.width)
    }

    let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
        var x: CGFloat = 0
        for (i, (img, text, size)) in parts.enumerated() {
            if i > 0 { x += segmentGap }
            if let img = img {
                img.draw(in: NSRect(x: x, y: (height - img.size.height) / 2, width: img.size.width, height: img.size.height))
                x += img.size.width + iconGap
            }
            text.draw(at: NSPoint(x: x, y: (height - size.height) / 2), withAttributes: attrs)
            x += ceil(size.width)
        }
        return true
    }
    image.isTemplate = true
    return image
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
    var currentFormat: DisplayFormat = .allCompact
    var latestQuota: GeminiQuota?
    var isFetching = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load saved preferences
        if let savedFormat = UserDefaults.standard.value(forKey: "StatusStyle") as? Int,
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
            if let data = UserDefaults.standard.data(forKey: "LastGroups"),
               let groups = try? JSONDecoder().decode([ModelGroupInfo].self, from: data) {
                cached.allGroups = groups
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
                if let data = try? JSONEncoder().encode(quota.allGroups) {
                    UserDefaults.standard.set(data, forKey: "LastGroups")
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
        let segments = currentFormat.segments(quota: quota)
        guard !segments.isEmpty, let button = statusItem.button else {
            setStatusBar(icon: .antigravity, text: "—")
            return
        }
        button.image = renderSegments(segments, height: NSStatusBar.system.thickness)
        button.title = ""
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
            // macOS 27+ hides menu item images by default; opt in explicitly.
            if #available(macOS 27.0, *) {
                item.preferredImageVisibility = .visible
            }
        }
        if let attrs = attributes {
            item.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        }
        item.indentationLevel = indent
        return item
    }

    /// 5-segment bar, each segment = 20% remaining.
    func textBar(_ percent: Int) -> String {
        let filled = max(0, min(5, Int((Double(percent) / 20.0).rounded())))
        return String(repeating: "▮", count: filled) + String(repeating: "▯", count: 5 - filled)
    }

    /// Model list from a group description ("Models within this group: A, B" -> "A, B").
    func groupModels(_ group: ModelGroupInfo) -> String {
        let desc = group.description.trimmingCharacters(in: .whitespaces)
        guard !desc.isEmpty, !group.displayName.contains("Argon") else { return "" }
        if let colon = desc.range(of: ":"), desc.lowercased().hasPrefix("models within") {
            return desc[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return desc
    }

    /// One row per bucket, columns pinned with tab stops so every column
    /// (name, window, bar, percent, countdown) lines up regardless of glyph widths:
    ///   Gemini  5h  ▮▮▮▮▯   78%  1h28m
    ///           Wk  ▮▮▯▯▯   38%  2d2h
    /// Model list and exact reset time are in the row tooltip.
    func addCompactRows(to menu: NSMenu, groups: [ModelGroupInfo]) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        func w(_ s: String) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: font]).width) }

        let names = groups.map { shortGroupName($0.displayName) }
        let gap: CGFloat = 6
        let nameW = names.map(w).max() ?? 0
        let winW = max(w("5h"), w("Wk"))
        let barW = max(w("▮▮▮▮▮"), w("▯▯▯▯▯"))
        let pctW = w("100%")

        let winX = nameW + gap
        let barX = winX + winW + gap
        let pctRightX = barX + barW + gap + pctW
        let cdX = pctRightX + gap

        let para = NSMutableParagraphStyle()
        para.tabStops = [
            NSTextTab(textAlignment: .left, location: winX),
            NSTextTab(textAlignment: .left, location: barX),
            NSTextTab(textAlignment: .right, location: pctRightX),
            NSTextTab(textAlignment: .left, location: cdX)
        ]
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]

        // Logos padded to one common width so titles stay aligned; continuation rows get a blank of that width.
        let logos = groups.map { iconImage(groupIcon($0.displayName), size: 13) }
        let logoW = logos.compactMap { $0?.size.width }.max() ?? 0
        let logoH = logos.compactMap { $0?.size.height }.max() ?? 0
        func padded(_ img: NSImage?) -> NSImage {
            let canvas = NSImage(size: NSSize(width: logoW, height: logoH), flipped: false) { _ in
                if let img = img {
                    img.draw(in: NSRect(x: 0, y: (logoH - img.size.height) / 2, width: img.size.width, height: img.size.height))
                }
                return true
            }
            canvas.isTemplate = true
            return canvas
        }
        let blank = padded(nil)

        for (gi, (group, name)) in zip(groups, names).enumerated() {
            let models = groupModels(group)
            let logo = padded(logos[gi])
            for (i, b) in group.buckets.enumerated() {
                let cd = formatFullCountdown(from: b.resetTime)
                let cdShort = cd?.short.replacingOccurrences(of: " ", with: "") ?? ""
                let title = "\(i == 0 ? name : "")\t\(windowLabel(b))\t\(textBar(b.percent))\t\(b.percent)%\t\(cdShort)"

                let item = makeItem(title, attributes: attrs)
                item.image = i == 0 ? logo : blank
                if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
                var tip = [group.displayName + (models.isEmpty ? "" : " (\(models))")]
                if let cd = cd { tip.append("\(b.displayName): resets in \(cd.detailed) (\(cd.absolute))") }
                else if !b.description.isEmpty { tip.append(b.description) }
                item.toolTip = tip.joined(separator: "\n")
                menu.addItem(item)
            }
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        // Info rows have no action; without this AppKit draws them as disabled (faded gray).
        menu.autoenablesItems = false

        if let quota = latestQuota {
            let groups = quota.allGroups.isEmpty
                ? [ModelGroupInfo(displayName: "Gemini", description: "", buckets: [
                    ModelBucketInfo(id: "5h", displayName: "5h Limit", window: "5h",
                                    percent: quota.fiveHourPercent, resetTime: quota.fiveHourResetTime, description: ""),
                    ModelBucketInfo(id: "weekly", displayName: "Weekly Limit", window: "weekly",
                                    percent: quota.weeklyPercent, resetTime: quota.weeklyResetTime, description: "")
                  ])]
                : quota.allGroups
            addCompactRows(to: menu, groups: groups)
            menu.addItem(NSMenuItem.separator())
        } else {
            menu.addItem(makeItem("Loading quota information…", icon: .sf("hourglass")))
            menu.addItem(NSMenuItem.separator())
        }

        // Format submenu
        let formatMenu = NSMenu()
        for fmt in DisplayFormat.allCases {
            let item = makeItem(fmt.title, action: #selector(changeFormat(_:)))
            // Live preview of how this style looks with the current numbers
            if let quota = latestQuota {
                let segments = fmt.segments(quota: quota)
                if !segments.isEmpty {
                    item.image = renderSegments(segments, height: 16, fontSize: 12)
                    if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
                }
            }
            item.tag = fmt.rawValue
            item.state = (fmt == currentFormat) ? .on : .off
            formatMenu.addItem(item)
        }

        let formatSubmenuItem = makeItem("Style", icon: .sf("menubar.rectangle"))
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
        let intervalSubmenuItem = makeItem("Interval", icon: .sf("timer"))
        intervalSubmenuItem.submenu = intervalMenu
        menu.addItem(intervalSubmenuItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh, with last-updated time on the same row
        var refreshTitle = "Refresh"
        if let quota = latestQuota {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            refreshTitle += " · \(formatter.string(from: quota.lastUpdated))"
        }
        // No ⌘ shortcut labels: they reserve an empty right-hand column on every row.
        let refreshItem = makeItem(refreshTitle, icon: .sf("arrow.clockwise"), action: #selector(fetchData))
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Launch at Login
        let launchItem = makeItem("Launch at Login", icon: .sf("power"), action: #selector(toggleLaunchAtLogin(_:)))
        launchItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchItem)

        // Quit item
        let quitItem = makeItem("Quit", icon: .sf("xmark.circle"), action: #selector(quitApp))
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
        let quitItem = makeItem("Quit", icon: .sf("xmark.circle"), action: #selector(quitApp))
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func changeFormat(_ sender: NSMenuItem) {
        guard let format = DisplayFormat(rawValue: sender.tag) else { return }
        currentFormat = format
        UserDefaults.standard.setValue(format.rawValue, forKey: "StatusStyle")
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
