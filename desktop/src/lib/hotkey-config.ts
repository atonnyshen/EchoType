// lib/hotkey-config.ts — 快捷鍵模式配置 (v0.3.0)

export type HotkeyMode = "push_to_talk" | "toggle";

export interface HotkeyConfig {
  mode: HotkeyMode;
  triggerKey: string; // "fn" | "F13" | 自訂
}

export const DEFAULT_HOTKEY_CONFIG: HotkeyConfig = {
  mode: "push_to_talk",
  triggerKey: "fn",
};

export const HOTKEY_MODE_LABELS: Record<HotkeyMode, { name: string; desc: string }> = {
  push_to_talk: {
    name: "長按錄音",
    desc: "按住 fn 鍵開始錄音，放開停止",
  },
  toggle: {
    name: "點按切換",
    desc: "短按 fn 鍵開始錄音，再按一次停止",
  },
};
