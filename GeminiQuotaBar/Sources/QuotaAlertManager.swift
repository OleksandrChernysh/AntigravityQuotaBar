import Cocoa
import UserNotifications

/// Tracks daily weekly-quota consumption and 5-hour limit exhaustion per model
/// group, firing a macOS notification when a group reaches:
///   1) 5h limit exhausted (<= 5% remaining), once per 5h reset cycle
///   2) >= 20% of weekly quota used today, once per calendar day
final class QuotaAlertManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = QuotaAlertManager()

    private let enabledKey = "AlertsEnabled"
    private let dateKey = "AlertBaselineDate"
    private let baselinesKey = "AlertWeeklyBaselines"
    private let alertedDailyKey = "AlertedDailyGroups"
    private let alerted5hKey = "Alerted5hCycles"

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { requestPermission() }
        }
    }

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        if isEnabled {
            requestPermission()
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Shows notifications even if the accessory app happens to be frontmost.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    private func todayString() -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar.current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    /// Returns how many percentage points of weekly quota were used today for a group.
    func weeklyUsedToday(for groupDisplayName: String, currentWeeklyPercent: Int) -> Int {
        let key = shortGroupName(groupDisplayName)
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dateKey) == todayString(),
              let baselines = defaults.dictionary(forKey: baselinesKey) as? [String: Int],
              let base = baselines[key] else {
            return 0
        }
        return max(0, base - currentWeeklyPercent)
    }

    /// Evaluates freshly fetched quota data and sends notifications if thresholds are crossed.
    func evaluate(quota: GeminiQuota) {
        let groups = statusGroups(quota)
        guard !groups.isEmpty else { return }

        let defaults = UserDefaults.standard
        let today = todayString()

        var baselines = defaults.dictionary(forKey: baselinesKey) as? [String: Int] ?? [:]
        var alertedDaily = Set(defaults.stringArray(forKey: alertedDailyKey) ?? [])
        var alerted5h = defaults.dictionary(forKey: alerted5hKey) as? [String: String] ?? [:]

        // New calendar day: reset daily baselines and daily-alert flags.
        if defaults.string(forKey: dateKey) != today {
            baselines = [:]
            alertedDaily = []
            defaults.set(today, forKey: dateKey)
        }

        for group in groups {
            let groupKey = shortGroupName(group.displayName)
            let fiveHourBucket = group.buckets.first { windowLabel($0) == "5h" }
            let weeklyBucket = group.buckets.first { windowLabel($0) == "Wk" }

            var hit5h = false
            var hitDaily20 = false
            var usedToday = 0

            if let wk = weeklyBucket {
                if let existingBase = baselines[groupKey] {
                    if wk.percent > existingBase {
                        // Weekly quota reset occurred mid-day; adopt new baseline.
                        baselines[groupKey] = wk.percent
                    }
                } else {
                    baselines[groupKey] = wk.percent
                }
                let base = baselines[groupKey] ?? wk.percent
                usedToday = max(0, base - wk.percent)

                if usedToday >= 20 && !alertedDaily.contains(groupKey) {
                    hitDaily20 = true
                    alertedDaily.insert(groupKey)
                }
            }

            if let fh = fiveHourBucket {
                let cycleKey = fh.resetTime.isEmpty ? "active" : fh.resetTime
                if fh.percent <= 5 {
                    if alerted5h[groupKey] != cycleKey {
                        hit5h = true
                        alerted5h[groupKey] = cycleKey
                    }
                } else if fh.percent >= 50 && alerted5h[groupKey] != nil && alerted5h[groupKey] != cycleKey {
                    alerted5h.removeValue(forKey: groupKey)
                }
            }

            if isEnabled && (hit5h || hitDaily20) {
                sendNotification(
                    groupName: group.displayName,
                    groupKey: groupKey,
                    hit5h: hit5h,
                    fiveHour: fiveHourBucket,
                    hitDaily20: hitDaily20,
                    usedToday: usedToday,
                    weekly: weeklyBucket
                )
            }
        }

        defaults.set(baselines, forKey: baselinesKey)
        defaults.set(Array(alertedDaily), forKey: alertedDailyKey)
        defaults.set(alerted5h, forKey: alerted5hKey)
    }

    private func sendNotification(groupName: String,
                                  groupKey: String,
                                  hit5h: Bool,
                                  fiveHour: ModelBucketInfo?,
                                  hitDaily20: Bool,
                                  usedToday: Int,
                                  weekly: ModelBucketInfo?) {
        let content = UNMutableNotificationContent()
        content.sound = .default

        if hit5h && hitDaily20 {
            content.title = "\(groupName): 5h & 20% Daily Limit Reached"
        } else if hit5h {
            content.title = "\(groupName): 5h Limit Exhausted"
        } else {
            content.title = "\(groupName): 20% Daily Weekly Budget Reached"
        }

        var parts: [String] = []
        if hit5h, let fh = fiveHour {
            let cd = formatShortCountdown(from: fh.resetTime)
            let resetInfo = cd.isEmpty ? "" : " (resets in \(cd))"
            parts.append("5h: \(fh.percent)% left\(resetInfo)")
        }
        if hitDaily20, let wk = weekly {
            parts.append("Weekly: -\(usedToday)% today (\(wk.percent)% left)")
        }
        parts.append("Consider switching to another model group.")
        content.body = parts.joined(separator: "\n")

        let id = "quota-\(groupKey)-\(Date().timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
