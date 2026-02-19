import Foundation

// MARK: - QwenEngine
/// Qwen3-ASR-0.6B via MLX Swift framework.
/// 支援 52 個語言，專為裝置端設計，適合手機端（600MB）。
/// 依賴: mlx-swift (Apple MLX Swift framework)
/// 模型路徑: ~/Library/Application Support/EchoType/models/qwen3-asr-0.6b
public actor QwenEngine: @preconcurrency ASREngineProtocol {
    public let engineName = "Qwen3-ASR 0.6B (MLX)"
    public private(set) var isLoaded = false

    private let modelPath: URL
    // 實際整合時為 MLX model reference
    private var model: AnyObject?

    public init(modelPath: URL? = nil) {
        if let path = modelPath {
            self.modelPath = path
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.modelPath = appSupport
                .appendingPathComponent("EchoType/models/qwen3-asr-0.6b")
        }
    }

    public func load() async throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ASRError.modelNotFound(modelPath.path)
        }
        // TODO: import MLX; model = try await MLXASRModel.load(from: modelPath)
        isLoaded = true
    }

    public func unload() {
        model = nil
        isLoaded = false
    }

    public func transcribe(audio: Data, language: String? = nil) async throws -> ASRResult {
        guard isLoaded else { throw ASRError.modelNotLoaded }
        let start = Date()
        // TODO: let result = try await model.transcribe(audio, language: language)
        let dummyText = "[Qwen3 stub] \(audio.count) bytes audio received"
        let duration = Date().timeIntervalSince(start)
        return ASRResult(text: dummyText, detectedLanguage: language, durationSeconds: duration)
    }

    public func transcribe(audio: Data, language: String? = nil, context: String? = nil) async throws -> ASRResult {
        // Qwen3-ASR 不支援 initial_prompt，忽略 context
        return try await transcribe(audio: audio, language: language)
    }
}

// MARK: - ASR Engine Manager (Runtime Switcher)
/// 單例管理器，負責在兩個引擎之間切換。
@MainActor
public final class ASREngineManager: ObservableObject {
    public static let shared = ASREngineManager()

    @Published public private(set) var currentEngineType: ASREngineType = .whisperTurbo
    @Published public private(set) var isLoading = false

    private var whisperEngine: WhisperEngine?
    private var qwenEngine: QwenEngine?

    private init() {}

    public var currentEngine: (any ASREngineProtocol)? {
        switch currentEngineType {
        case .whisperTurbo: return whisperEngine
        case .qwen3ASR:     return qwenEngine
        }
    }

    public func switchEngine(to type: ASREngineType) async throws {
        guard type != currentEngineType else { return }
        isLoading = true
        defer { isLoading = false }

        // 卸載當前引擎
        currentEngine?.unload()

        currentEngineType = type

        // 載入新引擎
        switch type {
        case .whisperTurbo:
            let engine = WhisperEngine()
            try await engine.load()
            whisperEngine = engine
        case .qwen3ASR:
            let engine = QwenEngine()
            try await engine.load()
            qwenEngine = engine
        }
    }

    public func transcribe(audio: Data, language: String? = nil, context: String? = nil) async throws -> ASRResult {
        guard let engine = currentEngine else {
            throw ASRError.modelNotLoaded
        }
        return try await engine.transcribe(audio: audio, language: language, context: context)
    }
}
