# Antigravity Quota Bar (macOS Menu Bar App)

Native macOS menu bar app that displays your remaining **Google Antigravity** model quotas in real time next to your Mac's clock, adapts automatically to the model selected in the Antigravity app, and warns you before you burn through your daily or 5-hour limits.

> **Upstream / Fork Attribution:**  
> Forked and customized from [`cursoraiht-maker/gemini_antigravity`](https://github.com/cursoraiht-maker/gemini_antigravity) (originally based on `alainjpdev/antigravityCounter`).

---

## ✨ Works Out of the Box (No Extra Setup)

Everything below works immediately after installing **Antigravity Quota Bar** — no extra scripts or local models required:

- **Native macOS Menu Bar UI**:
  - Written in Swift with AppKit / Cocoa (no Electron, minimal footprint).
  - Monochrome brand logos (Antigravity, Gemini, Claude, OpenAI) that adapt automatically to light and dark mode, paired with native SF Symbols.
- **Direct Local RPC & Multi-Account Support**:
  - Automatically discovers running Antigravity daemons (`agy` / `language_server`) and queries `RetrieveUserQuotaSummary` and `GetAvailableModels` via Connect-RPC over `127.0.0.1`.
  - Tracks quota per active Antigravity account.
- **Menu Bar Styles (Live Previews in `Style` submenu)**:
  - **`Auto (current model)`**: Detects the model currently selected in Antigravity and switches the menu bar to that model's quota group (falls back to all groups if unknown).
  - **`✦ 78% | 94%  ✱ 0% | 49%  ✦ Ar 100%`** — All groups compact.
  - **`✦ 78% (20m) | 94% (6d)`** — Gemini Models (`5h` | `weekly`).
  - **`✱ 0% (4h) | 49% (6d)`** — Claude & GPT Models (`5h` | `weekly`).
  - **`✦ Argon 100% (6d)`** — Gemini 4 Argon (`weekly`).
- **Compact Drop-Down Menu**:
  - Native progress bars, hover tooltips with model lists, exact reset date/time, and today's weekly quota usage (`Used today: -X%`).
  - Shows the currently active Antigravity model (e.g. `Model: Gemini 4 Hydrogen (Medium)`).
- **Daily Budget & 5-Hour Alerts**:
  - Native macOS notifications (`UNUserNotificationCenter`) when a group reaches **≤ 5% on 5h limit** or **≥ 20% of weekly quota used today** (toggleable via **Alerts**).
- **Instant Startup & Controls**:
  - Cached last state on launch, configurable refresh interval (`30s`, `1m`, `5m`), manual **Refresh**, and **Launch at Login** (`LaunchAgent`).

---

## 🧩 Optional: Local & Free-Cloud Token Savings (Requires External Scripts)

You can safely ignore this section if you only want quota monitoring.

- **What it does:** Displays your daily token savings percentage in parentheses (e.g. `(+85% saved)`) and a tooltip breakdown (`X local vs Y cloud tokens today`), toggleable via **Local Savings** in the menu.
- **What is required:** **Antigravity Quota Bar** only *reads* telemetry — it does not run local models by itself. To populate this metric, you need external helper scripts (`local_bridge.py` / `cli_meter.py` from `dev-suite` / SavingsBridge) configured with Ollama (`qwen2.5:7b` / `qwen2.5-coder:14b`) and/or free-cloud CLIs that log usage to `~/.gemini/antigravity/local_tokens.jsonl`.

---

## 🛠️ Requirements

- macOS 13.0 (Ventura) or later (Apple Silicon).
- Antigravity app / IDE running locally.
- *Optional (only for building from source):* Xcode Command Line Tools (`swiftc`).

---

## 🚀 Install

### Option 1: Download DMG (Recommended)
1. Download the latest `Antigravity Quota Bar-*.dmg` from [Releases](https://github.com/OleksandrChernysh/AntigravityQuotaBar/releases).
2. Open the `.dmg` and drag **Antigravity Quota Bar.app** to **Applications**.
3. Launch **Antigravity Quota Bar** (if macOS Gatekeeper asks on first run, right-click → **Open**).

### Option 2: Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/OleksandrChernysh/AntigravityQuotaBar.git
   cd AntigravityQuotaBar
   ```
2. Build the `.app` bundle:
   ```bash
   chmod +x build.sh
   ./build.sh
   ```
3. Install and launch:
   ```bash
   cp -R build/AntigravityQuotaBar.app "/Applications/Antigravity Quota Bar.app"
   open "/Applications/Antigravity Quota Bar.app"
   ```

---

## 📄 Project Structure

```text
├── Sources/
│   ├── AccountManager.swift      # Active Antigravity account detection
│   ├── AppDelegate.swift         # Menu bar rendering, styles, LaunchAgent, and UI
│   ├── LocalSavingsManager.swift # Optional reader for ~/.gemini/antigravity/local_tokens.jsonl
│   ├── ModelTracker.swift        # Active model detection via state file + RPC
│   ├── QuotaAlertManager.swift   # 5h exhaustion & 20% daily weekly-usage notifications
│   ├── QuotaFetcher.swift        # Daemon discovery and Connect-RPC quota queries
│   └── main.swift                # Accessory app entry point
├── Resources/
│   ├── AppIcon.icns              # macOS squircle icon with Antigravity logo & quota ring
│   └── Icons/                    # Brand SVG template icons + CREDITS.txt
├── build.sh                      # Native swiftc build script & .app packaging
├── .gitignore
└── README.md
```

---

## 🙏 Credits

- Upstream fork source: [`cursoraiht-maker/gemini_antigravity`](https://github.com/cursoraiht-maker/gemini_antigravity) (originally based on `alainjpdev/antigravityCounter`).
- Brand icons: LobeHub Icons (`@lobehub/icons-static-svg`, MIT) and Simple Icons (`googlegemini`, CC0 1.0). See [CREDITS.txt](Resources/Icons/CREDITS.txt).
