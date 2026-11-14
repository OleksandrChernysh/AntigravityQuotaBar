# AntigravityQuotaBar (macOS Menu Bar App)

Native macOS menu bar app that displays your remaining **Google Antigravity** model quotas in real time next to your Mac's clock, automatically adapts to the model you currently have selected in the Antigravity app, and warns you before you burn through your daily or 5-hour limits.

> **Upstream / Fork Attribution:**  
> Forked and heavily customized from [`cursoraiht-maker/gemini_antigravity`](https://github.com/cursoraiht-maker/gemini_antigravity) (which was originally based on `alainjpdev/antigravityCounter`).

---

## ✨ Features

- **Native macOS design**:
  - Written in Swift with AppKit / Cocoa (no Electron, minimal footprint).
  - White macOS squircle app icon featuring the iridescent Antigravity logo and a matching quota ring.
  - Official monochrome brand logos (Antigravity, Gemini, Claude, OpenAI) rendered as template images that adapt automatically to light and dark mode, paired with native SF Symbols for menu actions (with explicit `preferredImageVisibility = .visible` support for macOS 27+).
- **Direct local RPC**:
  - Discovers running Antigravity daemons (`agy` / `language_server`) and queries `RetrieveUserQuotaSummary` and `GetAvailableModels` via Connect-RPC over `127.0.0.1` with CSRF token authentication.
- **Menu Bar Styles (Live Previews in `Style` submenu)**:
  - **`Auto (current model)`**: Automatically detects the model currently selected in the Antigravity app (via `antigravity_state.pbtxt` + `GetAvailableModels` RPC) and switches the menu bar to show that model's quota group (falls back to all groups if unknown).
  - **`✦ 78% | 94%  ✱ 0% | 49%  ✦ Ar 100%`** — All groups compact (no countdowns).
  - **`✦ 78% (20m) | 94% (6d)`** — Gemini Models (`5h` | `weekly` with short countdowns).
  - **`✱ 0% (4h) | 49% (6d)`** — Claude and GPT Models (`5h` | `weekly` with short countdowns).
  - **`✦ Argon 100% (6d)`** — Gemini 4 Argon (`weekly` with short countdown).
  - Each style item (except `Auto`) is rendered directly as a live preview using your current quota numbers, with no extra text labels.
- **Compact Drop-Down Menu**:
  - Continuous native vector progress bars with system accent color (`NSColor.controlAccentColor`) and 1% smoothness, with a subtle background track showing total capacity.
  - Hover tooltips with full model lists, exact reset date/time, and today's weekly quota usage (`Used today: -X%`).
  - Displays the currently active Antigravity model (e.g. `Model: Gemini 4 Hydrogen (Medium)`).
- **Local Model Token Savings (Ollama)**:
  - Tracks tokens generated locally for free via Ollama models (`qwen2.5-coder:14b`, `qwen2.5:7b`) and displays savings percentage in parentheses (e.g. `(+85% saved)`).
  - Hover tooltip displays detailed token breakdown (`X local vs Y cloud tokens today`).
  - Toggleable via **Local Savings (Ollama)** in the menu settings.
- **Daily Budget & 5-Hour Alerts**:
  - Sends native macOS notifications (`UNUserNotificationCenter`) when any group reaches:
    - **5h limit exhausted** (≤ 5% remaining, once per 5h cycle), or
    - **≥ 20% of weekly quota used today** (ideal ~20%/day pace for a 5-day work week, once per calendar day).
  - Toggleable via **Alerts (5h & 20% Daily)** in the menu.
- **Instant Startup & Controls**:
  - Caches latest quotas and groups in `UserDefaults` for instant display on launch.
  - Configurable refresh interval (`30s`, `1m`, `5m`), manual **Refresh**, and **Launch at Login** (`LaunchAgent`).

---

## 🛠️ Requirements

- macOS 13.0 (Ventura) or later (Apple Silicon).
- Antigravity app / IDE running locally.
- For building from source: Xcode Command Line Tools (`swiftc`).

---

## 🚀 Install

### Option 1: Download DMG (Recommended)
1. Download `AntigravityQuotaBar-v1.1.0.dmg` from [Releases](https://github.com/OleksandrChernysh/AntigravityQuotaBar/releases).
2. Open the `.dmg` and drag **AntigravityQuotaBar.app** to **Applications**.
3. Launch **AntigravityQuotaBar** (if macOS Gatekeeper asks on first run, right-click → **Open**).

### Option 2: Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/OleksandrChernysh/AntigravityQuotaBar.git
   cd AntigravityQuotaBar
   ```
2. Build the `.app` bundle:
   ```bash
   chmod +x GeminiQuotaBar/build.sh
   ./GeminiQuotaBar/build.sh
   ```
3. Install and launch:
   ```bash
   cp -R GeminiQuotaBar/build/AntigravityQuotaBar.app /Applications/
   open /Applications/AntigravityQuotaBar.app
   ```

---

## 📄 Project Structure

```text
├── GeminiQuotaBar/
│   ├── Sources/
│   │   ├── AppDelegate.swift        # Menu bar rendering, styles, LaunchAgent, and UI
│   │   ├── QuotaFetcher.swift       # Daemon discovery and Connect-RPC quota queries
│   │   ├── ModelTracker.swift       # Active model detection via state file + GetAvailableModels RPC
│   │   ├── QuotaAlertManager.swift  # 5h exhaustion & 20% daily weekly-usage macOS notifications
│   │   └── main.swift               # Accessory app entry point
│   ├── Resources/
│   │   ├── AppIcon.icns             # macOS squircle icon with iridescent Antigravity logo & quota ring
│   │   └── Icons/                   # Brand SVG template icons + CREDITS.txt
│   └── build.sh                     # Native swiftc build script & .app packaging
├── .gitignore
└── README.md
```

---

## 🙏 Credits

- Upstream fork source: [`cursoraiht-maker/gemini_antigravity`](https://github.com/cursoraiht-maker/gemini_antigravity) (originally based on `alainjpdev/antigravityCounter`).
- Brand icons: LobeHub Icons (`@lobehub/icons-static-svg`, MIT) and Simple Icons (`googlegemini`, CC0 1.0). See [CREDITS.txt](GeminiQuotaBar/Resources/Icons/CREDITS.txt).
