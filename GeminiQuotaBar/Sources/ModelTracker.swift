import Foundation

/// Tracks the model currently selected in the Antigravity App.
///
/// The App stores the last selected agent model in
/// `~/.gemini/antigravity/antigravity_state.pbtxt` as an opaque code, e.g.
/// `last_selected_agent_model: MODEL_PLACEHOLDER_M319`. The code-to-name mapping
/// lives on Google's servers, so the user teaches us once which group each code
/// belongs to ("model code table"), stored in UserDefaults.
final class ModelTracker {
    static let shared = ModelTracker()

    /// Called on the main queue whenever the selected model code changes.
    var onChange: (() -> Void)?

    private(set) var currentCode: String?
    private var lastModified: Date?
    private var timer: Timer?
    private let mapKey = "ModelCodeMap"

    private var stateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity/antigravity_state.pbtxt")
    }

    /// Starts polling the state file (cheap: only the modification date is
    /// checked; the file is re-read only when it changes).
    func start() {
        check()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: stateURL.path)
        let modified = attrs?[.modificationDate] as? Date
        guard modified != lastModified || currentCode == nil else { return }
        lastModified = modified

        let code = readCode()
        if code != currentCode {
            currentCode = code
            onChange?()
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

    /// "MODEL_PLACEHOLDER_M319" -> "M319"
    static func shortCode(_ code: String) -> String {
        code.replacingOccurrences(of: "MODEL_PLACEHOLDER_", with: "")
    }

    // MARK: - Model code table

    var table: [String: GroupKind] {
        let raw = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        return raw.compactMapValues { GroupKind(rawValue: $0) }
    }

    func assign(_ code: String, to kind: GroupKind?) {
        var raw = UserDefaults.standard.dictionary(forKey: mapKey) as? [String: String] ?? [:]
        raw[code] = kind?.rawValue
        UserDefaults.standard.set(raw, forKey: mapKey)
    }

    func clearTable() {
        UserDefaults.standard.removeObject(forKey: mapKey)
    }

    /// Group of the currently selected model, if the code is in the table.
    var currentKind: GroupKind? {
        guard let code = currentCode else { return nil }
        return table[code]
    }
}
