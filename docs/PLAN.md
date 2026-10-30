# Zed 扩展追平计划（4gl-full / zed-bdl）

> **盘点日期**：2026-10-28（本次为**全量重写**，旧 PLAN 已删除）
> **参照物**：VSCode 插件 `vscode-bdl` **0.9.2**（33 条命令 / 50 个设置键 / 2 个侧边栏视图）
> **后端基线**：`bdl-lsp` **v0.3.16**（四平台 Release，2026-10-29）· `tiptop` **v0.1.10**（四平台 Release，2026-10-29）
> **本仓库基线**：`zed-bdl` **0.3.0**（0.2.0 已落地全部 P0–P4 能力；0.3.0 起有 tag 即发布流水线）
> **目的**：以 VSCode 侧**当前**已有进度为基准，把 Zed 侧推进到同等能力；平台做不到的部分**逐条给出已确认的降级方案**，不留"两边不一样"的模糊状态。
>
> **授权状态（用户 2026-10-28 已确认）**
> - ✅ 可以改**本仓库**（`zed-extension/`）。
> - ✅ 可以改 `bdl-lsp`：加 `workspace/executeCommand`、实现 `textDocument/codeLens`。
> - ✅ 可以改 `tiptop`：打 tag + 四平台 Release。
> - ⚠️ **新增发现、待单独确认**：`bdl-lsp` 加 `workspace/configuration`（Z-P3-1）——本次盘点后才发现 Zed 的 `settings` 通道需要服务端主动请求才生效；不做也能工作（配置仅在服务器启动时下发），只是改设置要重启。
> - ⚠️ 其他仓库（`vscode-bdl` 文档、`tree-sitter-*`）**未授权**，需要时单独确认。
>
> 本文件是 Zed 侧**唯一**计划与待办来源；VSCode 侧的待办在 `vscode-bdl/docs/TODO.md`。

---

## 0. 结论先说

| 维度 | VSCode 0.9.2 | Zed 现状（0.1.1） | 追平目标 | 处置 |
|---|---|---|---|---|
| 语言智能（诊断/悬停/跳转/引用/补全/重命名/格式化/Code Action/语义高亮） | ✅ 同一个 `bdl-lsp` | ✅ 同一个 `bdl-lsp` | ✅ 无需后端改动 | 看 §6.1 |
| 语法高亮 / outline / 括号 / 缩进 / SQL 注入 | ✅ TextMate | ✅ Tree-sitter（47 项 query 校验全绿） | ✅ 已对齐 | — |
| **用户配置是否真的生效** | ✅ 插件 `initializationOptions` + `didChangeConfiguration` | ❌ **设置根本没到服务端**（见 §4.4） | 🔧 修正下发路径 | **Z-P0-3** |
| 轻量档默认（不连库/不写盘） | ✅ 三开关默认 off | ❌ 一个都不发 → 服务端兜底 **启用** | 🔧 补默认 | **Z-P0-3** |
| 语义高亮 | ✅ 默认开 | ⚠️ Zed 默认 off，且缺 `semantic_token_rules.json` | 🔧 规则文件 + 文档 | **Z-P0-4** |
| 命令入口（33 条） | ✅ 命令面板/按钮/视图工具栏 | ❌ **无任何命令注册 API** | ⬇️ slash command（只读）+ task（写盘/长任务） | **Z-P1** |
| 链接资料视图（三级树 + 反查） | ✅ 侧边栏 TreeView | ❌ **无树视图 API** | ⬇️ **Code Lens 挂 MAIN 函数头** + 函数级反查 | **Z-P2 / Z-P3-3** |
| 字段资料视图（过滤/勾选/批量） | ✅ 侧边栏 TreeView | ❌ 无树视图 API | ⬇️ slash command 文本列表 + 悬停/补全 | **Z-P1 / §8** |
| 进度条 + 取消 | ✅ 通知式进度 | ❌ 无进度 API | ⬇️ task 终端流式输出 + 可取消 | §8 |
| 输出面板（`4gl` / `4gl 任务`） | ✅ OutputChannel | ❌ 无 | ⬇️ task 终端 + `zed: open log` | §8 |
| 编译错误回写 Problems | ✅ DiagnosticCollection | ❌ 无诊断注入 API | ❌ **永久差异**（只看终端） | §8 |
| 编辑器标题栏/右键按钮、状态栏、`when` 门控 | ✅ | ❌ 均无 API | ⬇️ 命令面板 + task + keymap | §8 |
| 二进制分发 | ✅ 平台 VSIX 内置 | ⚠️ 需手工构建 | 🔧 运行时自动下载（bdl-lsp Release 已就绪） | **Z-P4** |
| 版本兼容 | ⚠️ 无矩阵（VSCode 侧 P-10 亦未解） | ⚠️ artifacts 里的二进制已过期 | 🔧 `/bdl-env-check` 显示三方版本 | **Z-P4-4** |

**一句话**：Zed 侧能追平的是「配置正确性 + 语义高亮 + 只读命令入口 + 链接视图的 Code Lens 形态 + 自动下载」；
**追不平的是 VSCode 的 UI 容器能力**（树视图、输出面板、状态栏、标题栏按钮、Problems 注入），这五项按已确认方案降级，并在文档里写成永久差异。

---

## 1. 基线与事实来源

### 1.1 版本基线（实测，2026-10-28）

| 组件 | 版本 / 状态 | 证据 |
|---|---|---|
| `vscode-bdl`（4gl-full） | **0.9.2**，`bin/` 内置 `bdl-lsp` + `tiptop`，33 命令 / 50 设置键 / 2 视图 / 55 条 menus / 27 activationEvents / 0 keybindings | `vscode-extension/package.json:2,5,60,531-1019` |
| `bdl-lsp` | **0.3.16**，tag `v0.3.16`（2026-10-29 发布：executeCommand / Code Lens / workspaceSymbolProvider + **函数级反查** + `bdl.showInfo`），`.github/workflows/release.yml` 出四平台产物 + `SHA256SUMS`；**Release 产物已实测**：SHA256 校验通过、`bdl-lsp version` = 0.3.16、握手实测 `codeLensProvider` / `workspaceSymbolProvider: true` / 7 条 executeCommand（含 `bdl.showInfo`）都在 | `bdl-lsp/main.go:35`、`release.yml` |
| `tiptop` | **v0.1.10**（2026-10-29 首次发布）；新增 `release.yml`：tag `v*` → 四平台产物 + `SHA256SUMS` | `tiptop/main.go:40`、`.github/workflows/release.yml` |
| `zed-bdl`（本仓库） | **0.3.0**（P0–P4 已落地 + 发布流水线）；`src/` 拆为 `lib.rs` + `config.rs` + `binary.rs` + `download.rs` + `project.rs` + `slash.rs` + `version.rs`；10 个 `.scm`；**17 项**清单校验 + 47 项 query 校验 + 13 项发布校验 + **17** 个单元测试 | `extension.toml:4`、`Cargo.toml:3`、`tests/` |
| 本地已构建二进制 | `bdl-lsp 0.3.13`、`tiptop 0.1.8` —— **都过期**，`tiptop` 旧二进制缺 `download` / `-region` / `-login-profile` | 实跑 `artifacts/bin/* version` |

### 1.2 事实来源（本计划所有数字与结论的可核对出处）

| 结论类别 | 出处 |
|---|---|
| VSCode 命令/设置/视图/菜单数 | `vscode-extension/package.json`；`docs/COMMANDS.md`、`docs/FEATURES.md` §13 |
| VSCode 调用后端的真实参数 | `vscode-extension/src/linktools.ts`、`schema.ts`、`deploy.ts`、`build.ts`、`client.ts` |
| LSP 能力/自定义方法/配置形状/诊断码 | `bdl-lsp/internal/server/server.go:208-405`、`forceparse.go`、`linkui.go`、`schemaui.go`、`internal/config/config.go`、`docs/DIAGNOSTICS.md` |
| tiptop 子命令/参数/退出码/进度协议/目录约定 | `tiptop/internal/{linkcli,schemacli,deploycli,execcli,progress}`、`internal/oradb/oradb.go`、`README.md` |
| Zed 能力边界 | `zed_extension_api 0.7.0` crate 源码（本机 `bdl-lsp/artifacts/toolchain/cargo/registry/.../zed_extension_api-0.7.0`，即本扩展实际编译所用）+ zed.dev 官方文档（languages / configuring-languages / tasks） |
| Zed 设置语义 | zed.dev `configuring-languages.md`：`initialization_options` 只在启动时下发一次；`settings` 作为 **Configuration Request** 的应答，服务端不问就不发 |

### 1.3 与旧 PLAN 的三点重要更正

| 旧结论 | 实测更正 |
|---|---|
| 「Zed 侧原样透传用户设置，服务端兜底 true」 | **更严重**：`lsp.bdl-lsp.settings` 根本不会到达 `bdl-lsp`（服务端从不发 `workspace/configuration`）。自定义键、`link.mode`、`diagnostics` 在 Zed 上今天**全部无效**。→ Z-P0-3 / Z-P3-1 |
| 「二进制自动下载的前置是 bdl-lsp 要有 Release」 | **前置已完全满足**：`bdl-lsp`（**v0.3.16**）与 `tiptop`（v0.1.10）都有四平台 Release + `SHA256SUMS`。→ Z-P4-1 / Z-P4-2 均已落地 |
| 「跨仓库文档 `bdl-lsp/docs/PENDING.md` 是待办唯一清单」 | 该文件**已不存在**（现只有 `DIAGNOSTICS.md` + `FEATURES.md`）；VSCode 侧唯一待办是 `vscode-bdl/docs/TODO.md`，Zed 侧唯一待办是**本文件**。 |

> 另需注意：`vscode-bdl/docs/FEATURES.md` 头部仍写 0.6.2、`COMMANDS.md` 里的命令数与设置键数互相矛盾、文档写了 `bdl/linkReferences` 但源码从未发送该请求。**追平时一律以源码/`package.json` 为准，不要抄 VSCode 侧文档的数字。**

---

## 2. VSCode 0.9.2 能力基线（追平的靶子）

### 2.1 33 条命令（全部 `category: "4gl"`），按组

| 组 | 条数 | 命令 |
|---|---|---|
| 服务器/排障 | 3 | 重启语言服务器、显示语言服务器信息、强制解析当前文件 |
| 项目初始化 | 1 | 初始化项目（从生产服务器拉取代码） |
| 上传/下载 | 3 | 下载当前文件、上传当前文件、预演上传 |
| 链接资料 | 9 | 刷新、反查引用程序、显示更多反查结果、迁移项目资料目录、从 CSV 导入、按模组更新、全量更新、查看状态、从数据库更新 |
| 编译/链接/预览 | 6 | 4GL 预演编译/编译/链接、Form 预演编译/编译/预览画面 |
| 数据库字段 | 11 | 从 CSV 导入、刷新、正则过滤表名、清除过滤、同步选中的表、复制列定义、打开表资料文件、从数据库同步、同步已选中的表、全选当前列表、清除勾选 |

### 2.2 50 个设置键（3 组）

- **基本设置 22 键**：`server.path`、`tools.path`、`server.logLevel`、`trace.server`、`generoVersion`、`diagnostics`、`format.{keywords,indentStyle,indentSize}`、`index.enable`、`globals.searchPaths`、`perRoots`、`builtins.{enable,paths,disable}`、`ignore.{files,fields,forms}`、`limits.{maxFileBytes,maxFileLines,maxIssues,parseTimeoutMs}`
- **账号、生产环境、配置 17 键**：`prod.oracle.{host,port,service,user}`、`prod.deploy.{host,port,user,region,strictHostKey}`、`link.{mode,dataDir,moduleRoots,globalModules}`、`schema.{mode,dataDir,batchSize,timeoutSec}`
- **上传编译链接 11 键**：`deploy.enable`、`prod.deploy.transport`、`prod.deploy.{localRoot,remoteRoot}`、`build.enable`、`build.<lang>.<mode>.command` ×6

> 映射到 Zed 时**去掉 `bdl.` 前缀**（`bdl-lsp` 的 `config.Settings` 无前缀），仅 Zed 扩展自用的键收进 `ext.*`（见 §5.2）。

### 2.3 VSCode 专有 API（Zed 无等价物 → 必须降级）

`registerCommand`(28 处) · `TreeDataProvider`/`createTreeView`/`TreeItemCheckboxState` · `OutputChannel` · `setStatusBarMessage` · `withProgress`+取消 · `showQuickPick`/`showInputBox`/`showOpenDialog` · 消息框 · `createTerminal` · `FileSystemWatcher` · `setContext` + menus `when`/`enablement` · `editor/title`+`editor/context`+`view/title`+`view/item/context` 按钮 · 剪贴板 · `globalStorage`/`logUri` · `languages.getDiagnostics`（按钮门控） · `executeDocumentSymbolProvider`（MAIN 门控）。

### 2.4 VSCode 实际怎么调后端（Zed 要照抄的契约）

| 场景 | 真实命令 |
|---|---|
| 启动 LSP | `bdl-lsp serve [--log-level <级别>]`，stdio，cwd = 工作区根 |
| 自定义请求 | 仅 `bdl/forceParse`、`bdl/linkTree`、`bdl/schemaTables`、`bdl/schemaColumns`（`bdl/linkReferences` **未使用**） |
| 链接资料 | `tiptop link import -csv … -root …` / `link sync -root … -source golang -host … -service … -user … [-files|-modules]` / `link status -root …` |
| 字段资料 | `tiptop schema import -csv … -root … -out …` / `schema sync … -batch-size 200 -timeout 120 [-tables|-tables-file|-prune]` |
| 上传/下载 | `tiptop upload/download -workspace <root> -file <相对路径> [-dry-run]` |
| 编译/链接/预览 | `tiptop exec -command "<展开后的模板>" [-region …] [-login-profile …]` |
| 整包部署 | **插件从不调用** `tiptop deploy`（只有 `-dry-run`/`-list` 是 CLI 用法） |

---

## 3. 后端接口契约（实现时必须按此硬编码）

### 3.1 `bdl-lsp`（LSP 服务端）

| 项 | 事实 | 对 Zed 的影响 |
|---|---|---|
| 标准方法 | initialize / didOpen / didChange / didClose / documentSymbol / workspace/symbol / hover / definition / references / formatting / completion / completionItem/resolve / prepareRename / rename / codeAction / semanticTokens/full | 全部由 Zed 宿主消费，扩展不用管 |
| 自定义 request | `bdl/forceParse`（参数 `{"uri": "…"}`，**平铺**）、`bdl/linkTree`、`bdl/linkReferences`、`bdl/schemaTables`、`bdl/schemaColumns`（这四个用 `{"textDocument":{"uri":…}}`，`schemaTables` 用 `{query,limit}`） | **Zed 扩展发不了自定义请求** → 必须转成 `workspace/executeCommand`（Z-P3-2） |
| 自定义 notification | `bdl/parseDone`（服务端→客户端） | Zed 扩展收不到 → "强制解析完成"的耗时回执只能靠服务端写日志或 `executeCommand` 的返回值 |
| `workspace/executeCommand` | **无**（无 `ExecuteCommandProvider`） | Z-P3-2 新增 |
| `workspace/configuration` | **从不请求**；配置只走 `initialize` 的 `initializationOptions` 与客户端主动 `workspace/didChangeConfiguration` | Z-P0-3 用 initializationOptions 下发；Z-P3-1 给服务端加 `workspace/configuration` 才能真正热更新 |
| 配置形状 | `{"generoVersion","logLevel","globals":{"searchPaths"},"perRoots","diagnostics":{码:级别},"builtins":{…},"link":{enable,mode,dataDir,moduleRoots,globalModules},"schema":{enable,mode,dataDir},"index":{enable},"ignore":{…},"format":{…},"limits":{…}}`，**无 `bdl.` 前缀**；未知键被忽略 | 与 VSCode 的 `bdl.*` 一一对应，去掉前缀即可 |
| 默认值陷阱 | `LinkEnabled()`/`SchemaEnabled()` 在客户端未下发时返回 **true** | Zed 必须显式下发 `mode: "off"`（或 `enable:false`）才等于 VSCode 的轻量档 |
| 工作区根 | 按 `rootUri` → `workspaceFolders[0]` → `rootPath` 解析；三级都空则绝对路径类功能静默降级 | Zed 必须保证 rootUri/workspaceFolders 有值 |
| 诊断 | 14 个静态码 + 动态 `missing-<kind>`；`link-data-legacy-dir` 默认 **hint**、`record-member-unknown` 默认 **off**、`file-too-large` 默认 **warning** | 文档与设置示例照 `bdl-lsp/docs/DIAGNOSTICS.md` |
| CLI | `serve [--log-level|--log-file|--stdio]`、`check [--json|--max-issues|-q] <文件…>`、`version` | Z-P0-5 的 `/bdl-env-check` 用 `version` 探测 |
| 环境变量 | **服务端不读任何环境变量**；`BDL_LSP_PATH` 是客户端侧约定 | 扩展自行实现 |

### 3.2 `tiptop`（采集/部署 CLI）

| 子命令 | 关键参数 | 退出码 / 输出 |
|---|---|---|
| `link import` | `-csv`(必填) `-root` `-out` `-roots` `-modules` `-files` `-dry-run` `-replace` | 0/1/2；stdout 中文报告，**无 JSON** |
| `link sync` | `-source golang\|command\|file` `-command` `-file` `-host` `-port` `-service` `-user` `-query` `-modules` `-files` `-dry-run` `-root` `-out` | 同上 |
| `link status` | `-root` `-out` `-global` | 无资料 → **退出码 1** |
| `schema import` | `-csv`(必填) `-root` `-out` `-tables` `-tables-file` `-only-new` `-dry-run` | 0/1/2 |
| `schema sync` | `-source golang\|file` `-file` `-host` `-port` `-service` `-user` `-owner` `-query` `-root` `-out` `-tables` `-tables-file` `-only-new` `-prune` `-dry-run` `-batch-size`(默认200) `-timeout`(默认120s) | 同上；进度走 stderr |
| `schema status` | `-root` `-out` | 无资料 → 1 |
| `deploy` | `-target` `-config` `-workspace` `-dry-run` `-no-compile` `-no-upload` `-json` `-list` `[文件…]` | 0/1/2；**唯一有 `-json` 的场景** |
| `upload` / `download` | `-file`(必填,相对路径) `-workspace` `-config` `-target` `-dry-run` `-json` | 0/1/2 |
| `exec` | `-command`(必填) `-file` `-workspace` `-config` `-target` `-region` `-login-profile` `-dry-run` `-json` | **退出码 = 远程退出码** |

- **进度协议（stderr）**：`进度\t<阶段>\t<详情>[\t<i>\t<n>]`，阶段固定为 `采集 / 扫描源码 / 成链 / 解析 / 清理 / 写入完成`。`\t` 分隔，只写 stderr。
- **目录约定**：`<项目根>/.project/{secrets.json, link/{links.jsonl,links.meta.json}, schema/{tables.json,tables/*.json}, deploy/deploy.json}`；旧布局（`.link/`、`.project/.schema/`、`.project/deploy.json`、`.bdl-lsp/deploy.json`）**只读兼容**。
- **secrets**：固定 `<项目根>/.project/secrets.json`，`{"<用户名>":"<密码>"}`，`"*"` 为默认；Unix 必须 `chmod 600`（否则直接报错），Windows 跳过校验。密码优先级：配置内 `${env:VAR}` → 环境变量 `BDL_ORA_PASSWORD` → `secrets.json`。
- **⚠️ artifacts 里的 `tiptop` 是 0.1.8 且缺 `download` / `-region` / `-login-profile`**；Zed 侧联调必须用当前源码构建（`make build` / `scripts/build.ps1`）。

---

## 4. Zed 平台能力边界（已核实）

> 依据：`zed_extension_api 0.7.0`（WIT 冻结在 `since_v0.6.0`，兼容 Zed **0.205.x**）+ zed.dev 官方文档。
> 宿主源码本机不存在，manifest 字段以 GitHub main 分支 `crates/extension/src/extension_manifest.rs` 与官方文档为准；**Zed 安装后的真实行为必须实机验证**。

### 4.1 能做

| 能力 | 证据 |
|---|---|
| 执行外部进程（**阻塞式**，收集 stdout/stderr，**无 cwd 字段**） | `wit/since_v0.6.0/process.wit:28` `run-command`；`src/process.rs` |
| 下载文件 + 设可执行 | `extension.wit:57,60` `download-file` / `make-file-executable` |
| 查 GitHub Release / 按 tag | `github.wit:29,34` |
| LSP 安装状态提示 | `extension.wit:63` `set-language-server-installation-status`（`CheckingForUpdate`/`Downloading`/`Failed(msg)`） |
| 读工作区文件 / `which` / shell env | `extension.wit:68-76` |
| slash command（Agent 面板）+ 参数补全 | `extension_api.rs:142-158`；manifest `[slash_commands.<name>]`（只有 `description` + `requires_argument`） |
| 扩展级语义 token 规则 | 语言目录放 `semantic_token_rules.json`（用户规则 > 扩展规则 > Zed 内置） |
| Code Lens / Call Hierarchy / Inlay Hints | **宿主** 的 LSP 客户端功能：服务端实现即可，用户开 `code_lens`（默认 `off`） |
| 扩展 manifest 的 `capabilities`（`process:exec` / `download_file` / `npm:install`） | 官方 capabilities 文档 |

### 4.2 不能做（→ 永久差异或降级）

| 不能做 | 说明 |
|---|---|
| 注册任意命令到命令面板 | `Extension` trait 19 个方法里没有任何命令注册 |
| 树视图 / 侧边栏面板 | 无 API |
| 状态栏、编辑器标题栏/右键按钮、视图工具栏 | 无 API |
| 独立输出面板 / 流式日志 | 无 API（只有 task 的终端与 `zed: open log`） |
| 注入诊断（把远程编译错误写进 Problems） | 无 API |
| 扩展主动发 LSP 自定义请求 | trait 无 `send_request`（所以 `bdl/linkTree` 等只能靠 `executeCommand` 或直接读文件） |
| 扩展定义 task | 官方文档把"语言扩展"列为 task 来源之一，但 manifest **没有 task 字段**；该路径实为 `runnables.scm`（行内 ▶ + `tags` 绑定）与 DAP 的 task/build 模板，**不能注册任意命令** → 本方案用「生成项目 `.zed/tasks.json` + 文档模板」 |
| 读取任意 Zed 设置分类 | 公开 API 只有 `LspSettings::for_worktree`（即 `lsp.<server>` 整块），其它分类读不到 → **扩展配置必须放在 `lsp.bdl-lsp.settings` 里** |
| **在扩展里内置平台二进制** | ★ **做不到**（2026-10-29 查 Zed main 源码证实，三重限制）：① `ExtensionManifest` 没有 `bin`/`assets` 字段；② 打包只复制白名单（`extension.toml`/`extension.wasm`/`grammars`/`themes`/`languages`/`snippets`…），任意 `bin/` 会被丢掉；③ wasm 沙箱只 preopen 扩展自己的 work 目录，**读不到扩展安装目录**（`Worktree` 的 `read-text-file`/`which` 都是**工作区/PATH** 作用域）。官方发布要求也明写 "Do not bundle a language server with the extension" → **只能运行时 `download_file` 下载**（Zed 官方扩展 glsl/proto 就是这么做的） |

### 4.2.1 ★ Zed 扩展的安装/发布模型（2026-10-29 查 Zed main 源码证实）

| 路径 | 谁编译 wasm | 客户端要什么 |
|---|---|---|
| **注册表安装** | registry CI（`zed-industries/extensions`）用 `zed-extension` CLI 在**发布时** release 编译，打成 `archive.tar.gz` 传 blob store | 客户端只**下载**预构建 wasm，**不编译** |
| **dev extension** | 用户机器上 `cargo build --target wasm32-wasip2`（**无 `--locked`**；debug 模式），装成 symlink 指向源码目录 | 需要 rustup + `wasm32-wasip2`；带 grammar 还需要 wasi-sdk（Zed 自动下载，或 `WASI_SDK_PATH`） |

- grammar 由 Zed 本地用 wasi-sdk 的 clang 编译 `parser.c`（**不需要 tree-sitter CLI**）；
  grammar 仓库是 git 拉取后按 `rev` checkout 的。
- ⇒ 本仓库提交 `Cargo.lock` 是有用的（cargo 用它作解析种子），但 Zed **不强制**它
  （没有 `--locked`）；dev 安装时 cargo 甚至可能改写工作区里的 `Cargo.lock`。
- ⇒ 本扩展的 GitHub Release **不能替代**安装；它的价值是**分发两个后端二进制**
  （扩展运行时下载），见 Z-P4-6。


### 4.3 task 的可用能力（替代按钮/命令/进度的主力）

- 变量：`$ZED_FILE`、`$ZED_RELATIVE_FILE`、`$ZED_RELATIVE_DIR`、`$ZED_STEM`、`$ZED_WORKTREE_ROOT`、`$ZED_LANGUAGE`、`${VAR:默认值}`；`cwd` 默认项目根。
- 字段：`command` / `args` / `env` / `cwd` / `use_new_terminal` / `allow_concurrent_runs` / `reveal` / `hide` / `shell` / `show_summary` / `show_command` / **`save`（`all`/`current`/`none`，上传前保存脏文档用它）** / `tags` / `hooks`。
- 取消：`use_new_terminal: false` + `allow_concurrent_runs: true` 可在重跑时取消上一次。
- keymap 绑定：`{"bindings": {"alt-g": ["task::Spawn", {"task_name": "…"}]}}`。
- **task 读不到 Zed 设置** → 需要参数的 task 由「生成脚本」把值写进 `.zed/tasks.json`（见 §5.3）。

### 4.4 ★ 关键结论：Zed 设置如何到达 `bdl-lsp`

zed.dev 官方语义：
- `lsp.<server>.initialization_options` → **启动时下发一次**，改动必须重启服务器；
- `lsp.<server>.settings` → Zed **在启动时与设置变化时**都用 `workspace/didChangeConfiguration` 推给服务端（`crates/project/src/lsp_store.rs:694-721` 启动、`:9831-9932` 变化时），而不是"只等服务端请求 `workspace/configuration`"—— **这一条修正了 2026-10-28 的判断**；
- `lsp.<server>.settings` → 服务端发 **`workspace/configuration`** 时作为应答返回（"May be queried by the server multiple times"）。

`bdl-lsp` **从不发 `workspace/configuration`**（全仓库无该字符串）。因此：

1. 今天 Zed 用户在 `lsp.bdl-lsp.settings` 里写的一切（`diagnostics`、`link.mode`、`format.*`…）**都不会生效**；
2. 修法（本仓库，无需跨仓库）：在 `language_server_initialization_options` 里下发**有效配置** = 默认值 ⊕ `settings`（去掉 `ext`）⊕ `initialization_options`，并补 `link.mode="off"` / `schema.mode="off"` 默认；
3. ~~想让"改设置立即生效"，需要 `bdl-lsp` 支持 `workspace/configuration`~~ → **结论已推翻**（2026-10-29 查 Zed 源码）：Zed 主动用 `workspace/didChangeConfiguration` 推设置（启动 + 每次设置变化），而 `bdl-lsp` **一直**在处理它（`internal/server/config.go` 的 `handleDidChangeConfiguration` → `cfg.Apply` + 重算诊断）。所以**改设置本来就会热应用**；`workspace/configuration` 再做一遍是冗余 → **Z-P3-1 不采纳**。扩展侧仍保留 `initializationOptions` 下发（兜底给不发 didChangeConfiguration 的客户端 + 注入轻量档默认）。

---

## 5. 总体方案

### 5.1 三层入口模型

```text
① LSP 原生（零入口，Zed 宿主消费）
   诊断 / 悬停 / 跳转 / 引用 / 补全 / 重命名 / Code Action / 格式化 / 语义高亮
   + Code Lens（服务端实现后，用户开 code_lens: "on"）

② slash command（Agent 面板；只读、短、不写盘）
   /bdl-env-check  /bdl-link-status  /bdl-schema-status
   /bdl-schema-tables <正则>  /bdl-schema-columns <表>
   /bdl-deploy-list  /bdl-deploy-dry-run  /bdl-force-parse

③ task（终端；写盘 / 长任务 / 需要交互输入的）
   资料采集与导入 / 上传 / 下载 / 编译 / 链接 / 预览 / 整包部署 / 项目与工程初始化
   终端里的路径可点击直达文件，进度行原样可见，可手动取消
```

**原则**：会话写盘的操作（采集/导入/同步/上传/下载/部署）**只给 task**；slash command 只做只读查询与只打印的预演，避免误触改项目。

### 5.2 配置单一来源

用户在 `.zed/settings.json` 只写一处 `lsp.bdl-lsp.settings`：

- **发往 `bdl-lsp` 的键（无 `bdl.` 前缀）**：`generoVersion`、`logLevel`、`globals`、`perRoots`、`diagnostics`、`builtins`、`link{mode,dataDir,moduleRoots,globalModules,lensMax}`、`schema{mode,dataDir}`、`index`、`ignore`、`format`、`limits`。
- **仅 Zed 扩展自用（不下发）**：`ext.tools.path`、`ext.schema.{batchSize,timeoutSec}`、`ext.prod.oracle.*`、`ext.prod.deploy.*`、`ext.deploy.enable`、`ext.build.{enable,4gl.*,per.*}`、`ext.download.{bdlLsp,tiptop}`。
  语言服务器日志级别统一用下发的 `logLevel`（`logLevel != "info"` 时扩展同时把它作为 `serve --log-level <级别>` 参数，与 VSCode 侧一致）。
- 兼容路径：`lsp.bdl-lsp.initialization_options` 仍可用（优先级最高，作为逃生口）；`binary.path` / `binary.arguments` / `binary.env` 沿用 Zed 原生。

### 5.3 命令入口怎么落地

| VSCode 入口 | Zed 替代 | 落地方式 |
|---|---|---|
| 命令面板 33 条 | task（`.zed/tasks.json`）+ slash command | 仓库内提供 task 模板；`4gl: 初始化 Zed 工程` 任务用交互式脚本生成 `.zed/{settings.json,tasks.json,bdl-tool.json}`（凭证/模板值来自脚本提问，不依赖扩展读设置） |
| 编辑器标题栏/右键按钮 | 命令面板 `task: spawn` / `task: rerun` + keymap 绑定 | 文档给 keymap 片段（如 `alt-u` = 上传当前文件） |
| 视图工具栏按钮 | slash command | 只读命令 |
| 进度条 + 取消 | task 终端（流式 stdout/stderr）+ `allow_concurrent_runs` | task 定义 |
| OutputChannel | task 终端 + `zed: open log` | 文档说明 |
| 通知/确认弹窗 | task 终端里的交互提问（`read`/PowerShell `Read-Host`） | 初始化脚本 |
| 状态栏/Problems 注入/树视图 | **不做** | 文档写清永久差异 |

---

## 6. 差距矩阵（逐项处置）

图例：✅ 已对齐 · 🔧 待做 · ⬇️ 降级替代 · ❌ 平台做不到 · 🔒 需跨仓库（**本次已授权**）

### 6.1 语言与配置

| 能力 | VSCode 0.9.2 | Zed 现状 | 处置 | 任务 |
|---|---|---|---|---|
| 诊断/悬停/跳转/引用/补全/重命名/Code Action/格式化 | ✅ | ✅ 同一个 `bdl-lsp` | ✅ | — |
| 项目符号搜索（工作区索引） | ✅ `Ctrl+T` | ❌ 服务端实现了 `workspace/symbol`，但**未声明 `workspaceSymbolProvider`**；Zed 对 `None` 的 server **直接跳过**（源码 `crates/project/src/lsp_store.rs:9438-9447`） | 🔒 需 `bdl-lsp` 补一行 `WorkspaceSymbolProvider: true`（**已由源码证实，不再是猜测**；等待授权） | Z-P3-6 |
| 语义高亮 | ✅ 默认开 | ⚠️ Zed 默认 `off`，扩展规则文件**已加**（0.2.0） | ✅ 落地；文档教开 `semantic_tokens: "combined"`；着色效果待实机（§11.2 #6） | Z-P0-4 |
| 设置是否生效 | ✅ | ❌ 未到服务端 | ✅ **0.2.0 已修**：有效配置从 `initializationOptions` 下发 + 补 `mode:"off"` 默认；待实机（§11.2 #4/#5） | Z-P0-3 |
| 设置热更新 | ✅ `didChangeConfiguration` | ✅ **本来就有**：Zed 在启动与设置变化时推送 `didChangeConfiguration`，`bdl-lsp` 热应用并重算诊断 | ✅ 已对齐；**Z-P3-1（服务端加 `workspace/configuration`）不需要做**（原判断有误） | — |
| 大文件跳过提示 + 强制解析 | ✅ 标题栏按钮 + 状态栏 | ❌ 无按钮 | ⬇️ `/bdl-force-parse` 已就位（当前返回"需 Z-P3-2 + 替代办法"）；`lsp command selector` 亦可 | Z-P3-2 |

### 6.2 命令与运行

| 能力 | VSCode 0.9.2 | Zed 现状 | 处置 | 任务 |
|---|---|---|---|---|
| 资料采集/导入/局部同步（link 5 条 + schema 11 条） | ✅ | ❌ | ⬇️ task 调 `tiptop …`（**0.2.0 起**：仓库提供 22 条 task 模板 + 交互式生成脚本 `scripts/zed/`） | Z-P1-2 |
| 只读查询（状态/表清单/列清单/链接关系/目标列表/预演） | ✅ | ❌ | ✅ **0.2.0 已落地**：9 条 slash command（读 `.project/` 资料；`/bdl-deploy-dry-run` 调 CLI） | Z-P1-1 |
| 上传/下载/预演上传（单文件） | ✅ | ❌ | ⬇️ task（`$ZED_RELATIVE_FILE` + `"save": "current"`；0.2.0 起由生成脚本产出） | Z-P1-2 |
| 编译/链接/预览（生产端执行，6 条） | ✅ | ❌ | ⬇️ task 调 `tiptop exec`（`-region` / `-login-profile` 由生成脚本按区写入） | Z-P1-2 |
| 整包部署（预演/列目标/执行） | ✅ CLI 用法 | ❌ | ⬇️ task 调 `tiptop deploy`；只读的预演/列目标另有 slash command | Z-P1-1 / Z-P1-2 |
| 项目初始化（拉代码） | ✅ 向导 + 集成终端 | ❌ | ⬇️ task 调 `scripts/init-project` 同款脚本（终端内交互；生成脚本可写入） | Z-P1-2 |
| 迁移旧资料目录（`.link/` → `.project/link/`） | ✅ 命令 | ❌ | ✅ **0.2.0 已落地**：生成脚本产出 `.zed/bdl/migrate-data.{sh,ps1}` + task（只搬移、绝不覆盖，空旧目录顺手删） | Z-P2-2 |
| 反查引用程序 | ✅ 视图分页 | ❌ | ⬇️ **函数级反查已实现**（`bdl-lsp` 0.3.16，`9ca180a`）：函数定义那行挂「🔗 函数名 被 N 处调用」，点它跳到第一处调用；要看全部用 Zed 原生「查找引用」 | Z-P3-3 ✅ |
| 进度通知 + 取消 | ✅ | ❌ | ⬇️ task 终端原样输出 + 重跑取消（生成脚本已给 6 条 exec + deploy 加 `allow_concurrent_runs`） | Z-P1-2 |

### 6.3 视图与输出

| 能力 | VSCode 0.9.2 | Zed 现状 | 处置 | 任务 |
|---|---|---|---|---|
| 链接资料三级树（点击跳转） | ✅ | ❌ 无树视图 API | ⬇️ **Code Lens 挂在 MAIN 函数头**：✅ **服务端已实现**（`bdl-lsp c0102a2`，每子文件一条、`link.lensMax` 上限 10 + 汇总行、`bdl.openLink` → `window/showDocument`）；**点击链路已由 Zed 源码证实**（`apply_code_action` → `workspace/executeCommand`；`window/showDocument` 会真的打开文件），**只剩实机看观感**（Z-P2-1） | Z-P3-3 ✅ |
| 字段资料树（正则过滤/勾选/批量/复制列定义） | ✅ | ❌ | ⬇️ **0.2.0 已落地** `/bdl-schema-tables`（子串 + `^`/`$` 锚点）+ `/bdl-schema-columns`；悬停与补全承担"看列说明"；批量同步用 task 的 `-tables`/`-tables-file`。**与 VSCode 的差异**：无勾选/多选、无完整正则、无「复制列定义」 | Z-P1-1 |
| 输出面板（`4gl` / `4gl 任务`） | ✅ | ❌ | ⬇️ task 终端 + `zed: open log` | §8 |
| 编译错误回写 Problems | ✅ | ❌ | ❌ 永久差异：只看终端 | §8 |
| 状态栏 / 标题栏按钮 / 视图工具栏 / `when` 门控 | ✅ | ❌ | ⬇️ 命令面板 + keymap；门控由脚本自查并提示 | §8 |
| 运行日志落盘 | ✅ `last-run-*.log` | ❌ | ⬇️ task 终端可复制；可选：生成脚本把输出 `tee` 到 `.project/logs/` | Z-P1-2（可选） |

### 6.4 分发与版本

| 能力 | VSCode 0.9.2 | Zed 现状 | 处置 | 任务 |
|---|---|---|---|---|
| 二进制内置（平台包） | ✅ | ❌ | ✅ **Z-P4-1 / Z-P4-2 都已落地**：`bdl-lsp`（Release **v0.3.15**）与 `tiptop`（Release v0.1.10）都能按平台自动下载；本地已有则优先不下载 | Z-P4-1 / Z-P4-2 |
| `bdl-lsp` Release | — | ✅ 已有 **v0.3.15** + 四平台 + SHA256SUMS | 直接可用（含 executeCommand / Code Lens / workspaceSymbolProvider） | — |
| `tiptop` Release | — | ✅ **已发 v0.1.10**（四平台 + `SHA256SUMS`，2026-10-29） | 流水线 `tiptop/.github/workflows/release.yml`；tag 推送自动出包 | Z-P3-4 |
| 下载状态反馈 | ✅ 进度条 | ❌ | 🔧 `set_language_server_installation_status` + slash 文本 | Z-P4-3 |
| 版本兼容矩阵 | ⚠️ 未解（VSCode P-10） | ⚠️ artifacts 二进制过期 | 🔧 `/bdl-env-check` 显示三方版本与最低要求 | Z-P4-4 |
| 平台覆盖 | Linux/Windows 已验，macOS 待验 | v1 只承诺 Linux+Windows | 实机清单区分必须/后续 | Z-P5-1 |

---

## 7. 阶段与任务

> 编号规则：`Z-P<阶段>-<序号>`；每条给「落点 / 验收 / 依赖 / 写作用域」。
> 写作用域是给并行协作用的（同一文件不要两人同时改）。

### P0 · 配置地基与文档（只改本仓库，立即做）

> **进展（2026-10-29）**：Z-P0-1…Z-P0-6 **代码与文档已落地**，版本 **0.2.0**；
> 护栏全绿（清单 17 项 / query 47 项 / `cargo test` 3 项 / wasm 构建 198 KB）。
> 仍待**实机验收**：§11.2 #1–#7、#19（本沙箱无 GUI，验不了 UI 行为）。

| # | 任务 | 落点 | 验收 | 写作用域 |
|---|---|---|---|---|
| **Z-P0-1** | 三份文档重建（本文件 + `README.md` + `docs/USER-GUIDE.md`），全部口径对齐 0.9.2/v0.3.14/0.1.10 | `docs/PLAN.md`、`README.md`、`docs/USER-GUIDE.md` | 三份文档互相引用一致；全文无 `bdl-lsp link`/`bdl-lsp deploy`/`link.maxAgeDays`/`link.sync.*` | 三份文档 |
| **Z-P0-2** | 版本 0.1.1 → **0.2.0** | `extension.toml:4`、`Cargo.toml:3` | 两处一致；`verify-manifest.py` 通过 | `extension.toml`、`Cargo.toml` |
| **Z-P0-3** | **配置下发修正**：`language_server_initialization_options` 返回「默认值 ⊕ `settings`(去掉 `ext`) ⊕ `initialization_options`」，并补 `link.mode="off"`、`schema.mode="off"`；`language_server_workspace_configuration` 返回同一份；`logLevel != "info"` 时同时作为 `serve --log-level` 参数 | `src/lib.rs` | 空设置时服务端拿到 `mode:"off"`（对照 `bdl-lsp` 的 `LinkEnabled`）；用户在 `settings` 里写的 `diagnostics`/`format` 生效；`ext` 不下发；`--log-level` 与 VSCode 一致 | `src/lib.rs` |
| **Z-P0-4** | 语义高亮规则：`languages/bdl/semantic_token_rules.json` + `languages/per/semantic_token_rules.json`（按 bdl-lsp legend：`variable/parameter/function/struct/property/keyword`） | 两个语言目录 + `verify-manifest.py` | 新文件被校验；开 `semantic_tokens: "combined"` 后自定义符号着色（实机） | `languages/**`、`tests/verify-manifest.py` |
| **Z-P0-5** | 二进制定位扩展：新增 `tiptop` 四级查找（`ext.tools.path` → `TIPTOP_PATH` → 工作区 `.bdl-lsp/bin/tiptop[.exe]` → `PATH`），错误文案可操作 | `src/lib.rs`（抽 `binary.rs` 亦可） | 找不到时有可操作提示；与 `bdl-lsp` 的查找语义一致 | `src/lib.rs` |
| **Z-P0-6** | 校验脚本扩展：`verify-manifest.py` 增加「`[slash_commands.*]` 声明 ↔ `src/` 的 `SLASH_COMMANDS` 常量一一对应」「`semantic_token_rules.json` 存在且 token_type/modifiers 属于 bdl-lsp legend」「`slash_commands` 必须有 description」；后续新增 **`verify-docs.py`**（文档契约：版本三处一致 / 命令条数与护栏数字对拍 / 无过期引用） | `tests/verify-manifest.py`、`tests/verify-docs.py` | 故意写错命令名/规则名/文档数字时校验失败（14 → 17 项；文档 9 项） | `tests/**` |

**P0 验收门槛（任何提交前必过）**

```bash
cd /code/workspace/zed-extension
python3 tests/verify-manifest.py
export PATH="/code/workspace/tree-sitter-per/node_modules/.bin:$PATH"
export HOME=/code/workspace/bdl-lsp/artifacts/home
node tests/verify-queries.mjs
source /code/workspace/bdl-lsp/scripts/dev-env.sh   # Rust + wasm32-wasip2
cargo build --release --target wasm32-wasip2
```

### P1 · 命令入口（只改本仓库）

> **进展（2026-10-29）**：Z-P1-1…Z-P1-4 **全部落地**并提交（`57a433b`）：
> 9 条 slash command（`src/slash.rs` + `src/project.rs`；`/bdl-link-chain` 为 Z-P2-2 的替代视图）、capability 声明
> （格式已从宿主 `ExtensionManifest`/`capabilities.rs` 核实）、
> `scripts/zed/init-workspace.{sh,ps1}`（20 固定 + 1 可选 task；bash 版实跑通过，
> ps1 本机无 pwsh 未实跑、留 CI）、`/bdl-env-check` 深度版。
> 新增护栏 `tests/verify-init-script.py`（原 9 项；Z-P2-2/Z-P2-4 后 14 项：deploy.json 两场景 + 迁移 helper + ext.build 覆盖）。
> 护栏：清单 17 项 ✓ · init-script 9 项 ✓ · query 47 项 ✓ · `cargo test` 6 项 ✓ · wasm 274 KB ✓。
> 仍待**实机验收**：§11.2 #8–#10c（slash/task/capability/生成脚本）。

| # | 任务 | 落点 | 验收 | 写作用域 |
|---|---|---|---|---|
| **Z-P1-1** | 实现 `run_slash_command` + `[slash_commands.*]` 声明：9 条只读命令（`/bdl-env-check`、`/bdl-link-status`、`/bdl-link-chain <代码>`、`/bdl-schema-status`、`/bdl-schema-tables <过滤>`、`/bdl-schema-columns <表>`、`/bdl-deploy-list`、`/bdl-deploy-dry-run`、`/bdl-force-parse`） | `src/slash.rs` + `src/project.rs`、`extension.toml` | 命令名与声明一一对应（Z-P0-6 校验）；读文件类命令在无资料时给引导文案而非报错；`/bdl-force-parse` 在 P3-2 之前明确提示"需要服务端支持" | `src/**`、`extension.toml` |
| **Z-P1-2** | task 模板与生成脚本：`scripts/zed/`（`init-workspace.sh` / `init-workspace.ps1`，交互式提问）+ 文档内置 task 模板（§3.3 清单） | `scripts/zed/**`、`README.md`、`docs/USER-GUIDE.md` | 脚本在干净项目里生成可用的 `.zed/{settings.json,tasks.json,bdl-tool.json}`；生成的 task 能在 Zed 里跑通（实机）；`.gitignore` 提示 secrets | `scripts/zed/**`、两份文档 |
| **Z-P1-3** | 声明所需 capability（`process:exec` / `download_file`）：**先核实宿主 `ExtensionManifest.capabilities` 的确切字段格式再写**（官方 capabilities 文档只描述了用户侧 `granted_extension_capabilities` 的收紧格式） | `extension.toml` | 老版本 Zed 忽略未知键；新版本 Zed 首次使用按 capability 授权；文档说明用户可用 `granted_extension_capabilities` 收紧 | `extension.toml` |
| **Z-P1-4** | `/bdl-env-check` 的深度版：显示生效设置摘要、`bdl-lsp`/`tiptop` 版本（跑 `version`）、资料目录状态、缺失项清单 | `src/lib.rs` | 输出可一条条对照 `docs/USER-GUIDE.md` §8 | `src/lib.rs` |

> P1 不做"会写盘"的 slash command；所有写盘/长任务走 task。

### P2 · 链接视图的落地（先验证，再实现）

> **进展（2026-10-29）**：**Z-P2-2 ① 已完成**（新增 `/bdl-link-chain <代码>`，3 个单测）、
> **Z-P2-2 ② 已完成**（`.zed/bdl/migrate-data.{sh,ps1}` + 迁移 task，测试场景三实跑验证）、
> **Z-P2-3 已完成**（P1 的 `/bdl-schema-tables` / `/bdl-schema-columns`）、
> **Z-P2-4 ①② 已完成**（deploy.json 合成 + ext.build.* 回读，测试场景二/四）。
> **Z-P3-3 已完成、Z-P2-1 转为"验收"**：服务端 Code Lens 已实现（`bdl-lsp c0102a2`，6 个测试含反向请求），
> 现在 Z-P2-1 要确认的只剩 Zed 侧的**渲染与点击**（多条同 range 是否各占一行、点击是否执行 `bdl.openLink`）。
>
> **★ Z-P2-1 的两条关键不确定性已由源码证实（2026-10-29，查 zed-industries/zed main 分支）**：
>
> | 问题 | 结论 | 证据 |
> |---|---|---|
> | 点击 lens 会不会执行 `workspace/executeCommand`？ | **会**。Zed 走 `project.apply_code_action` → `workspace/executeCommand`；但命令**必须在服务端 `executeCommandProvider.commands` 里声明过**，否则被静默跳过 | `crates/project/src/lsp_store.rs` 的 `apply_code_action`（`available_commands.contains(&command.command)` 才发） |
> | 服务端反向的 `window/showDocument` 会被 Zed 支持吗？ | **支持，而且会真的打开文件**。客户端能力里 `show_document: Some(support: true)`；`file:` URI → 打开成新标签并返回 `success: true`（非 `file:` scheme 才返回 false） | `crates/lsp/src/lsp.rs:1153`；`crates/project/src/lsp_store.rs:1309` 注册 handler；`crates/editor/src/items.rs` 的 `handle_lsp_show_document`（`workspace.open_abs_path` → `respond(success)`） |
>
> ⇒ **`bdl.openLink` 的链路是通的**，实机只需确认"看起来对不对"（渲染位置、多条是否各占一行）。
> ⇒ 同时查出一条**必须遵守的硬约束**：**Zed 只显示 `lens.command.title`**；没有 command 的
> lens 会先渲染占位、等 `codeLens/resolve` 补标题，服务端不声明 `resolveProvider` 时就永远占位，
> 最终回落到一个**假的**「0 references」文本（`crates/editor/src/code_lens.rs` 的 `EMPTY_LENS_FALLBACK_TITLE`）。
> **所以"纯文本汇总行"在 Zed 里是陷阱** —— 已在 `bdl-lsp` 侧改用新命令 `bdl.showInfo`
> （弹 `window/showMessage`），并加测试 `TestEveryLensHasCommand` 锁定这条不变量。

| # | 任务 | 落点 | 验收 | 写作用域 |
|---|---|---|---|---|
| **Z-P2-1** | **Code Lens 实机验证（必须先做）**：① `code_lens: "on"` 时同一 range 的多条 lens 是否**各占一行**；② 点击 lens 的 `command` 能否执行 `workspace/executeCommand` 并打开目标文件；③ 决定了实现方式后再投入 Z-P3-3 | 需要**有 GUI 的机器**；结论回写本文件与 USER-GUIDE | 三条结论有截图/录屏；若②不成立，改用备选方案（终端清单 + `lsp command selector`）并更新 §8 | 本文件 + USER-GUIDE |
| **Z-P2-2** ✅ | 链接关系视图的替代 + 旧资料目录迁移：① slash command `/bdl-link-chain <代码>`（读 `links.jsonl`，Agent 面板文本；最多 30 个文件）——比终端清单跨平台、可单测；② 生成脚本产出 `.zed/bdl/migrate-data.{sh,ps1}` + task「4gl: 迁移项目资料目录」，**只搬移、绝不覆盖**（`.link/`→`.project/link/`、`.project/.schema/`→`.project/schema/`、`.project/deploy.json`/`.bdl-lsp/deploy.json`→`.project/deploy/deploy.json`，空旧目录删除） | `src/project.rs`、`scripts/zed/**`、文档 | ①✅ 单测覆盖（命中/未命中/大小写/带后缀）；②✅ `verify-init-script.py` 场景三：搬移成功、目标已存在时**原文件保留**、旧空目录删除 | `src/project.rs`、`scripts/zed/**`、文档 |
| **Z-P2-3** | 字段资料只读列表（slash）与 `RECORD LIKE` 体验文档化 | `src/lib.rs`、`docs/USER-GUIDE.md` | `/bdl-schema-tables`、`/bdl-schema-columns` 输出正确 | `src/lib.rs`、USER-GUIDE |
| **Z-P2-4** ✅ | **让 `ext.*` 真正生效**（本轮盘点发现的空档）：① 生成脚本按问答**合成 `.project/deploy/deploy.json`** —— ✅ 已完成；② 生成脚本**回读 `ext.build.*` 模板**，把 tiptop 占位符映射成 Zed 变量后写进 exec task —— ✅ 已完成（未配置则保持内置默认）；③ `ext.deploy.enable=false` 时 `/bdl-deploy-*` 给提示 —— **有意不做**：Zed 没有「按钮显隐」的对应物，跑不跑 task 由用户决定（文档已写明） | `scripts/zed/**`、文档 | ①✅ 填了生产环境的项目能直接 `tiptop upload/download/deploy`；②✅ `verify-init-script.py` 场景四：覆盖生效、映射正确、未配置的保持默认、产物无 `${…}` | `scripts/zed/**`、文档 |

### P3 · 跨仓库（executeCommand / Code Lens / tiptop Release 已授权；标 ⚠️ 的两项待确认）

> **进展（2026-10-29）**：**Z-P3-2 已完成**（`bdl-lsp@9e48960`：`workspace/executeCommand` + 5 条命令，5 个协议级用例通过，`go test ./...` 全绿）。**Z-P3-4 已完成**（`tiptop` release.yml + tag **v0.1.10**，四平台产物 + `SHA256SUMS` 实测可用）。**Z-P3-3（Code Lens）已完成**（`bdl-lsp c0102a2`，服务端 6 个测试全绿）。**Z-P3-3 续：函数级反查也已完成**（`bdl-lsp@9ca180a`，源码 0.3.16）：给被调用过的函数挂「🔗 被 N 处调用」；同时**修掉一个只有 Zed 才会暴露的坑** —— Zed 只显示 `lens.command.title`，没有 command 的 lens 会回落到**假的**「0 references」，所以所有汇总/说明行改用新命令 `bdl.showInfo`（弹 `window/showMessage`），并加测试 `TestEveryLensHasCommand` 锁定不变量。**Z-P3-6 已完成并随 v0.3.15 发布**（`bdl-lsp d88cd97`：声明 `workspaceSymbolProvider`；本地 0.3.15 构建握手实测三个 capability 都在）。**Z-P3-1 经证据推翻、不采纳**（Zed 用 `didChangeConfiguration` 推设置，热更新本来就有）。**v0.3.15 已打 tag 并出包**（四平台 + SHA256SUMS）；**0.3.16 源码已推，tag 待打**。

| # | 任务 | 仓库 | 要做的事 | 验收 |
|---|---|---|---|---|
| ~~**Z-P3-1**~~ ❌ **不采纳** | `workspace/configuration` 支持 | `bdl-lsp` | **证据推翻需求**：Zed 主动推 `didChangeConfiguration`（启动 `lsp_store.rs:694-721`、变化时 `:9831-9932`），`bdl-lsp` 已在处理并热应用；再加 `workspace/configuration` 只是冗余 | — |
| **Z-P3-2** | `workspace/executeCommand` 通道 | `bdl-lsp` | 加 `ExecuteCommandProvider`，把 `bdl/linkTree` / `bdl/linkReferences` / `bdl/schemaTables` / `bdl/schemaColumns` / `bdl/forceParse` 转接为标准命令（参数用 `arguments` 数组） | 协议级测试；VSCode 侧继续用自定义请求，**不受影响** |
| **Z-P3-3** ✅ | `textDocument/codeLens`（**与 VSCode 侧 P1-8 同一份实现，两端共用**） | `bdl-lsp` | 链内子文件各一条 lens 挂 **MAIN 那一行**（数据来自 `link.Resolver.Tree()`，纯内存）；上限 `link.lensMax`（默认 10）+ 汇总行；点击命令 `bdl.openLink` → 反向 `window/showDocument`。**续**：函数级反查（`9ca180a`，0.3.16） | ✅ **已完成**（`c0102a2` + `9ca180a`）：链接 lens 6 个测试 + 反查 4 个 + 「每条 lens 必须带 command」不变量测试；**Zed 侧渲染与点击的链路已由 Zed 源码证实**（只剩实机看观感，Z-P2-1） |
| **Z-P3-4** ✅ | tag + 四平台 Release | `tiptop` | **已完成**：新增 `release.yml`（tag `v*` + dispatch，四平台原生 runner，检出兄弟目录 bdl-lsp；ref = 显式输入 > bdl-lsp 最近 Release tag > main），已打 **v0.1.10** 并推送 | ✅ Release v0.1.10 实测有 4 个产物 + `SHA256SUMS`；下载校验和通过、`tiptop version` = 0.1.10、`download`/`exec` 子命令在 |
| **Z-P3-5** | 文档同步 | `bdl-lsp` / `tiptop` | `FEATURES.md` 补 `workspace/configuration`、`executeCommand`、Code Lens 行；`tiptop` 补 Release | 两处口径一致 |
| **Z-P3-6** ✅ | 声明 `workspaceSymbolProvider: true` | `bdl-lsp` | **已完成**（`d88cd97`，随 v0.3.15 发布）：服务端一直在处理 `workspace/symbol`，Zed 对 `None` 的 server 直接跳过（`crates/project/src/lsp_store.rs:9438-9447`）；声明后「项目符号」能搜到 4GL 函数 | 本地 0.3.15 握手实测 `workspaceSymbolProvider: true`；实机按 §11.2 #19 复验 |
| ~~Z-P3-7~~ | `vscode-bdl/docs/TODO.md` §3.5 Zed 章节更新 | `vscode-bdl` | **未授权**（用户只授权了 bdl-lsp/tiptop）；需要时单独确认，或由本文件取代 | — |

### P4 · 无感分发（只改本仓库）

> **进展（2026-10-29）**：**Z-P4-1 已落地**（`src/download.rs`：`latest_github_release` →
> 平台资产名 → `download_file` → `make_file_executable` → 清旧版本目录；四级本地查找全落空才下载；
> `ext.download.bdlLsp=off` 可关；`set_language_server_installation_status` 三态上报；
> 资产名已对 `api.github.com` 实测（`bdl-lsp-linux-amd64.tar.gz` 等 4 个 + SHA256SUMS 均存在），
> 新增 2 个单测）。**Z-P4-2 也已可用**：tiptop v0.1.10 Release 已发布，同一套 `ensure_tools` 代码路径生效。
> **Z-P4-3 已落地**（三态安装状态上报）；**缓存优先**：本地已有 `<prefix>-<版本>/` 缓存时直接复用最新一份，
> **不再每次启动都查 GitHub**（离线也能起，`cached_binary` 有单测：数值比版本、忽略缺二进制的目录）；
> **Z-P4-4 已落地**：`/bdl-env-check` **只查本地、不触发下载**（`lookup_lsp_path` / `lookup_tools_path`——
> 诊断命令不该悄悄拉 9 MB），并解析
> `bdl-lsp`/`tiptop` 的 `version` 输出，低于最低要求（0.3.13 / 0.1.10）时给一句升级提醒（不硬拦），
> 新增 3 个单测（`version::parse` / `version_warning` / `cached_binary`）。
> 待实机：§11.2 #16。

| # | 任务 | 落点 | 验收 | 依赖 |
|---|---|---|---|---|
| **Z-P4-1** | `bdl-lsp` 自动下载：`latest_github_release` → `current_platform()` 拼资产名（`bdl-lsp-<os>-<arch>.tar.gz|.zip`）→ 缓存到扩展目录 → `make_file_executable` → 清旧版本目录；设置 `ext.download.bdlLsp = auto\|off` | `src/lib.rs` | 无本地二进制时自动下载成功；删缓存后能重下；下载失败给出可操作错误 | bdl-lsp Release（已有） |
| **Z-P4-2** ✅ | `tiptop` 自动下载（同上，Windows 用 `.zip`） | `src/download.rs` | 与 Z-P4-1 同一实现（`ensure_tools`）；资产名已对 v0.1.10 实测 | Z-P3-4 ✅ |
| **Z-P4-3** ✅ | 下载状态显示：`set_language_server_installation_status`（`CheckingForUpdate` / `Downloading` / `Failed(msg)`） | `src/download.rs` | 失败时用户能看到原因而不是"服务器起不来" | Z-P4-1 |
| **Z-P4-4** ✅ | 版本兼容提示：`/bdl-env-check` 解析两个二进制的 `version` 输出，低于最低要求（`bdl-lsp ≥ 0.3.13`、`tiptop ≥ 0.1.10`）时提醒升级（**不硬拦**，解析不出就不打扰） | `src/slash.rs` | 2 个单测覆盖（版本解析四种写法 / 只在低于最低值时提醒） | Z-P1-4 ✅ |
| **Z-P4-5**（可选） | `runnables.scm`：把 `MAIN`/`FUNCTION` 标为可运行，标签绑定到编译/链接 task（Zed 的"行内 ▶"替代编辑器按钮） | `languages/bdl/runnables.scm`、文档 | 只在真实可用后再写；需要 `tags` 与 task 对齐 | Z-P1-2 |
| **Z-P4-6** ✅ | **本扩展自己的发布流水线**（tag → 四平台 → GitHub Release） | `.github/workflows/release.yml`、`src/download.rs` | ①`v*` tag 推送即发布；②Release 含扩展 wasm + `bdl-lsp`/`tiptop` 四平台二进制 + `SHA256SUMS` + `BUILD-INFO.json`；③扩展的下载链改成「后端 Release → 本扩展 Release（兜底）」；④新增护栏 `verify-release-workflow.py`（13 项）对拍资产名 | ✅ 已落地（护栏 13 项全绿） |

### P5 · 实机验收与发布

| # | 任务 | 说明 |
|---|---|---|
| **Z-P5-1** | Zed 实机验收（Linux + Windows 必做；macOS 后续） | 按 §11.2 逐条勾选，结论回写 USER-GUIDE |
| **Z-P5-2** | 扩展注册表发布（zed.dev 扩展市场） | **未排期**（用户未要求）；发布前必须有 Release + 实机验收全绿 |


---

## 8. 已确认的降级方案（用户 2026-10-28 逐条确认）

| # | VSCode 能力 | Zed 结论 | 落地 |
|---|---|---|---|
| D1 | 链接资料 TreeView（三级树 + 点击跳转） | ❌ 无树视图 API | **Code Lens 挂在 MAIN 函数头**：链内子文件各一条、可点、上限 10 条 + 汇总行；依赖 Z-P3-3 |
| D2 | 字段资料 TreeView（过滤/勾选/批量/复制列定义） | ❌ 无树视图 API | slash command 文本列表（表/列）+ 悬停与补全承担列说明；批量同步用 task（`-tables`/`-tables-file`） |
| D3 | 命令面板 33 条 | ❌ 无命令注册 API | task（写盘/长任务）+ slash command（只读短查询）双轨 |
| D4 | 输出面板 / 进度条 / 取消 | ❌ 无 API | task 终端流式输出 + `allow_concurrent_runs` 重跑取消 + `zed: open log` |
| D5 | 编译错误回写 Problems | ❌ 无诊断注入 API | **永久差异**：只看 task 终端输出；文档明确写"编译才是最终验证" |
| D6 | 二进制内置（平台包） | ⚠️ 需自建 | 运行时自动下载（`latest_github_release` + `download_file` + `make_file_executable`） |
| D7 | 无侧边栏 / 无状态栏 / 无标题栏按钮 | ❌ 无 API | **永久差异**，只写进文档；用户改用命令面板、task、keymap |

> 用户明确认可的、**没变**的旧决策也一并保留：链接树归属**留在 `bdl-lsp`**（不搬 `tiptop`）；反查用**函数级**口径；`Call Hierarchy`（语义是调用关系≠链接关系）与 `documentLink`（位置分散）**不采纳**；不把链接资料塞进 `documentSymbol`（会产生不可跳转的假符号）。

---

## 9. 明确不做

| # | 不做 | 原因 |
|---|---|---|
| N1 | 在 Zed 里复刻侧边栏树视图（链接/字段） | 无 API；改用 Code Lens 与 slash 文本（§8 D1/D2） |
| N2 | 复刻输出面板 | 无 API；用 task 终端（§8 D4） |
| N3 | 把远程编译错误注入 Problems | 无诊断注入 API（§8 D5） |
| N4 | 在 slash command 里做会写盘的采集/导入/上传/部署 | 误触成本高；只给显式 task |
| N5 | 跨文件重命名 | 与 VSCode 侧一致：有意不做（只改当前文件） |
| N6 | 4gl 5.0 语法 | 未排期（与 `bdl-lsp` 一致） |
| N7 | Zed 扩展注册表发布 | 未排期（用户未要求） |
| N8 | 把链接资料塞进 `documentSymbol` | 会产生不可跳转的假符号 |
| N9 | 在 Zed 侧把链接解析搬去 `tiptop` | 用户决策：保持原状（`bdl-lsp` 只读资料，纯内存查询） |
| N10 | macOS 实机验收 | v1 承诺 Linux + Windows；macOS 后续补齐 |

---

## 10. 跨仓库改动清单

### 10.1 已授权（用户 2026-10-28）

| 仓库 | 改动 | 任务 |
|---|---|---|
| `bdl-lsp` | 新增 `workspace/executeCommand` + `ExecuteCommandProvider`（转接 5 个自定义能力） | Z-P3-2 |
| `bdl-lsp` | 新增 `textDocument/codeLens`（挂 MAIN、`bdl.link.lensMax` 默认 10、函数级反查；VSCode 侧 P1-8 共用） | Z-P3-3 |
| `bdl-lsp` | `FEATURES.md` 补能力行 | Z-P3-5 |
| `tiptop` | 打 tag + 四平台 Release + `SHA256SUMS` | Z-P3-4 |
| `tiptop` | `FEATURES.md` 补发布说明 | Z-P3-5 |

### 10.2 待授权

| 仓库 | 改动 | 说明 |
|---|---|---|
| ~~`bdl-lsp`~~ | ~~`workspace/configuration` 支持（Z-P3-1）~~ → **不采纳** | **证据推翻**：Zed 用 `workspace/didChangeConfiguration` 主动推设置（启动 + 变化时，`lsp_store.rs:694-721`/`:9831-9932`），bdl-lsp 已处理并热应用（`internal/server/config.go`） |

| `vscode-bdl` | `docs/TODO.md` §3.5（Zed 章节）与 `docs/OPEN-ITEMS.md` E-01…E-08 更新为本计划口径 | 用户本次只授权 bdl-lsp/tiptop；不授权也能进行：Zed 侧以本文件为准 |
| `tree-sitter-bdl` | grammar rev 漂移治理：`extension.toml` 固定 `ad54d643…`，本地 HEAD 已到 `76ddcd3…`；`bdl-lsp/go.mod` 用 tag `v1.0.1`；`zed-ext` 注册表里另一个扩展固定 `c832493e…` | R3，见 §12；需要时再确认 |
| ~~`bdl-lsp`~~ | ~~打 tag + Release~~ | ✅ **已完成**：tag **v0.3.15**（2026-10-29）已推送并出包（四平台 + `SHA256SUMS`），扩展自动下载（`latest_github_release`）会拿到它 |
| `zed-ext`（扩展注册表） | 注册 `4gl-full`（Z-P5-2 未排期） | — |

---

## 11. 验证与验收

### 11.1 自动化（每次改动必过）

```bash
cd /code/workspace/zed-extension
python3 tests/verify-manifest.py                       # 清单 17 项（含语义规则 / slash 声明一致性）
export PATH="/code/workspace/tree-sitter-per/node_modules/.bin:$PATH"
export HOME=/code/workspace/bdl-lsp/artifacts/home
node tests/verify-queries.mjs                          # query 47 项（含真实语料 15 文件 ×2 语言）
cargo test                                             # 单元测试（配置合并 / ext 剥离 / 轻量档默认 / 资料解析）
python3 tests/verify-init-script.py                     # 初始化脚本产物 15 项（R12 无 ${…}、task 齐全、字段白名单、deploy.json、迁移 helper、ext.build 覆盖）
python3 tests/verify-docs.py                            # 文档契约 10 项（版本三处一致 / 命令条数与护栏数字对拍 / 无过期引用）
python3 tests/verify-release-workflow.py                # 发布流水线 20 项（资产名与扩展解析逻辑对拍 / 矩阵 / 触发器 / wasm 与 BUILD-INFO 独立 job）
source /code/workspace/bdl-lsp/scripts/dev-env.sh
cargo check --target wasm32-wasip2
cargo build --release --target wasm32-wasip2           # 产物：target/wasm32-wasip2/release/zed_bdl.wasm
```

后端侧（P3 阶段新增）：`bdl-lsp` 的协议级测试 + `tiptop` 的 release 工作流 dry-run。

### 11.2 Zed 实机验收清单（需 GUI 机器；本沙箱做不了）

| # | 项目 | 期望 | 阶段 |
|---|---|---|---|
| 1 | `zed: install dev extension` 加载本目录 | 扩展面板显示 `4gl-full` | P0 |
| 2 | 打开 `.4gl` | 语言 = Genero BDL，LSP 状态"运行中" | P0 |
| 3 | 打开含语法错误的文件 | 诊断出现，位置正确 | P0 |
| 4 | **设置是否生效** | 在 `lsp.bdl-lsp.settings` 把 `diagnostics.record-member-unknown` 设为 `warning` → 诊断出现（验证 Z-P0-3） | P0 |
| 5 | **轻量档默认** | 不写任何设置时，`link/schema` 不启用（无资料相关诊断/索引负载） | P0 |
| 6 | **语义高亮** | 开 `semantic_tokens: "combined"`，自定义符号着色（验证 Z-P0-4） | P0 |
| 7 | 跳转 GLOBALS / 引用 / 悬停 / 补全 / 重命名 / Code Action / 格式化 | 与 VSCode 行为一致；`.per` 不格式化 | P0 |
| 8 | slash command | `/bdl-env-check`、`/bdl-schema-status`、`/bdl-schema-tables`、`/bdl-schema-columns` 在 Agent 面板有响应、文本正确；无资料时给引导文案而不是报错 | P1 |
| 9 | task | 链接资料状态 / 全量更新 / 上传当前文件 / 预演上传 / 下载当前文件 / 4GL 编译 / Form 预览 | P1 |
| 10 | 初始化工程脚本 | `bash .zed/bdl/init-workspace.sh` 生成 `.zed/{settings.json,tasks.json,bdl-tool.json}` 且内容正确（Windows 用 `.ps1`） | P1 |
| 10b | **task 没被变量过滤** | `task: spawn` 列表里能看到全部 21 条 `4gl:` task（**尤其 6 条 exec**：它们的 `-command` 里含 Zed 变量，写错会被过滤掉）；已存在的 `settings.json` 不被覆盖（写 `.bdl-new`） | P1 |
| 10c | capability | 首次使用 slash command 触发 `process:exec` 时，Zed **不会**报 "capability ... was not listed in the extension manifest"；若用户收紧了 `granted_extension_capabilities`，按文档放行同形状 | P1 |
| 11 | **Code Lens ①** | 开 `code_lens: "on"`：MAIN 那行出现链内子文件 lens，**同一 range 的多条各占一行** | P3（服务端已实现） |
| 12 | **Code Lens ②** | 点击 lens → `bdl.openLink` → 服务端反向 `window/showDocument` 打开目标文件。**源码已证实这条路是通的**（Zed 注册了 `ShowDocument` handler，`file:` URI 会真的打开并返回 `success: true`）。**若点击无反应**：从 `lsp command selector` 手动跑 `bdl.openLink`（会给出明确错误），或改用 `/bdl-link-chain` | P3（已实现，链路已由源码证实，待实机确认观感） |
| 13 | Code Lens ③ | 链内文件数 > `link.lensMax`（默认 10）时只显示前 N 条 + 一条**汇总**（标题「…另有 N 个链内文件」，**点了会弹提示**说明还剩多少 —— 这是 `bdl.showInfo` 命令；不再是"点了没反应"的纯文本）；把 `link.lensMax` 调小可复现 | P3（已实现） |
| 14 | **函数级反查** | ✅ **已实现**（`bdl-lsp` 0.3.16）：函数定义那行出现「🔗 函数名 被 N 处调用（点开首处 …）」，点它跳到**第一处调用**。口径与「查找引用」一致（只算可达模组：本模组 + 全局模组）。要看全部调用点用 Zed 原生「查找引用」。**依赖工作区索引**，索引没建好时不显示（属正常，不是故障） | P3（已实现，待实机） |
| 15 | 设置热更新 | 改 `settings`（例如 `diagnostics` 级别）后**无需重启**即生效；`zed: open log` 里应出现 bdl-lsp 的 `配置已更新` | P3（已由源码解释，实机顺手确认） |
| 16 | 自动下载 | 无 `bdl-lsp`/`tiptop` 时自动下载成功（应拿到 **bdl-lsp v0.3.16** / tiptop v0.1.10；**Release 已实测**：SHA256 校验通过、`version` = 0.3.16、握手 7 条命令含 `bdl.showInfo`）；**删掉扩展目录里的 `bdl-lsp-*` 缓存目录**再打开 `.4gl` 应重下；离线时应复用缓存而不是报错；失败有可操作提示 | P4（已实现） |
| 17 | 路径含空格与中文 | 诊断/跳转/下载/上传均正常（Windows 尤其） | P1/P4 |
| 18 | ABI 15 ↔ Zed tree-sitter 运行时 | 高亮/outline 正常（若异常，是 grammar 兼容问题，需换 rev） | P0 |
| 19 | **项目符号搜索** | `project symbols: toggle` 能搜到 BDL 函数（`bdl-lsp ≥ 0.3.15` 已声明 `workspaceSymbolProvider`；0.3.15 之前预期搜不到） | P3（Z-P3-6 已修，待实机） |

> **"CI 绿"≠"装上能用"**：以上 18 项必须在真机勾完才算追平完成。

---

## 12. 风险与已知坑

| # | 风险 | 说明 | 缓解 |
|---|---|---|---|
| R1 | **误判 Zed API 能力** | 旧文档已出现三处过时结论（语义 token、无法执行命令、Code Lens 替代树视图的语义）。Zed 宿主源码本机不存在，manifest 与设置语义靠官方文档 + GitHub main 分支核对 | §4 每条都带证据；动手前先在本机 crate 源码里确认；实机验证优先 |
| R2 | ~~**Code Lens 点击行为未知**~~ **已由源码证实** | Zed 把 lens 的 `command` 转成 `workspace/executeCommand`（`crates/project/src/lsp_store.rs` 的 `apply_code_action`），**命令必须在服务端 `executeCommandProvider.commands` 里声明过**否则静默跳过；反向的 `window/showDocument` **Zed 支持**（客户端能力 `show_document: Some(support: true)`，`file:` URI 会真的打开文件并返回 `success: true`，`crates/editor/src/items.rs` 的 `handle_lsp_show_document`） | 已在 `bdl-lsp` 侧落地（`bdl.openLink` / `bdl.showInfo` 都已进 `executeCommandIDs()`）；实机只需确认观感（Z-P2-1）。**新踩到的坑**：Zed 只显示 `lens.command.title`，没有 command 的 lens 会回落成**假的**「0 references」→ 所有汇总行必须带 command |
| R3 | **grammar rev 漂移** | `extension.toml` 固定 `ad54d64…`（tree-sitter-bdl 本地 HEAD 已 `76ddcd3…`）；`bdl-lsp/go.mod` 用 tag `v1.0.1`；`zed-ext` 注册表另一扩展固定 `c832493e…` → 高亮/outline 与后端解析可能不一致 | 每轮升级 grammar 时三处一起对齐；`verify-queries.mjs` 必须绿 |
| R4 | **slash command 静默失效** | `extension.toml` 声明与 Rust `match` 名对不上时编译通过但命令不响应 | Z-P0-6 校验脚本专门拦这个 |
| R5 | **配置下发路径改错的回归** | Z-P0-3 改了初始化参数，可能覆盖用户显式配置 | 优先级固定为 `initialization_options` > `settings` > 默认值；补诊断级单测/实机验证（清单 4、5） |
| R6 | **本地二进制过期** | `artifacts/bin` 里是 `tiptop 0.1.8` / `bdl-lsp 0.3.13`，缺 `download`/`-region`/`-login-profile` | 联调前先 `make build`；文档写清版本 |
| R7 | **task 读不到设置** | task 无法插值 Zed 设置，凭证/模板只能靠生成脚本落文件 | 生成脚本 + 文档模板双轨；凭证放 `.project/secrets.json`（0600）或环境变量 |
| R8 | **VSCode 侧文档本身失真** | `FEATURES.md` 版本头 0.6.2、命令数 31/49 与实测 33/50 不符、`bdl/linkReferences` 从未发送 | 一律以 `package.json` 与源码为准；本文只引用实测数字 |
| R9 | **无 GUI 无法自证** | 本沙箱没有 Zed，也没有 GUI | 自动化只覆盖清单/query/Rust 编译；UI 行为交 §11.2 清单 |
| R10 | **本机网络受限** | `web_search` 端点余额不足；`raw.githubusercontent.com` 被 reset（`api.github.com`、`zed.dev` 可达） | 需要外部事实时用 `api.github.com`/`zed.dev`；不依赖搜索 |
| R11 | **版本三仓库独立递增** | 无兼容矩阵，混装症状隐蔽 | Z-P4-4 的版本提示；文档给最低/推荐版本表 |
| R12 | **tiptop 模板占位符在 Zed task 里会失效**（本轮实测） | VSCode 的 `bdl.build.*.command` 用 `${path}`/`${name}`/`${fullname}`，由插件展开后交给 tiptop；Zed 的 task 会把 `$…`/`${…}` 当**自己的变量**——未知变量要么让整条 task 被 `task: spawn` 过滤掉，要么展开成空串，远端命令直接跑错 | 生成脚本与文档统一改用 Zed 变量：`${path}`/`${fullpath}` → `$ZED_RELATIVE_DIR`、`${name}` → `$ZED_STEM`、`${fullname}` → `$ZED_FILENAME`；`tests/verify-init-script.py` 断言产物不含 `${` |
| R13 | **`settings.ext.*` 的消费者**（本轮盘点发现，**已解决**） | 原状：扩展不读 `ext.build.*` / `ext.prod.deploy.*`，task 也读不到设置 → 上传/部署没有配置、模板改了不生效 | ✅ Z-P2-4 已补：生成脚本合成 `.project/deploy/deploy.json`，并在重跑时回读 `ext.build.*` 写进 task。**仍只是记录**的只剩 `ext.deploy.enable` / `ext.build.enable`（Zed 无按钮显隐，文档写明） |
| R14 | **Zed 的 Code Lens 只显示 `command.title`**（本轮由源码发现，**已解决**） | 没有 command 的 lens 在 Zed 里会先渲染占位，等 `codeLens/resolve` 回来补标题；服务端不声明 `resolveProvider` 时就永远占位，最终回落到一个**假的**「0 references」文本（`crates/editor/src/code_lens.rs` 的 `EMPTY_LENS_FALLBACK_TITLE`）。也就是说"纯文本汇总行"在 Zed 里是陷阱 —— VSCode 侧好好的写法搬过来就变形了 | ✅ `bdl-lsp` 侧新增命令 `bdl.showInfo`（弹 `window/showMessage`），所有汇总/说明行改用它；加测试 `TestEveryLensHasCommand` 锁定"每条 lens 都必须带 command、且命令必须在 `executeCommandProvider.commands` 里" |

---

## 13. 执行顺序建议

> **进度（2026-10-29）**：
> 第一轮 ✅（`ca2d78b`）· 第二轮 ✅（`57a433b`/`3d2b87f`/`f4ac5c9`）·
> 第三轮：Z-P2-2 ①② ✅、Z-P2-3 ✅、Z-P2-4 ①② ✅（`7537987`/`e184832`/`d5825af`）·
> 第四轮：Z-P3-2 ✅（`bdl-lsp 9e48960`）、**Z-P3-3 ✅ 服务端 Code Lens 已实现（`bdl-lsp c0102a2`）**、
> Z-P3-4 ✅（`tiptop 9882882` + tag **v0.1.10**）、Z-P3-5 ✅（bdl-lsp/tiptop 文档已同步）·
> 第五轮 ✅（`90ae4d8`/`0c0cdf9`）· 第六轮：自测护栏加固（`2cfd8c8`/`f9e67e9`/`747bf1b`/`58a64ac`/`1754ab0`）。
> **第七轮（用户授权后）**：**Z-P3-6 ✅**（`bdl-lsp d88cd97` 声明 `workspaceSymbolProvider`）、
> **`bdl-lsp` tag v0.3.15 已发布**（四平台 + `SHA256SUMS`，含 executeCommand / Code Lens / 项目符号）、
> **Z-P3-1 ❌ 不采纳**（证据推翻：Zed 用 `didChangeConfiguration` 推设置，热更新本来就有）、
> 文档热更新口径全面更正（"改完必须重启" → "通常不用重启"）。
>
> **第八轮（2026-10-29 晚）**：**`bdl-lsp` tag v0.3.16 已发布**（四平台 + `SHA256SUMS`，Release 产物实测可用）。
> **函数级反查 Code Lens 已实现**（`bdl-lsp@9ca180a`，已推 origin/main）：
> 函数定义那行挂「🔗 函数名 被 N 处调用」，点它跳到第一处调用；口径与「查找引用」一致
> （只算可达模组）。同时**修掉一个只有 Zed 才会暴露的坑**：Zed 只显示 `lens.command.title`，
> 没有 command 的 lens 会回落到**假的**「0 references」→ 新增命令 `bdl.showInfo`，
> 所有汇总/说明行改用它，并加测试 `TestEveryLensHasCommand` 锁定不变量。
> **Z-P2-1 的两条关键不确定性已由 Zed 源码证实**：点击走 `workspace/executeCommand`（命令必须在
> `executeCommandProvider.commands` 里声明过）；反向的 `window/showDocument` **Zed 支持且会真的打开文件**。
>
> **只剩一项等实机**：§11.2 的 Zed 验收清单（Code Lens 渲染/点击观感 = Z-P2-1、项目符号 = #19、
> 设置热更新 = #15）。本地代偿已完成：capability 握手实测、lens 生成协议测试、
> `bdl.openLink` 反向请求测试、release 产物 API 校验、**Zed 源码逐条核对**。
>
> 护栏现状（**核心项数**，与环境无关）：清单 **17** 项 · init-script **15** 项 · release **20** 项 · 文档 **10** 项 · query **47** 项 · `cargo test` **17** 项 · wasm 315 KB。
>
> > init-script 的「15 项」指**核心项数**（bash 版）。装了 pwsh 的机器（CI runner 自带）
> > 还会额外跑 PowerShell 版 **10 项**，总项数变成 25 —— 那是**额外项**，不计入契约。
> > 脚本输出里会分别标注「核心 N 项 + PowerShell 额外 M 项」，`verify-docs.py` 对拍的是核心项数。
> > （2026-10-29 踩过：CI 报「文档=15 实际=25」，根因是把随环境变化的总项数当成了契约。）

```text
【第一轮 · 只改本仓库，零外部依赖】
  Z-P0-1 文档重建（本文件 + README + USER-GUIDE）
  Z-P0-2 版本 0.2.0
  Z-P0-3 配置下发修正（★ 最重要：今天 Zed 的设置根本没生效）
  Z-P0-4 语义高亮规则
  Z-P0-5 tiptop 定位
  Z-P0-6 校验脚本扩展
  └─ 门槛：verify-manifest / verify-queries / wasm build 全绿

【第二轮 · 命令入口】
  Z-P1-1 slash command（9 条只读）
  Z-P1-2 task 模板 + 初始化脚本
  Z-P1-3 capabilities 声明
  Z-P1-4 /bdl-env-check 深度版
  └─ 门槛：实机清单 8/9/10/17

【第三轮 · 先验证再投入】
  Z-P2-1 Code Lens 实机验证（有 GUI 的机器）◄── 结论决定 Z-P3-3 的实现方式
  Z-P2-2 链接关系终端清单 task（当前可用的替代）
  Z-P2-3 字段资料只读列表

【第四轮 · 跨仓库（executeCommand / Code Lens / tiptop Release 已授权）】
  Z-P3-1 bdl-lsp: workspace/configuration ◄── ⚠️ 待单独确认（新增发现）
  Z-P3-2 bdl-lsp: executeCommand 通道              ✅ 已授权
  Z-P3-3 bdl-lsp: Code Lens（与 VSCode P1-8 共用一份）✅ 已授权
  Z-P3-4 tiptop: tag + 四平台 Release              ✅ 已授权
  Z-P3-5 后端文档同步                              ✅ 已授权
  Z-P3-6 workspaceSymbolProvider 声明 ◄── ⚠️ 先实机核实（§11.2 #19）再决定
  └─ 门槛：协议级测试 + 实机清单 11–15

【第五轮 · 无感分发】
  Z-P4-1/2 自动下载（两个都已完成：bdl-lsp v0.3.15 / tiptop v0.1.10）
  Z-P4-3 下载状态提示
  Z-P4-4 版本兼容提示
  └─ 门槛：实机清单 16

【第六轮 · 验收】
  Z-P5-1 Linux + Windows 实机验收全绿
  Z-P5-2 注册表发布（未排期）
```

**立即可以开始的是第一轮全部**：`Z-P0-1`…`Z-P0-6` 都在 `zed-extension/` 内，不需要任何授权，也不需要 GUI。
**唯一需要外部条件的是 Z-P2-1**（一台装了 Zed 的 GUI 机器）——它必须早于 Z-P3-3。

---

## 14. 文档维护规则（本仓库）

1. **唯一性**：Zed 侧的待办只写在本文件（`docs/PLAN.md`）；不要再新增 `PENDING.md` / `NEXT.md` / `HANDOVER.md` 一类平行清单。
2. **完成即移出**：任务做完后 → ①能力写进本文件 §6 的处置列（改成 ✅）与 `docs/USER-GUIDE.md` 对应章节；②从 §7 的任务表删除该行；③版本号 +1。
3. **用户可见的新能力**必须同步 `README.md`（能力表）与 `docs/USER-GUIDE.md`（操作步骤），保持三份文档口径一致。
4. **数字必须实测**：命令数、设置键数、诊断码、参数名一律来自源码或实跑输出；不引用 VSCode 侧文档里未经核对的数字。
5. **跨仓库改动**：先在 §10.2 登记并取得用户确认，禁止先改后报。
6. **数字不许漂移**：`tests/verify-docs.py` 会把 README/USER-GUIDE/PLAN 里声明的版本号、slash command 条数、护栏项数与实际对拍；改动能力或护栏后先跑它。