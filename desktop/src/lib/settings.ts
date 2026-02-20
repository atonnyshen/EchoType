// Settings keys type-safe constants
// L7: 類型安全的設定鍵名，避免拼寫錯誤

export const SettingsKeys = {
  ASR_ENGINE: 'asr_engine',
  POLISHER_MODE: 'polisher_mode',
  INPUT_LANGUAGE: 'input_language',
  OUTPUT_LANGUAGE: 'output_language',
  SELECTED_MIC_ID: 'selected_mic_id',
  LAUNCH_AT_LOGIN: 'launch_at_login',
  HISTORY_RETENTION_DAYS: 'history_retention_days',
  API_KEY: 'api_key',
  API_BASE_URL: 'api_base_url',
  HOTKEY: 'hotkey',
} as const;

export type SettingsKey = typeof SettingsKeys[keyof typeof SettingsKeys];

// 設定值類型定義
export interface Settings {
  [SettingsKeys.ASR_ENGINE]: 'whisper_turbo' | 'qwen3_asr';
  [SettingsKeys.POLISHER_MODE]: 'none' | 'local' | 'cloud';
  [SettingsKeys.INPUT_LANGUAGE]: string;
  [SettingsKeys.OUTPUT_LANGUAGE]: string;
  [SettingsKeys.SELECTED_MIC_ID]: string;
  [SettingsKeys.LAUNCH_AT_LOGIN]: string; // "true" | "false"
  [SettingsKeys.HISTORY_RETENTION_DAYS]: string;
  [SettingsKeys.API_KEY]: string;
  [SettingsKeys.API_BASE_URL]: string;
  [SettingsKeys.HOTKEY]: 'push_to_talk' | 'toggle';
}
