import { useState, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useNavigate } from "react-router-dom";
import ReactECharts from "echarts-for-react";
import "./Hub.css";

interface HistoryEntry {
  id: string;
  transcript: string;
  polished_text: string | null;
  app_name: string | null;
  web_domain: string | null;
  asr_engine: string;
  created_at: string;
}

export default function Hub() {
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [search, setSearch] = useState("");
  const [activeTab, setActiveTab] = useState<"history" | "stats">("history");
  const navigate = useNavigate();

  useEffect(() => {
    invoke<HistoryEntry[]>("get_history", { limit: 50 })
      .then(setHistory)
      .catch(console.error);
  }, []);

  const filtered = history.filter(e =>
    e.transcript.includes(search) || (e.polished_text ?? "").includes(search)
  );

  // 按日期分組歷史記錄
  const groupByDate = (entries: HistoryEntry[]) => {
    const groups: { label: string; entries: HistoryEntry[] }[] = [];
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const weekAgo = new Date(today);
    weekAgo.setDate(weekAgo.getDate() - 7);

    const todayEntries: HistoryEntry[] = [];
    const yesterdayEntries: HistoryEntry[] = [];
    const thisWeekEntries: HistoryEntry[] = [];
    const olderEntries: HistoryEntry[] = [];

    entries.forEach(e => {
      const date = new Date(e.created_at);
      if (date >= today) {
        todayEntries.push(e);
      } else if (date >= yesterday) {
        yesterdayEntries.push(e);
      } else if (date >= weekAgo) {
        thisWeekEntries.push(e);
      } else {
        olderEntries.push(e);
      }
    });

    if (todayEntries.length > 0) groups.push({ label: "今天", entries: todayEntries });
    if (yesterdayEntries.length > 0) groups.push({ label: "昨天", entries: yesterdayEntries });
    if (thisWeekEntries.length > 0) groups.push({ label: "本週", entries: thisWeekEntries });
    if (olderEntries.length > 0) groups.push({ label: "更早以前", entries: olderEntries });

    return groups;
  };

  const groupedHistory = groupByDate(filtered);

  // 統計數據：每日使用量
  const getStatsOption = () => {
    // 模擬數據
    const dates = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const values = [5, 12, 8, 15, 20, 8, 10]; // Words count or entries
    
    return {
      tooltip: { trigger: 'axis' },
      grid: { top: 30, right: 20, bottom: 20, left: 40, containLabel: true },
      xAxis: {
        type: 'category',
        data: dates,
        axisLine: { lineStyle: { color: 'rgba(255,255,255,0.3)' } },
        axisLabel: { color: 'rgba(255,255,255,0.6)' }
      },
      yAxis: {
        type: 'value',
        splitLine: { lineStyle: { color: 'rgba(255,255,255,0.1)' } },
        axisLabel: { color: 'rgba(255,255,255,0.6)' }
      },
      series: [
        {
          data: values,
          type: 'bar',
          itemStyle: {
            color: {
              type: 'linear',
              x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: '#8b5cf6' },
                { offset: 1, color: '#6366f1' }
              ]
            },
            borderRadius: [4, 4, 0, 0]
          },
          barWidth: '40%'
        }
      ],
      backgroundColor: 'transparent'
    };
  };

  return (
    <div className="hub-root">
      {/* 側邊欄 */}
      <nav className="hub-sidebar">
        <div className="sidebar-logo">
          <span className="logo-icon">🎙️</span>
          <span className="logo-text">EchoType</span>
        </div>
        <button className={`sidebar-tab ${activeTab === "history" ? "active" : ""}`} onClick={() => setActiveTab("history")}>
          📋 歷史記錄
        </button>
        <button className={`sidebar-tab ${activeTab === "stats" ? "active" : ""}`} onClick={() => setActiveTab("stats")}>
          📊 統計
        </button>
        <div className="sidebar-spacer" />
        <button className="sidebar-tab" onClick={() => navigate("/settings")}>
          ⚙️ 設定
        </button>
      </nav>

      {/* 主內容 */}
      <main className="hub-main">
        {activeTab === "history" && (
          <>
            <div className="hub-header">
              <h1>歷史記錄</h1>
              <input
                className="search-input"
                placeholder="搜尋…"
                value={search}
                onChange={e => setSearch(e.target.value)}
              />
            </div>
            <div className="history-list">
              {filtered.length === 0 ? (
                <div className="empty-state">
                  <p>尚無記錄。按下快捷鍵開始錄音！</p>
                </div>
              ) : (
                groupedHistory.map(group => (
                  <div key={group.label}>
                    <div className="history-group-header">{group.label}</div>
                    {group.entries.map(entry => (
                      <div key={entry.id} className="history-item glass-card">
                        <div className="history-text">{entry.polished_text ?? entry.transcript}</div>
                        <div className="history-meta">
                          <span>{entry.app_name ?? "—"}</span>
                          {entry.web_domain && <span>· {entry.web_domain}</span>}
                          <span>· {entry.asr_engine === "whisper_turbo" ? "Whisper" : "Qwen3"}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                ))
              )}
            </div>
          </>
        )}

        {activeTab === "stats" && (
          <div style={{ padding: 40, height: "100%", display: "flex", flexDirection: "column" }}>
            <h1 style={{ fontSize: 24, marginBottom: 20 }}>使用統計</h1>
            <div className="glass-card" style={{ padding: 20, flex: 1, maxHeight: 400 }}>
               <h3>本週輸入字數</h3>
               <ReactECharts option={getStatsOption()} style={{ height: "100%", width: "100%" }} />
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 20, marginTop: 20 }}>
                <div className="glass-card" style={{ padding: 20, textAlign: "center" }}>
                    <div style={{ fontSize: 32, fontWeight: 700, color: "#6366f1" }}>1,204</div>
                    <div style={{ fontSize: 13, color: "var(--color-text-muted)" }}>總字數</div>
                </div>
                <div className="glass-card" style={{ padding: 20, textAlign: "center" }}>
                    <div style={{ fontSize: 32, fontWeight: 700, color: "#10b981" }}>15m</div>
                    <div style={{ fontSize: 13, color: "var(--color-text-muted)" }}>節省時間</div>
                </div>
                <div className="glass-card" style={{ padding: 20, textAlign: "center" }}>
                    <div style={{ fontSize: 32, fontWeight: 700, color: "#f43f5e" }}>42</div>
                    <div style={{ fontSize: 13, color: "var(--color-text-muted)" }}>錄音次數</div>
                </div>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
