// Onboarding.tsx — 6 步驟權限引導流程 (v0.3.0)
// Pre-Permission Pattern：先解釋再請求

import { useState, useEffect, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import { useNavigate } from "react-router-dom";
import { invoke } from "@tauri-apps/api/core";
import {
  checkAllPermissions,
  openSystemPreferences,
  requestMicrophone,
  pollPermission,
  type PermissionStatus,
} from "../lib/permissions";

// MARK: - 總步驟數

const TOTAL_STEPS = 6;

// MARK: - Step 0: 歡迎

function OnboardingWelcome({ onNext }: { onNext: () => void }) {
  return (
    <div className="step-content">
      <div className="onboarding-icon">👋</div>
      <h1>歡迎使用 EchoType</h1>
      <p className="onboarding-desc">AI 驅動的語音輸入助手，專為 macOS 設計。</p>
      <p className="onboarding-desc" style={{ fontSize: 14, opacity: 0.7 }}>
        完全本地運行・隱私優先・上下文感知
      </p>
      <div className="onboarding-actions">
        <button className="btn btn-primary" onClick={onNext}>
          開始設定
        </button>
      </div>
    </div>
  );
}

// MARK: - Step 1: 隱私承諾

function OnboardingPrivacy({ onNext }: { onNext: () => void }) {
  return (
    <div className="step-content">
      <div className="onboarding-icon">🔒</div>
      <h1>隱私承諾</h1>
      <p className="onboarding-desc">EchoType 的核心理念是隱私。</p>
      <ul style={{ textAlign: "left", display: "inline-block", margin: "12px 0", lineHeight: 1.8, fontSize: 15, color: "var(--color-text-muted)" }}>
        <li>✓ 語音在裝置端處理，不上傳雲端</li>
        <li>✓ 只有必要的上下文（如視窗標題）會被讀取</li>
        <li>✓ 歷史記錄僅儲存在本機</li>
      </ul>
      <div className="onboarding-actions">
        <button className="btn btn-primary" onClick={onNext}>
          我瞭解了
        </button>
      </div>
    </div>
  );
}

// MARK: - Step 2: 麥克風權限

function OnboardingMicrophone({ onNext, onSkip }: { onNext: () => void; onSkip: () => void }) {
  const [micStatus, setMicStatus] = useState<string>("not_determined");
  const [requesting, setRequesting] = useState(false);

  // 載入時先查詢當前狀態
  useEffect(() => {
    checkAllPermissions().then((p) => setMicStatus(p.microphone)).catch(() => {});
  }, []);

  const handleRequest = async () => {
    setRequesting(true);
    try {
      const result = await requestMicrophone();
      setMicStatus(result);
      if (result === "authorized") {
        setTimeout(onNext, 800);
      }
    } catch {
      setMicStatus("denied");
    } finally {
      setRequesting(false);
    }
  };

  return (
    <div className="step-content">
      <div className="onboarding-icon">🎙️</div>
      <h1>麥克風權限</h1>
      <p className="onboarding-desc">
        EchoType 需要存取麥克風才能將您的語音轉換為文字。
        <br />
        <strong>所有語音資料僅在本機處理，絕不上傳。</strong>
      </p>

      {micStatus === "authorized" ? (
        <div className="permission-success">
          <span className="check-icon">✓</span> 麥克風已授權
        </div>
      ) : micStatus === "denied" || micStatus === "restricted" ? (
        <div className="permission-denied">
          <p className="onboarding-desc">麥克風權限被拒絕，請手動前往系統設定開啟：</p>
          <div className="onboarding-actions">
            <button
              className="btn btn-primary"
              onClick={() => openSystemPreferences("microphone")}
            >
              打開系統設定
            </button>
            <button className="btn btn-ghost" onClick={onSkip}>
              稍後再說
            </button>
          </div>
        </div>
      ) : (
        <div className="onboarding-actions">
          <button className="btn btn-primary" onClick={handleRequest} disabled={requesting}>
            {requesting ? "請求中…" : "授權麥克風"}
          </button>
          <button className="btn btn-ghost" onClick={onSkip}>
            稍後再說
          </button>
        </div>
      )}
    </div>
  );
}

// MARK: - Step 3: Accessibility 權限

function OnboardingAccessibility({ onNext, onSkip }: { onNext: () => void; onSkip: () => void }) {
  const [granted, setGranted] = useState(false);
  const [opened, setOpened] = useState(false);

  // 每 2 秒輪詢 Accessibility 狀態，授權後自動進入下一步
  const handleGranted = useCallback(() => {
    setGranted(true);
    setTimeout(onNext, 1000);
  }, [onNext]);

  useEffect(() => {
    const cleanup = pollPermission(
      async () => {
        const perms = await checkAllPermissions();
        return perms.accessibility;
      },
      handleGranted,
      2000
    );
    return cleanup;
  }, [handleGranted]);

  const handleOpenSettings = async () => {
    await openSystemPreferences("accessibility");
    setOpened(true);
  };

  return (
    <div className="step-content">
      <div className="onboarding-icon">⌨️</div>
      <h1>輔助使用權限</h1>
      <p className="onboarding-desc">
        EchoType 需要「輔助使用」權限才能將轉錄文字<br />
        自動輸入到您正在使用的應用程式中。
      </p>

      {granted ? (
        <div className="permission-success">
          <span className="check-icon">✓</span> 輔助使用已授權
        </div>
      ) : (
        <>
          <div className="permission-guide">
            <div className="guide-step">
              <span className="guide-number">1</span>
              <span>點擊下方按鈕打開系統設定</span>
            </div>
            <div className="guide-step">
              <span className="guide-number">2</span>
              <span>在「隱私權與安全性 → 輔助使用」列表中找到 EchoType</span>
            </div>
            <div className="guide-step">
              <span className="guide-number">3</span>
              <span>開啟 EchoType 旁邊的開關</span>
            </div>
          </div>

          <div className="onboarding-actions">
            <button className="btn btn-primary" onClick={handleOpenSettings}>
              {opened ? "重新打開系統設定" : "打開系統設定"}
            </button>
            <button className="btn btn-ghost" onClick={onSkip}>
              稍後再說
            </button>
          </div>

          {opened && (
            <p className="permission-waiting">
              <span className="spinner-sm" /> 等待授權中…開啟後將自動繼續
            </p>
          )}
        </>
      )}
    </div>
  );
}

// MARK: - Step 4: fn 鍵設定引導

function OnboardingKeyboardSetup({ onNext }: { onNext: () => void }) {
  return (
    <div className="step-content">
      <div className="onboarding-icon">🌐</div>
      <h1>設定 fn 鍵</h1>
      <p className="onboarding-desc">
        EchoType 使用 fn (Globe 🌐) 鍵作為錄音觸發鍵。
        <br />
        為避免與系統功能衝突，建議進行以下設定：
      </p>

      <div className="permission-guide">
        <div className="guide-step">
          <span className="guide-number">1</span>
          <span>打開「系統設定 → 鍵盤」</span>
        </div>
        <div className="guide-step">
          <span className="guide-number">2</span>
          <span>找到「按下 🌐 鍵時」選項</span>
        </div>
        <div className="guide-step">
          <span className="guide-number">3</span>
          <span>選擇「不做任何動作」</span>
        </div>
      </div>

      <div className="hotkey-preview">
        <div className="hotkey-mode">
          <strong>長按 fn</strong> → 按住錄音，放開停止（push-to-talk）
        </div>
        <div className="hotkey-mode">
          <strong>短按 fn</strong> → 點一下開始，再點一下停止（toggle）
        </div>
      </div>

      <div className="onboarding-actions">
        <button className="btn btn-primary" onClick={onNext}>
          我知道了，繼續
        </button>
      </div>
    </div>
  );
}

// MARK: - Step 5: 完成

function SummaryRow({ label, ok }: { label: string; ok: boolean }) {
  return (
    <div className="summary-row">
      <span>{label}</span>
      {ok ? (
        <span className="status-ok">✓ 已授權</span>
      ) : (
        <span className="status-missing">— 未授權</span>
      )}
    </div>
  );
}

function OnboardingFinish({ onComplete }: { onComplete: () => void }) {
  const [perms, setPerms] = useState<PermissionStatus | null>(null);

  useEffect(() => {
    checkAllPermissions().then(setPerms).catch(() => {});
  }, []);

  const allGranted = perms
    ? perms.microphone === "authorized" && perms.accessibility
    : false;

  return (
    <div className="step-content">
      <div className="onboarding-icon">🎉</div>
      <h1>設定完成！</h1>

      {/* 權限摘要 */}
      {perms ? (
        <div className="permission-summary">
          <SummaryRow label="麥克風" ok={perms.microphone === "authorized"} />
          <SummaryRow label="輔助使用" ok={perms.accessibility} />
          <SummaryRow label="輸入監控" ok={perms.input_monitoring} />
        </div>
      ) : (
        <div style={{ minHeight: 80 }} />
      )}

      {/* 缺少權限的警告 */}
      {perms && !allGranted && (
        <p className="onboarding-warning">
          部分權限尚未授權，某些功能可能無法正常運作。
          <br />
          您可以稍後在「設定 → 權限狀態」中補充開啟。
        </p>
      )}

      <div className="onboarding-actions">
        <button className="btn btn-primary" onClick={onComplete}>
          開始使用 EchoType
        </button>
      </div>
    </div>
  );
}

// MARK: - Onboarding 主元件

export default function Onboarding() {
  const [step, setStep] = useState(0);
  const navigate = useNavigate();

  const handleComplete = async () => {
    await invoke("set_setting", { key: "onboarding_completed", value: "true" });
    navigate("/");
  };

  const handleSkip = () => setStep((s) => Math.min(s + 1, TOTAL_STEPS - 1));
  const handleNext = () => setStep((s) => Math.min(s + 1, TOTAL_STEPS - 1));

  return (
    <div className="onboarding-root">
      {/* 進度條 */}
      <div className="progress-bar">
        <div
          className="progress-fill"
          style={{ width: `${((step + 1) / TOTAL_STEPS) * 100}%` }}
        />
      </div>

      <AnimatePresence mode="wait">
        <motion.div
          key={step}
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -20 }}
          transition={{ duration: 0.25 }}
          style={{ width: "100%", maxWidth: 520 }}
        >
          {step === 0 && <OnboardingWelcome onNext={handleNext} />}
          {step === 1 && <OnboardingPrivacy onNext={handleNext} />}
          {step === 2 && <OnboardingMicrophone onNext={handleNext} onSkip={handleSkip} />}
          {step === 3 && <OnboardingAccessibility onNext={handleNext} onSkip={handleSkip} />}
          {step === 4 && <OnboardingKeyboardSetup onNext={handleNext} />}
          {step === 5 && <OnboardingFinish onComplete={handleComplete} />}
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
          padding: 40px 24px;
        }
        .step-content {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 16px;
          width: 100%;
        }
        h1 { font-size: 28px; font-weight: 700; margin: 0; }
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
          transition: width 0.4s ease;
        }
      `}</style>
    </div>
  );
}
