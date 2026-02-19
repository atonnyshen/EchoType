import Foundation
import GRDB

// MARK: - History Entry
public struct HistoryEntry: Codable, FetchableRecord, PersistableRecord, Sendable {
    public var id: String
    public var transcript: String          // 原始轉錄
    public var polishedText: String?       // AI 潤飾後
    public var editedText: String?         // 使用者手動編輯
    public var appName: String?
    public var bundleId: String?
    public var windowTitle: String?
    public var webUrl: String?
    public var webDomain: String?
    public var contextBefore: String?
    public var asrEngine: String           // "whisper_turbo" | "qwen3_asr"
    public var audioPath: String?
    public var durationSeconds: Double
    public var createdAt: Date
    public var mode: String                // "voice_transcript" | "replace" | "append"

    public static let databaseTableName = "history"

    public init(
        id: String = UUID().uuidString,
        transcript: String,
        polishedText: String? = nil,
        editedText: String? = nil,
        appName: String? = nil,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        webUrl: String? = nil,
        webDomain: String? = nil,
        contextBefore: String? = nil,
        asrEngine: String = "whisper_turbo",
        audioPath: String? = nil,
        durationSeconds: Double = 0,
        createdAt: Date = Date(),
        mode: String = "voice_transcript"
    ) {
        self.id = id
        self.transcript = transcript
        self.polishedText = polishedText
        self.editedText = editedText
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.webUrl = webUrl
        self.webDomain = webDomain
        self.contextBefore = contextBefore
        self.asrEngine = asrEngine
        self.audioPath = audioPath
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.mode = mode
    }

    /// 最終顯示文字 (優先順序: edited > polished > transcript)
    public var displayText: String {
        editedText ?? polishedText ?? transcript
    }
}

// MARK: - History Store
public actor HistoryStore {
    public static let shared = HistoryStore()

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
        let dbPath = dbDir.appendingPathComponent("history.db").path

        let queue = try DatabaseQueue(path: dbPath)
        try await queue.write { db in
            try db.create(table: "history", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("transcript", .text).notNull()
                t.column("polishedText", .text)
                t.column("editedText", .text)
                t.column("appName", .text)
                t.column("bundleId", .text)
                t.column("windowTitle", .text)
                t.column("webUrl", .text)
                t.column("webDomain", .text)
                t.column("contextBefore", .text)
                t.column("asrEngine", .text).notNull().defaults(to: "whisper_turbo")
                t.column("audioPath", .text)
                t.column("durationSeconds", .double).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
                t.column("mode", .text).notNull().defaults(to: "voice_transcript")
            }
        }
        dbQueue = queue
        isReady = true
    }

    /// 確保 DB 已初始化，最多等待 5 秒
    private func ensureReady() async throws {
        if isReady { return }
        for _ in 0..<50 {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            if isReady { return }
        }
        throw NSError(domain: "HistoryStore", code: -1,
                       userInfo: [NSLocalizedDescriptionKey: "Database initialization timeout"])
    }

    // MARK: - CRUD

    public func insert(_ entry: HistoryEntry) async throws {
        try await ensureReady()
        try await dbQueue?.write { db in
            try entry.insert(db)
        }
    }

    public func update(_ entry: HistoryEntry) async throws {
        try await ensureReady()
        try await dbQueue?.write { db in
            try entry.update(db)
        }
    }

    public func fetchAll(limit: Int = 100) async throws -> [HistoryEntry] {
        try await ensureReady()
        return try await dbQueue?.read { db in
            try HistoryEntry.order(Column("createdAt").desc).limit(limit).fetchAll(db)
        } ?? []
    }

    public func search(query: String) async throws -> [HistoryEntry] {
        try await ensureReady()
        // 轉義 LIKE 特殊字元，防止 SQL 注入
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        let pattern = "%\(escaped)%"
        return try await dbQueue?.read { db in
            try HistoryEntry
                .filter(
                    SQL(sql: "transcript LIKE ? ESCAPE '\\'", arguments: [pattern]) ||
                    SQL(sql: "polishedText LIKE ? ESCAPE '\\'", arguments: [pattern])
                )
                .order(Column("createdAt").desc)
                .fetchAll(db)
        } ?? []
    }

    public func delete(id: String) async throws {
        try await ensureReady()
        try await dbQueue?.write { db in
            try HistoryEntry.deleteOne(db, key: id)
        }
    }

    /// 清理超過指定天數的舊記錄
    public func pruneOldEntries(days: Int) async throws {
        try await ensureReady()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        try await dbQueue?.write { db in
            try HistoryEntry
                .filter(Column("createdAt") < cutoffDate)
                .deleteAll(db)
        }
    }
}
