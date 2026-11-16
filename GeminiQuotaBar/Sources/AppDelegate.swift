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
enum GroupKind: String, CaseIterable {
    case gemini, claudeGPT, argon, other

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .claudeGPT: return "Claude and GPT Models"
        case .argon: return "Argon"
        case .other: return "Other"
        }
    }

    var icon: Icon {
        switch self {
        case .gemini, .argon: return .gemini
        case .claudeGPT: return .brand("claude")
        case .other: return .antigravity
        }
    }
}

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
    case auto = 5         // follows the model selected in the Antigravity App
    case allCompact = 0   // [Gemini] 88% | 96%  [Claude] 100% | 100%  [Gemini] Ar 100%
    case gemini = 2       // [Gemini] 88% (1h) | 96% (6d)
    case claudeGPT = 3    // [Claude] 100% (4h) | 100% (6d)
    case argon = 4        // [Gemini] Argon 100% (6d)

    /// Label used in the "Style" submenu (a live preview image is shown next to it).
    var title: String {
        switch self {
        case .auto: return "Auto (current model)"
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
        case .auto:
            // Model selected in the App -> its group's style; unknown -> All, compact.
            let target: DisplayFormat?
            switch ModelTracker.shared.currentKind {
            case .gemini: target = .gemini
            case .claudeGPT: target = .claudeGPT
            case .argon: target = .argon
            default: target = nil
            }
            if let t = target {
                let segs = t.segments(quota: quota)
                if !segs.isEmpty { return segs }
            }
            return DisplayFormat.allCompact.segments(quota: quota)
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
func renderSegments(_ segments: [StatusSegment], height: CGFloat, fontSize: CGFloat = 0, prefixBadge: String? = nil) -> NSImage {
    let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize > 0 ? fontSize : NSFont.systemFontSize, weight: .regular)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let iconGap: CGFloat = 4, segmentGap: CGFloat = 10

    var badgeSize: NSSize? = nil
    var badgeStrSize: NSSize = .zero
    let badgeFont = NSFont.systemFont(ofSize: max(9, font.pointSize - 3), weight: .semibold)
    let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: NSColor.black]
    let badgeGap: CGFloat = 6
    if let badge = prefixBadge, !badge.isEmpty {
        badgeStrSize = (badge as NSString).size(withAttributes: badgeAttrs)
        badgeSize = NSSize(width: ceil(badgeStrSize.width) + 8, height: ceil(badgeStrSize.height) + 2)
    }

    let parts: [(NSImage?, NSString, NSSize)] = segments.map { seg in
        let text = seg.text as NSString
        return (iconImage(seg.icon, size: font.pointSize - 1), text, text.size(withAttributes: attrs))
    }
    var width: CGFloat = 0
    if let bSize = badgeSize {
        width += bSize.width + badgeGap
    }
    for (i, (img, _, size)) in parts.enumerated() {
        if i > 0 { width += segmentGap }
        if let img = img { width += img.size.width + iconGap }
        width += ceil(size.width)
    }

    let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
        var x: CGFloat = 0
        if let badge = prefixBadge, let bSize = badgeSize {
            let bRect = NSRect(x: x, y: (height - bSize.height) / 2, width: bSize.width, height: bSize.height)
            let path = NSBezierPath(roundedRect: bRect, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1.0
            NSColor.black.setStroke()
            path.stroke()
            (badge as NSString).draw(
                at: NSPoint(x: bRect.minX + (bSize.width - badgeStrSize.width) / 2,
                            y: bRect.minY + (bSize.height - badgeStrSize.height) / 2),
                withAttributes: badgeAttrs
            )
            x += bSize.width + badgeGap
        }
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

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private struct HighlightState {
        let normalTitle: NSAttributedString
        let highlightedTitle: NSAttributedString
        let normalImage: NSImage?
        let highlightedImage: NSImage?
    }

    var statusItem: NSStatusItem!
    var timer: Timer?
    var refreshInterval: TimeInterval = 60.0 // 1 minute default
    var currentFormat: DisplayFormat = .allCompact
    private var highlightStates: [ObjectIdentifier: HighlightState] = [:]
    private weak var currentlyHighlightedItem: NSMenuItem?
    var showSavedInTopMenu: Bool {
        get {
            if UserDefaults.standard.object(forKey: "ShowSavedInTopMenu") == nil { return true }
            return UserDefaults.standard.bool(forKey: "ShowSavedInTopMenu")
        }
        set { UserDefaults.standard.set(newValue, forKey: "ShowSavedInTopMenu") }
    }
    var latestQuota: GeminiQuota?
    var accountQuotas: [String: QuotaFetcher.CloudAccountQuota] = [:]
    var accountErrors: [String: String] = [:]
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

        QuotaAlertManager.shared.setup()

        // Follow the model selected in the Antigravity App (for the Auto style)
        ModelTracker.shared.onChange = { [weak self] in
            guard let self = self, let quota = self.activeQuotaForStatusBar() else { return }
            if self.currentFormat == .auto { self.updateStatusBarTitle(quota: quota) }
            self.buildMenu()
        }
        ModelTracker.shared.start()

        // Follow active Antigravity App / IDE window and account changes
        AccountManager.shared.onFocusOrAccountsChanged = { [weak self] in
            guard let self = self else { return }
            ModelTracker.shared.syncToClient(AccountManager.shared.lastActiveClient)
            if let quota = self.activeQuotaForStatusBar() {
                self.latestQuota = quota
                self.updateStatusBarTitle(quota: quota)
            }
            self.buildMenu()
        }
        AccountManager.shared.refreshDetectedClientEmails()

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

    private func activeQuotaForStatusBar() -> GeminiQuota? {
        if let activeEmail = AccountManager.shared.activeAccountEmail(),
           let cloud = accountQuotas[activeEmail.lowercased()] {
            return cloud.quota
        }
        return latestQuota
    }

    private func activeBadgeForStatusBar() -> String? {
        guard AccountManager.shared.showBadgeInMenuBar,
              !AccountManager.shared.accounts.isEmpty,
              let email = AccountManager.shared.activeAccountEmail() else {
            return nil
        }
        return AccountManager.shared.shortBadge(for: email)
    }

    @objc func fetchData() {
        guard !isFetching else { return }
        isFetching = true

        AccountManager.shared.refreshDetectedClientEmails()
        let cloudAccounts = AccountManager.shared.accounts

        if !cloudAccounts.isEmpty {
            QuotaFetcher.shared.fetchAllCloudQuotas(accounts: cloudAccounts) { [weak self] results in
                guard let self = self else { return }
                self.isFetching = false

                for (key, res) in results {
                    switch res {
                    case .success(let cq):
                        self.accountQuotas[key] = cq
                        self.accountErrors.removeValue(forKey: key)
                    case .failure(let err):
                        self.accountErrors[key] = err.localizedDescription
                    }
                }

                if let quota = self.activeQuotaForStatusBar() {
                    self.latestQuota = quota
                    QuotaAlertManager.shared.evaluate(quota: quota)
                    self.cacheQuota(quota)
                    self.updateStatusBarTitle(quota: quota)
                }
                self.buildMenu()
                self.startTimer(interval: self.refreshInterval)
            }
            return
        }

        QuotaFetcher.shared.fetchQuota { [weak self] result in
            guard let self = self else { return }
            self.isFetching = false
            switch result {
            case .success(let quota):
                self.latestQuota = quota
                QuotaAlertManager.shared.evaluate(quota: quota)
                self.cacheQuota(quota)
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

    private func cacheQuota(_ quota: GeminiQuota) {
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
    }

    /// Sets the menu bar icon (template image, adapts to light/dark) and text.
    func setStatusBar(icon: Icon, text: String) {
        guard let button = statusItem.button else { return }
        button.image = iconImage(icon, size: 14, weight: .medium)
        button.title = text.isEmpty ? "" : " " + text
    }

    func withSavedSuffix(_ segments: [StatusSegment]) -> [StatusSegment] {
        guard showSavedInTopMenu,
              let badge = LocalSavingsManager.shared.topMenuBadge(),
              !segments.isEmpty else {
            return segments
        }
        var updated = segments
        let last = updated[updated.count - 1]
        updated[updated.count - 1] = StatusSegment(icon: last.icon, text: "\(last.text) | \(badge)")
        return updated
    }

    func updateStatusBarTitle(quota: GeminiQuota) {
        let segments = withSavedSuffix(currentFormat.segments(quota: quota))
        guard !segments.isEmpty, let button = statusItem.button else {
            setStatusBar(icon: .antigravity, text: "—")
            return
        }
        button.image = renderSegments(segments, height: NSStatusBar.system.thickness, prefixBadge: activeBadgeForStatusBar())
        button.title = ""
    }

    /// Centers and aspect-fits any menu icon into a uniform box so all rows share identical icon-to-text spacing.
    private func normalizedMenuIcon(_ img: NSImage?, boxSize: NSSize = NSSize(width: 15, height: 15), isTemplate: Bool? = nil) -> NSImage {
        let canvas = NSImage(size: boxSize, flipped: false) { _ in
            if let img = img, img.size.width > 0, img.size.height > 0 {
                let scale = min(1.0, min(boxSize.width / img.size.width, boxSize.height / img.size.height))
                let drawW = img.size.width * scale
                let drawH = img.size.height * scale
                let x = (boxSize.width - drawW) / 2.0
                let y = (boxSize.height - drawH) / 2.0
                img.draw(in: NSRect(x: x, y: y, width: drawW, height: drawH))
            }
            return true
        }
        canvas.isTemplate = isTemplate ?? (img?.isTemplate ?? true)
        return canvas
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
            let raw = iconImage(icon, size: symbolSize, color: symbolColor)
            item.image = raw.map { normalizedMenuIcon($0) }
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

    /// Native macOS continuous track bar:
    /// Subtle background line shows total capacity, solid foreground line shows remaining quota.
    func renderTrackBar(percent: Int, width: CGFloat = 38, height: CGFloat = 10, highlighted: Bool = false) -> NSAttributedString {
        let capHeight = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular).capHeight
        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let trackH: CGFloat = 3.0
            // NSTextAttachmentCell aligns image bottom to text baseline, so center on font capHeight.
            let trackY = max(0, min(rect.height - trackH, (capHeight - trackH) / 2.0))
            let radius = trackH / 2.0

            // 1. Subtle background track line (shows total quota capacity)
            let trackPath = NSBezierPath(roundedRect: NSRect(x: 0, y: trackY, width: width, height: trackH), xRadius: radius, yRadius: radius)
            let trackColor = highlighted ? NSColor.white.withAlphaComponent(0.35) : NSColor.labelColor.withAlphaComponent(0.18)
            trackColor.setFill()
            trackPath.fill()

            // 2. System Accent color filled line (or white when row is highlighted)
            let pctClamped = CGFloat(max(0, min(100, percent))) / 100.0
            if pctClamped > 0 {
                let fillW = max(trackH, width * pctClamped)
                let fillPath = NSBezierPath(roundedRect: NSRect(x: 0, y: trackY, width: fillW, height: trackH), xRadius: radius, yRadius: radius)
                let fillColor = highlighted ? NSColor.white : NSColor.controlAccentColor
                fillColor.setFill()
                fillPath.fill()
            }

            return true
        }
        img.isTemplate = false

        let cell = NSTextAttachmentCell(imageCell: img)
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        return NSAttributedString(attachment: attachment)
    }

    /// 5-segment bar fallback (legacy).
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

    private struct CompactRowLayout {
        let font: NSFont
        let boldFont: NSFont
        let barW: CGFloat
        let para: NSParagraphStyle

        init(names: [String], windows: [String]) {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            let boldFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            func w(_ s: String) -> CGFloat { ceil((s as NSString).size(withAttributes: [.font: boldFont]).width) }

            let gap: CGFloat = 6
            let nameW = names.map(w).max() ?? 0
            let winW = windows.map(w).max() ?? 0
            let barW: CGFloat = 38
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
            self.font = font
            self.boldFont = boldFont
            self.barW = barW
            self.para = para
        }
    }

    /// One row per bucket, columns pinned with tab stops so every column
    /// (name, window, bar, percent, countdown) lines up regardless of glyph widths:
    ///   Gemini  5h  ▮▮▮▮▯   78%  1h28m
    ///           Wk  ▮▮▯▯▯   38%  2d2h
    /// Model list and exact reset time are in the row tooltip.
    private func addCompactRows(to menu: NSMenu, groups: [ModelGroupInfo], activeModelKind: GroupKind? = nil, layout: CompactRowLayout? = nil) {
        let names = groups.map { shortGroupName($0.displayName) }
        let resolvedLayout = layout ?? CompactRowLayout(names: names, windows: ["5h", "Wk"])
        let font = resolvedLayout.font
        let boldFont = resolvedLayout.boldFont
        let barW = resolvedLayout.barW
        let para = resolvedLayout.para
        let baseAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let boldAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]

        // Logos padded to one common width so titles stay aligned; continuation rows get a blank of that width.
        let rawLogos = groups.map { iconImage(groupIcon($0.displayName), size: 13) }
        let logos = zip(groups, rawLogos).map { (g, img) -> NSImage? in
            let isActiveGroup = (activeModelKind != nil && groupKind(g.displayName) == activeModelKind)
            guard let img = img else { return nil }
            if isActiveGroup {
                let tinted = NSImage(size: img.size, flipped: false) { rect in
                    img.draw(in: rect)
                    NSColor.controlAccentColor.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.isTemplate = false
                return tinted
            }
            return img
        }
        let blank = normalizedMenuIcon(nil, isTemplate: true)

        for (gi, (group, name)) in zip(groups, names).enumerated() {
            let models = groupModels(group)
            let isActiveGroup = (activeModelKind != nil && groupKind(group.displayName) == activeModelKind)
            let logo = normalizedMenuIcon(logos[gi], isTemplate: !isActiveGroup)
            let highlightedLogo = normalizedMenuIcon(rawLogos[gi], isTemplate: true)
            for (i, b) in group.buckets.enumerated() {
                let cd = formatFullCountdown(from: b.resetTime)
                let cdShort = cd?.short.replacingOccurrences(of: " ", with: "") ?? ""

                func makeRowTitle(highlighted: Bool) -> NSAttributedString {
                    let s = NSMutableAttributedString()
                    let nameAttrs = isActiveGroup ? boldAttrs : baseAttrs
                    s.append(NSAttributedString(string: i == 0 ? name : "", attributes: nameAttrs))
                    s.append(NSAttributedString(string: "\t\(windowLabel(b))\t", attributes: secondaryAttrs))
                    s.append(renderTrackBar(percent: b.percent, width: barW, highlighted: highlighted))
                    s.append(NSAttributedString(string: "\t\(b.percent)%", attributes: boldAttrs))
                    s.append(NSAttributedString(string: "\t\(cdShort)", attributes: secondaryAttrs))
                    return s
                }

                let normalTitle = makeRowTitle(highlighted: false)
                let highlightedTitle = makeRowTitle(highlighted: true)
                let normalImg = i == 0 ? logo : blank
                let highlightedImg = i == 0 ? highlightedLogo : blank

                let item = NSMenuItem()
                item.attributedTitle = normalTitle
                item.image = normalImg
                if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
                highlightStates[ObjectIdentifier(item)] = HighlightState(
                    normalTitle: normalTitle,
                    highlightedTitle: highlightedTitle,
                    normalImage: normalImg,
                    highlightedImage: highlightedImg
                )
                var tip = [group.displayName + (models.isEmpty ? "" : " (\(models))")]
                if let cd = cd { tip.append("\(b.displayName): resets in \(cd.detailed) (\(cd.absolute))") }
                else if !b.description.isEmpty { tip.append(b.description) }
                if windowLabel(b) == "Wk" {
                    let used = QuotaAlertManager.shared.weeklyUsedToday(for: group.displayName, currentWeeklyPercent: b.percent)
                    if used > 0 { tip.append("Used today: -\(used)%") }
                }
                item.toolTip = tip.joined(separator: "\n")
                menu.addItem(item)
            }
        }
    }

    /// Appends `(item1 · item2)` with gray parentheses/dots and accent-colored active items (white when highlighted).
    private func appendBadgeList(
        _ items: [(text: String, isActive: Bool)],
        font: NSFont,
        highlighted: Bool,
        to target: NSMutableAttributedString
    ) {
        guard !items.isEmpty else { return }
        let grayAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        target.append(NSAttributedString(string: "(", attributes: grayAttrs))
        for (idx, entry) in items.enumerated() {
            if idx > 0 {
                target.append(NSAttributedString(string: " · ", attributes: grayAttrs))
            }
            let color: NSColor = entry.isActive ? (highlighted ? .white : .controlAccentColor) : .secondaryLabelColor
            target.append(NSAttributedString(string: entry.text, attributes: [.font: font, .foregroundColor: color]))
        }
        target.append(NSAttributedString(string: ")", attributes: grayAttrs))
    }

    /// Separate section showing today's output token savings from local (Mac) and free cloud models.
    private func addLocalSavingsSection(to menu: NSMenu, layout: CompactRowLayout? = nil) {
        let mgr = LocalSavingsManager.shared
        let savings = mgr.currentSavings()

        // Header matching account header style
        let headerFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let providers = mgr.configuredProviders()
        let providerItems = providers.map { (text: $0, isActive: savings.activeProviders.contains($0)) }
        let hasActiveProvider = providerItems.contains { $0.isActive }

        func buildHeaderTitle(highlighted: Bool) -> NSAttributedString {
            let s = NSMutableAttributedString()
            s.append(NSAttributedString(string: "Local and Free", attributes: [.font: headerFont, .foregroundColor: NSColor.secondaryLabelColor]))
            if !providerItems.isEmpty {
                s.append(NSAttributedString(string: "  ·  ", attributes: [.font: headerFont, .foregroundColor: NSColor.secondaryLabelColor]))
                appendBadgeList(providerItems, font: headerFont, highlighted: highlighted, to: s)
            }
            return s
        }

        let normalHeaderTitle = buildHeaderTitle(highlighted: false)
        let headerItem = NSMenuItem(title: "Local and Free", action: nil, keyEquivalent: "")
        headerItem.attributedTitle = normalHeaderTitle
        headerItem.toolTip = mgr.summaryTooltip(for: savings)
        if hasActiveProvider {
            highlightStates[ObjectIdentifier(headerItem)] = HighlightState(
                normalTitle: normalHeaderTitle,
                highlightedTitle: buildHeaderTitle(highlighted: true),
                normalImage: nil,
                highlightedImage: nil
            )
        }
        menu.addItem(headerItem)

        let rows: [(name: String, icon: Icon, window: String, percent: Int, tokens: Int)] = [
            ("Mac", .sf("laptopcomputer"), "Day", savings.localPercent, savings.localOutputTokens),
            ("Cloud", .sf("cloud"), "Day", savings.freeCloudPercent, savings.freeCloudOutputTokens)
        ]

        let resolvedLayout = layout ?? CompactRowLayout(names: rows.map(\.name), windows: ["5h", "Wk", "Day"])
        let font = resolvedLayout.font
        let boldFont = resolvedLayout.boldFont
        let barW = resolvedLayout.barW
        let para = resolvedLayout.para
        let baseAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let boldAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]

        let icons = rows.map { iconImage($0.icon, size: 13) }

        let summaryTip = mgr.summaryTooltip(for: savings)
        for (idx, row) in rows.enumerated() {
            func makeRowTitle(highlighted: Bool) -> NSAttributedString {
                let s = NSMutableAttributedString()
                s.append(NSAttributedString(string: row.name, attributes: baseAttrs))
                s.append(NSAttributedString(string: "\t\(row.window)\t", attributes: secondaryAttrs))
                s.append(renderTrackBar(percent: row.percent, width: barW, highlighted: highlighted))
                s.append(NSAttributedString(string: "\t\(row.percent)%", attributes: boldAttrs))
                s.append(NSAttributedString(string: "\t\(mgr.formatK(row.tokens))", attributes: secondaryAttrs))
                return s
            }

            let normalTitle = makeRowTitle(highlighted: false)
            let highlightedTitle = makeRowTitle(highlighted: true)
            let img = normalizedMenuIcon(icons[idx], isTemplate: true)

            let item = NSMenuItem()
            item.attributedTitle = normalTitle
            item.image = img
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            highlightStates[ObjectIdentifier(item)] = HighlightState(
                normalTitle: normalTitle,
                highlightedTitle: highlightedTitle,
                normalImage: img,
                highlightedImage: img
            )
            item.toolTip = summaryTip
            menu.addItem(item)
        }
    }

    /// "Model: M319 → Claude and GPT Models" with a submenu to assign the
    /// current code to a group and to view / clear the learned code table.
    func makeModelItem() -> NSMenuItem {
        let tracker = ModelTracker.shared
        if let name = tracker.currentDisplayName, let kind = tracker.currentKind {
            return makeItem("Model: \(name)", icon: kind.icon)
        } else if let code = tracker.currentCode {
            let short = code.replacingOccurrences(of: "MODEL_PLACEHOLDER_", with: "")
            let kind = tracker.currentKind
            return makeItem("Model: \(short)", icon: kind?.icon ?? .sf("questionmark.circle"))
        } else {
            return makeItem("Model: App not detected", icon: .sf("questionmark.circle"))
        }
    }

    private func makeAccountHeaderItem(account: StoredAccount, isActive: Bool, cloud: QuotaFetcher.CloudAccountQuota?) -> NSMenuItem {
        let dot = isActive ? "● " : "○ "
        let tier = cloud?.subscriptionTier ?? account.subscriptionTier
        let credits = cloud?.credits ?? account.credits
        var metaParts: [String] = []
        if let tier = tier, !tier.isEmpty { metaParts.append(tier) }
        if let credits = credits {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            let crStr = fmt.string(from: NSNumber(value: credits)) ?? "\(credits)"
            metaParts.append("\(crStr) cr")
        }
        let clientKinds = AccountManager.shared.clientBadges(for: account.email)
        let clientItems = clientKinds.map { (text: $0.badge, isActive: isActive) }

        let font = isActive
            ? NSFont.systemFont(ofSize: 12, weight: .semibold)
            : NSFont.systemFont(ofSize: 12, weight: .regular)
        let emailColor: NSColor = isActive ? .labelColor : .secondaryLabelColor
        let dotColor: NSColor = isActive ? .controlAccentColor : .secondaryLabelColor

        func buildTitle(highlighted: Bool) -> NSAttributedString {
            let s = NSMutableAttributedString()
            let curDotColor = (isActive && highlighted) ? NSColor.white : dotColor
            s.append(NSAttributedString(string: dot, attributes: [.font: font, .foregroundColor: curDotColor]))
            s.append(NSAttributedString(string: account.email, attributes: [.font: font, .foregroundColor: emailColor]))
            if !metaParts.isEmpty {
                s.append(NSAttributedString(string: "  ·  " + metaParts.joined(separator: " · "), attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            }
            if !clientItems.isEmpty {
                s.append(NSAttributedString(string: "  ·  ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
                appendBadgeList(clientItems, font: font, highlighted: highlighted, to: s)
            }
            return s
        }

        let normalTitle = buildTitle(highlighted: false)
        let item = NSMenuItem(title: account.email, action: nil, keyEquivalent: "")
        item.attributedTitle = normalTitle
        if isActive {
            highlightStates[ObjectIdentifier(item)] = HighlightState(
                normalTitle: normalTitle,
                highlightedTitle: buildTitle(highlighted: true),
                normalImage: nil,
                highlightedImage: nil
            )
        }
        return item
    }

    private func makeFocusSubmenuItem() -> NSMenuItem {
        let mgr = AccountManager.shared
        let focusMenu = NSMenu()

        let autoItem = makeItem("Auto (Follow Active App / IDE)", action: #selector(selectFocusAuto))
        autoItem.state = (mgr.focusMode == .auto) ? .on : .off
        focusMenu.addItem(autoItem)

        for acc in mgr.accounts {
            let item = makeItem("Pin: \(acc.email)", action: #selector(selectFocusPinned(_:)))
            item.representedObject = acc.email
            if case .pinned(let pinned) = mgr.focusMode, pinned.lowercased() == acc.key {
                item.state = .on
            } else {
                item.state = .off
            }
            focusMenu.addItem(item)
        }

        focusMenu.addItem(NSMenuItem.separator())

        let badgeItem = makeItem("Show Account Badge in Menu Bar", action: #selector(toggleAccountBadge))
        badgeItem.state = mgr.showBadgeInMenuBar ? .on : .off
        focusMenu.addItem(badgeItem)

        focusMenu.addItem(makeItem("Add Account (Google Sign-In)…", action: #selector(addGoogleAccount)))

        if !mgr.accounts.isEmpty {
            let removeMenu = NSMenu()
            for acc in mgr.accounts {
                let rItem = makeItem(acc.email, action: #selector(removeGoogleAccount(_:)))
                rItem.representedObject = acc.email
                removeMenu.addItem(rItem)
            }
            let removeSubmenu = makeItem("Remove Account")
            removeSubmenu.submenu = removeMenu
            focusMenu.addItem(removeSubmenu)
        }

        let focusValue: String
        switch mgr.focusMode {
        case .auto:
            focusValue = mgr.accounts.isEmpty ? "Add Account" : "Auto (\(mgr.lastActiveClient.badge))"
        case .pinned(let email):
            focusValue = email.split(separator: "@").first.map(String.init) ?? email
        }
        let item = makeItem("Focus: \(focusValue)", icon: .sf("person.crop.circle"))
        item.submenu = focusMenu
        return item
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        if let prev = currentlyHighlightedItem,
           let state = highlightStates[ObjectIdentifier(prev)] {
            prev.attributedTitle = state.normalTitle
            prev.image = state.normalImage
        }
        currentlyHighlightedItem = item
        if let item = item,
           let state = highlightStates[ObjectIdentifier(item)] {
            item.attributedTitle = state.highlightedTitle
            item.image = state.highlightedImage
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if let prev = currentlyHighlightedItem,
           let state = highlightStates[ObjectIdentifier(prev)] {
            prev.attributedTitle = state.normalTitle
            prev.image = state.normalImage
        }
        currentlyHighlightedItem = nil
    }

    func buildMenu() {
        highlightStates.removeAll()
        currentlyHighlightedItem = nil
        let menu = NSMenu()
        menu.delegate = self
        // Info rows have no action; without this AppKit draws them as disabled (faded gray).
        menu.autoenablesItems = false

        let cloudAccounts = AccountManager.shared.accounts
        let savingsEnabled = LocalSavingsManager.shared.isEnabled
        var allRowNames: [String] = savingsEnabled ? ["Mac", "Cloud"] : []
        if !cloudAccounts.isEmpty {
            for account in cloudAccounts {
                if let cloud = accountQuotas[account.key] {
                    allRowNames.append(contentsOf: statusGroups(cloud.quota).map { shortGroupName($0.displayName) })
                }
            }
        } else if let quota = latestQuota {
            allRowNames.append(contentsOf: statusGroups(quota).map { shortGroupName($0.displayName) })
        }
        let allWindows = savingsEnabled ? ["5h", "Wk", "Day"] : ["5h", "Wk"]
        let rowLayout = CompactRowLayout(names: allRowNames, windows: allWindows)

        if !cloudAccounts.isEmpty {
            let activeEmail = AccountManager.shared.activeAccountEmail()?.lowercased()
            let ordered = cloudAccounts.sorted { a, b in
                (a.key == activeEmail) && (b.key != activeEmail)
            }
            for account in ordered {
                let isActive = (account.key == activeEmail)
                let cloud = accountQuotas[account.key]
                menu.addItem(makeAccountHeaderItem(account: account, isActive: isActive, cloud: cloud))
                if let cloud = cloud {
                    addCompactRows(to: menu,
                                   groups: statusGroups(cloud.quota),
                                   activeModelKind: isActive ? ModelTracker.shared.currentKind : nil,
                                   layout: rowLayout)
                } else if let err = accountErrors[account.key] {
                    menu.addItem(makeItem("Error: \(err)",
                                          icon: .sf("exclamationmark.triangle"),
                                          symbolColor: .systemOrange,
                                          attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
                } else {
                    menu.addItem(makeItem("Loading quota…", icon: .sf("hourglass")))
                }
                menu.addItem(NSMenuItem.separator())
            }
        } else if let quota = latestQuota {
            let groups = statusGroups(quota)
            addCompactRows(to: menu, groups: groups, layout: rowLayout)
            menu.addItem(NSMenuItem.separator())
        } else {
            menu.addItem(makeItem("Loading quota information…", icon: .sf("hourglass")))
            menu.addItem(NSMenuItem.separator())
        }

        if savingsEnabled {
            addLocalSavingsSection(to: menu, layout: rowLayout)
            menu.addItem(NSMenuItem.separator())
        }

        // Format submenu ("Top Menu Style")
        let formatMenu = NSMenu()
        for fmt in DisplayFormat.allCases {
            let item = makeItem(fmt.title, action: #selector(changeFormat(_:)))
            // Live preview of how this style looks with the current numbers
            if let quota = latestQuota {
                let segments = withSavedSuffix(fmt.segments(quota: quota))
                // Auto keeps its name (its preview would duplicate another style);
                // the other styles show only the preview, without a text label.
                if !segments.isEmpty && fmt != .auto {
                    item.image = renderSegments(segments, height: 16, fontSize: 12)
                    item.image?.accessibilityDescription = fmt.title
                    item.title = ""
                    if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
                }
            }
            item.tag = fmt.rawValue
            item.state = (fmt == currentFormat) ? .on : .off
            formatMenu.addItem(item)
        }
        if LocalSavingsManager.shared.isConfigured {
            formatMenu.addItem(NSMenuItem.separator())
            let badgeExample = LocalSavingsManager.shared.topMenuBadge() ?? "(+0%)"
            let savedTopItem = makeItem("Saved % | \(badgeExample)", action: #selector(toggleShowSavedInTopMenu(_:)))
            savedTopItem.state = showSavedInTopMenu ? .on : .off
            formatMenu.addItem(savedTopItem)
        }

        let formatSubmenuItem = makeItem("Top Menu Style", icon: .sf("eye"))
        formatSubmenuItem.submenu = formatMenu
        menu.addItem(formatSubmenuItem)

        // Account Focus & Multi-Account management
        menu.addItem(makeFocusSubmenuItem())

        // Current App model + model code table (used by the Auto style)
        menu.addItem(makeModelItem())

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

        // Refresh, with last-updated time dimmed on the same row
        let refreshItem = makeItem("Refresh", icon: .sf("arrow.clockwise"), action: #selector(fetchData))
        if let quota = latestQuota {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let timeStr = " · \(formatter.string(from: quota.lastUpdated))"
            let menuFont = NSFont.menuFont(ofSize: 0)
            let attr = NSMutableAttributedString(string: "Refresh", attributes: [.font: menuFont, .foregroundColor: NSColor.labelColor])
            attr.append(NSAttributedString(string: timeStr, attributes: [.font: menuFont, .foregroundColor: NSColor.secondaryLabelColor]))
            refreshItem.attributedTitle = attr
        }
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Toggles: no checkmarks; enabled = normal label color, disabled = dimmed gray
        let alertsOn = QuotaAlertManager.shared.isEnabled
        let alertsItem = makeItem("Alerts (5h & 20% Daily)",
                                  icon: .sf(alertsOn ? "bell.fill" : "bell"),
                                  symbolColor: alertsOn ? nil : .secondaryLabelColor,
                                  action: #selector(toggleAlerts(_:)),
                                  attributes: alertsOn ? nil : [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(alertsItem)

        if LocalSavingsManager.shared.isConfigured {
            let savingsOn = LocalSavingsManager.shared.isEnabled
            let savingsItem = makeItem("Local & Free Savings",
                                       icon: .sf(savingsOn ? "cpu.fill" : "cpu"),
                                       symbolColor: savingsOn ? nil : .secondaryLabelColor,
                                       action: #selector(toggleLocalSavings(_:)),
                                       attributes: savingsOn ? nil : [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor])
            menu.addItem(savingsItem)
        }

        let launchOn = isLaunchAtLoginEnabled()
        let launchItem = makeItem("Launch at Login",
                                  icon: .sf("power"),
                                  symbolColor: launchOn ? nil : .secondaryLabelColor,
                                  action: #selector(toggleLaunchAtLogin(_:)),
                                  attributes: launchOn ? nil : [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor])
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
        menu.addItem(makeItem("Antigravity Quota Bar",
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
        menu.addItem(makeFocusSubmenuItem())
        let refreshItem = makeItem("Retry Connection", icon: .sf("arrow.clockwise"), action: #selector(fetchData), key: "r")
        refreshItem.keyEquivalentModifierMask = .command
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = makeItem("Quit", icon: .sf("xmark.circle"), action: #selector(quitApp))
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func selectFocusAuto() {
        AccountManager.shared.setFocusMode(.auto)
    }

    @objc func selectFocusPinned(_ sender: NSMenuItem) {
        guard let email = sender.representedObject as? String else { return }
        AccountManager.shared.setFocusMode(.pinned(email))
    }

    @objc func toggleAccountBadge() {
        AccountManager.shared.setShowBadgeInMenuBar(!AccountManager.shared.showBadgeInMenuBar)
    }

    @objc func addGoogleAccount() {
        AccountManager.shared.startOAuthLogin { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success:
                self.fetchData()
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Google Sign-In Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc func removeGoogleAccount(_ sender: NSMenuItem) {
        guard let email = sender.representedObject as? String else { return }
        accountQuotas.removeValue(forKey: email.lowercased())
        accountErrors.removeValue(forKey: email.lowercased())
        AccountManager.shared.removeAccount(email: email)
        if AccountManager.shared.accounts.isEmpty {
            fetchData()
        }
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

    @objc func toggleAlerts(_ sender: NSMenuItem) {
        QuotaAlertManager.shared.isEnabled.toggle()
        buildMenu()
    }

    @objc func toggleLocalSavings(_ sender: NSMenuItem) {
        LocalSavingsManager.shared.isEnabled.toggle()
        if let quota = latestQuota {
            updateStatusBarTitle(quota: quota)
        }
        buildMenu()
    }

    @objc func toggleShowSavedInTopMenu(_ sender: NSMenuItem) {
        showSavedInTopMenu.toggle()
        if let quota = latestQuota {
            updateStatusBarTitle(quota: quota)
        }
        buildMenu()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch at Login Helper
    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/com.antigravity.antigravityquotabar.plist")
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
            let execPath = (appBundlePath as NSString).appendingPathComponent("Contents/MacOS/AntigravityQuotaBar")
            let plistContent = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.antigravity.antigravityquotabar</string>
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
