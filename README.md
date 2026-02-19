# EchoType

[English](./README.en.md) | 繁體中文

> 🎙️ 高精度語音輸入工具 - Typeless App 的開源替代方案

EchoType 是一款專為 macOS 設計的語音轉文字應用，採用 Whisper Turbo 引擎，支援中英夾雜、多語言識別，並提供 AI 智能潤飾功能。

## ✨ 核心特性

- **🎯 高精度語音識別**
  - Whisper Turbo (CoreML) - Apple 晶片優化
  - Qwen3-ASR 0.6B (MLX) - 輕量多語言支援
  - 支援中英夾雜、自動語言偵測

- **🤖 AI 智能潤飾**
  - 雲端 API 支援（Groq / OpenAI / Anthropic）
  - 多語言輸出（繁體/簡體中文、英文等）
  - 地區用語自動調整（台灣/香港/中國大陸）

- **🔧 進階功能**
  - Context Injection - 根據應用場景提升準度
  - 歷史記錄管理 - 自動分組與搜尋
  - 注入失敗防呆 - 自動顯示複製按鈕
  - 開機自啟動 - 背景常駐

## 🏗️ 技術架構

```
EchoType/
├── CoreKit/          # Swift 核心框架
│   ├── ASR/         # 語音識別引擎
│   ├── AI/          # AI 潤飾模組
│   ├── Audio/       # 音訊管理
│   ├── Context/     # 上下文讀取
│   └── Database/    # 本地資料庫
├── helper/          # Swift CLI 橋接程式
└── desktop/         # Tauri + React 桌面應用
    ├── src/         # React UI
    └── src-tauri/   # Rust 後端
```

### 技術棧

- **前端**: React 18 + TypeScript + Vite
- **後端**: Rust (Tauri v2)
- **核心**: Swift 6.0 + Actor Concurrency
- **ASR**: Whisper.cpp (CoreML) / MLX
- **資料庫**: GRDB.swift (SQLite)

## 🚀 快速開始

### 系統需求

- macOS 13.0+ (Ventura 或更新版本)
- Apple Silicon (M1/M2/M3) 或 Intel 晶片
- 8GB RAM 以上

### 安裝

1. 從 [Releases](https://github.com/atonnyshen/EchoType/releases) 下載最新版本的 DMG
2. 拖曳到應用程式資料夾
3. 首次啟動時，跟隨引導流程授予必要權限：
   - 麥克風權限（語音錄製）
   - 輔助使用權限（文字注入與上下文讀取）
   - 輸入監控權限（全域快捷鍵）

### 使用方式

1. 按下 **fn (Globe 🌐)** 鍵開始錄音
   - **長按模式**：按住錄音，放開停止
   - **點按模式**：按一下開始，再按一下停止
2. 說話完畢後，文字會自動注入到當前應用程式
3. 如果注入失敗，會自動顯示複製按鈕

## ⚙️ 設定

### 語音識別

- **輸入語言**: 建議使用「自動偵測」
- **ASR 引擎**: Whisper Turbo（高精度）或 Qwen3（輕量）

### AI 潤飾

1. 選擇雲端 API 服務商（推薦 Groq）
2. 取得 API Key：[console.groq.com](https://console.groq.com)
3. 設定輸出語言偏好（繁體中文-台灣 / 簡體中文 / 英文等）

### 隱私設定

- **歷史記錄保留**: 7天 / 30天 / 90天 / 1年 / 永久
- **開機自啟**: 背景常駐，隨時可用

## 🔒 隱私保護

- ✅ 語音識別完全在本地執行
- ✅ 歷史記錄儲存在本地 SQLite 資料庫
- ✅ AI 潤飾使用加密 HTTPS 連線
- ✅ 不收集任何使用者數據

## 📦 版本資訊

**當前版本**: v0.2.1

### v0.2.1 更新內容

- ✅ **新增 webTitle 欄位** - 完整記錄網頁標題資訊
- ✅ **改進錯誤處理** - 詞典儲存失敗時顯示友善提示
- ✅ **空白歷史記錄提示** - 貼上空白歷史時播放提示音
- ✅ **修復關鍵 Bug**
  - 修正 hotkey_mode 設定鍵不一致問題
  - 修正 launch_at_login 永遠回傳 false 的問題
  - 修正 get_settings 缺少 hotkey 欄位的問題
- ✅ **程式碼清理** - 移除死碼、修復編譯警告
- ✅ **完整測試覆蓋** - 32 個自動化測試全數通過

### 已完成功能

- ✅ 核心語音識別功能（Whisper Turbo / Qwen3-ASR）
- ✅ AI 潤飾與多語言支援
- ✅ 歷史記錄管理與搜尋
- ✅ 系統整合（開機自啟、快捷鍵）
- ✅ 模型自動下載機制
- ✅ Context Injection（上下文感知）
- ✅ 權限管理與引導流程

## 🛠️ 本地開發

### 編譯 CoreKit

```bash
cd CoreKit
swift build
```

### 編譯 Helper

```bash
cd helper
swift build
```

### 執行桌面應用

```bash
cd desktop
npm install
npm run tauri dev
```

## 📄 授權

本專案為私人專案，暫不開放原始碼。

## 🙏 致謝

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) - 高效能 Whisper 實作
- [Tauri](https://tauri.app/) - 跨平台桌面應用框架
- [GRDB.swift](https://github.com/groue/GRDB.swift) - Swift SQLite 工具包

---

Made with ❤️ by [Atonny Shen](https://github.com/atonnyshen)
