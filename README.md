# dsh-plugin-session-improvements

deepseek-harness **Web 端会话操作增强补丁**:为 Web GUI 的会话操作补齐 **恢复归档(restore/unarchive)** 与 **删除(delete)** 两个功能。

补丁前,Web 端对一个会话只能 rename / fork / archive。补丁后:

- 会话行操作菜单新增 **「删除会话」**:弹出确认对话框(明示不可恢复),确认后由 host 端持久删除——停掉 live agent(如持有)、从 host 会话注册表移除、从 workspace 注册表 durable detach、删除磁盘日志文件与目录,并向客户端推送移除事件。
- 已归档(已存档)会话区新增 **「恢复会话」**:把会话从全局归档集合中移除并 durable 落盘,行立即回到原工作区分组;host 端推送 `host/archived-sessions-changed`,所有已连接客户端同步刷新。
- 安全门禁:子代理 owner 会话不可直接删除;live 会话无持有句柄时返回 `session-busy`;冷会话删除前校验持久层可定位该日志,找不到则 `session-not-found`;后端删除钩子带串行化门禁(拒绝 live/仍绑定/在途提交的会话)。

## 包内容

```
dsh-plugin-session-improvements/
├── README.md                     # 本文档
├── LICENSE                       # MIT(含上游 deepseek-harness 版权声明保留)
├── dsh-plugin-session-improvements.patch    # 完整 git 补丁(45 个文件,1329+/31-)
├── file-list.txt                 # 涉及文件清单(45)
├── manifest.json                 # 每文件 SHA256(原始/修改后)与基线 commit
├── files/
│   ├── original/                 # 修改前的原始文件(按仓库路径存放,取自基线 commit)
│   └── modified/                 # 修改后的文件(按仓库路径存放)
├── install.ps1                   # Windows 安装/回滚脚本(PowerShell)
└── install.sh                    # Linux/macOS 安装/回滚脚本(bash)
```

`original/` 与 `modified/` 逐文件对照即可审阅全部改动;`dsh-plugin-session-improvements.patch` 是一键应用载体。两者内容完全一致(见 manifest 校验)。

## 前置条件

| 项 | 要求 |
|---|---|
| deepseek-harness 源码 | git 检出,基线 commit `47f943859b`(release 0.1.0-rc.5 系列);任何能干净应用本补丁的 commit 均可 |
| Node.js | 与仓库一致(LTS 即可) |
| pnpm | 11.x(仓库实测 11.7.0,与 lockfile 一致) |
| git | 2.x |

本补丁 **不新增任何依赖**(未改动任何 package.json),不改变存储布局与既有数据。

## 安装

### Windows(PowerShell)

```powershell
# 在 dsh-plugin-session-improvements 目录内执行,指向你的 deepseek-harness 检出
.\install.ps1 -HarnessRoot D:\src\deepseek-harness

# 先只检查补丁能否干净应用(不改动任何文件)
.\install.ps1 -HarnessRoot D:\src\deepseek-harness -CheckOnly

# 应用补丁 + 构建 + 跑受影响测试
.\install.ps1 -HarnessRoot D:\src\deepseek-harness -Build -Test
```

### Linux / macOS(bash)

```bash
./install.sh /path/to/deepseek-harness            # 检查并应用
./install.sh /path/to/deepseek-harness --check    # 只检查
./install.sh /path/to/deepseek-harness --build --test
```

脚本流程:
1. `git apply --check` 验证补丁可干净应用(失败则中止,不动任何文件);
2. 把 45 个目标文件的当前版本备份到 `<harness>/dsh-plugin-session-improvements-backup-<时间戳>/`(双保险,git 之外再留一份);
3. `git apply dsh-plugin-session-improvements.patch`;
4. 可选 `pnpm run build`(build:lib + build:web)与受影响测试。

### 手动安装(不用脚本)

```bash
cd <deepseek-harness 检出>
git apply /path/to/dsh-plugin-session-improvements.patch
pnpm run build
```

## 验证

```bash
# 全量构建
pnpm run build

# 会话持久化单测(删除路径:memory/jsonl/sqlite 三后端)
pnpm vitest run packages/session/session-persistence/tests/persistence.spec.ts

# 客户端/ host / test-support 全量单测
pnpm vitest run packages/client packages/host packages/test-support

# Web 端 e2e(含 归档→恢复→删除 完整生命周期;需先 pnpm run build)
pnpm vitest run --config vitest.web.config.ts apps/web/tests/workspace-management.e2e.ts
```

### 部署

重启你的 dsh 进程即可(例如 `dsh web` / `node --import tsx/esm apps/cli/src/bin.ts web`)。既有会话数据不受影响;已归档会话可立即在「已归档」区点击「恢复会话」,任意会话可删除。

## 回滚

```powershell
# Windows:一键回滚(反向应用补丁 + 恢复备份)
.\install.ps1 -HarnessRoot D:\src\deepseek-harness -Rollback

# 或手动
git -C <harness> apply -R /path/to/dsh-plugin-session-improvements.patch
# 或彻底恢复到基线
git -C <harness> checkout HEAD -- <file-list.txt 中列出的 45 个文件>
```

回滚只影响本补丁涉及的 45 个文件;补丁运行期间产生的数据变化(如已删除的会话)不会被恢复——删除本来就是持久不可逆的。

## 涉及文件(45)

按模块分组(完整清单见 `file-list.txt`):

- **host/apiproxy**:RPC 端点 `session.delete`、`workspace.unarchiveSession`、推送帧、schema、rpc-map、fetch 通道
- **workspace**:注册表 `unarchiveSession` / `forgetSession`(durable detach + 归档集清理)
- **session-persistence(+jsonl/sqlite)**:协调器 `delete` 串行化门禁、三后端 `deleteStored`
- **contract / client-runtime**:客户端契约、sessions manager `delete`、workspaces `unarchiveSession`、fixture/doubles
- **client/ui-workspace**:行菜单(删除/恢复)、确认对话框、三 surface 接线、i18n(zh/en)
- **tests**:持久化单测、UI 单测、web e2e、scaffold

## 许可证

MIT 协议,见 `LICENSE`。本补丁基于 MIT 协议的 deepseek-harness(Copyright (c) 2026 DeepSeek)源码,按 MIT 条款保留原版权声明;本仓库新增的文件(README、安装脚本、manifest)同样以 MIT 发布。

## 免责声明

- 补丁基于 deepseek-harness `47f943859b`。若上游演进导致 `git apply --check` 失败,请用 `files/original` 与 `files/modified` 对照人工合并(改动集中、边界清晰)。
- 会话删除为 **持久不可逆** 操作(日志文件与注册表记录同时清除);部署前请知悉。

---

## English summary

Drop-in patch for deepseek-harness adding **session restore (un-archive)** and **session delete** to the Web GUI (previously only rename/fork/archive existed). The host `session.delete` RPC disposes live agents when held, prunes the host session registry, detaches workspace durable accounts, and wipes the on-disk JSONL/SQLite log; `workspace.unarchiveSession` durably restores archived sessions and pushes `host/archived-sessions-changed` to all connected clients. 45 files changed, no new dependencies. Install: `git apply dsh-plugin-session-improvements.patch && pnpm run build`. Rollback: `git apply -R`. See `manifest.json` for per-file SHA256 of original vs modified copies under `files/`. Licensed MIT (see `LICENSE`); the patch derives from the MIT-licensed deepseek-harness codebase, with the upstream copyright notice preserved.
