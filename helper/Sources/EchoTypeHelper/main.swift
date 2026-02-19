import Foundation
import CoreKit

// MARK: - JSON IPC Bridge
// Rust (Tauri) ─stdin JSON→ EchoTypeHelper ─stdout JSON→ Rust

let audioManager = AudioManager.shared
let historyStore = HistoryStore.shared
let settingsStore = SettingsStore.shared
let contextReader = MacOSContextReader()
let textInjector = MacOSTextInjector()
let asrManager = ASREngineManager.shared
let modelDownloader = ModelDownloader.shared

func respond(_ result: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: ["ok": true, "result": result]),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func respondError(_ message: String) {
    if let data = try? JSONSerialization.data(withJSONObject: ["ok": false, "error": message]),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func dispatch(cmd: String, args: [String: Any]) async {
    switch cmd {

    case "get_context":
        let ctx = await contextReader.getFocusedContext()
        respond([
            "app_name":       ctx?.appName as Any,
            "bundle_id":      ctx?.bundleId as Any,
            "window_title":   ctx?.windowTitle as Any,
            "web_url":        ctx?.webUrl as Any,
            "web_domain":     ctx?.webDomain as Any,
            "context_before": ctx?.contextBefore as Any,
            "context_after":  ctx?.contextAfter as Any,
            "selected_text":  ctx?.selectedText as Any
        ])

    case "start_recording":
        do {
            try await audioManager.startRecording()
            respond("recording_started")
        } catch {
            respondError(error.localizedDescription)
        }

    case "stop_recording":
        guard let wavData = await audioManager.stopRecording() else {
            respondError("No audio captured")
            return
        }
        do {
            // 取得當前上下文，用於 Whisper initial_prompt
            let ctx = await contextReader.getFocusedContext()
            let contextPrompt = ctx?.toMinimalPromptContext() ?? ""

            // 傳入 context 作為 Whisper prompt（提升準度）
            let result = try await asrManager.transcribe(audio: wavData, context: contextPrompt)
            respond([
                "transcript":  result.text,
                "language":    result.detectedLanguage as Any,
                "duration":    result.durationSeconds,
                "asr_engine":  await MainActor.run { asrManager.currentEngineType.rawValue }
            ])
        } catch {
            respondError(error.localizedDescription)
        }

    case "inject_text":
        guard let text = args["text"] as? String else {
            respondError("Missing 'text' argument")
            return
        }
        do {
            try await textInjector.insertText(text)
            respond(true)
        } catch {
            respondError(error.localizedDescription)
        }

    case "get_microphones":
        let devices = await audioManager.availableDevices
        let list = devices.map { d -> [String: Any] in
            ["id": d.id, "name": d.name, "is_default": d.isDefault]
        }
        respond(list)

    case "get_settings":
        let engine   = await settingsStore.get(.asrEngine)    ?? "whisper_turbo"
        let polisher = await settingsStore.get(.polisherMode) ?? "none"
        let inputLang  = await settingsStore.get(.inputLanguage)  ?? "auto"
        let outputLang = await settingsStore.get(.outputLanguage) ?? "zh-TW"
        let mic      = await settingsStore.get(.selectedMic)  ?? "default"
        let apiKey   = await settingsStore.get(.apiKey)       ?? ""
        let apiBaseUrl = await settingsStore.get(.apiBaseUrl) ?? "https://api.groq.com/openai/v1/chat/completions"
        let retention = await settingsStore.get(.historyRetentionDays) ?? "30"
        respond([
            "asr_engine":      engine,
            "polisher_mode":   polisher,
            "input_language":  inputLang,
            "output_language": outputLang,
            "selected_mic_id": mic,
            "api_key":         apiKey,
            "api_base_url":    apiBaseUrl,
            "history_retention_days": retention,
            "launch_at_login": false
        ])

    case "set_setting":
        guard let key = args["key"] as? String, let value = args["value"] as? String else {
            respondError("Missing 'key' or 'value'")
            return
        }
        guard let settingKey = SettingsKey(rawValue: key) else {
            respondError("Unknown setting key: \(key)")
            return
        }
        do {
            try await settingsStore.set(settingKey, value: value)
            if settingKey == .asrEngine, let engineType = ASREngineType(rawValue: value) {
                try await asrManager.switchEngine(to: engineType)
            }
            respond(true)
        } catch {
            respondError(error.localizedDescription)
        }

    case "get_history":
        let limit = args["limit"] as? Int ?? 50
        do {
            let entries = try await historyStore.fetchAll(limit: limit)
            let list: [[String: Any]] = entries.map { e in
                var dict: [String: Any] = [
                    "id":         e.id,
                    "transcript": e.transcript,
                    "asr_engine": e.asrEngine,
                    "created_at": ISO8601DateFormatter().string(from: e.createdAt)
                ]
                if let p = e.polishedText  { dict["polished_text"] = p }
                if let a = e.appName      { dict["app_name"]       = a }
                if let d = e.webDomain    { dict["web_domain"]     = d }
                return dict
            }
            respond(list)
        } catch {
            respondError(error.localizedDescription)
        }

    case "save_history":
        guard let transcript = args["transcript"] as? String else {
            respondError("Missing 'transcript'")
            return
        }
        let entry = HistoryEntry(
            transcript:     transcript,
            polishedText:   args["polished_text"] as? String,
            appName:        args["app_name"]      as? String,
            webDomain:      args["web_domain"]    as? String,
            asrEngine:      args["asr_engine"]    as? String ?? "whisper_turbo",
            durationSeconds: args["duration"]      as? Double ?? 0
        )
        do {
            try await historyStore.insert(entry)
            respond(entry.id)
        } catch {
            respondError(error.localizedDescription)
        }

    case "prune_history":
        guard let days = args["days"] as? Int else {
            respondError("Missing 'days' argument")
            return
        }
        do {
            try await historyStore.pruneOldEntries(days: days)
            respond(true)
        } catch {
            respondError(error.localizedDescription)
        }

    case "check_model_status":
        let whisperDownloaded = await modelDownloader.isWhisperDownloaded()
        let qwen3Downloaded = await modelDownloader.isQwen3Downloaded()
        respond([
            "whisper_downloaded": whisperDownloaded,
            "qwen3_downloaded": qwen3Downloaded
        ])

    case "download_model":
        guard let modelType = args["model_type"] as? String else {
            respondError("Missing 'model_type' argument")
            return
        }
        do {
            if modelType == "whisper" {
                let _ = try await modelDownloader.downloadWhisper { progress in
                    // TODO: 可以透過 emit 回報進度給前端
                    print("Whisper download progress: \(Int(progress * 100))%")
                }
                respond(true)
            } else if modelType == "qwen3" {
                let _ = try await modelDownloader.downloadQwen3 { progress in
                    print("Qwen3 download progress: \(Int(progress * 100))%")
                }
                respond(true)
            } else {
                respondError("Unknown model_type: \(modelType)")
            }
        } catch {
            respondError(error.localizedDescription)
        }

    default:
        respondError("Unknown command: \(cmd)")
    }
}

// MARK: - Main Loop (newline-delimited JSON)
for line in AnySequence({ () -> AnyIterator<String> in
    AnyIterator { readLine(strippingNewline: true) }
}) {
    guard
        let data = line.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let cmd = json["cmd"] as? String
    else {
        respondError("Invalid JSON or missing 'cmd' field")
        continue
    }
    let args = json["args"] as? [String: Any] ?? [:]
    await dispatch(cmd: cmd, args: args)
}
