import Foundation
import GRDB

// MARK: - Settings Keys
public enum SettingsKey: String, Sendable {
    case asrEngine          = "asrEngine"           // "whisper_turbo" | "qwen3_asr"
    case polisherMode       = "polisherMode"         // "cloud" | "none"
    case hotkey             = "hotkey"               // e.g. "fn+shift"
    case selectedMic        = "selectedMicId"
    case inputLanguage      = "inputLanguage"        // ASR 輸入語言: "auto" | "zh" | "en" etc.
    case outputLanguage     = "outputLanguage"       // AI 輸出語言: "zh-TW" | "zh-CN" | "en-US" etc.
    case apiKey             = "apiKey"               // Cloud API Key
    case apiBaseUrl         = "apiBaseUrl"           // Cloud API Base URL
    case launchAtLogin      = "launchAtLogin"
    case showInMenuBar      = "showInMenuBar"
    case historyRetentionDays = "historyRetentionDays" // 歷史記錄保留天數
}

// MARK: - Settings Store
public actor SettingsStore {
    public static let shared = SettingsStore()

    private var dbQueue: DatabaseQueue?
    private var isReady = false

    private init() {
        Task { try? await setup() }
    }

    private func setup() async throws {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dbDir = appSupport.appendingPathComponent("EchoType")
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("settings.db").path
        let queue = try DatabaseQueue(path: dbPath)
        try await queue.write { db in
            try db.create(table: "settings", ifNotExists: true) { t in
                t.primaryKey("key", .text)
                t.column("value", .text)
            }
        }
        dbQueue = queue
        isReady = true
    }

    /// 確保 DB 已初始化
    private func ensureReady() async throws {
        if isReady { return }
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if isReady { return }
        }
        throw NSError(domain: "SettingsStore", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Database initialization timeout"])
    }

    public func get(_ key: SettingsKey) async -> String? {
        try? await { () async throws -> String? in
            try await ensureReady()
            return try await dbQueue?.read { db in
                try Row.fetchOne(db, sql: "SELECT value FROM settings WHERE key = ?", arguments: [key.rawValue])?["value"]
            }
        }()
    }

    public func set(_ key: SettingsKey, value: String) async throws {
        try await ensureReady()
        try await dbQueue?.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)",
                arguments: [key.rawValue, value]
            )
        }
    }

    public func getASREngine() async -> ASREngineType {
        let raw = await get(.asrEngine) ?? ASREngineType.whisperTurbo.rawValue
        return ASREngineType(rawValue: raw) ?? .whisperTurbo
    }

    public func getPolisherMode() async -> PolisherMode {
        let raw = await get(.polisherMode) ?? PolisherMode.transcriptOnly.rawValue
        return PolisherMode(rawValue: raw) ?? .transcriptOnly
    }
}
