import Foundation

// MARK: - WhisperEngine
/// Whisper large-v3-turbo, via whisper.cpp with CoreML acceleration.
/// 依賴: whisper.cpp Swift binding (手動加入 xcframework 或 SPM)
/// 模型路徑: ~/Library/Application Support/EchoType/models/ggml-large-v3-turbo.mlmodelc
public actor WhisperEngine: @preconcurrency ASREngineProtocol {
    public let engineName = "Whisper Turbo (CoreML)"
    public private(set) var isLoaded = false

    private let modelPath: URL
    // 實際整合時替換為 whisper.cpp 的 OpaquePointer
    private var whisperContext: UnsafeMutableRawPointer?

    public init(modelPath: URL? = nil) {
        if let path = modelPath {
            self.modelPath = path
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            self.modelPath = appSupport
                .appendingPathComponent("EchoType/models/ggml-large-v3-turbo.mlmodelc")
        }
    }

    public func load() async throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ASRError.modelNotFound(modelPath.path)
        }
        // TODO: whisper_init_from_file_with_params_no_state(modelPath.path, params)
        // whisperContext = whisper_init_from_file(modelPath.path)
        isLoaded = true
    }

    public func unload() {
        // TODO: whisper_free(whisperContext)
        whisperContext = nil
        isLoaded = false
    }

    public func transcribe(audio: Data, language: String? = nil) async throws -> ASRResult {
        guard isLoaded else { throw ASRError.modelNotLoaded }
        let start = Date()
        // TODO: 實際呼叫 whisper_full() / whisper_full_parallel()
        // 此為 stub，等待 whisper.cpp xcframework 整合
        let dummyText = "[Whisper stub] \(audio.count) bytes audio received"
        let duration = Date().timeIntervalSince(start)
        return ASRResult(text: dummyText, detectedLanguage: language ?? "zh", durationSeconds: duration)
    }

    /// Whisper 支援 initial_prompt，可傳入上下文提升準度
    public func transcribe(audio: Data, language: String? = nil, context: String? = nil) async throws -> ASRResult {
        guard isLoaded else { throw ASRError.modelNotLoaded }
        let start = Date()

        // 建構 Whisper initial_prompt（精簡版，避免過長）
        _ = buildInitialPrompt(context: context)

        // TODO: 實際呼叫 whisper_full_with_params()
        // let prompt = buildInitialPrompt(context: context)
        // params.initial_prompt = prompt.cString(using: .utf8)
        // whisper_full(whisperContext, params, audio)

        let dummyText = "[Whisper stub with context] \(audio.count) bytes audio received"
        let duration = Date().timeIntervalSince(start)
        return ASRResult(text: dummyText, detectedLanguage: language ?? "zh", durationSeconds: duration)
    }

    /// 建構 Whisper initial_prompt（控制在 50 字以內）
    private func buildInitialPrompt(context: String?) -> String {
        guard let ctx = context, !ctx.isEmpty else { return "" }

        // 提取關鍵詞（避免過長影響準度）
        // Whisper initial_prompt 建議：簡短、相關、不超過 1-2 句
        let lines = ctx.split(separator: "\n")
        let keywords = lines.prefix(2).joined(separator: " ")

        // 限制長度在 50 字以內
        let truncated = String(keywords.prefix(50))
        return truncated
    }
}
