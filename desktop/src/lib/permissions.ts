// lib/permissions.ts — 前端權限管理 API (v0.3.0)
// 提供統一的權限查詢、請求、系統設定跳轉介面

import { invoke } from "@tauri-apps/api/core";
import { useState, useEffect, useCallback } from "react";

// MARK: - Types

export interface PermissionStatus {
  microphone: "not_determined" | "authorized" | "denied" | "restricted";
  accessibility: boolean;
  input_monitoring: boolean;
}

// MARK: - Core APIs

/** 一次性檢查所有權限狀態 */
export async function checkAllPermissions(): Promise<PermissionStatus> {
  return await invoke<PermissionStatus>("check_permissions");
}

/** 打開系統偏好設定對應面板 */
export async function openSystemPreferences(
  pane: "microphone" | "accessibility" | "input_monitoring"
): Promise<void> {
  await invoke("open_system_preferences", { pane });
}

/** 請求麥克風權限（透過 AVCaptureDevice.requestAccess 觸發系統對話框） */
export async function requestMicrophone(): Promise<string> {
  return await invoke<string>("request_microphone");
}

// MARK: - Polling Utility

/**
 * 輪詢權限狀態（用於 Accessibility 等需手動開啟的權限）
 * 返回 cleanup 函數，在 useEffect return 中呼叫即可停止輪詢
 */
export function pollPermission(
  checkFn: () => Promise<boolean>,
  onGranted: () => void,
  intervalMs: number = 2000
): () => void {
  const timer = setInterval(async () => {
    try {
      const granted = await checkFn();
      if (granted) {
        clearInterval(timer);
        onGranted();
      }
    } catch {
      // 忽略偵測過程中的錯誤，繼續輪詢
    }
  }, intervalMs);

  return () => clearInterval(timer);
}

// MARK: - React Hook

/**
 * usePermissions — 持續監控權限狀態的 React Hook
 * 每 10 秒自動刷新（Accessibility 可能被手動開啟/撤銷）
 * 降低輪詢頻率以減少 CGEventTap probe 的系統開銷
 */
export function usePermissions() {
  const [status, setStatus] = useState<PermissionStatus | null>(null);
  const [loading, setLoading] = useState(true);

  const refresh = useCallback(async () => {
    try {
      const s = await checkAllPermissions();
      setStatus(s);
    } catch (e) {
      console.error("[permissions] check failed:", e);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refresh();
    // Poll every 10 seconds (reduced from 3s to minimize CGEventTap probe overhead)
    const timer = setInterval(refresh, 10000);
    return () => clearInterval(timer);
  }, [refresh]);

  return { status, loading, refresh };
}
