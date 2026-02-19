import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";

export default function Onboarding() {
  const [step, setStep] = useState(0);
  const navigate = useNavigate();

  const next = () => setStep(s => s + 1);

  const requestPermissions = async () => {
    // TODO: Invoke Rust command to request permissions (Mic, Accessibility)
    // For now simulate
    console.log("Requesting permissions...");
    next();
  };

  const finish = () => {
    navigate("/");
  };

  const steps = [
    // Step 0: Welcome
    <div key="welcome" className="step-content">
      <div style={{ fontSize: 64, marginBottom: 20 }}>👋</div>
      <h1>歡迎使用 EchoType</h1>
      <p>AI 驅動的語音輸入助手，專為 macOS 設計。</p>
      <p style={{ fontSize: 14, opacity: 0.7 }}>完全本地運行・隱私優先・上下文感知</p>
      <button className="btn btn-primary" onClick={next}>開始設定</button>
    </div>,

    // Step 1: Privacy
    <div key="privacy" className="step-content">
      <div style={{ fontSize: 64, marginBottom: 20 }}>🔒</div>
      <h1>隱私承諾</h1>
      <p>EchoType 的核心理念是隱私。</p>
      <ul style={{ textAlign: "left", display: "inline-block", margin: "20px 0", lineHeight: 1.8, fontSize: 15 }}>
        <li>✓ 語音在裝置端處理，不上傳雲端</li>
        <li>✓ 本地 LLM 進行文字潤飾</li>
        <li>✓ 只有必要的上下文（如視窗標題）會被讀取</li>
      </ul>
      <button className="btn btn-primary" onClick={next}>我瞭解了</button>
    </div>,

    // Step 2: Permissions
    <div key="permissions" className="step-content">
      <div style={{ fontSize: 64, marginBottom: 20 }}>🔐</div>
      <h1>需要權限</h1>
      <p>為了正常運作，EchoType 需要以下權限：</p>
      <div className="permissions-list">
        <div className="perm-item">
          <span className="perm-icon">🎤</span>
          <div>
            <strong>麥克風</strong>
            <div style={{ fontSize: 12, opacity: 0.7 }}>用於語音輸入</div>
          </div>
        </div>
        <div className="perm-item">
          <span className="perm-icon">⌨️</span>
          <div>
            <strong>輔助功能 (Accessibility)</strong>
            <div style={{ fontSize: 12, opacity: 0.7 }}>用於讀取上下文與輸入文字</div>
          </div>
        </div>
      </div>
      <button className="btn btn-primary" onClick={requestPermissions}>授權並繼續</button>
    </div>,

    // Step 3: Finish
    <div key="finish" className="step-content">
      <div style={{ fontSize: 64, marginBottom: 20 }}>🎉</div>
      <h1>設定完成！</h1>
      <p>您現在可以開始使用 EchoType 了。</p>
      <div className="glass-card" style={{ padding: 16, margin: "20px 0" }}>
        <strong>快捷鍵：Fn (F13)</strong>
        <div style={{ fontSize: 13, opacity: 0.7, marginTop: 4 }}>長按開始錄音，放開結束。</div>
      </div>
      <button className="btn btn-primary" onClick={finish}>開始使用</button>
    </div>
  ];

  return (
    <div className="onboarding-root">
      <div className="progress-bar">
        <div className="progress-fill" style={{ width: `${((step + 1) / steps.length) * 100}%` }} />
      </div>
      <AnimatePresence mode="wait">
        <motion.div
          key={step}
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -20 }}
          transition={{ duration: 0.3 }}
          style={{ width: "100%", maxWidth: 500 }}
        >
          {steps[step]}
        </motion.div>
      </AnimatePresence>

      <style>{`
        .onboarding-root {
          height: 100vh;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          text-align: center;
          background: radial-gradient(circle at center, #1e1e24 0%, #0d0d0f 100%);
        }
        .step-content {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 20px;
        }
        h1 { font-size: 28px; font-weight: 700; margin-bottom: 8px; }
        p { color: var(--color-text-muted); line-height: 1.6; }
        .progress-bar {
          position: fixed;
          top: 0;
          left: 0;
          width: 100%;
          height: 4px;
          background: rgba(255,255,255,0.1);
        }
        .progress-fill {
          height: 100%;
          background: var(--gradient-accent);
          transition: width 0.3s ease;
        }
        .permissions-list {
          display: flex;
          flex-direction: column;
          gap: 12px;
          width: 100%;
          text-align: left;
        }
        .perm-item {
          display: flex;
          align-items: center;
          gap: 16px;
          padding: 16px;
          background: rgba(255,255,255,0.05);
          border-radius: 12px;
          border: 1px solid rgba(255,255,255,0.1);
        }
        .perm-icon { font-size: 24px; }
      `}</style>
    </div>
  );
}
