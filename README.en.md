# EchoType

English | [繁體中文](./README.md)

> 🎙️ High-Precision Voice Input Tool - Open Source Alternative to Typeless App

EchoType is a voice-to-text application designed for macOS, powered by Whisper Turbo engine, supporting mixed Chinese-English input, multilingual recognition, and AI-powered text polishing.

## ✨ Core Features

- **🎯 High-Precision Speech Recognition**
  - Whisper Turbo (CoreML) - Optimized for Apple Silicon
  - Qwen3-ASR 0.6B (MLX) - Lightweight multilingual support
  - Mixed Chinese-English input, automatic language detection

- **🤖 AI-Powered Text Polishing**
  - Cloud API support (Groq / OpenAI / Anthropic)
  - Multilingual output (Traditional/Simplified Chinese, English, etc.)
  - Regional terminology adaptation (Taiwan/Hong Kong/Mainland China)

- **🔧 Advanced Features**
  - Context Injection - Improves accuracy based on application context
  - History Management - Auto-grouping and search
  - Injection Failure Fallback - Auto-display copy button
  - Launch at Login - Background resident

## 🏗️ Architecture

```
EchoType/
├── CoreKit/          # Swift Core Framework
│   ├── ASR/         # Speech Recognition Engine
│   ├── AI/          # AI Polishing Module
│   ├── Audio/       # Audio Management
│   ├── Context/     # Context Reader
│   └── Database/    # Local Database
├── helper/          # Swift CLI Bridge
└── desktop/         # Tauri + React Desktop App
    ├── src/         # React UI
    └── src-tauri/   # Rust Backend
```

### Tech Stack

- **Frontend**: React 18 + TypeScript + Vite
- **Backend**: Rust (Tauri v2)
- **Core**: Swift 6.0 + Actor Concurrency
- **ASR**: Whisper.cpp (CoreML) / MLX
- **Database**: GRDB.swift (SQLite)

## 🚀 Quick Start

### System Requirements

- macOS 13.0+ (Ventura or later)
- Apple Silicon (M1/M2/M3) or Intel chip
- 8GB RAM or more

### Installation

1. Download the latest DMG from [Releases](https://github.com/atonnyshen/EchoType/releases)
2. Drag to Applications folder
3. Follow the onboarding guide to grant necessary permissions on first launch:
   - Microphone permission (for voice recording)
   - Accessibility permission (for text injection and context reading)
   - Input Monitoring permission (for global hotkey)

### Usage

1. Press **fn (Globe 🌐)** key to start recording
   - **Push-to-talk mode**: Hold to record, release to stop
   - **Toggle mode**: Press once to start, press again to stop
2. After speaking, text will be automatically injected into the current application
3. If injection fails, a copy button will be displayed automatically

## ⚙️ Settings

### Speech Recognition

- **Input Language**: Recommended to use "Auto Detect"
- **ASR Engine**: Whisper Turbo (high accuracy) or Qwen3 (lightweight)

### AI Polishing

1. Choose cloud API provider (Groq recommended)
2. Get API Key: [console.groq.com](https://console.groq.com)
3. Set output language preference (Traditional Chinese-Taiwan / Simplified Chinese / English, etc.)

### Privacy Settings

- **History Retention**: 7 days / 30 days / 90 days / 1 year / Forever
- **Launch at Login**: Background resident, always available

## 🔒 Privacy Protection

- ✅ Speech recognition runs entirely locally
- ✅ History stored in local SQLite database
- ✅ AI polishing uses encrypted HTTPS connection
- ✅ No user data collection

## 📦 Version Information

**Current Version**: v0.2.1

### v0.2.1 Updates

- ✅ **Added webTitle field** - Complete web page title recording
- ✅ **Improved error handling** - Friendly alerts for dictionary save failures
- ✅ **Empty history feedback** - Sound notification when pasting empty history
- ✅ **Critical Bug Fixes**
  - Fixed hotkey_mode settings key mismatch
  - Fixed launch_at_login always returning false
  - Fixed missing hotkey field in get_settings
- ✅ **Code cleanup** - Removed dead code, fixed compiler warnings
- ✅ **Full test coverage** - All 32 automated tests passing

### Completed Features

- ✅ Core speech recognition (Whisper Turbo / Qwen3-ASR)
- ✅ AI polishing and multilingual support
- ✅ History management and search
- ✅ System integration (launch at login, hotkeys)
- ✅ Model auto-download mechanism
- ✅ Context Injection (context awareness)
- ✅ Permission management and onboarding flow

## 🛠️ Local Development

### Build CoreKit

```bash
cd CoreKit
swift build
```

### Build Helper

```bash
cd helper
swift build
```

### Run Desktop App

```bash
cd desktop
npm install
npm run tauri dev
```

## 📄 License

This is a private project and the source code is not currently open.

## 🙏 Acknowledgments

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance Whisper implementation
- [Tauri](https://tauri.app/) - Cross-platform desktop application framework
- [GRDB.swift](https://github.com/groue/GRDB.swift) - Swift SQLite toolkit

---

Made with ❤️ by [Atonny Shen](https://github.com/atonnyshen)
