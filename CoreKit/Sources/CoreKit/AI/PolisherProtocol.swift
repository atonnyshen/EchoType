import Foundation

// MARK: - AI Polisher Protocol
public protocol PolisherProtocol: Sendable {
    var isAvailable: Bool { get }
    func polish(transcript: String, context: AppContext?) async throws -> String
}

// MARK: - Polisher Mode
public enum PolisherMode: String, Sendable, CaseIterable {
    case cloud = "cloud"        // 雲端 API (統一策略)
    case transcriptOnly = "none" // 只轉錄，不潤飾

    public var displayName: String {
        switch self {
        case .cloud: return "雲端 AI（需網路）"
        case .transcriptOnly: return "只轉錄"
        }
    }
}

// MARK: - Local Polisher (MLX on macOS)
/// 使用 MLX 本地 LLM 進行文字潤飾。
/// 模型: Qwen2.5-3B-Instruct (MLX 量化版)
/// 完全離線，無隱私風險。
public actor LocalPolisher: @preconcurrency PolisherProtocol {
    public private(set) var isAvailable = false
    private let modelPath: URL
    private var model: AnyObject?  // MLX LLM model

    public init(modelPath: URL? = nil) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        self.modelPath = modelPath ?? appSupport
            .appendingPathComponent("EchoType/models/qwen2.5-3b-instruct-mlx")
    }

    public func load() async throws {
        guard FileManager.default.fileExists(atPath: modelPath.path) else { return }
        // TODO: import MLX; model = try await MLXLLM.load(from: modelPath)
        isAvailable = true
    }

    public func polish(transcript: String, context: AppContext?) async throws -> String {
        guard isAvailable else { return transcript }  // Passthrough if not loaded

        let systemPrompt = buildSystemPrompt(context: context)
        let userPrompt = "請潤飾以下語音轉錄文字，保留原意，修正語法，使其更自然流暢：\n\n\(transcript)"

        // TODO: let response = try await model.generate(system: systemPrompt, user: userPrompt, maxTokens: 500)
        // 此為 stub，暫時消除 unused 警告
        _ = systemPrompt
        _ = userPrompt
        return transcript + " [潤飾中...]"
    }

    private func buildSystemPrompt(context: AppContext?) -> String {
        var prompt = "你是一個書寫助手，負責潤飾語音轉錄文字。"

        if let ctx = context {
            prompt += "\n當前上下文：\n\(ctx.toMinimalPromptContext())"

            // 根據 App 類型調整語氣
            if let domain = ctx.webDomain {
                if domain.contains("slack") || domain.contains("discord") {
                    prompt += "\n語氣：輕鬆友善"
                } else if domain.contains("gmail") || domain.contains("outlook") {
                    prompt += "\n語氣：正式專業"
                } else if domain.contains("notion") || domain.contains("confluence") {
                    prompt += "\n語氣：清晰結構化"
                }
            }
        }

        prompt += "\n請只返回潤飾後的文字，不要加任何解釋。"
        return prompt
    }
}

// MARK: - Cloud Polisher (API fallback for iOS)
public actor CloudPolisher: @preconcurrency PolisherProtocol {
    public var isAvailable: Bool { !apiKey.isEmpty && !apiEndpoint.isEmpty }

    private let apiKey: String
    private let apiEndpoint: String
    private let outputLanguage: String

    public init(apiKey: String = "", apiEndpoint: String = "https://api.openai.com/v1/chat/completions", outputLanguage: String = "zh-TW") {
        self.apiKey = apiKey
        self.apiEndpoint = apiEndpoint
        self.outputLanguage = outputLanguage
    }

    public func polish(transcript: String, context: AppContext?) async throws -> String {
        guard isAvailable else { return transcript }

        let systemPrompt = buildSystemPrompt(outputLanguage: outputLanguage, context: context)
        let contextNote = context.map { "上下文：\($0.toMinimalPromptContext())\n\n" } ?? ""
        let userMessage = "\(contextNote)請潤飾：\(transcript)"

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 500,
            "temperature": 0.3
        ]

        var request = URLRequest(url: URL(string: apiEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        // 檢查 HTTP 狀態碼
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "CloudPolisher", code: httpResponse.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "API 回傳錯誤 \(httpResponse.statusCode): \(body.prefix(200))"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return (message?["content"] as? String) ?? transcript
    }

    /// 根據輸出語言建構 System Prompt
    private func buildSystemPrompt(outputLanguage: String, context: AppContext?) -> String {
        var prompt = "你是書寫助手，負責潤飾語音轉錄文字。"

        // 語言與地區偏好
        switch outputLanguage {
        case "zh-TW":
            prompt += "\n請使用繁體中文（台灣用語），例如：軟體、網路、資料庫。"
        case "zh-HK":
            prompt += "\n請使用繁體中文（香港用語），例如：軟件、網絡、數據庫。"
        case "zh-CN":
            prompt += "\n請使用简体中文（中国大陆用语），例如：软件、网络、数据库。"
        case "zh-SG":
            prompt += "\n請使用简体中文（新加坡用语）。"
        case "en-US":
            prompt += "\nPlease use American English (e.g., color, organize, center)."
        case "en-GB":
            prompt += "\nPlease use British English (e.g., colour, organise, centre)."
        case "en-AU":
            prompt += "\nPlease use Australian English."
        case "ja-JP":
            prompt += "\n日本語で出力してください。"
        case "ko-KR":
            prompt += "\n한국어로 출력해 주세요."
        default:
            prompt += "\n請保持原語言。"
        }

        // 根據上下文調整語氣
        if let ctx = context {
            if let domain = ctx.webDomain {
                if domain.contains("slack") || domain.contains("discord") {
                    prompt += "\n語氣：輕鬆友善"
                } else if domain.contains("gmail") || domain.contains("outlook") {
                    prompt += "\n語氣：正式專業"
                } else if domain.contains("notion") || domain.contains("confluence") {
                    prompt += "\n語氣：清晰結構化"
                }
            }
        }

        prompt += "\n請只返回潤飾後的文字，不要加任何解釋。"
        return prompt
    }
}
