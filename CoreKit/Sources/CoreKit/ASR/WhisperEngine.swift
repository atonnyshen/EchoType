import Foundation
import WhisperKit

// MARK: - WhisperEngine
/// Whisper large-v3-turbo via WhisperKit with CoreML acceleration.
/// 模型路徑遵循 macOS 最佳實踐：
/// - 優先使用 ~/Library/Caches/huggingface/hub/ (HuggingFace 標準路徑)
/// - WhisperKit 自動管理模型下載與快取
public actor WhisperEngine: @preconcurrency ASREngineProtocol {
    public let engineName = "Whisper Turbo (CoreML)"
    public private(set) var isLoaded = false

    nonisolated(unsafe) private var whisperKit: WhisperKit?
    private let modelVariant: String

    public init(modelVariant: String = "large-v3-turbo") {
        self.modelVariant = modelVariant
    }

    public func load() async throws {
        guard !isLoaded else { return }

        // H4 修復：添加重試機制（最多 3 次）
        var lastError: Error?
        for attempt in 1...3 {
            do {
                whisperKit = try await WhisperKit(
                    model: modelVariant,
                    verbose: false,
                    logLevel: .none,
                    prewarm: true,
                    load: true,
                    download: true
                )
                isLoaded = true
                print("[WhisperEngine] Model loaded successfully on attempt \(attempt)")
                return
            } catch {
                lastError = error
                print("[WhisperEngine] Load attempt \(attempt)/3 failed: \(error)")
                if attempt < 3 {
                    // 等待後重試（指數退避：2秒、4秒）
                    try? await Task.sleep(nanoseconds: UInt64(attempt * 2_000_000_000))
                }
            }
        }

        // 所有重試都失敗
        throw lastError ?? ASRError.modelLoadFailed
    }

    public func unload() {
        whisperKit = nil
        isLoaded = false
    }

    public func transcribe(audio: Data, language: String? = nil) async throws -> ASRResult {
        guard isLoaded, let whisperKit else {
            throw ASRError.modelNotLoaded
        }

        let start = Date()
        let samples = try extractPCMSamples(from: audio)

        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: language != nil,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        // WhisperKit transcribe 接受 [[Float]]，回傳 [[TranscriptionResult]?]
        let results = await whisperKit.transcribe(
            audioArrays: [samples],
            decodeOptions: options
        )

        let duration = Date().timeIntervalSince(start)

        // 從巢狀結果中提取文字
        let text = results.first??.first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detectedLang = results.first??.first?.language ?? language ?? "zh"

        return ASRResult(
            text: text,
            detectedLanguage: detectedLang,
            confidence: 1.0,
            durationSeconds: duration
        )
    }

    /// Whisper 支援 initial_prompt，可傳入上下文提升準度
    public func transcribe(audio: Data, language: String? = nil, context: String? = nil) async throws -> ASRResult {
        guard isLoaded, let whisperKit else {
            throw ASRError.modelNotLoaded
        }

        let start = Date()
        let samples = try extractPCMSamples(from: audio)

        // promptTokens 需要 tokenizer 編碼，目前先不傳 prompt
        // WhisperKit 的 promptTokens 是 [Int]（token IDs），不是字串
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0.0,
            temperatureFallbackCount: 3,
            usePrefillPrompt: language != nil,
            usePrefillCache: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        let results = await whisperKit.transcribe(
            audioArrays: [samples],
            decodeOptions: options
        )

        let duration = Date().timeIntervalSince(start)

        let text = results.first??.first?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detectedLang = results.first??.first?.language ?? language ?? "zh"

        return ASRResult(
            text: text,
            detectedLanguage: detectedLang,
            confidence: 1.0,
            durationSeconds: duration
        )
    }

    /// 從 WAV Data 提取 PCM Float32 樣本
    /// WhisperKit 期望：16kHz mono Float32 陣列，範圍 [-1.0, 1.0]
    private func extractPCMSamples(from wavData: Data) throws -> [Float] {
        guard wavData.count > 44 else {
            throw ASRError.invalidAudioFormat
        }

        let pcmData = wavData.subdata(in: 44..<wavData.count)
        let sampleCount = pcmData.count / 2

        return pcmData.withUnsafeBytes { rawBuffer -> [Float] in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            var samples = [Float]()
            samples.reserveCapacity(sampleCount)
            for i in 0..<int16Buffer.count {
                samples.append(Float(int16Buffer[i]) / 32768.0)
            }
            return samples
        }
    }
}

// MARK: - Model Management Utilities
extension WhisperEngine {
    /// 檢查模型是否已下載（在標準 HuggingFace 快取路徑）
    public static func isModelDownloaded(variant: String = "large-v3-turbo") -> Bool {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        let modelPath = cacheDir
            .appendingPathComponent("huggingface/hub")
            .appendingPathComponent("models--argmaxinc--whisperkit-coreml")
            .appendingPathComponent("snapshots")

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            return false
        }

        do {
            let snapshots = try FileManager.default.contentsOfDirectory(
                at: modelPath,
                includingPropertiesForKeys: nil
            )
            for snapshot in snapshots {
                let variantPath = snapshot.appendingPathComponent(variant)
                if FileManager.default.fileExists(atPath: variantPath.path) {
                    return true
                }
            }
        } catch {
            return false
        }

        return false
    }

    public static func getModelCachePath() -> String {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        return cacheDir
            .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml")
            .path
    }

    public static func getModelSize(variant: String = "large-v3-turbo") -> String? {
        guard isModelDownloaded(variant: variant) else { return nil }

        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        let modelPath = cacheDir
            .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml")

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: modelPath.path)
            if let size = attributes[.size] as? Int64 {
                return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
        } catch {
            return nil
        }

        return nil
    }
}
