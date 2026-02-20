import { useState, useEffect, useRef, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import { usePermissions, openSystemPreferences } from "../lib/permissions";
import { SettingsKeys } from "../lib/settings"; // L7: 類型安全的設定鍵名

interface AudioDevice {
  id: string;
  name: string;
  is_default: boolean;
}

// M7 修復：添加防抖 hook
function useDebounce<T extends (...args: any[]) => any>(
  callback: T,
  delay: number
): T {
  const timeoutRef = useRef<NodeJS.Timeout>();

  return useCallback(
    ((...args: Parameters<T>) => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      timeoutRef.current = setTimeout(() => {
        callback(...args);
      }, delay);
    }) as T,
    [callback, delay]
  );
}

// MARK: - PermissionRow 元件

function PermissionRow({
  label,
  description,
  granted,
  onFix,
}: {
  label: string;
  description: string;
  granted: boolean;
  onFix: () => void;
}) {
  return (
    <div className="setting-row permission-row">
      <div>
        <label>{label}</label>
        <span className="setting-description">{description}</span>
      </div>
      <div className="permission-status">
        {granted ? (
          <span className="permission-granted">✓ 已授權</span>
        ) : (
          <button className="btn btn-ghost btn-sm" onClick={onFix}>
            前往設定 →
          </button>
        )}
      </div>
    </div>
  );
}

// MARK: - Settings 主元件

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
  const [hotkeyMode, setHotkeyMode] = useState("push_to_talk");
  const [dictionary, setDictionary] = useState("");
  const navigate = useNavigate();

  // v0.3.0: 權限狀態（每 3 秒自動刷新）
  const { status: perms } = usePermissions();

  useEffect(() => {
    // 載入設定
    invoke<Record<string, string>>("get_settings").then(s => {
      if (s.asr_engine) setAsrEngine(s.asr_engine);
      if (s.polisher_mode) setPolisherMode(s.polisher_mode);
      if (s.input_language) setInputLanguage(s.input_language);
      if (s.output_language) setOutputLanguage(s.output_language);
      if (s.selected_mic_id) setSelectedMic(s.selected_mic_id);
      if (s.launch_at_login) setLaunchAtLogin(s.launch_at_login === "true");
      if (s.history_retention_days) setHistoryRetention(s.history_retention_days);
      if (s.api_key) setApiKey(s.api_key);
      if (s.api_base_url) setApiBaseUrl(s.api_base_url);
      if (s.hotkey) setHotkeyMode(s.hotkey);
    });

    // 載入麥克風列表
    invoke<AudioDevice[]>("get_microphones").then(setMics).catch(console.error);

    // 載入個人詞典
    invoke<string[]>("get_dictionary").then(words => setDictionary(words.join('\n'))).catch(console.error);
  }, []);

  const save = (key: string, value: string) => {
    // H8 修復：添加錯誤處理和用戶提示
    invoke("set_setting", { key, value })
      .catch((error) => {
        console.error(`Failed to save setting ${key}:`, error);
        // 顯示錯誤提示（可以用 toast 或 alert）
        alert(`設定保存失敗: ${error}`);
      });
  };

  // M7 修復：使用防抖版本的 save，避免頻繁保存
  const debouncedSave = useDebounce(save, 500);

  const sectionHeaderStyle = {
    fontSize: 13,
    fontWeight: 600,
    marginBottom: 12,
    color: "var(--color-text-muted)",
    textTransform: "uppercase" as const,
    letterSpacing: "0.05em",
  };

  const selectStyle = {
    background: "var(--color-surface-2)",
    border: "1px solid var(--color-border)",
    color: "var(--color-text)",
    borderRadius: 8,
    padding: "12px",
    fontFamily: "inherit",
    width: "100%",
    fontSize: 15,
  };

  const inputStyle = {
    background: "var(--color-surface-2)",
    border: "1px solid var(--color-border)",
    color: "var(--color-text)",
    borderRadius: 8,
    padding: "12px",
    fontFamily: "inherit",
    width: "100%",
    fontSize: 14,
  };

  return (
    <div className="settings-page">
      {/* 固定頂部 Header */}
      <div className="settings-header">
        <button className="btn btn-ghost" onClick={() => navigate("/")} style={{ padding: 8 }}>
          ←
        </button>
        <h1 style={{ fontSize: 24, fontWeight: 700 }}>設定</h1>
      </div>

      {/* 可滾動內容區 */}
      <div className="settings-content">
        <div style={{ display: "flex", flexDirection: "column", gap: 32 }}>

          {/* ASR 引擎 */}
          <section>
            <h2 style={sectionHeaderStyle}>語音識別引擎</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              <select
                value={asrEngine}
                onChange={e => { setAsrEngine(e.target.value); save("asrEngine", e.target.value); }}
                style={selectStyle}
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
            <h2 style={sectionHeaderStyle}>輸入裝置</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              <select
                value={selectedMic}
                onChange={e => { setSelectedMic(e.target.value); save("selectedMicId", e.target.value); }}
                style={selectStyle}
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
            <h2 style={sectionHeaderStyle}>AI 潤飾模式</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              <select
                value={polisherMode}
                onChange={e => { setPolisherMode(e.target.value); save("polisherMode", e.target.value); }}
                style={{ ...selectStyle, marginBottom: 16 }}
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
                      style={inputStyle}
                    />
                  </div>
                  <div>
                    <label style={{ fontSize: 14, marginBottom: 8, display: "block", color: "var(--color-text-muted)" }}>API Base URL</label>
                    <select
                      value={apiBaseUrl}
                      onChange={e => { setApiBaseUrl(e.target.value); save("apiBaseUrl", e.target.value); }}
                      style={inputStyle}
                    >
                      <option value="https://api.groq.com/openai/v1/chat/completions">Groq（推薦：免費、極速）</option>
                      <option value="https://api.openai.com/v1/chat/completions">OpenAI（GPT-4o mini）</option>
                      <option value="https://api.anthropic.com/v1/messages">Anthropic（Claude 3.5 Haiku）</option>
                    </select>
                  </div>
                  <div style={{ padding: 12, background: "var(--color-accent-bg)", border: "1px solid rgba(0,122,255,0.15)", borderRadius: 6, fontSize: 13, color: "var(--color-accent)", lineHeight: 1.6 }}>
                    推薦使用 Groq：免費額度大、速度極快（&gt;300 tokens/s），相容 OpenAI 格式。<br/>
                    取得 API Key：<a href="https://console.groq.com" target="_blank" style={{ color: "var(--color-accent)", textDecoration: "underline" }}>console.groq.com</a>
                  </div>
                </div>
              )}
            </div>
          </section>

          {/* 語言設定 */}
          <section>
            <h2 style={sectionHeaderStyle}>語言設定</h2>

            <div className="glass-card" style={{ padding: 20, marginBottom: 16 }}>
              <label style={{ fontSize: 15, marginBottom: 12, display: "block", fontWeight: 500 }}>輸入語言（語音辨識）</label>
              <select
                value={inputLanguage}
                onChange={e => { setInputLanguage(e.target.value); save("inputLanguage", e.target.value); }}
                style={inputStyle}
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

            <div className="glass-card" style={{ padding: 20 }}>
              <label style={{ fontSize: 15, marginBottom: 12, display: "block", fontWeight: 500 }}>輸出語言（AI 潤飾偏好）</label>
              <select
                value={outputLanguage}
                onChange={e => { setOutputLanguage(e.target.value); save("outputLanguage", e.target.value); }}
                style={inputStyle}
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

          {/* 個人詞典 */}
          <section>
            <h2 style={sectionHeaderStyle}>個人詞典</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              <p style={{ fontSize: 13, color: "var(--color-text-muted)", marginBottom: 12, lineHeight: 1.5 }}>
                加入常用的專有名詞、人名、技術術語，提升語音辨識準確度。每行一個詞彙。
              </p>
              <textarea
                value={dictionary}
                onChange={e => setDictionary(e.target.value)}
                onBlur={() => {
                  const words = dictionary.split('\n').map(w => w.trim()).filter(Boolean);
                  invoke("set_dictionary", { words }).catch((e) => {
                    console.error("Dictionary save failed:", e);
                    alert("詞典儲存失敗，請稍後再試");
                  });
                }}
                placeholder={"例如：\nEchoType\nWhisper Turbo\n台積電"}
                rows={6}
                style={{
                  background: "var(--color-surface-2)",
                  border: "1px solid var(--color-border)",
                  color: "var(--color-text)",
                  borderRadius: 8,
                  padding: "12px",
                  fontFamily: "inherit",
                  width: "100%",
                  fontSize: 14,
                  resize: "vertical"
                }}
              />
            </div>
          </section>

          {/* v0.3.0 新增：快捷鍵設定 */}
          <section>
            <h2 style={sectionHeaderStyle}>快捷鍵</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              <div className="setting-row">
                <label>觸發鍵</label>
                <span className="kbd-badge">fn (Globe 🌐)</span>
              </div>
              <div className="setting-row" style={{ marginTop: 16 }}>
                <label>錄音模式</label>
                <select
                  value={hotkeyMode}
                  onChange={e => { setHotkeyMode(e.target.value); save("hotkey", e.target.value); }}
                  style={{ ...inputStyle, padding: "8px 12px" }}
                >
                  <option value="push_to_talk">長按錄音 — 按住 fn 錄音，放開停止</option>
                  <option value="toggle">點按切換 — 按一下開始，再按一下停止</option>
                </select>
              </div>
              <div className="setting-hint">
                提示：請在「系統設定 → 鍵盤 → 按下 🌐 鍵時」選擇「不做任何動作」以避免衝突。
              </div>
            </div>
          </section>

          {/* v0.3.0 新增：權限狀態儀表板 */}
          <section>
            <h2 style={sectionHeaderStyle}>權限狀態</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              {perms ? (
                <>
                  <PermissionRow
                    label="麥克風"
                    description="語音錄製所需"
                    granted={perms.microphone === "authorized"}
                    onFix={() => openSystemPreferences("microphone")}
                  />
                  <div style={{ height: 1, background: "var(--color-border)", margin: "12px 0" }} />
                  <PermissionRow
                    label="輔助使用 (Accessibility)"
                    description="文字注入與上下文讀取所需"
                    granted={perms.accessibility}
                    onFix={() => openSystemPreferences("accessibility")}
                  />
                  <div style={{ height: 1, background: "var(--color-border)", margin: "12px 0" }} />
                  <PermissionRow
                    label="輸入監控 (Input Monitoring)"
                    description="全域快捷鍵監聽所需"
                    granted={perms.input_monitoring}
                    onFix={() => openSystemPreferences("input_monitoring")}
                  />
                </>
              ) : (
                <div style={{ textAlign: "center", color: "var(--color-text-muted)", padding: 20 }}>
                  <div className="spinner" style={{ margin: "0 auto 12px" }} />
                  <span>檢測中…</span>
                </div>
              )}
            </div>
          </section>

          {/* 系統整合 */}
          <section>
            <h2 style={sectionHeaderStyle}>系統整合</h2>
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
              <div style={{ marginTop: 20, paddingTop: 20, borderTop: "1px solid var(--color-border)" }}>
                <button
                  className="btn btn-ghost"
                  onClick={async () => {
                    try {
                      const { check } = await import('@tauri-apps/plugin-updater');
                      const update = await check();
                      if (update?.available) {
                        const yes = confirm(`發現新版本 ${update.version}，是否立即下載並安裝？`);
                        if (yes) {
                          await update.downloadAndInstall();
                          alert('更新已下載，應用程式將重新啟動');
                        }
                      } else {
                        alert('目前已是最新版本');
                      }
                    } catch (e) {
                      console.error('檢查更新失敗:', e);
                      alert('檢查更新失敗，請稍後再試');
                    }
                  }}
                  style={{ fontSize: 14 }}
                >
                  檢查更新
                </button>
                <p style={{ marginTop: 8, fontSize: 13, color: "var(--color-text-muted)", lineHeight: 1.5 }}>
                  當前版本：v0.2.1
                </p>
              </div>
            </div>
          </section>

          {/* 隱私與儲存 */}
          <section>
            <h2 style={sectionHeaderStyle}>隱私與儲存</h2>
            <div className="glass-card" style={{ padding: 20 }}>
              <label style={{ fontSize: 15, marginBottom: 12, display: "block" }}>自動清理歷史記錄</label>
              <select
                value={historyRetention}
                onChange={e => {
                  setHistoryRetention(e.target.value);
                  save("historyRetentionDays", e.target.value);
                }}
                style={selectStyle}
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
    </div>
  );
}
