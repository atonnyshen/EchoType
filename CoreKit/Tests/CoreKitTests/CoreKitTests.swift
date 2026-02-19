import Testing
import Foundation
@testable import CoreKit

// MARK: - ASR Engine Type Tests

@Test func asrEngineTypeRawValues() async throws {
    #expect(ASREngineType.whisperTurbo.rawValue == "whisper_turbo")
    #expect(ASREngineType.qwen3ASR.rawValue == "qwen3_asr")
}

@Test func asrEngineTypeDisplayNames() async throws {
    #expect(ASREngineType.whisperTurbo.displayName == "Whisper Turbo (CoreML)")
    #expect(ASREngineType.qwen3ASR.displayName == "Qwen3-ASR 0.6B (MLX)")
}

@Test func asrEngineTypeFromRawValue() async throws {
    #expect(ASREngineType(rawValue: "whisper_turbo") == .whisperTurbo)
    #expect(ASREngineType(rawValue: "qwen3_asr") == .qwen3ASR)
    #expect(ASREngineType(rawValue: "invalid") == nil)
}

// MARK: - ASR Result Tests

@Test func asrResultInit() async throws {
    let result = ASRResult(text: "Hello", detectedLanguage: "en", confidence: 0.95, durationSeconds: 1.5)
    #expect(result.text == "Hello")
    #expect(result.detectedLanguage == "en")
    #expect(result.confidence == 0.95)
    #expect(result.durationSeconds == 1.5)
}

@Test func asrResultDefaults() async throws {
    let result = ASRResult(text: "Test", durationSeconds: 0.5)
    #expect(result.detectedLanguage == nil)
    #expect(result.confidence == 1.0)
}

// MARK: - ASR Error Tests

@Test func asrErrorDescriptions() async throws {
    #expect(ASRError.modelNotLoaded.errorDescription == "ASR 模型尚未載入")
    #expect(ASRError.modelNotFound("/path").errorDescription == "找不到模型: /path")
    #expect(ASRError.transcriptionFailed("timeout").errorDescription == "轉錄失敗: timeout")
    #expect(ASRError.invalidAudioFormat.errorDescription == "不支援的音訊格式")
}

// MARK: - Polisher Mode Tests

@Test func polisherModeRawValues() async throws {
    #expect(PolisherMode.cloud.rawValue == "cloud")
    #expect(PolisherMode.transcriptOnly.rawValue == "none")
}

@Test func polisherModeFromRawValue() async throws {
    #expect(PolisherMode(rawValue: "cloud") == .cloud)
    #expect(PolisherMode(rawValue: "none") == .transcriptOnly)
    #expect(PolisherMode(rawValue: "invalid") == nil)
}

// MARK: - Settings Key Tests

@Test func settingsKeyRawValues() async throws {
    #expect(SettingsKey.asrEngine.rawValue == "asrEngine")
    #expect(SettingsKey.polisherMode.rawValue == "polisherMode")
    #expect(SettingsKey.hotkey.rawValue == "hotkey")
    #expect(SettingsKey.selectedMic.rawValue == "selectedMicId")
    #expect(SettingsKey.inputLanguage.rawValue == "inputLanguage")
    #expect(SettingsKey.outputLanguage.rawValue == "outputLanguage")
    #expect(SettingsKey.apiKey.rawValue == "apiKey")
    #expect(SettingsKey.apiBaseUrl.rawValue == "apiBaseUrl")
    #expect(SettingsKey.launchAtLogin.rawValue == "launchAtLogin")
    #expect(SettingsKey.historyRetentionDays.rawValue == "historyRetentionDays")
    #expect(SettingsKey.personalDictionary.rawValue == "personalDictionary")
}

// MARK: - History Entry Tests

@Test func historyEntryDefaults() async throws {
    let entry = HistoryEntry(transcript: "Hello world")
    #expect(entry.transcript == "Hello world")
    #expect(entry.polishedText == nil)
    #expect(entry.editedText == nil)
    #expect(entry.appName == nil)
    #expect(entry.bundleId == nil)
    #expect(entry.windowTitle == nil)
    #expect(entry.webUrl == nil)
    #expect(entry.webDomain == nil)
    #expect(entry.webTitle == nil)
    #expect(entry.contextBefore == nil)
    #expect(entry.asrEngine == "whisper_turbo")
    #expect(entry.audioPath == nil)
    #expect(entry.durationSeconds == 0)
    #expect(entry.mode == "voice_transcript")
    #expect(!entry.id.isEmpty)
}

@Test func historyEntryFullInit() async throws {
    let entry = HistoryEntry(
        transcript: "你好世界",
        polishedText: "你好，世界！",
        appName: "Safari",
        bundleId: "com.apple.Safari",
        windowTitle: "Google Search",
        webUrl: "https://google.com",
        webDomain: "google.com",
        webTitle: "Google",
        asrEngine: "qwen3_asr",
        durationSeconds: 3.5,
        mode: "replace"
    )
    #expect(entry.appName == "Safari")
    #expect(entry.webTitle == "Google")
    #expect(entry.asrEngine == "qwen3_asr")
    #expect(entry.durationSeconds == 3.5)
    #expect(entry.mode == "replace")
}

@Test func historyEntryDisplayText() async throws {
    // transcript only
    let e1 = HistoryEntry(transcript: "raw")
    #expect(e1.displayText == "raw")

    // polished takes priority
    let e2 = HistoryEntry(transcript: "raw", polishedText: "polished")
    #expect(e2.displayText == "polished")

    // edited takes highest priority
    var e3 = HistoryEntry(transcript: "raw", polishedText: "polished")
    e3.editedText = "edited"
    #expect(e3.displayText == "edited")
}

@Test func historyEntryUniqueIds() async throws {
    let e1 = HistoryEntry(transcript: "a")
    let e2 = HistoryEntry(transcript: "b")
    #expect(e1.id != e2.id)
}

// MARK: - AppContext Tests

@Test func appContextMinimalPrompt() async throws {
    let ctx = AppContext(
        appName: "VS Code",
        windowTitle: "main.swift",
        webDomain: "github.com",
        contextBefore: "let x = 42"
    )
    let prompt = ctx.toMinimalPromptContext()
    #expect(prompt.contains("App: VS Code"))
    #expect(prompt.contains("網站: github.com"))
    #expect(prompt.contains("標題: main.swift"))
    #expect(prompt.contains("游標前文字"))
}

@Test func appContextMinimalPromptEmpty() async throws {
    let ctx = AppContext()
    let prompt = ctx.toMinimalPromptContext()
    #expect(prompt.isEmpty)
}

@Test func appContextWebTitleFallback() async throws {
    // When windowTitle is nil, webTitle should be used for 標題
    let ctx = AppContext(webTitle: "GitHub - EchoType")
    let prompt = ctx.toMinimalPromptContext()
    #expect(prompt.contains("標題: GitHub - EchoType"))
}

@Test func appContextTruncation() async throws {
    let longText = String(repeating: "a", count: 500)
    let ctx = AppContext(contextBefore: longText, contextAfter: longText)
    let prompt = ctx.toMinimalPromptContext()
    // contextBefore should be truncated to last 200 chars
    // contextAfter should be truncated to first 100 chars
    #expect(prompt.count < longText.count * 2)
}

// MARK: - SurroundingText Tests

@Test func surroundingTextDefaults() async throws {
    let st = SurroundingText()
    #expect(st.before.isEmpty)
    #expect(st.after.isEmpty)
    #expect(st.selected.isEmpty)
}

// MARK: - Injector Error Tests

@Test func injectorErrorDescriptions() async throws {
    #expect(InjectorError.accessibilityPermissionDenied.errorDescription == "需要無障礙功能權限")
    #expect(InjectorError.noFocusedElement.errorDescription == "找不到焦點輸入欄位")
    #expect(InjectorError.insertionFailed("test").errorDescription == "文字注入失敗: test")
}

// MARK: - HistoryStore Database Tests

@Test func historyStoreInsertAndFetch() async throws {
    let store = HistoryStore.shared
    let entry = HistoryEntry(
        transcript: "test_\(UUID().uuidString)",
        asrEngine: "whisper_turbo",
        durationSeconds: 1.0
    )
    try await store.insert(entry)
    let all = try await store.fetchAll(limit: 100)
    #expect(all.contains(where: { $0.id == entry.id }))
}

@Test func historyStoreSearch() async throws {
    let store = HistoryStore.shared
    let unique = "UNIQUE_\(UUID().uuidString)"
    let entry = HistoryEntry(transcript: unique)
    try await store.insert(entry)

    let results = try await store.search(query: unique)
    #expect(results.count >= 1)
    #expect(results.first?.transcript == unique)
}

@Test func historyStoreSearchEscapesSpecialChars() async throws {
    let store = HistoryStore.shared
    let entry = HistoryEntry(transcript: "100% done_test")
    try await store.insert(entry)

    // Search with SQL special chars should not crash
    let results = try await store.search(query: "100%")
    #expect(results.contains(where: { $0.transcript == "100% done_test" }))
}

@Test func historyStoreDelete() async throws {
    let store = HistoryStore.shared
    let entry = HistoryEntry(transcript: "to_delete_\(UUID().uuidString)")
    try await store.insert(entry)

    try await store.delete(id: entry.id)
    let all = try await store.fetchAll(limit: 1000)
    #expect(!all.contains(where: { $0.id == entry.id }))
}

@Test func historyStoreUpdate() async throws {
    let store = HistoryStore.shared
    var entry = HistoryEntry(transcript: "original_\(UUID().uuidString)")
    try await store.insert(entry)

    entry.polishedText = "polished version"
    try await store.update(entry)

    let all = try await store.fetchAll(limit: 1000)
    let found = all.first(where: { $0.id == entry.id })
    #expect(found?.polishedText == "polished version")
}

@Test func historyStoreFetchOrder() async throws {
    let store = HistoryStore.shared
    let e1 = HistoryEntry(transcript: "older_\(UUID().uuidString)", createdAt: Date(timeIntervalSinceNow: -100))
    let e2 = HistoryEntry(transcript: "newer_\(UUID().uuidString)", createdAt: Date())
    try await store.insert(e1)
    try await store.insert(e2)

    let all = try await store.fetchAll(limit: 2)
    // Newest first
    if all.count >= 2 {
        #expect(all[0].createdAt >= all[1].createdAt)
    }
}

// MARK: - SettingsStore Database Tests

@Test func settingsStoreSetAndGet() async throws {
    let store = SettingsStore.shared
    let testKey = SettingsKey.hotkey
    let testValue = "test_\(UUID().uuidString)"
    try await store.set(testKey, value: testValue)
    let retrieved = await store.get(testKey)
    #expect(retrieved == testValue)
}

@Test func settingsStoreOverwrite() async throws {
    let store = SettingsStore.shared
    let key = SettingsKey.polisherMode
    try await store.set(key, value: "cloud")
    try await store.set(key, value: "none")
    let val = await store.get(key)
    #expect(val == "none")
}

@Test func settingsStoreGetNonexistent() async throws {
    let store = SettingsStore.shared
    // showInMenuBar is unlikely to be set in tests
    let val = await store.get(.showInMenuBar)
    // Should return nil or a previously set value, not crash
    _ = val
}

@Test func settingsStoreGetASREngine() async throws {
    let store = SettingsStore.shared
    let engine = await store.getASREngine()
    // Should return a valid engine type
    #expect(ASREngineType.allCases.contains(engine))
}

@Test func settingsStoreGetPolisherMode() async throws {
    let store = SettingsStore.shared
    let mode = await store.getPolisherMode()
    #expect(PolisherMode.allCases.contains(mode))
}

// MARK: - HistoryEntry with webTitle Tests

@Test func historyEntryWebTitlePersistence() async throws {
    let store = HistoryStore.shared
    let entry = HistoryEntry(
        transcript: "webTitle_test_\(UUID().uuidString)",
        webUrl: "https://github.com/echotype",
        webDomain: "github.com",
        webTitle: "EchoType - GitHub"
    )
    try await store.insert(entry)

    let all = try await store.fetchAll(limit: 100)
    let found = all.first(where: { $0.id == entry.id })
    #expect(found?.webTitle == "EchoType - GitHub")
    #expect(found?.webDomain == "github.com")
}

// MARK: - Model Downloader Path Tests

@Test func modelDownloaderPaths() async throws {
    let whisperPath = ModelDownloader.whisperModelPath()
    let qwen3Path = ModelDownloader.qwen3ModelPath()
    #expect(whisperPath.lastPathComponent == "ggml-large-v3-turbo.bin")
    #expect(qwen3Path.lastPathComponent == "qwen3-asr-0.6b")
    #expect(whisperPath.path.contains("EchoType/models"))
    #expect(qwen3Path.path.contains("EchoType/models"))
}
