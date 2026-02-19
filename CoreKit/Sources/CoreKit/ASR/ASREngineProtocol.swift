import Foundation

// MARK: - ASR Engine Protocol
/// 語音辨識引擎統一介面。支援切換 Whisper / Qwen3-ASR。
public protocol ASREngineProtocol: Sendable {
    var engineName: String { get }
    var isLoaded: Bool { get }

    /// 載入模型（可能需要數秒）
    func load() async throws

    /// 釋放模型資源
    func unload()

    /// 轉錄音訊資料（PCM WAV 格式）
    /// - Parameters:
    ///   - audio: WAV 格式的音訊資料
    ///   - language: 語言代碼，nil 代表自動偵測
    /// - Returns: 轉錄結果
    func transcribe(audio: Data, language: String?) async throws -> ASRResult

    /// 轉錄音訊資料（支援 context prompt）
    /// - Parameters:
    ///   - audio: WAV 格式的音訊資料
    ///   - language: 語言代碼，nil 代表自動偵測
    ///   - context: 上下文提示（Whisper initial_prompt）
    /// - Returns: 轉錄結果
    func transcribe(audio: Data, language: String?, context: String?) async throws -> ASRResult
}

// MARK: - ASR Result
public struct ASRResult: Sendable {
    public let text: String
    public let detectedLanguage: String?
    public let confidence: Float
    public let durationSeconds: Double

    public init(text: String, detectedLanguage: String? = nil, confidence: Float = 1.0, durationSeconds: Double) {
        self.text = text
        self.detectedLanguage = detectedLanguage
        self.confidence = confidence
        self.durationSeconds = durationSeconds
    }
}

// MARK: - ASR Engine Type
public enum ASREngineType: String, Sendable, CaseIterable {
    case whisperTurbo = "whisper_turbo"
    case qwen3ASR     = "qwen3_asr"

    public var displayName: String {
        switch self {
        case .whisperTurbo: return "Whisper Turbo (CoreML)"
        case .qwen3ASR:     return "Qwen3-ASR 0.6B (MLX)"
        }
    }
}

// MARK: - ASR Errors
public enum ASRError: LocalizedError {
    case modelNotLoaded
    case modelNotFound(String)
    case transcriptionFailed(String)
    case invalidAudioFormat

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:           return "ASR 模型尚未載入"
        case .modelNotFound(let path):  return "找不到模型: \(path)"
        case .transcriptionFailed(let msg): return "轉錄失敗: \(msg)"
        case .invalidAudioFormat:       return "不支援的音訊格式"
        }
    }
}
