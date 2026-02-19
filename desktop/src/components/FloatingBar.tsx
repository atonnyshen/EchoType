import { useState, useEffect, useRef, useCallback } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { writeText } from "@tauri-apps/plugin-clipboard-manager";
import { motion, AnimatePresence } from "framer-motion";
import "./FloatingBar.css";

type RecordingState = "idle" | "recording" | "processing" | "done" | "inject-failed";

interface RecordingResult {
  transcript: string;
  polished_text: string;
  duration_seconds: number;
  asr_engine: string;
}

export default function FloatingBar() {
  const [state, setState] = useState<RecordingState>("idle");
  const [duration, setDuration] = useState(0);
  const [result, setResult] = useState<RecordingResult | null>(null);
  const [waveHeights, setWaveHeights] = useState<number[]>(Array(12).fill(4));
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const waveRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const stateRef = useRef<RecordingState>(state);

  // 同步 stateRef 與 state
  useEffect(() => { stateRef.current = state; }, [state]);

  const handleStartRecording = useCallback(async () => {
    if (stateRef.current !== "idle") return;
    setState("recording");
    setDuration(0);
    setResult(null);

    // 播放開始音效
    new Audio("/sounds/Tink.aiff").play().catch(console.error);

    await invoke("start_recording");

    // 計時器
    timerRef.current = setInterval(() => {
      setDuration(d => d + 1);
    }, 1000);

    // 波形動畫
    waveRef.current = setInterval(() => {
      setWaveHeights(Array(12).fill(0).map(() => 4 + Math.random() * 20));
    }, 80);
  }, []);

  const handleCancelRecording = useCallback(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (waveRef.current) clearInterval(waveRef.current);
    setWaveHeights(Array(12).fill(4));
    setState("idle");

    // Stop backend recording to prevent AudioManager from staying in recording state
    invoke("stop_recording").catch(() => {
      // Ignore errors - recording may not have started yet
    });
  }, []);

  const handleStopRecording = useCallback(async () => {
    if (stateRef.current !== "recording") return;
    setState("processing");

    // 播放停止音效
    new Audio("/sounds/Pop.aiff").play().catch(console.error);

    if (timerRef.current) clearInterval(timerRef.current);
    if (waveRef.current) clearInterval(waveRef.current);
    setWaveHeights(Array(12).fill(4));

    try {
      const res = await invoke<RecordingResult>("stop_recording");
      setResult(res);
      setState("done");

      // 自動注入文字
      try {
        await invoke("inject_text", { text: res.polished_text });
        // 注入成功，2 秒後回到 idle
        setTimeout(() => setState("idle"), 2000);
      } catch (injectError) {
        // 注入失敗會由 inject-failed 事件處理，這裡不做額外處理
        console.error("Inject failed:", injectError);
      }
    } catch (e) {
      console.error("Recording failed:", e);
      setState("idle");
    }
  }, []);

  const handleCopyToClipboard = useCallback(async () => {
    if (!result) return;
    try {
      await writeText(result.polished_text);
      setState("done"); // 切換到成功狀態
      setTimeout(() => setState("idle"), 1500);
    } catch (e) {
      console.error("Copy failed:", e);
    }
  }, [result]);

  // 監聽全域快捷鍵事件（v0.3.0：支援長按 + 點按兩種模式）
  useEffect(() => {
    const listeners: Promise<() => void>[] = [];

    // 長按模式：fn 按住 > 300ms → 開始錄音
    listeners.push(
      listen("hotkey-pressed", () => {
        if (stateRef.current === "idle") {
          handleStartRecording();
        }
      })
    );

    // 長按模式：fn 放開 → 停止錄音
    listeners.push(
      listen("hotkey-released", () => {
        if (stateRef.current === "recording") {
          handleStopRecording();
        }
      })
    );

    // 點按模式：fn 短按 < 300ms → toggle 錄音
    listeners.push(
      listen("hotkey-tap", () => {
        if (stateRef.current === "idle") {
          handleStartRecording();
        } else if (stateRef.current === "recording") {
          handleStopRecording();
        }
      })
    );

    // 錄音太短（300ms~500ms 之間放開）→ 取消，顯示提示
    listeners.push(
      listen("hotkey-cancelled", () => {
        if (stateRef.current === "recording") {
          handleCancelRecording();
          new Audio("/sounds/Basso.aiff").play().catch(console.error);
        }
      })
    );

    // Ctrl+Cmd+V → 貼上最後一次轉錄
    listeners.push(
      listen("paste-last-transcript", async () => {
        if (stateRef.current !== "idle") return;
        try {
          const history = await invoke<any[]>("get_history", { limit: 1 });
          if (history.length > 0) {
            const text = history[0].polished_text ?? history[0].transcript;
            await invoke("inject_text", { text });
          } else {
            // 無歷史記錄，播放提示音
            new Audio("/sounds/Basso.aiff").play().catch(console.error);
          }
        } catch (e) {
          console.error("Paste last transcript failed:", e);
        }
      })
    );

    return () => {
      listeners.forEach((p) => p.then((f) => f()));
    };
  }, [handleStartRecording, handleStopRecording, handleCancelRecording]);


  // 監聽注入失敗事件
  useEffect(() => {
    const unlisten = listen<{ text: string }>("inject-failed", () => {
      setState("inject-failed");
    });
    return () => {
      unlisten.then(f => f());
    };
  }, []);

  const truncateText = (text: string, maxLength: number): string => {
    if (text.length <= maxLength) return text;
    // Use Array.from to handle Unicode properly (including emoji and multi-byte chars)
    const chars = Array.from(text);
    if (chars.length <= maxLength) return text;
    return chars.slice(0, maxLength).join('') + '…';
  };

  const formatDuration = (s: number) =>
    `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;

  return (
    <div className="floating-bar-root">
      <AnimatePresence mode="wait">
        {state === "idle" && (
          <motion.div
            key="idle"
            className="floating-bar idle"
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.9 }}
          >
            <span className="dot idle-dot" />
            <span className="hint-text">按下快捷鍵開始錄音</span>
          </motion.div>
        )}

        {state === "recording" && (
          <motion.div
            key="recording"
            className="floating-bar recording"
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.9 }}
          >
            <div className="record-indicator">
              <div className="recording-ring" style={{ width: 28, height: 28 }} />
              <div className="recording-ring" style={{ width: 28, height: 28, animationDelay: "0.4s" }} />
              <div className="dot recording-dot" />
            </div>
            <div className="waveform">
              {waveHeights.map((h, i) => (
                <div
                  key={i}
                  className="waveform-bar"
                  style={{ height: h, animationDelay: `${i * 0.05}s` }}
                />
              ))}
            </div>
            <span className="duration">{formatDuration(duration)}</span>
            <button className="btn btn-ghost stop-btn" onClick={handleStopRecording}>
              停止
            </button>
          </motion.div>
        )}

        {state === "processing" && (
          <motion.div
            key="processing"
            className="floating-bar processing"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
          >
            <div className="spinner" />
            <span>AI 潤飾中…</span>
          </motion.div>
        )}

        {state === "done" && result && (
          <motion.div
            key="done"
            className="floating-bar done"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
          >
            <span className="done-icon">✓</span>
            <span className="done-text">{truncateText(result.polished_text, 40)}</span>
          </motion.div>
        )}

        {state === "inject-failed" && result && (
          <motion.div
            key="inject-failed"
            className="floating-bar inject-failed"
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
          >
            <span className="warning-icon">⚠️</span>
            <span className="done-text">{truncateText(result.polished_text, 30)}</span>
            <button className="btn btn-primary copy-btn" onClick={handleCopyToClipboard}>
              複製
            </button>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
