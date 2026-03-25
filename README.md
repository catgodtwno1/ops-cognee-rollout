# ops-cognee-rollout

Cognee 知識圖譜記憶伺服器的部署、修復與驗證技能，適用於 OpenClaw 五層記憶棧的 L3 層。

## 功能

- **伺服器部署** — 在 Mac mini 上用 Docker/Colima 部署 Cognee 0.5.5
- **客戶端接入** — 多台機器連接同一 Cognee 伺服器
- **Sidecar 共存** — 與 LanceDB Pro 記憶插槽共存模式
- **NAS 部署** — 支援 QNAP/Synology NAS 上的 Docker 部署
- **故障診斷** — 覆蓋 embedding 維度、TCP 連接洩漏、搜索超時等問題

## 適用場景

- 從零搭建 Cognee 記憶伺服器
- 將 Cognee 轉為 Sidecar 模式（與 LanceDB Pro 共存）
- 排查 recall 不注入、搜索超時、embedding 失敗
- 在 NAS 上部署 Cognee（QNAP Container Station / Synology Docker）
- 新機器客戶端接入

## 核心知識

### SiliconFlow + bge-m3 配置

使用 SiliconFlow 作為 embedding provider，模型 `BAAI/bge-m3`，維度 1024。需要 patch Cognee 後端以禁止傳遞 `dimensions` 參數給 LiteLLM。

### 搜索模式

**必須使用 `CHUNKS` 模式**（純向量搜索）。預設的 `GRAPH_COMPLETION` 模式會調 LLM 做後處理，在高負載下導致 30 秒超時。

### 用戶帳號隔離

Cognee 有多租戶隔離。切換用戶後看不到舊用戶的資料。目前所有資料屬於 `default_user@example.com`。

### 已修復的已知問題

| 問題 | 根因 | 修復方案 |
|------|------|----------|
| 搜索延遲逐漸惡化 | litellm TCP 連接洩漏（無連接池） | 降低 timeout 至 30s + 注入共享 httpx 連接池 |
| 壓測 11% 失敗率 | GRAPH_COMPLETION 模式調 LLM 超時 | 使用 CHUNKS 模式（生產環境不受影響） |
| 切換帳號後資料消失 | 多租戶隔離 | 保持使用 default_user@example.com |
| NAS 容器 DNS 解析失敗 | 預設 bridge 網路 | 使用自訂 Docker network `oc-memory` |

## 目錄結構

```
SKILL.md                           # 完整操作手冊
scripts/
  apply_cognee_hotfix.sh           # Patch bge-m3 embedding 維度
  patch_openclaw_cognee_plugin.py  # Patch update→replace 邏輯
  onboard_cognee_client.sh         # 一鍵客戶端接入
  configure_openclaw_cognee_client.py  # 手動配置客戶端
  make_cognee_sidecar_clone.py     # 生成 Sidecar 克隆
  toggle_cognee_sidecar_mode.py    # 切換 Sidecar/原始模式
  cognee_smoke_test.py             # 完整驗證腳本
  memory-5a-bench.py               # 五層記憶壓力測試
references/
  troubleshooting.md               # 故障排除手冊
  server-mode.md                   # 伺服器部署參考
  client-mode.md                   # 客戶端配置參考
  validated-config.md              # 驗證過的配置
  sidecar-coexistence.md           # Sidecar 共存模式
```

## 安裝

將此目錄放到 `~/.openclaw/workspace/skills/` 下，OpenClaw 會自動載入。

## 授權

MIT
