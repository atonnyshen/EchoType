import Foundation

// MARK: - Model Downloader
/// 統一管理 ASR 模型下載與快取檢查
///
/// 模型儲存策略（遵循 macOS 最佳實踐）：
/// 1. Whisper (WhisperKit): ~/Library/Caches/huggingface/hub/
///    - WhisperKit 自動管理下載與快取
///    - 遵循 HuggingFace 標準路徑
/// 2. Qwen3 (MLX): ~/Library/Application Support/EchoType/models/
///    - 手動下載管理
///    - 應用專屬模型儲存
public actor ModelDownloader {
    public static let shared = ModelDownloader()

    private init() {}

    // MARK: - Model URLs
    private static let qwen3URL = URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B-MLX/resolve/main/model.safetensors")!

    // MARK: - Model Paths

    /// 取得應用專屬模型目錄（用於 Qwen3 等非 WhisperKit 模型）
    public static func getModelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let modelsDir = appSupport.appendingPathComponent("EchoType/models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    /// Whisper 模型路徑（由 WhisperKit 自動管理）
    /// 實際路徑：~/Library/Caches/huggingface/hub/models--argmaxinc--whisperkit-coreml/
    public static func whisperModelPath() -> URL {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!

        return cacheDir
            .appendingPathComponent("huggingface/hub/models--argmaxinc--whisperkit-coreml")
    }

    public static func qwen3ModelPath() -> URL {
        getModelsDirectory().appendingPathComponent("qwen3-asr-0.6b")
    }

    // MARK: - Check Model Existence

    /// 檢查 Whisper 模型是否已下載
    /// WhisperKit 會在首次使用時自動下載，此方法用於 UI 顯示
    public func isWhisperDownloaded(variant: String = "large-v3-turbo") -> Bool {
        return WhisperEngine.isModelDownloaded(variant: variant)
    }

    public func isQwen3Downloaded() -> Bool {
        FileManager.default.fileExists(atPath: Self.qwen3ModelPath().path)
    }

    // MARK: - Model Info

    /// 取得 Whisper 模型資訊
    public func getWhisperModelInfo(variant: String = "large-v3-turbo") -> ModelInfo {
        let isDownloaded = isWhisperDownloaded(variant: variant)
        let path = WhisperEngine.getModelCachePath()
        let size = WhisperEngine.getModelSize(variant: variant)

        return ModelInfo(
            name: "Whisper \(variant)",
            path: path,
            isDownloaded: isDownloaded,
            size: size,
            source: "HuggingFace (argmaxinc/whisperkit-coreml)"
        )
    }

    /// 取得 Qwen3 模型資訊
    public func getQwen3ModelInfo() -> ModelInfo {
        let isDownloaded = isQwen3Downloaded()
        let path = Self.qwen3ModelPath().path

        var size: String?
        if isDownloaded {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: path)
                if let fileSize = attributes[.size] as? Int64 {
                    size = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                }
            } catch {}
        }

        return ModelInfo(
            name: "Qwen3-ASR 0.6B",
            path: path,
            isDownloaded: isDownloaded,
            size: size,
            source: "HuggingFace (Qwen/Qwen3-ASR-0.6B-MLX)"
        )
    }

    // MARK: - Download with Progress

    /// 下載 Qwen3 模型（Whisper 由 WhisperKit 自動處理）
    public func downloadQwen3(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = Self.qwen3ModelPath()

        // 如果已存在，直接返回
        if FileManager.default.fileExists(atPath: destination.path) {
            progress(1.0)
            return destination
        }

        return try await download(from: Self.qwen3URL, to: destination, progress: progress)
    }

    // MARK: - Generic Download
    private func download(from url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadDelegate(progressHandler: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (localURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ModelDownloader", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "下載失敗：HTTP 錯誤"])
        }

        // 移動到目標位置
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: localURL, to: destination)

        progress(1.0)
        return destination
    }
}

// MARK: - Model Info
public struct ModelInfo: Sendable {
    public let name: String
    public let path: String
    public let isDownloaded: Bool
    public let size: String?
    public let source: String

    public init(name: String, path: String, isDownloaded: Bool, size: String?, source: String) {
        self.name = name
        self.path = path
        self.isDownloaded = isDownloaded
        self.size = size
        self.source = source
    }
}

// MARK: - Download Delegate (for progress tracking)
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 實際移動由 download() 方法處理
    }
}
