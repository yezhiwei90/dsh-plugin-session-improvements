# dsh-plugin-session-improvements

> **deepseek-harness Web 端会话操作增强插件**
> 
> 本工具基于 **deepseek-harness** 框架并结合 **Qwen3.8-27B** 模型协同开发完成。

为 `deepseek-harness` Web GUI 补齐会话生命周期管理的最后两块拼图：**会话恢复（Unarchive）**与**物理删除（Delete）**。

---

## 💡 核心功能

* **恢复归档（Restore / Unarchive）**
  * 将归档会话从全局归档集中移除并持久化落盘，瞬间恢复至原 Workspace 分组。
  * 主控端广播 `host/archived-sessions-changed` 事件，实现全量在线客户端实时同步。

* **彻底删除（Delete Session）**
  * **深度清理**：停止 Live Agent 实例 → 移除 Host 注册表记录 → 解除 Workspace 解绑 → 物理清除磁盘日志及目录（支持 JSONL / SQLite 双后端）。
  * **安全门禁**：拦截 Live 运行中 / 子代理拥有 / 在途提交的会话；丢失日志直接报 `session-not-found`；并发安全串行化校验。
  * **实时通知**：推送移除事件并触发前端 UI 状态更新。

---

## 🛠️ 改动概览

| 项目 | 说明 |
| :--- | :--- |
| **基线版本** | deepseek-harness `47f943859b` (v0.1.0-rc.5 系列) |
| **代码变动** | 45 个文件 (`+1329 / -31` 行)，无任何新增第三方依赖 |
| **影响模块** | RPC API Proxy、Workspace 注册表、Session Storage (JSONL/SQLite)、UI 交互与国际化 (zh/en)、E2E 测试套件 |

---

## 🚀 快速使用

### 安装

```bash
# 1. 应用 Git 补丁
git apply dsh-plugin-session-improvements.patch

# 2. 编译构建
pnpm run build
自动化脚本（含自动备份与检测）：

Linux / macOS: ./install.sh /path/to/deepseek-harness --build --test

Windows (PowerShell): .\install.ps1 -HarnessRoot D:\path\to\deepseek-harness -Build -Test

一键回滚
Bash
git apply -R dsh-plugin-session-improvements.patch
🧪 验证与测试
Bash
# 1. 运行持久化后端单测 (JSONL / SQLite / Memory)
pnpm vitest run packages/session/session-persistence/tests/persistence.spec.ts

# 2. 运行 Web E2E 完整生命周期测试 (归档 -> 恢复 -> 删除)
pnpm vitest run --config vitest.web.config.ts apps/web/tests/workspace-management.e2e.ts
📄 开源协议
本项目采用 MIT 协议开源，完整保留上游 deepseek-harness 版权声明。详见 LICENSE。
