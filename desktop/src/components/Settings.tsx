import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";

interface AudioDevice {
  id: string;
  name: string;
  is_default: boolean;
}

export default function Settings() {
  const [asrEngine, setAsrEngine] = useState("whisper_turbo");
  const [polisherMode, setPolisherMode] = useState("cloud");
  const [inputLanguage, setInputLanguage] = useState("auto");
  const [outputLanguage, setOutputLanguage] = useState("zh-TW");
  const [mics, setMics] = useState<AudioDevice[]>([]);
  const [selectedMic, setSelectedMic] = useState("default");
  const [launchAtLogin, setLaunchAtLogin] = useState(false);
  const [historyRetention, setHistoryRetention] = useState("30");
  const [apiKey, setApiKey] = useState("");
  const [apiBaseUrl, setApiBaseUrl] = useState("https://api.groq.com/openai/v1/chat/completions");
  const navigate = useNavigate();

  useEffect(() => {
    // Load settings
    invoke<Record<string,string>>("get_settings").then(s => {
      if (s.asr_engine) setAsrEngine(s.asr_engine);
      if (s.polisher_mode) setPolisherMode(s.polisher_mode);
      if (s.input_language) setInputLanguage(s.input_language);
      if (s.output_language) setOutputLanguage(s.output_language);
      if (s.selected_mic_id) setSelectedMic(s.selected_mic_id);
      if (s.launch_at_login) setLaunchAtLogin(s.launch_at_login === "true");
      if (s.history_retention_days) setHistoryRetention(s.history_retention_days);
      if (s.api_key) setApiKey(s.api_key);
      if (s.api_base_url) setApiBaseUrl(s.api_base_url);
    });

    // Load mics
    invoke<AudioDevice[]>("get_microphones").then(setMics).catch(console.error);
  }, []);

  const save = (key: string, value: string) =>
    invoke("set_setting", { key, value });

  return (
    <div style={{ padding: 32, maxWidth: 640, margin: "0 auto", paddingBottom: 80 }}>
      <header style={{ marginBottom: 32, display: "flex", alignItems: "center", gap: 12 }}>
        <button className="btn btn-ghost" onClick={() => navigate("/")} style={{ padding: 8 }}>
          ←
        </button>
        <h1 style={{ fontSize: 24, fontWeight: 700 }}>設定</h1>
      </header>

      <div style={{ display: "flex", flexDirection: "column", gap: 32 }}>
        
        {/* ASR 引擎 */}
        <section>
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: "var(--color-text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>語音識別引擎</h2>
          <div className="glass-card" style={{ padding: 20 }}>
            <select
              value={asrEngine}
              onChange={e => { setAsrEngine(e.target.value); save("asrEngine", e.target.value); }}
              style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 15 }}
            >
              <option value="whisper_turbo">Whisper Turbo (CoreML) — 高精度、蘋果晶片優化</option>
              <option value="qwen3_asr">Qwen3-ASR 0.6B (MLX) — 輕量、多語言支援</option>
            </select>
            <p style={{ marginTop: 12, fontSize: 13, color: "var(--color-text-muted)", lineHeight: 1.5 }}>
              Whisper Turbo 適合 M1/M2/M3 晶片，提供最佳準確度。Qwen3 較為輕量，適合記憶體較少的設備。
            </p>
          </div>
        </section>

        {/* 麥克風 */}
        <section>
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: "var(--color-text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>輸入裝置</h2>
          <div className="glass-card" style={{ padding: 20 }}>
            <select
              value={selectedMic}
              onChange={e => { setSelectedMic(e.target.value); save("selectedMicId", e.target.value); }}
              style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 15 }}
            >
              <option value="default">系統預設</option>
              {mics.map(m => (
                <option key={m.id} value={m.id}>{m.name}</option>
              ))}
            </select>
          </div>
        </section>

        {/* AI 潤飾 */}
        <section>
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: "var(--color-text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>AI 潤飾模式</h2>
          <div className="glass-card" style={{ padding: 20 }}>
            <select
              value={polisherMode}
              onChange={e => { setPolisherMode(e.target.value); save("polisherMode", e.target.value); }}
              style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 15, marginBottom: 16 }}
            >
              <option value="cloud">雲端 AI（推薦：Groq 免費高速）</option>
              <option value="none">只轉錄，不潤飾</option>
            </select>

            {polisherMode === "cloud" && (
              <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
                <div>
                  <label style={{ fontSize: 14, marginBottom: 8, display: "block", color: "var(--color-text-muted)" }}>API Key</label>
                  <input
                    type="password"
                    value={apiKey}
                    onChange={e => setApiKey(e.target.value)}
                    onBlur={() => save("apiKey", apiKey)}
                    placeholder="sk-..."
                    style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 14 }}
                  />
                </div>
                <div>
                  <label style={{ fontSize: 14, marginBottom: 8, display: "block", color: "var(--color-text-muted)" }}>API Base URL</label>
                  <select
                    value={apiBaseUrl}
                    onChange={e => {
                      setApiBaseUrl(e.target.value);
                      save("apiBaseUrl", e.target.value);
                    }}
                    style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 14 }}
                  >
                    <option value="https://api.groq.com/openai/v1/chat/completions">Groq（推薦：免費、極速）</option>
                    <option value="https://api.openai.com/v1/chat/completions">OpenAI（GPT-4o mini）</option>
                    <option value="https://api.anthropic.com/v1/messages">Anthropic（Claude 3.5 Haiku）</option>
                  </select>
                </div>
                <div style={{ padding: 12, background: "rgba(99, 102, 241, 0.1)", border: "1px solid rgba(99, 102, 241, 0.2)", borderRadius: 6, fontSize: 13, color: "#818cf8", lineHeight: 1.6 }}>
                  💡 <strong>推薦使用 Groq</strong>：免費額度大、速度極快（&gt;300 tokens/s），相容 OpenAI 格式。<br/>
                  取得 API Key：<a href="https://console.groq.com" target="_blank" style={{ color: "#a5b4fc", textDecoration: "underline" }}>console.groq.com</a>
                </div>
              </div>
            )}
          </div>
        </section>

        {/* 語言設定 */}
        <section>
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: "var(--color-text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>語言設定</h2>

          {/* 輸入語言（ASR 辨識） */}
          <div className="glass-card" style={{ padding: 20, marginBottom: 16 }}>
            <label style={{ fontSize: 15, marginBottom: 12, display: "block", fontWeight: 500 }}>輸入語言（語音辨識）</label>
            <select
              value={inputLanguage}
              onChange={e => { setInputLanguage(e.target.value); save("inputLanguage", e.target.value); }}
              style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 14 }}
            >
              <optgroup label="🌟 推薦">
                <option value="auto">自動偵測（推薦）</option>
                <option value="zh">中文（繁體/簡體混合）</option>
                <option value="en">English（英文）</option>
              </optgroup>
              <optgroup label="亞洲語言">
                <option value="ja">日本語（日文）</option>
                <option value="ko">한국어（韓文）</option>
                <option value="th">ภาษาไทย（泰文）</option>
                <option value="vi">Tiếng Việt（越南文）</option>
              </optgroup>
              <optgroup label="歐洲語言">
                <option value="es">Español（西班牙文）</option>
                <option value="fr">Français（法文）</option>
                <option value="de">Deutsch（德文）</option>
                <option value="it">Italiano（義大利文）</option>
                <option value="pt">Português（葡萄牙文）</option>
                <option value="ru">Русский（俄文）</option>
              </optgroup>
            </select>
            <p style={{ marginTop: 12, fontSize: 13, color: "var(--color-text-muted)", lineHeight: 1.5 }}>
              💡 建議使用「自動偵測」，Whisper 會自動識別語言，並支援中英夾雜。
            </p>
          </div>

          {/* 輸出語言（AI 潤飾） */}
          <div className="glass-card" style={{ padding: 20 }}>
            <label style={{ fontSize: 15, marginBottom: 12, display: "block", fontWeight: 500 }}>輸出語言（AI 潤飾偏好）</label>
            <select
              value={outputLanguage}
              onChange={e => { setOutputLanguage(e.target.value); save("outputLanguage", e.target.value); }}
              style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 14 }}
            >
              <optgroup label="🌟 推薦">
                <option value="zh-TW">繁體中文（台灣）</option>
                <option value="zh-HK">繁體中文（香港）</option>
                <option value="zh-CN">简体中文（中国大陆）</option>
                <option value="en-US">English (US)</option>
              </optgroup>
              <optgroup label="中文變體">
                <option value="zh-SG">简体中文（新加坡）</option>
                <option value="zh-MO">繁體中文（澳門）</option>
              </optgroup>
              <optgroup label="英文變體">
                <option value="en-GB">English (UK)</option>
                <option value="en-AU">English (Australia)</option>
                <option value="en-CA">English (Canada)</option>
              </optgroup>
              <optgroup label="其他語言">
                <option value="ja-JP">日本語</option>
                <option value="ko-KR">한국어</option>
                <option value="es-ES">Español</option>
                <option value="fr-FR">Français</option>
                <option value="de-DE">Deutsch</option>
              </optgroup>
            </select>
            <p style={{ marginTop: 12, fontSize: 13, color: "var(--color-text-muted)", lineHeight: 1.5 }}>
              AI 潤飾時會將文字轉換為此語言，並遵循該地區的用語習慣（如「軟體」vs「軟件」）。
            </p>
          </div>
        </section>

        {/* 開機自啟 */}
        <section>
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: "var(--color-text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>系統整合</h2>
          <div className="glass-card" style={{ padding: 20 }}>
            <label style={{ display: "flex", alignItems: "center", gap: 12, cursor: "pointer" }}>
              <input
                type="checkbox"
                checked={launchAtLogin}
                onChange={e => {
                  const val = e.target.checked;
                  setLaunchAtLogin(val);
                  save("launchAtLogin", val ? "true" : "false");
                }}
                style={{ width: 18, height: 18, cursor: "pointer" }}
              />
              <span style={{ fontSize: 15 }}>開機時自動啟動 EchoType</span>
            </label>
            <p style={{ marginTop: 12, fontSize: 13, color: "var(--color-text-muted)", lineHeight: 1.5, marginLeft: 30 }}>
              啟用後，EchoType 會在登入 macOS 時自動在背景執行。
            </p>
          </div>
        </section>

        {/* 歷史記錄保留 */}
        <section>
          <h2 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12, color: "var(--color-text-muted)", textTransform: "uppercase", letterSpacing: "0.05em" }}>隱私與儲存</h2>
          <div className="glass-card" style={{ padding: 20 }}>
            <label style={{ fontSize: 15, marginBottom: 12, display: "block" }}>自動清理歷史記錄</label>
            <select
              value={historyRetention}
              onChange={e => {
                setHistoryRetention(e.target.value);
                save("historyRetentionDays", e.target.value);
              }}
              style={{ background: "rgba(0,0,0,0.2)", border: "1px solid var(--color-border)", color: "var(--color-text)", borderRadius: 8, padding: "12px", fontFamily: "inherit", width: "100%", fontSize: 15 }}
            >
              <option value="7">保留 7 天</option>
              <option value="30">保留 30 天</option>
              <option value="90">保留 90 天</option>
              <option value="365">保留 1 年</option>
              <option value="0">永久保留</option>
            </select>
            <p style={{ marginTop: 12, fontSize: 13, color: "var(--color-text-muted)", lineHeight: 1.5 }}>
              超過指定天數的歷史記錄將自動刪除，保護您的隱私。
            </p>
          </div>
        </section>

      </div>
    </div>
  );
}
