# Antigravity Counter ♊ (macOS Menu Bar App)

Native macOS menu bar (status bar) app that shows, in real time next to your Mac's clock, the remaining quota percentages for **Google Antigravity**:
- **Gemini 5-Hour Limit Remaining** (5-hour window)
- **Gemini Weekly Limit Remaining** (weekly limit)
- **Claude & GPT Models Quota** (5-hour window and weekly cycle)
- **Gemini 4 Argon Quota** (new frontier model with its own independent weekly quota)

---

## ✨ Features

- **Ultra-lightweight and native**: Written in Swift with Cocoa / AppKit (no Electron, no heavy dependencies).
- **Straight to the source**: Dynamically detects the local Antigravity daemons (`agy` or `language_server`) via Connect-RPC in milliseconds, with HTTP/HTTPS and CSRF token support.
- **Menu bar display**:
  - `♊ 5h: 78% (1h 28m) · Wk: 38% (2d 2h)` (or 10 configurable styles, with or without countdown).
- **Interactive drop-down menu**:
  - Dynamic model grouping: **Google Gemini**, **Claude and GPT**, and **Gemini 4 Argon**.
  - Color emoji health indicators (🟢 ≥ 50%, 🟡 20–50%, 🔴 < 20%).
  - **Exact reset countdown**: Shows the days and hours remaining for each metric (e.g. `⏳ 2d 2h`) plus the exact date/time (`Resets in 2 days, 2 hours (Sat 7 Nov, 01:31)`).
  - Manual refresh button (`⌘R`).
  - Configurable refresh interval (30s, 1m, 5m).
  - Option to launch automatically at login.
- **Instant startup**: Caches the latest values locally (`UserDefaults`) so they appear immediately after a restart.

---

## 🛠️ Requirements

- macOS 13.0 (Ventura) or later (tested on Apple Silicon M1/M2/M3/M4).
- Antigravity IDE installed.
- Xcode Command Line Tools (`swiftc`).

---

## 🚀 Build & Install

1. Clone the repository:
   ```bash
   git clone https://github.com/cursoraiht-maker/gemini_antigravity.git
   cd gemini_antigravity
   ```

2. Build the app:
   ```bash
   chmod +x GeminiQuotaBar/build.sh
   ./GeminiQuotaBar/build.sh
   ```

3. Install the app into your Applications folder:
   ```bash
   cp -r GeminiQuotaBar/build/GeminiQuotaBar.app /Applications/
   open /Applications/GeminiQuotaBar.app
   ```

---

## 📄 Project Structure

```text
├── GeminiQuotaBar/
│   ├── Sources/
│   │   ├── AppDelegate.swift    # Menu bar logic, UI, and LaunchAgent
│   │   ├── QuotaFetcher.swift   # Process detection and Connect-RPC query to Antigravity
│   │   └── main.swift           # Entry point for the accessory app
│   └── build.sh                 # Native build script and .app packaging
├── .gitignore
└── README.md
```
