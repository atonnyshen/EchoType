import Foundation

// MARK: - Model Downloader
/// 統一管理 ASR 模型下載（Whisper / Qwen3）
public actor ModelDownloader {
    public static let shared = ModelDownloader()

    private init() {}

    // MARK: - Model URLs
    private static let whisperURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
    private static let qwen3URL = URL(string: "https://huggingface.co/Qwen/Qwen3-ASR-0.6B-MLX/resolve/main/model.safetensors")!

    // MARK: - Model Paths
    public static func getModelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let modelsDir = appSupport.appendingPathComponent("EchoType/models")
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    public static func whisperModelPath() -> URL {
        getModelsDirectory().appendingPathComponent("ggml-large-v3-turbo.bin")
    }

    public static func qwen3ModelPath() -> URL {
        getModelsDirectory().appendingPathComponent("qwen3-asr-0.6b")
    }

    // MARK: - Check Model Existence
    public func isWhisperDownloaded() -> Bool {
        FileManager.default.fileExists(atPath: Self.whisperModelPath().path)
    }

    public func isQwen3Downloaded() -> Bool {
        FileManager.default.fileExists(atPath: Self.qwen3ModelPath().path)
    }

    // MARK: - Download with Progress
    public func downloadWhisper(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let destination = Self.whisperModelPath()

        // 如果已存在，直接返回
        if FileManager.default.fileExists(atPath: destination.path) {
            progress(1.0)
            return destination
        }

        return try await download(from: Self.whisperURL, to: destination, progress: progress)
    }

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
