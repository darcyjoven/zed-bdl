# Genero BDL for Zed 使用手册

本手册面向**使用者**。面向开发者的计划与待办在 [`PLAN.md`](PLAN.md)；语言服务能力见 [`bdl-lsp/docs/FEATURES.md`](https://github.com/darcyjoven/bdl-lsp/blob/main/docs/FEATURES.md)；采集与部署 CLI 见 [`tiptop`](https://github.com/darcyjoven/tiptop)。

| 项目 | 值 |
|---|---|
| 扩展 id | **`4gl-full`**（仓库 `zed-bdl`；可与只有 grammar 的轻量扩展 `bdl` 共存） |
| 本手册对应版本 | 扩展 **`0.2.0`**（阶段见 [PLAN §7](PLAN.md)） |
| 语言服务器 | `bdl-lsp` **v0.3.14**（已有 Linux / macOS(Intel,ARM) / Windows 四平台 GitHub Release + `SHA256SUMS`） |
| 采集 / 部署 CLI | `tiptop` **v0.1.10**（四平台 GitHub Release + `SHA256SUMS`；2026-10-29 首次发布） |
| 参照物 | VSCode 插件 `4gl-full` **0.9.2**（33 条命令 / 50 个设置键 / 2 个侧边栏树视图） |
| v1 承诺平台 | **Linux + Windows**（macOS 后续补齐） |

**状态标记**（本手册每节标题后都带一个）：

| 标记 | 含义 | 你现在能做什么 |
|---|---|---|
| ✅ 当前可用 | 今天就能用（`0.2.0` 已实现，或由 Zed 宿主直接提供） | 直接照命令执行 |
| ✅ 0.2.0 已落地 | 原 P0/P1 计划项已随 `0.2.0` 实现 | 直接用，不必再找替代入口 |
| 🔧 计划中·P2…P5 | 已排期、方案已确认 | 看「当前替代」；别去找还不存在的入口 |
| ⬇️ 降级替代 | Zed 没有对应 UI API，功能换入口，能力仍在 | 用文档给的 task / slash command / keymap |
| ❌ 平台不支持 | Zed 平台**永久**没有该能力（不是没做完） | 接受差异，或改用终端 |
| ⚠️ 待实机核实 | 依赖一台装了 Zed 的 GUI 机器才能定论（本沙箱无 GUI） | 见对应章节的核实项 |

**两个入口**：会写盘、耗时长、需要交互输入的事（采集 / 导入 / 同步 / 上传 / 下载 / 部署 / 初始化）→ **task**；只读短查询（状态 / 表清单 / 列清单 / 部署目标 / 环境自检）→ **slash command**（Agent 面板，`/bdl-…`）。Zed 扩展**无法注册任意命令到命令面板**，所以「命令面板里搜 `4gl:` 就有 33 条命令」在 Zed 上**不存在**（§9）。

**0.2.0 起配置会真正下发到 `bdl-lsp`**（`settings` 合并进 `initializationOptions`）；但生效配置**只在语言服务器启动时读一次**——**改了 `lsp.bdl-lsp.settings` 必须重启语言服务器**（§1.3 / §10.7）。

---

## 0. 实现状态总表 [✅ 当前可用 / ✅ 0.2.0 已落地 / 🔧 计划中·P2…P5 / ⬇️ 降级替代 / ❌ 平台不支持 / ⚠️ 待实机核实]

一句话口径：**语言智能（诊断/悬停/跳转/引用/补全/重命名/Code Action/格式化）与语法高亮今天就能用，且是同一个 `bdl-lsp` 与同一套 tree-sitter grammar；差的全部是 VSCode 的 UI 容器能力与命令入口。**

| 能力 | 触发方式 | 状态 | 阶段 |
|---|---|---|---|
| 语法高亮 / Outline / 缩进 / 括号 / SQL 注入 | 打开、编辑 | ✅ 当前可用 | — |
| 诊断（14 静态码 + 动态 `missing-<kind>`） | 打开、编辑 | ✅ 当前可用 | — |
| 悬停 / 跳转 / 引用 / 补全 / Code Action / 重命名（仅当前文件） | Zed 原生命令与快捷键 | ✅ 当前可用 | — |
| 格式化（`.4gl` / `.global`；`.per` 不格式化） | Zed 原生 | ✅ 当前可用 | — |
| GLOBALS 跨文件跳转与来源标注 | 自动 | ✅ 当前可用 | — |
| 工作区符号索引（未打开文件也能搜/跳） | 自动后台 + 持久化快照 | ⚠️ 待实机核实（服务端未声明 `workspaceSymbolProvider`，见 §6.5） | — |
| 字段悬停说明 / `RECORD LIKE t.*` 成员校验 / 列补全 | 编辑时自动 | ✅ 当前可用 | — |
| 链接资料：状态 / CSV 导入 / 全量更新 / 按模组更新 / 更新当前文件 | task → `tiptop link …` | ✅ 当前可用 | — |
| 字段资料：状态 / CSV 导入 / 直连 Oracle 分批同步 | task → `tiptop schema …` | ✅ 当前可用 | — |
| 上传当前文件 / 预演上传 / 下载当前文件（单文件） | task → `tiptop upload` / `download` | ✅ 当前可用 | — |
| 4GL / Form 的预演编译 / 编译 / 链接 / 预览画面 | task → `tiptop exec`（生产端执行） | ✅ 当前可用 | — |
| 整包部署（`-dry-run` / `-list` / `-json`） | 终端 → `tiptop deploy`（**只有命令行**） | ✅ 当前可用 | — |
| **用户设置真正到达 `bdl-lsp`** | 自动 | ✅ 0.2.0 已落地（改完**需重启语言服务器**） | P0（Z-P0-3） |
| **轻量档默认**（不写 `link/schema` 时补 `mode:"off"`） | 自动 | ✅ 0.2.0 已落地 | P0（Z-P0-3） |
| 语义高亮（扩展自带 `semantic_token_rules.json`） | `"semantic_tokens": "combined"` | ✅ 0.2.0 已提供规则（**着色效果 ⚠️ 待实机核实**） | P0（Z-P0-4） |
| `tiptop` 四级二进制定位 | 自动 | ✅ 0.2.0 已落地 | P0（Z-P0-5） |
| 只读 slash command（9 条）+ task 生成脚本 + 扩展 `capabilities` 声明 | Agent 面板 `/bdl-…`；`scripts/zed/init-workspace.{sh,ps1}`；自动（首次弹授权） | ✅ 0.2.0 已落地 | P1（Z-P1-1 / Z-P1-2 / Z-P1-3） |
| 项目初始化（拉代码，task 可挂载）+ 迁移旧资料目录（`.link/` → `.project/link/`） | task → 自备 `scripts/init-project/` 同款脚本；迁移用生成脚本产出的 `.zed/bdl/migrate-data.{sh,ps1}` | ✅ 0.2.0 已落地（两者都有 task） | P1（Z-P1-2）/ P2（Z-P2-2） |
| 表清单 / 列清单（无侧边栏树） | slash command 文本列表 | ✅ 0.2.0 已落地 | P1（Z-P1-1） |
| 链接关系查看：终端清单（当前替代）+ 就地 Code Lens | task 打印清单 / Code Lens 挂在 **MAIN** 上 | 🔧 计划中 | P2（Z-P2-2）→ 验证后 P3（Z-P2-1 / Z-P3-3） |
| 反查引用（**函数级**口径） | Code Lens / `executeCommand` | 🔧 计划中 | P3（Z-P3-2 / Z-P3-3） |
| 设置热更新 + `workspace/executeCommand` 通道 | 改 `settings` / slash 间接调用 | 🔧 计划中 | P3（Z-P3-1 / Z-P3-2） |
| `bdl-lsp` / `tiptop` 自动下载 | 首次打开时按平台下载 | 🔧 计划中 | P4（Z-P4-1 / Z-P4-2） |
| 下载状态提示 / 三方版本兼容提示 | 自动 / `/bdl-env-check` | 🔧 计划中 | P4（Z-P4-3 / Z-P4-4） |
| 扩展注册表（zed.dev）发布 | 面板搜索安装 | 🔧 计划中 | P5（Z-P5-2，**未排期**） |
| 侧边栏 / 树视图（链接资料视图、数据库字段视图） | — | ❌ 平台不支持 | 永久差异（§9） |
| 状态栏 | — | ❌ 平台不支持 | 永久差异（§9） |
| 编辑器标题栏 / 右键 / 视图工具栏按钮 | — | ❌ 平台不支持 | ⬇️ 命令面板 + task + keymap |
| 独立输出面板（`4gl` / `4gl 任务` 通道） | — | ⬇️ task 终端 + `zed: open log` | 永久差异（§9） |
| 进度条 + 取消 | — | ⬇️ task 终端流式输出 + 重跑取消 | 永久差异（§9） |
| 把远程编译错误注入 Problems | — | ❌ 平台不支持 | 永久差异（§9） |

---

## 1. 安装与准备 [✅ 当前可用 / 🔧 计划中·P4]

### 1.1 安装扩展 [✅ 当前可用（dev extension）/ 🔧 计划中·注册表发布]

注册表（zed.dev 扩展市场）发布**未排期**，当前只有一条路：**作为 dev extension 从本地目录加载**。

```text
Zed 命令面板（cmd-shift-p / ctrl-shift-p）→ 输入 zed: install dev extension → 选择本仓库目录
```

加载成功后扩展面板里应出现 **`4gl-full`**（名称 `Genero BDL & Form (Full)`，版本 `0.2.0`）。

> 📷 待补：扩展面板中显示 4gl-full 已加载（docs/images/zed/01-install-extension-panel.png）

- 本扩展 id 刻意取 `4gl-full`（不是 `4gl`），可与只提供 grammar 的轻量扩展 `bdl` 同时安装；改了 `src/lib.rs` 或 `languages/**` 后需重新执行 `zed: install dev extension`。
- grammars 是 `tree-sitter-bdl` / `tree-sitter-per`（`rev` 固定在 `extension.toml`），首次加载要**联网**拉取并编译。

### 1.2 准备 bdl-lsp 与 tiptop [✅ 手工构建 / ✅ 指定路径 / 🔧 计划中·P4 自动下载]

扩展本身**不含二进制**：

| 二进制 | 作用 | 当前获取方式 |
|---|---|---|
| `bdl-lsp` | 语言服务器（stdio LSP）+ `check` CLI | 已有四平台 GitHub Release，可直接下载；也可手工构建 |
| `tiptop` | 链接/字段资料采集、上传下载、生产端执行、整包部署 | **已有四平台 GitHub Release（v0.1.10）**，可自动下载；也可手工构建（源码 0.1.10） |

**① 自动下载【✅ 0.2.0：`bdl-lsp`（Z-P4-1）与 `tiptop`（Z-P3-4 + Z-P4-2）都已可用】**

四级本地查找全部落空时，扩展会**兜底**从 GitHub Release 下载（`latest_github_release` → 按平台拼资产名 →
`download_file` 解包 → `make_file_executable` → 清旧版本目录），状态用
`set_language_server_installation_status` 显示（`CheckingForUpdate` / `Downloading` / `Failed(msg)`）。

| 平台 | 资产名 |
|---|---|
| Linux x64 | `bdl-lsp-linux-amd64.tar.gz` |
| macOS Intel / Apple Silicon | `bdl-lsp-darwin-amd64.tar.gz` / `bdl-lsp-darwin-arm64.tar.gz` |
| Windows x64 | `bdl-lsp-windows-amd64.zip` |

`tiptop` 同样有四个平台产物（`tiptop-<os>-<arch>.tar.gz|.zip`，含 `SHA256SUMS`）。

- **本地已有二进制时永远优先**：只有「设置路径 → `BDL_LSP_PATH`/`TIPTOP_PATH` → 工作区 `.bdl-lsp/bin/` → `PATH`」全部落空才会下载。
- 缓存：扩展工作目录下按版本分目录（如 `bdl-lsp-0.3.14/`），同版本再次启动直接复用。
- 关闭：`lsp.bdl-lsp.settings.ext.download.bdlLsp = "off"` / `ext.download.tiptop = "off"`（键缺省即 `auto`）。
- capability：需要 `download_file`（`extension.toml` 已声明 `host=github.com`、`path=["darcyjoven","**"]`）；
  若你在 `granted_extension_capabilities` 里收紧了权限，要放行同样形状，否则会提示 capability 错误。
- macOS 首次运行未签名二进制可能需要 `xattr -d com.apple.quarantine <文件>`（见 bdl-lsp README）。

> 📷 待补：首次打开时自动下载二进制的状态提示（docs/images/zed/02-auto-download-status.png）

**② 手工构建【✅ 当前可行】**

```bash
# Linux / macOS
cd bdl-lsp && make build          # 产物：bdl-lsp/artifacts/bin/bdl-lsp
cd tiptop  && make build          # 产物：tiptop/artifacts/bin/tiptop
cd bdl-lsp && source scripts/dev-env.sh && make build    # 受限环境先加载工具链
```

```powershell
# Windows（无 make）
cd bdl-lsp; powershell -File scripts\build.ps1
cd tiptop;  powershell -File scripts\build.ps1
```

> ⚠️ **先看这条坑**：本机 `artifacts/bin/` 里可能有**过期二进制**（`bdl-lsp 0.3.13`、`tiptop 0.1.8`）。
> 0.1.8 的 `tiptop` **缺 `download`、`-region`、`-login-profile`**，表现为「未知子命令 / 参数不认识」。

```bash
bdl-lsp version      # 期望 0.3.14
tiptop  version      # 期望 0.1.10
```

> 📷 待补：`bdl-lsp version` 与 `tiptop version` 输出对照（docs/images/zed/03-version-check.png）

**③ 指定已有二进制【✅ 当前可用】**

`bdl-lsp` 定位顺序（与 `src/lib.rs` 实现**逐条一致**）：

1. Zed 设置 `lsp.bdl-lsp.binary.path`（写了就用，**文件不存在直接报错**，不静默回退）；
2. 环境变量 `BDL_LSP_PATH`（同样要求文件存在）；
3. 工作区内的 `<工作区根>/.bdl-lsp/bin/bdl-lsp`（Windows 为 `bdl-lsp.exe`）；
4. `PATH` 里的 `bdl-lsp`。

四级都找不到时，Zed 会在「语言服务器」状态里显示**可操作**的错误（列出这四条与构建方法）。`tiptop` 同样有四级查找（`ext.tools.path` → `TIPTOP_PATH` → 工作区 `.bdl-lsp/bin/tiptop[.exe]` → `PATH`），**✅ 0.2.0 已落地（Z-P0-5）**——slash command（`/bdl-env-check`、`/bdl-deploy-*`）会按这四级自动找到 `tiptop`；而 task **读不到 Zed 设置**（§8.4），所以 task 里要么让它在 `PATH` 里，要么写**绝对路径**：

```bash
export PATH="/path/to/tiptop/artifacts/bin:$PATH"
tiptop version
```

### 1.3 配置语言服务器 [✅ 0.2.0 已落地（设置下发）/ ✅ 写法不变]

**只写一处**：`lsp.bdl-lsp.settings`。扩展读不到别的设置分类
（公开 API 只有 `LspSettings::for_worktree`，即 `lsp.<server>` 整块）。

```jsonc
{
  "lsp": {
    "bdl-lsp": {
      "binary": { "path": "", "arguments": [], "env": {} },
      "settings": {
        // —— 下发给 bdl-lsp：与 internal/config.Settings 同名，【没有】bdl. 前缀 ——
        "generoVersion": "2.50",
        "logLevel": "info",
        "globals": { "searchPaths": [] },
        "perRoots": [],
        "diagnostics": { "record-member-unknown": "warning" },
        "builtins": { "enable": true, "paths": [], "disable": [] },
        "link": { "mode": "off", "dataDir": ".project/link", "moduleRoots": [], "globalModules": ["sub", "lib", "qry"] },
        "schema": { "mode": "off", "dataDir": ".project/schema" },
        "index": { "enable": true },
        "ignore": { "files": [], "fields": [], "forms": [] },
        "format": { "keywords": "unchanged", "indentStyle": "auto", "indentSize": 0 },
        "limits": { "maxFileBytes": 2097152, "maxFileLines": 20000, "maxIssues": 200, "parseTimeoutMs": 2000 },

        // —— 仅 Zed 扩展自用（不下发给 LSP）——
        "ext": {
          "tools": { "path": "" },
          "schema": { "batchSize": 200, "timeoutSec": 120 },
          "prod": {
            "oracle": { "host": "", "port": 1521, "service": "", "user": "" },
            "deploy": { "host": "", "port": 22, "user": "", "region": "1", "strictHostKey": true, "transport": "off", "localRoot": ".", "remoteRoot": "" }
          },
          "deploy": { "enable": false },
          "build": {
            "enable": false,
            "4gl": { "preview": "cd ${path} && r.c2 ${name}", "compile": "cd ${path} && r.c2 ${name}", "link": "r.l2 ${name}" },
            "per": { "preview": "cd ${path} && fglform -M -W all ${fullname} && rm ${name}.42f", "compile": "cd ${path} && fglform -M -W all ${fullname} && mv ${name}.42f ../42f/ && gsform -M -W all -i -import ${fullname} && mv ${name}.4fd ../4fd/", "form": "cd ${path} && r.gf ${name} 2 p" }
          },
          "download": { "bdlLsp": "auto" }
        }
      }
    }
  },
  "languages": {
    "Genero BDL": { "semantic_tokens": "combined", "code_lens": "on" },
    "Genero Form": { "semantic_tokens": "combined" }
  }
}
```

> 📷 待补：`.zed/settings.json` 里配置 bdl-lsp 的完整样子（docs/images/zed/04-settings-json.png）

键名规则（最容易写错的地方）：下发给服务端的键与 `internal/config.Settings` **完全同名、无 `bdl.` 前缀**（VSCode 写 `bdl.diagnostics`，Zed 就是 `diagnostics`）；只属于扩展的键一律收在 **`ext`** 下，**不下发**；`binary.path` / `binary.arguments` / `binary.env` 是 **Zed 原生键**，不放在 `settings` 里。

**✅ 0.2.0 已落地（原 P0 修复，Z-P0-3）**：扩展在语言服务器启动时把三层合并后从 `initializationOptions` 下发，`settings` 里的键**会真正到达 `bdl-lsp`**：

```text
initialization_options（逃生口，最高优先级）
  ⊕ settings（去掉仅扩展自用的 ext）
  ⊕ 轻量档默认（link/schema 未显式配置时补 mode="off"）
```

同一份合并结果也作为 `workspace/configuration` 的应答返回（`bdl-lsp` 目前不请求它，服务端支持后自然生效，PLAN Z-P3-1）。原来「两个已知问题」现在的状态：

1. `settings` 里的键到不了 `bdl-lsp` → **✅ 已合并进 `initializationOptions` 下发，直接写 `settings` 即可**。
2. 不写 `link` / `schema` 时服务端按「启用」兜底（`LinkEnabled()` / `SchemaEnabled()` 在客户端未下发时返回 `true`）→ **✅ 扩展显式补 `mode:"off"`**（只在用户既没写 `mode` 也没写旧写法 `enable` 时补，不会覆盖显式配置）。

**代价（务必记住）**：生效配置**只在语言服务器启动时下发一次** —— **改了 `settings` 必须重启语言服务器**（命令面板 `editor: restart language server`）。「改完立即生效」要等服务端支持 `workspace/configuration`（PLAN Z-P3-1）。

`initialization_options` 仍是**优先级最高的逃生口**（同名键会覆盖 `settings`），用法不变：

```jsonc
{
  "lsp": { "bdl-lsp": {
    "binary": { "path": "/opt/bdl/bin/bdl-lsp" },
    "initialization_options": {
      "link": { "mode": "off" }, "schema": { "mode": "off" },
      "diagnostics": { "record-member-unknown": "warning" }
    },
    "settings": { "format": { "keywords": "lower" } }
  } }
}
```

**语言名必须与 `extension.toml` 完全一致**：`"Genero BDL"` 与 `"Genero Form"`；
写成 `"4gl"` 会让该语言下的 `semantic_tokens` / `code_lens` 不生效。

### 1.4 第一次打开项目 [✅ 当前可用]

1. 打开**项目根目录**（`.4gl` / `.global` / `.per` 所在目录）。工作区根很重要：`bdl-lsp` 按 `rootUri` → `workspaceFolders[0]` → `rootPath` 解析，三级都空时所有「绝对路径类」功能会静默降级。
2. 打开 `.4gl` 语言应显示 **Genero BDL**、语言服务器状态**运行中**；打开 `.per` 应显示 **Genero Form**。
3. 首次打开大仓库会建工作区符号索引（实测 7756 个文件约 **24.7 秒**，之后按 `(mtime,size)` 增量约 **22 毫秒**）；索引期间跳转/引用结果可能不全，属正常。

```bash
bdl-lsp check aap/4gl/*.4gl                       # 批量解析检查
bdl-lsp check --json --max-issues 50 <文件>        # 结构化输出
bdl-lsp check -q <文件...>                         # 只列有问题的文件
```

> `bdl-lsp serve` 是编辑器调用的入口，支持 `--stdio` 兼容写法，**但 Zed 不需要你显式传**——
> Zed 按 `extension.toml` 的 `[language_servers.bdl-lsp]` 自己起 stdio 会话。

> 📷 待补：第一次打开 .4gl（语言名、高亮、语言服务器运行中）（docs/images/zed/05-first-open.png）

---

## 2. 项目初始化（从生产服务器拉取代码） [✅ 0.2.0 已落地（Zed 配置生成）/ 🔧 计划中·P1（拉代码 task 需自备脚本）]

**目标**：把生产端（默认 `/u1/topprod`）下的 `*.4gl` / `*.per` / `*.global` 拉到本地，变成带 git 的工程。

### 2.1 初始化脚本 [🔧 计划中·P1（当前可手工执行同款脚本）]

计划的入口是 task `4gl: 初始化项目（从生产服务器拉取代码）`，调用与 VSCode 侧**同一套**脚本（`scripts/init-project/init-project.sh` 用于 Linux/WSL，`init-project.ps1` 用于 Windows），在**终端里跑**、可交互输入密码。**今天可用的做法**：拿到 `scripts/init-project/` 目录后直接跑。

```bash
# Linux / WSL：rsync 拉取，增量最快
scripts/init-project/init-project.sh \
  -t tiptop@192.168.1.19 -r /u1/topprod -d ~/tiptop-gp \
  --update --from-encoding gbk

scripts/init-project/init-project.sh -t <user@host> -r /u1/topprod -d <本地目录> --dry-run
```

```powershell
# Windows：生产端 tar 打包 → scp 回本地 → 解压 → 清理两端中间文件
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\init-project\init-project.ps1 `
  -Target tiptop@192.168.1.19 -RemoteRoot /u1/topprod -Dest D:\code\topprod-gp `
  -Region 1 -Update -FromEncoding gbk
```

| 用途 | Linux | Windows |
|---|---|---|
| 先空跑看计划（不写盘）；只看服务器上会执行什么（审计） | `--dry-run` / `--print-remote` | `-DryRun` / `-PrintRemote` |
| 增量更新（目标已存在时必须给） | `--update` | `-Update` |
| 删除本地多余源文件（默认**不删**，先列清单确认） | `--delete` | `-Delete` |
| 只取某些模组 | `--module topcust,other` | `-Module topcust,other` |
| 跳过编码询问 | `--from-encoding gbk` | `-FromEncoding gbk` |
| 没配密钥时用密码登录 | `--ask-password` | `-AskPassword` |
| 登录后先选区（默认 `1`，清空 = 不选） | —（rsync 不需要） | `-Region 1` |
| 老服务器 `ssh-rsa`/SHA-1 兼容 | `--legacy-ssh` | `-LegacySsh` |

脚本跑完还会：`git init -b main` + 自动提交；生成 `.gitignore`、`.gitattributes`、`.editorconfig`、`README-PROJECT.md`；**换行固定 LF**（`*.4gl`/`*.per`/`*.global` 全 `text eol=lf`，`core.autocrlf=false` + `core.eol=lf`），Windows 上改完不会产生空白符差异；并打印校验（`git ls-files --eol` 应全 `i/lf w/lf`）。

| 现象 | 处理 |
|---|---|
| `no matching host key type / kex`（老服务器） | 脚本会自动按 `ssh-rsa`/SHA-1 重试；也可显式 `--legacy-ssh` / `-LegacySsh` |
| `Permission denied (publickey)` | 没配密钥：脚本会问是否改用密码登录（或加 `--ask-password`）；**上传/编译必须先配密钥** |
| 中文乱码 | 先用 `--dry-run` / `-DryRun` 看编码报告，再用 `--from-encoding big5` 重跑 |
| 提示「目标已存在」 | 二次拉取要加 `--update` / `-Update` |
| 远端 `/u1/out` 有残留包 | 上次被强杀（清理没跑到），删掉即可；脚本每次用唯一名 |
| Windows 组策略禁脚本 | 从终端手动执行完整命令行 |

> 📷 待补：初始化脚本的交互提问（选脚本 / SSH 目标 / 生产根 / 编码）（docs/images/zed/06-init-project-prompt.png）
> 🎬 待补：从生产服务器拉取代码的完整过程与进度输出（docs/images/zed/07-init-project-run.mp4）

### 2.2 初始化后生成的 Zed 配置 [✅ 0.2.0 已落地（生成脚本已入库）]

生成脚本已随仓库提供：**`scripts/zed/init-workspace.sh`**（bash 3.2+，Linux / macOS / WSL）与 **`scripts/zed/init-workspace.ps1`**（PowerShell 5.1+，Windows），两者行为等价：在终端里交互提问（4 组：二进制路径 → Oracle 连接 → 生产环境 → init-project 脚本路径），然后生成三件套。脚本自己**不在**生成的 tasks.json 里，想一键重跑要先把它拷进项目：

```bash
mkdir -p .zed/bdl && cp -r <zed-bdl 仓库>/scripts/zed/* .zed/bdl/
bash .zed/bdl/init-workspace.sh          # 交互提问；每项回车即用默认值
```

> Windows：仓库同时提供 **`scripts/zed/init-workspace.ps1`**（PowerShell 5.1+，行为与 bash 版等价）：
> `pwsh -File .zed\bdl\init-workspace.ps1`（本沙箱无 `pwsh`，该版本**未实跑**，仅做静态审阅；
> CI 在 ubuntu runner 上会实跑，见 `tests/verify-init-script.py`）。

生成结果与行为：

| 文件 | 内容 | 已存在时 | 是否提交 git |
|---|---|---|---|
| `.zed/settings.json` | §1.3 的配置（含 `ext.prod.*`） | **不覆盖**，建议内容写到 `.zed/settings.json.bdl-new`（脚本提示手工合并） | ⚠️ 含主机/账号，**建议不进 git**（生产环境只写 Workspace 级） |
| `.zed/tasks.json` | §8.4 的 task 模板，参数按你的回答填好 | 先备份为 `.zed/tasks.json.bak`（已存在则加时间戳）再写 | 可以提交（不含密码） |
| `.zed/bdl-tool.json` | 本次输入值的记录（主机/区号/二进制路径/命令模板） | 直接覆盖 | 可以提交（不含密码） |
| `.project/deploy/deploy.json` | tiptop 的部署配置（上传/下载/部署都要它） | **不覆盖**，建议内容写到 `.project/deploy/deploy.json.bdl-new` | ⚠️ 含主机/账号，建议不进 git |
| `.zed/bdl/migrate-data.sh` / `.ps1` | 迁移旧资料目录的 helper（被「4gl: 迁移项目资料目录」task 调用） | 直接覆盖（脚本生成物） | 可以提交 |

填了生产环境时还会写 `.project/deploy/deploy.json`（见下）。脚本最多写出 **22 条 `4gl:` task**：21 条固定（链接资料 5 条、字段资料 3 条、上传/预演/下载 3 条、4GL/Form 执行 6 条、部署 3 条、迁移资料目录 1 条）+ 1 条可选的「初始化项目（从生产服务器拉取代码）」（仅当第 4 组填了 init-project 脚本路径时追加）。**脚本绝不询问、也绝不写入密码**；密码仍走 `.project/secrets.json` 或 `BDL_ORA_PASSWORD`。

**重跑与清理（容易踩）**：

- `.zed/settings.json` **一旦存在就永不覆盖**（即使上次是脚本自己生成的）→ 每次重跑都会再产出 `.zed/settings.json.bdl-new`，需要你手工合并；`.zed/tasks.json.bak`（以及 `.bak.<yyyyMMdd-HHmmss>`）会累积。建议把 `.zed/settings.json*` 加进 `.gitignore`，并定期删掉 `.bdl-new` / `.bak*`。
- **`allow_concurrent_runs: true` 只加在 6 条 `exec` 与 3 条 `deploy` 上**（"重跑即取消上一次"只对它们成立）；4 条 link/schema 同步**没有**这个字段。
- 两个 `…从 CSV 导入` task 里的 **`<CSV 绝对路径>` 是占位符**，每次运行前要改成实际路径；`按模组更新` 里的 `-modules lib,sub,qry` 是示例。
- 6 条 `exec` **不传 `-workspace`**（只传 `-region` / `-login-profile`），靠 task 的 `"cwd": "$ZED_WORKTREE_ROOT"`；`tiptop` 的 `-workspace` 默认就是 cwd。
- `$ZED_RELATIVE_DIR` 是"**当前文件所在目录**（相对工作区根）"，与 VSCode 的 `${path}`（固定**两层**目录）**近似但不完全等价**；`${fullpath}`（三层）在 Zed 里**没有对应物**。
- 脚本内置兜底：生成的 task 里一旦出现 `${…}` 就**拒绝写盘**（exit 1，不产生半份文件）——防止有人把 VSCode 的模板占位符改回来。

**为什么要有 `bdl-tool.json`**：task **读不到 Zed 设置**，无法把 `ext.prod.deploy.host` 插进命令行，所以生成脚本必须把值**写进文件**（或写进 task 的 `args`）；脚本还会提醒你把 `.zed/settings.json` 与 `.project/secrets.json` 加进 `.gitignore`。

也可以不用脚本：手工把 §1.3 的配置贴进 `.zed/settings.json`，按 §8.4 手工建 `.zed/tasks.json`。

> 📷 待补：生成后的 .zed/settings.json、tasks.json、bdl-tool.json 三件套（docs/images/zed/08-zed-config-generated.png）

---

## 3. 链接资料（程序 → 链 → 文件） [✅ 当前可用 / 🔧 计划中·P2/P3]

链接资料回答一个问题：**这个函数定义在哪个文件里**（因此跨模块函数可见、函数跳转可用）。数据来源 `DS.GAL_FILE`（CSV 表头 `GAL01,GAL02,GAL03,GAL04`；`gal04='Y'` 表示确实链接，`'N'` 过滤）。写侧全在 `tiptop`，`bdl-lsp` **只读**，两者只通过文件系统交互。产物：

```text
<项目根>/.project/link/
├── links.jsonl      # 每行一条链：程序 → 链内文件/函数
└── links.meta.json  # 生成时间、partial（时间/条件/作业数/重算链数）、外部函数表
```

旧布局（`.project` 根 / `.link/`）**只读兼容**，并会发 `link-data-legacy-dir`（默认 `hint`）诊断。

### 3.1 采集 / 导入 / 局部更新 / 查看状态 [✅ 当前可用]

全部是**写盘**操作，走 **task**（§8.4 有模板），也可直接在终端跑。进度写 **stderr**，格式 `进度\t<阶段>\t<详情>[\t<i>\t<n>]`，阶段为 `采集 / 扫描源码 / 成链 / 写入完成`。

```bash
# 状态：链 / orphan / ambiguous / 文件数 / 生成时间与天数 / 缺失文件数 / 模组根 / 局部更新记录
tiptop link status -root .
tiptop link status -root . -global sub,lib,qry

# CSV 导入（先在数据库端执行：SELECT gal01, gal02, gal03, gal04 FROM DS.GAL_FILE WHERE gal04 = 'Y';）
tiptop link import -csv DS.GAL_FILE.csv -root .
tiptop link import -csv DS.GAL_FILE.csv -root . -replace      # 覆盖式重建
tiptop link import -csv DS.GAL_FILE.csv -root . -dry-run      # 只预演

# 全量更新：直连 Oracle 采集（纯 Go 驱动，无需 Oracle 客户端）
tiptop link sync -root . -source golang \
  -host <Oracle主机> -port 1521 -service PROD -user <应用schema账号> -modules lib,sub,qry

# 局部更新：只重算受影响的作业
tiptop link sync -root . -source golang -host <主机> -service PROD -user <账号> -files aap/4gl/saapt310.4gl
tiptop link sync -root . -source golang -host <主机> -service PROD -user <账号> -modules lib,sub,qry
tiptop link sync -root . -source golang -host <主机> -service PROD -user <账号> \
  -files aap/4gl/saapt310.4gl -dry-run        # 先看「受影响作业 N 个」

# 其它采集来源
tiptop link sync -root . -source command -command "<输出 CSV 的命令>"     # 或 -source file / -file / -query
```

参数（与源码一致）：`-csv`、`-root`、`-out`、`-roots`、`-source golang|command|file`、`-command`、`-file`、`-host`、`-port`、`-service`、`-user`、`-query`、`-modules`、`-files`、`-dry-run`、`-replace`、`-global`。

- **局部更新写盘是「合并」**：受影响的程序用新链替换，其余链原样保留。
- **局部更新有前提**：资料目录里必须已有**一次全量导入基线**；没有基线会**明确报错**，而不是写半份资料。
- `source=golang` + 默认 SQL 时模组/文件条件下推到 Oracle；自定义 `-query` 只在内存过滤。
- 一个公共文件常被多个 MAIN 引用，「更新当前文件」会重算多个作业，耗时正常；`link status` **无资料时退出码为 1**（不是 0）；外部函数过滤会把被 ≥3 文件或 ≥5 次调用、全语料无定义的名字视为「存在」（候选 >2000 个时不启用）。

> 📷 待补：`tiptop link status` 的中文输出（链数、生成时间、模组根）（docs/images/zed/09-link-status.png）
> 🎬 待补：`tiptop link sync` 全量采集进度（采集/扫描源码/成链/写入完成）（docs/images/zed/10-link-sync-progress.mp4）

### 3.2 在 Zed 里查看链接关系 [✅ 0.2.0 已落地（`/bdl-link-chain`）/ 🔧 计划中·P3（Code Lens）]

**计划（Z-P3-3）**：`bdl-lsp` 实现 `textDocument/codeLens`，把**链内子文件**各做一条 Code Lens 挂在 **MAIN 程序块**头上（数据来自链接资料内存树），上限默认 10 条 + 一条「…共 M 个」汇总行。在 Zed 上可行是因为 **Code Lens 是宿主的 LSP 客户端功能**：服务端实现，用户在 `languages."Genero BDL"` 下开 `"code_lens": "on"`（**默认 `off`**）即可看到。

> **Z-P2-1 是硬前置**：需要有 GUI 的机器验证 ① 同一 range 的多条 lens 是否各占一行；② 点击 lens 的 `command` 能否执行 `workspace/executeCommand` 并打开目标文件。若 ② 不成立就改用备选方案（终端清单 + 命令面板）并同步改文档。

> 📷 待补：Code Lens 挂在 MAIN 上（开 code_lens: "on" 后）（docs/images/zed/11-code-lens-main.png）

**当前可用的替代（Z-P2-2 ①，已随 0.2.0 提供）**：Agent 面板里执行
`/bdl-link-chain <程序代码>`（例如 `/bdl-link-chain axmt620`，也可写 `APM/axmt620` 或带 `.4gl` 后缀）——
它读 `.project/link/links.jsonl`，列出命中链的 **MAIN / 模组 / 程序号** 与**链内全部文件**（最多 30 个，超出折叠），
命中查询的那一行会标 `← 查询的文件`。也可先跑 `tiptop link status -root .` 确认资料存在，或直接看 `.project/link/links.jsonl` 原始行。

> 与终端清单的差异：slash command 输出在 **Agent 面板**（路径不可点击），但跨平台、可单测；
> 「终端清单 task」当前**没有**产出：链接关系的文本视图已由上面的 slash command 覆盖，迁移则有了专门的 task（见 §8.4 与 §10.4）。

> 📷 待补：终端清单里 MAIN 与子文件路径清单（docs/images/zed/12-link-tree-terminal.png）

### 3.3 反查引用 [🔧 计划中·P3 / ⬇️ 降级替代]

**口径**：Zed 侧采用**函数级**反查（「这个函数被哪些作业调用」），**不做** VSCode 那种
「反查引用程序 + 分页」的完整视图。

- 计划：函数定义处显示「被 N 处调用」并可跳转（Code Lens / `workspace/executeCommand`，Z-P3-2 / Z-P3-3）。
- 今天（降级）：用 Zed 原生**查找引用**看工作区**可解析**的引用（依赖符号索引；跨模组调用需链接资料才能解析）；整体统计用 `tiptop link status -root .`；要精确到「哪些 MAIN」就读 `.project/link/links.jsonl` 自己筛。
- **明确不采纳**：`Call Hierarchy`（语义是调用关系 ≠ 链接关系）、`documentLink`（位置分散）、把链接资料塞进 `documentSymbol`（会产生不可跳转的假符号）。

### 3.4 账号与密码 [✅ 当前可用]

密码**绝不写进配置文件与设置**：

| 来源 | 写法 | 说明 |
|---|---|---|
| 环境变量 | `export BDL_ORA_PASSWORD='<密码>'` | 优先级高于 `secrets.json` |
| 项目文件 | `<项目根>/.project/secrets.json` | 内容 `{"<用户名>":"<密码>"}`；`"*"` 是默认密码 |

优先级：配置内 `${env:VAR}` → 环境变量 `BDL_ORA_PASSWORD` → `.project/secrets.json`。

```jsonc
// <项目根>/.project/secrets.json（link 与 schema 共用同一个文件）
{ "tiptop": "<密码>", "*": "<默认密码>" }
```

```bash
chmod 600 .project/secrets.json      # Unix：不是 0600 时 tiptop 会直接报错退出
```

```powershell
$env:BDL_ORA_PASSWORD = "<密码>"     # Windows：跳过权限校验；用环境变量最省事
```

- **不要**放在 `.project/link/` 里（历史上有过这个错读 bug）；`.project/` 根只留这一个文件，并把它加进 `.gitignore`。
- 连接账号要用**应用 schema 账号**（自己拥有业务表，且对字典表 `DS.ZTA_FILE` / `DS.GAQ_FILE` 有读权限）。
- SSH 侧**不支持在配置里存密码**：上传/下载/执行只用 SSH key / ssh-agent。

---

## 4. 数据库字段资料 [✅ 当前可用 / ✅ 0.2.0 已落地（slash command）]

字段资料回答**这一列的中文说明、类型、长度是什么**，并支撑 `RECORD LIKE t.*` 成员校验与列补全。写侧在 `tiptop`，产物 `<项目>/.project/schema/`（注意**没有点号**；旧布局 `.project/.schema` 只读兼容）：

```text
<项目根>/.project/schema/
├── tables.json             # 索引：importedAt / source / rowsTotal / 每表列数与文件名
└── tables/<大写表名>.json   # 列清单：name/desc/type/length/charLength/precision/scale/nullable/default
```

### 4.1 采集（CSV 导入 / 直连 Oracle 分批同步） [✅ 当前可用]

```bash
tiptop schema status -root .                        # 表数 / 列数 / 导入时间 / 来源

tiptop schema import -csv gal_schema.csv -root .   # CSV 导入（DBA 导出）
tiptop schema import -csv gal_schema.csv -root . -only-new      # 只补本地不存在的表
tiptop schema import -csv gal_schema.csv -root . -dry-run

# 直连 Oracle 分批同步（推荐：应用 schema 账号）
tiptop schema sync -root . -source golang -host <Oracle主机> -port 1521 -service PROD -user <账号> \
  -batch-size 200 -timeout 120
tiptop schema sync -root . -source golang -host <主机> -service PROD -user <账号> -tables ima_file,ima_file2
tiptop schema sync -root . -source golang -host <主机> -service PROD -user <账号> -tables-file tables.txt
tiptop schema sync -root . -source golang -host <主机> -service PROD -user <账号> -only-new
tiptop schema sync -root . -source golang -host <主机> -service PROD -user <账号> -prune   # 只与全量一起用
tiptop schema sync -root . -source golang -host <主机> -service PROD -user <账号> -dry-run
```

参数：`-csv`、`-root`、`-out`、`-source golang|file`、`-file`、`-host`、`-port`、`-service`、`-user`、`-query`、`-tables`、`-tables-file`、`-only-new`、`-prune`、`-dry-run`、`-batch-size`、`-timeout`、`-owner`（仅自定义 SQL 用）。

**来源口径**：`schema sync -source golang` 默认查 **TiTop 字典**——表/列来自 `DS.ZTA_FILE`（`zta02='ds'`）
+ `USER_TAB_COLUMNS`，列说明取 `DS.GAQ_FILE.gaq03`（`gaq02='2'`），**不是 Oracle 备注**；
字典表不存在（`ORA-00942`）时会提示**改用 CSV 导入**。
**分批**：先取表清单，再每 `-batch-size`（默认 **200**，`0` = 不分批）张表查一批，
每批独立超时 `-timeout`（默认 **120** 秒），避免慢链路上单条大查询被取消（`ORA-01013`）。实测规模参考：2648 张表 / 58096 列，约 2.4 秒。

DBA 侧导出 SQL 模板见 `vscode-extension/README.md` §3.1（字段名不要改，`column_desc` 即中文说明）。

- **逐表增量写**：全量查询后逐表逐字节比较，只有变化的表才重写（避免无意义 mtime 变化让编辑器重载）；CSV 里没有的表默认**保留不删**，要删得显式 `-prune`。
- **安全写入**：已有 `tables.json` 是坏 JSON（或 schema 版本过高）→ 报错退出并**保留原文件**；写盘一律临时文件 + `rename`；每次导入前清理遗留的 `tables/.tmp-*`。
- **容错解析**：表头归一化后按别名匹配（容忍 `data_precicison`、`default_legth` 之类拼写错误）；支持 UTF-8 BOM / CRLF / 引号包裹逗号；`nullable` 支持 `Y/N`、`YES/NO`；空行、列数不足、缺表名/列名 → 跳过并计数，不中断整份导入。
- `schema status` 无资料时退出码也是 **1**；旧的「扫各模组 `sch/*.sch`」采集与 `schema.paths` **已整包下线**，只有 `.sch` 的老项目必须重导 CSV 或直连库。

> 📷 待补：`tiptop schema status` 输出（表数 / 列数 / 导入时间 / 来源）（docs/images/zed/13-schema-status.png）
> 🎬 待补：`schema sync -batch-size 200` 分批进度（解析阶段带「第 N 个/共 M 个」）（docs/images/zed/14-schema-sync-batch.mp4）

### 4.2 在 Zed 里查看字段说明 [✅ 0.2.0 已落地（设置生效）/ ✅ 当前可用（读资料）]

这一节由 `bdl-lsp` 提供，Zed 侧同样生效。0.2.0 起 `lsp.bdl-lsp.settings` 会合并下发（§1.3），所以**直接写 `link.mode` / `schema.mode` 即可**；默认是**轻量档**（扩展在未显式配置时补 `mode:"off"`），要用资料得改成 `"file"`（CSV 导入）或 `"db"`（直连采集）。**改完必须重启语言服务器**；只要采了资料且 mode 打开，就能看到说明。

| 能力 | 触发 | 说明 |
|---|---|---|
| 列说明悬停 | `DEFINE x LIKE t.col` 上悬停 | 追加 `t.col · 类型(长度) · 中文说明` |
| 表摘要 | 表名上悬停 | 给出该表摘要 |
| `RECORD LIKE t.*` 展开 | `RECORD LIKE t.*` 上悬停 | 列出该表字段（**超 20 行折叠**） |
| 记录成员校验 | 自动诊断 | `record-member-unknown` —— **默认 `off`**；`RECORD LIKE t.*` 用字段资料展开成员 |
| 列补全 | 输入 `r.` | 候选带类型与中文说明；`Ctrl+Space` 手动触发 |

要让 `record-member-unknown` 生效（默认关，因为开启后偏噪）：

```jsonc
{ "lsp": { "bdl-lsp": { "settings": { "diagnostics": { "record-member-unknown": "warning" } } } } }
```

> 📷 待补：`DEFINE x LIKE t.col` 悬停显示类型与中文说明（docs/images/zed/15-hover-column.png）
> 📷 待补：`RECORD LIKE t.*` 悬停展开字段（超 20 行折叠）（docs/images/zed/16-record-like.png）

### 4.3 表清单 / 列清单 [✅ 0.2.0 已落地（slash command）/ ❌ 无树视图]

两条**只读** slash command 已随 0.2.0 提供（Z-P1-1），只读 `.project/schema/tables.json` 与 `.project/schema/tables/<大写表名>.json`，**不写盘**：

- `/bdl-schema-tables [过滤]` —— 列表面（表名过滤是**大小写不敏感子串**，额外支持 `^前缀` 与 `后缀$` 两种锚点；**不是完整正则**，与 VSCode 树视图不同）；一次最多列 **200 行**，超出会提示加过滤收窄；
- `/bdl-schema-columns <表名>` —— 列出该表列清单（名称 / 类型(长度) / NULL / 说明），表名大小写不敏感（内部转大写）。

Zed **无侧边栏树视图**（永久差异，§9），VSCode 的四个动作落点如下：

| VSCode 动作 | Zed 替代 |
|---|---|
| 正则过滤表名 | `/bdl-schema-tables <子串>` 的参数（`^` / `$` 锚点，非完整正则） |
| 勾选 / 全选 / 清除勾选 | 无对应 UI；批量同步用 task 的 `-tables` / `-tables-file` |
| 同步选中的表 | task：`tiptop schema sync … -tables a,b` 或 `-tables-file tables.txt` |
| 复制列定义 | 用 `/bdl-schema-columns <表>` 拿文本后自行复制 |

> 📷 待补：`/bdl-schema-tables` 返回的表清单文本（docs/images/zed/17-slash-schema-tables.png）

---

## 5. 上传 / 下载 / 编译 / 链接 / 预览 [✅ 当前可用 / ⬇️ 降级替代（无 Problems 注入）]

这一组操作全部由 `tiptop` 在**生产端**执行，Zed 只负责把命令发出去。
**插件不自动上传**：编译/链接/预览前请自己先上传，或确认生产端已是最新。

### 5.1 总开关与前置 [✅ 0.2.0 已落地（配置键写法）/ ❌ 无命令显隐门控（Zed 无命令注册 API）]

VSCode 用 `bdl.deploy.enable` / `bdl.build.enable` 门控命令显隐；Zed 把同名语义收在 `ext` 下（**只作为配置记录，扩展与 task 都不读它** —— Zed 无法把按钮显隐映射成命令门控）：

| VSCode 设置 | Zed 设置（`settings.ext.*`） | 默认 | 作用 |
|---|---|---|---|
| `bdl.deploy.enable` | `ext.deploy.enable` | `false` | 仅作记录（不读）；真正是否上传由你跑不跑 task 决定 |
| `bdl.prod.deploy.transport` | `ext.prod.deploy.transport` | `off` | 仅作记录（不读）：真正用哪种传输由 `.project/deploy/deploy.json` 的 `upload.mode` 决定 |
| `bdl.build.enable` | `ext.build.enable` | `false` | 仅作记录（不读）；命令模板以 `.zed/tasks.json` 为准 |
| `bdl.prod.deploy.host/port/user` | `ext.prod.deploy.host/port/user` | `22`，其余空 | SSH 主机/端口/账号（**只支持密钥**） |
| `bdl.prod.deploy.region` | `ext.prod.deploy.region` | `1` | 登录后要输入的「区」 |
| `bdl.prod.deploy.remoteRoot` / `localRoot` | `ext.prod.deploy.remoteRoot` / `localRoot` | 空 / `.` | 生产根与本地根 |
| `bdl.prod.oracle.*` / `bdl.schema.batchSize` / `timeoutSec` | `ext.prod.oracle.*` / `ext.schema.batchSize` / `timeoutSec` | `1521`，其余空 / `200` / `120` | 直连采集的 Oracle 连接；字段资料分批参数 |
| `bdl.tools.path` | `ext.tools.path` | 空 | `tiptop` 路径覆盖（0.2.0 起生效） |
| `bdl.server.path` | `lsp.bdl-lsp.binary.path`（**Zed 原生键**） | 空 | `bdl-lsp` 路径覆盖 |

**「区」的含义**（只影响编译/链接/预览）：登录后**先输入区号**，再 `source` 对应环境脚本，最后 `cd` 到生产根执行：

| 区 | 环境 | profile |
|---|---|---|
| `1` | topprod | `/u1/usr/profile/profile.topprod` |
| `2` | toptest | `/u1/usr/profile/profile.toptest` |
| `3` | topstd | `/u1/usr/profile/profile.topstd` |
| `4` | Browser-based | **不 source** |

区没配置时这些命令会直接报错并提示设置入口。初始化项目用的是脚本自己的 `-Region` / `--region`，与此无关。

前置：① SSH 能通且**已配密钥**；② `tiptop` 能被 task 找到（`PATH` 或绝对路径）；③ 生产环境这些键**只写 Workspace 级** `.zed/settings.json` 且**不要提交 git**。

> ⚠️ VSCode 侧 README 在 2026-10-27 明确写过「此功能还未经过完整测试」；Zed 走的是同一批 `tiptop` 命令，请先 `-dry-run` 确认计划。

### 5.2 上传当前文件 / 预演上传 / 下载当前文件 [✅ 当前可用]

三条命令**只动当前打开的那一个文件**，不做批量同步。

```bash
tiptop upload -workspace . -file aap/4gl/x.4gl                    # 工作区根 → 生产根，同相对路径
tiptop upload -workspace . -file aap/4gl/x.4gl -dry-run           # 预演上传：只打印计划

tiptop download -workspace . -file aap/4gl/x.4gl                  # 生产根 → 工作区根，【覆盖本地】
tiptop download -workspace . -file aap/4gl/x.4gl -dry-run
```

- `-file` **必须相对路径**：绝对路径、盘符、`..` 越界都会被拒绝（路径安全）。
- 下载是**覆盖写**，`tiptop` 自身**不备份也不询问**；Zed 侧没有差异确认弹窗（无 API），**下载前请自己 `git status` 或先提交**。
- 上传/下载与 `tiptop deploy` 用**同一份配置** `.project/deploy/deploy.json`；上传前 task 里加 `"save": "current"`，否则传的是磁盘旧内容。
- ✅ **`.project/deploy/deploy.json` 由生成脚本产出**（`scripts/zed/init-workspace.*`）：问答里填了「SSH 主机 + 生产根」且上传方式不是 `off` 时，脚本会按 `ext.prod.deploy.*` 同一批答案写出这份配置（目标名 `prod`，`upload.mode` 取你选的 rsync/scp，`compile.4gl` = `fglcomp -M {file}`、`compile.per` = `fglform {file}`）；已存在则**不覆盖**，改写 `deploy.json.bdl-new`。
  没用脚本 / 想改模板，就手写这份文件（样例见 §5.4），或用 `tiptop deploy -config <文件>` 指定别处配置。
  `settings.ext.prod.deploy.*` 本身仍只是记录（没有消费者）；PLAN Z-P2-4 的剩余部分是让生成脚本回读 `ext.build.*` 模板。

> 📷 待补：task 里「上传当前文件」的执行输出（含 rsync/scp 明细）（docs/images/zed/18-upload-task.png）

### 5.3 4GL 与 Form 的预演编译 / 编译 / 链接 / 预览 [✅ 当前可用]

六条命令在**生产服务器**上执行（工作目录 = 生产根），Zed 统一走 `tiptop exec`：

```bash
tiptop exec -workspace . -file aap/4gl/x.4gl -command 'cd aap/4gl && r.c2 x' -region 1
tiptop exec -workspace . -file aap/4gl/x.4gl -command 'r.l2 x' \
            -region 1 -login-profile /u1/usr/profile/profile.topprod
tiptop exec -command 'cd tiptop/axc/per && r.gf x 2 p' -region 1      # Form 预览画面
tiptop exec -command 'cd aap/4gl && r.c2 x' -dry-run                  # 只打印不执行
```

`-login-profile <路径>` 是「cd 之前 source 的环境脚本（覆盖配置里的 loginProfile）」；`-file` 在 `exec` 里**只用于打印上下文**，不参与命令本身。stdout/stderr 原样回传，
**退出码 = 远程退出码**。

模板占位符（模板可改，分隔符**恒为 `/`**）：`${path}`（两层，如 `aap/4gl`）、`${fullpath}`（三层）、`${name}`（去扩展名）、`${fullname}`（含扩展名）。默认模板（`ext.build.*`）：

> ⚠️ **Zed 侧 `ext.build.*` 目前不生效**：task 读不到 Zed 设置，生成脚本用的是内置默认模板；
> 也就是说 Zed 上"有效的模板"是 **`.zed/tasks.json` 里各 task 的 `-command`**（改那里即可生效）。
> `ext.build.*` 暂时只是配置记录（PLAN Z-P2-4 会让生成脚本读它）。

```text
4gl.preview   cd ${path} && r.c2 ${name}
4gl.compile   cd ${path} && r.c2 ${name}
4gl.link      r.l2 ${name}
per.preview   cd ${path} && fglform -M -W all ${fullname} && rm ${name}.42f
per.compile   cd ${path} && fglform -M -W all ${fullname} && mv ${name}.42f ../42f/ \
              && gsform -M -W all -i -import ${fullname} && mv ${name}.4fd ../4fd/
per.form      cd ${path} && r.gf ${name} 2 p
```

- **`2 p` 不是笔误**：Form「预览画面」默认命令字面就是 `cd ${path} && r.gf ${name} 2 p`（三个参数）。
- **只有 4GL「链接」在 VSCode 侧会弹 `${name}` 输入框**（可临时换主程序名）；Zed 无输入框 API——要改主程序名就**改 task 里的命令**。
- **无 MAIN 时「链接」不可用**（VSCode 按 MAIN 门控）；Zed 由 task 自己承担，不做门控。
- 命令**不自动上传**：先 §5.2 上传，再编译。

> 📷 待补：`tiptop exec` 的编译输出（远程 stdout/stderr 原样回传）（docs/images/zed/19-build-task.png）

### 5.4 整包部署 [✅ 当前可用（**只有命令行**，不进扩展）]

`tiptop deploy` 是整包/多文件上传 + 远程编译；**Zed 扩展从不调用它**（VSCode 插件也不调用）：

```bash
tiptop deploy -list                                   # 列出配置里的部署目标
tiptop deploy -dry-run                                # 只打印计划，不连接/不上传
tiptop deploy -dry-run -json                          # 结构化结果（给脚本用）
tiptop deploy -target prod aap/4gl/aapi202.4gl        # 只部署指定文件
tiptop deploy -workspace . -dry-run
tiptop deploy -no-compile -target prod                # 只上传
tiptop deploy -no-upload  -target prod                # 只编译
```

配置模型 `.project/deploy/deploy.json`（旧 `.bdl-lsp/deploy.json` 只读兼容）：`targets.<名>.{host,port,user,remoteRoot,localRoot,upload{include,exclude,mode,rsyncArgs,fallback,delete},compile{4gl,per},strictHostKey,connectTimeout}` + `defaultTarget`，例如 `"compile": { "4gl": "fglcomp -M {file}", "per": "fglform {file}" }`。认证用 SSH key / ssh-agent，**不支持在配置里存密码**；`{file}` 在 `compile.*` 里替换为**远端路径**。

**可直接改成自己环境的最小样例**（Zed 侧要手写；字段名写错会直接报错，因为解析用 `DisallowUnknownFields`）：

```jsonc
// <项目根>/.project/deploy/deploy.json
{
  "defaultTarget": "prod",
  "targets": {
    "prod": {
      "host": "10.0.0.10",
      "port": 22,
      "user": "appuser",
      "remoteRoot": "/u1/topprod",   // 必须是绝对路径
      "localRoot": ".",
      "strictHostKey": true,
      "upload": {
        "mode": "rsync",              // off | rsync | scp
        "fallback": "scp",
        "include": ["**/*.4gl", "**/*.per"],
        "rsyncArgs": ["-az"]
      },
      "compile": {
        "4gl": "fglcomp -M {file}",   // {file} = 远端路径，必填
        "per": "fglform {file}"
      }
    }
  }
}
```

> 📷 待补：`tiptop deploy -dry-run` 的计划输出（docs/images/zed/20-deploy-dry-run.png）

### 5.5 编译结果与日志 [❌ 平台不支持（Problems 注入）/ ⬇️ 降级替代]

**Zed 扩展无法把远程编译错误注入 Problems**（`zed_extension_api 0.7.0` 没有诊断注入 API）。这是**永久差异**。

| VSCode | Zed |
|---|---|
| 编译/部署结果解析成编辑器诊断，显示在 Problems | ❌ 只能**看 task 终端**的原始输出 |
| 「4gl」/「4gl 任务」两个输出通道 | ⬇️ task 终端（`reveal: "always"`）+ `zed: open log` |
| 每次运行落盘 `last-run-<cmd>.log` | ⬇️ 终端输出可复制；可选 `tee` 到 `.project/logs/`（P1 可选） |

- **看 task 输出**：task 设 `"reveal": "always"`；`use_new_terminal: false` + `allow_concurrent_runs: true` 让重跑时取消上一次。
- **看扩展与语言服务器日志**：命令面板执行 **`zed: open log`**。语言服务器起不来、配置下发异常、`initialize` 失败都写在这里——**排错第一步就是它**。
- `tiptop` 的进度与错误写 **stderr**；退出码 `0` 成功 / `1` 业务失败 / `2` 用法错误；`exec` 的退出码**就是远程退出码**。
- 口径：**编辑期辅助，编译才是最终验证**（`bdl-lsp` 不替代 `fglform` / `fglcomp`）。

> 📷 待补：`zed: open log` 里的语言服务器日志（docs/images/zed/21-open-log.png）

---

## 6. 编辑与导航 [✅ 当前可用 / ⚠️ 待实机核实（语义高亮着色）]

### 6.1 高亮 / outline / 括号 / 缩进 / SQL 注入 [✅ 当前可用]

全部由 tree-sitter query 实现（`languages/bdl/` 与 `languages/per/`，共 9 个 `.scm`），不在 Rust 侧、也不在 `bdl-lsp` 侧：

| 能力 | 说明 |
|---|---|
| 语法高亮 | `.4gl` / `.global` / `.per`；关键字 300 / 76 个全覆盖（清单校验 + 47 项 query 校验全绿） |
| Outline | 函数 / `REPORT` / `MAIN` / `TYPE` / `item` / `SCREEN RECORD` / `DEFINE` / `RECORD` / `PREPARE` 游标 |
| 括号匹配 | 由 query 提供 bracket 规则 |
| 缩进 | 由 query 提供；**`.per` 的 `LAYOUT` 绝不缩进**（表单靠列位，缩进会破坏排版） |
| SQL 注入 | `.4gl` 里 `SELECT` / `INSERT` / `UPDATE` / `DELETE` 内按 SQL 高亮（注入 language `sql`） |

> 📷 待补：`.4gl` 高亮 + Outline + `.per` LAYOUT 不缩进（docs/images/zed/22-highlight-outline.png）

### 6.2 悬停、跳转、引用、补全、重命名、Code Action [✅ 当前可用]

全部由 `bdl-lsp` 提供、Zed 宿主消费（快捷键是 Zed 原生的，本扩展不注册）：

| 能力 | 说明 |
|---|---|
| 悬停 | 变量来源、定义位置、函数信息；`LIKE t.col` 追加字段资料；悬停表名给表摘要 |
| 跳转定义 | 当前文件、GLOBALS（`.global`）、**链接资料内**文件 |
| 查找引用 | 工作区**可解析**的引用（自动排除注释与字符串） |
| 补全 | 关键字、变量、函数、表单字段、表名、列；`.` 触发记录成员/表单字段；`Ctrl+Space` 手动触发 |
| 重命名 / 快速修复 | `prepare` + `rename`（**只改当前文件**、大小写不敏感、不动字符串）；仅 `quickfix` 的字段名改名建议 |
| 游标 / PREPARE 符号 | `PREPARE` / `DECLARE CURSOR` 声明；`EXECUTE`/`FETCH`/`OPEN`/`CLOSE`/`FOREACH` 悬停与跳转 |

- **重命名只改当前文件**，不跨文件——这是**有意不做**的能力（与 VSCode 侧一致）。
- **变量检查只回答「这个名字有没有来源」，函数检查只回答「这个名字有没有定义」**；**不做类型检查、不做赋值兼容性检查**。
- **`function-not-found` 需要两个前提**：① 有链接资料；② 索引预热完成。缺任一个就**一律不报**（宁漏勿误）。查找引用依赖工作区符号索引（§6.5），索引没跑完时结果会偏少。

> 🎬 待补：跳转定义 / 查找引用 / 补全（含 `r.` 列补全）的演示（docs/images/zed/23-navigation.mp4）

### 6.3 格式化 [✅ 当前可用]

- 支持 **`.4gl` / `.global`**；`format.keywords`（`unchanged` / `upper` / `lower`，`lower` 同时作用于关键字补全）、
  `format.indentStyle`、`format.indentSize`（`0` = 自动/跟随文件）。
- **`.per` 一律不格式化**——不是"没做"，是**明确不做**（表单布局靠列位）。
- 安全守卫：文件里有 `ERROR` 时**不格式化**；格式化**幂等**。
- Zed 里 `editor: format` 即调用语言服务器；若同语言链了别的格式化器，可显式指定：

```jsonc
{ "languages": { "Genero BDL": { "formatter": "language_server", "format_on_save": "on" } } }
```

> 📷 待补：`.4gl` 格式化前后对比（docs/images/zed/24-format.png）

### 6.4 语义高亮 [✅ 0.2.0 已提供扩展规则 / ⚠️ 待实机核实（着色效果）]

现状：`bdl-lsp` 已发 `semanticTokens/full`；本扩展的 `languages/bdl/semantic_token_rules.json` 与 `languages/per/semantic_token_rules.json` 也已随 **0.2.0** 提供（各 **8 条**规则，Z-P0-4），按 `bdl-lsp` 的 legend 写、带主题回退（每条 `style` 给多个候选）。① **Zed 默认 `semantic_tokens: "off"`**，要显式打开；② Zed 的扩展级规则优先级为「用户规则 > 扩展规则 > Zed 内置」。**规则已就位，但着色效果仍为 ⚠️ 待实机核实。**

服务端口径：只发**用户自定义符号**（关键字/字符串交给 TextMate/tree-sitter 着色）；函数 `declaration`、常量 `readonly`、GLOBALS 块 `static`。规则文件覆盖 legend：`variable` / `parameter` / `function` / `struct` / `property` / `keyword`，以及 `readonly` / `static` 两个修饰符。

```jsonc
{ "languages": { "Genero BDL": { "semantic_tokens": "combined" }, "Genero Form": { "semantic_tokens": "combined" } } }
```

`combined` = 语义 token 与语法高亮**合并**显示；`off` 关闭。语言名写 `"Genero BDL"` / `"Genero Form"`，别写 `4gl`。

> 📷 待补：语义高亮开 / 关对比（同一段 .4gl）（docs/images/zed/25-semantic-on.png、26-semantic-off.png）

### 6.5 大纲与 worktree 符号索引 [✅ 当前可用]

| 能力 | 说明 |
|---|---|
| 文件内大纲 | `documentSymbol`；MAIN 程序块的 `detail` 为 `MAIN` |
| 工作区符号 | `bdl-lsp` 实现了 `workspace/symbol`（后台全工作区索引 + **持久化快照**，覆盖**未打开**的文件），但 `InitializeResult` **没有声明 `workspaceSymbolProvider`** → Zed 的命令面板符号搜索**可能不发这个请求**。已在 PLAN §11.2 #19 列为实机核实项；若确实不生效，需要 `bdl-lsp` 补一行声明（PLAN §10.2 待确认） |
| 索引开关 | `settings.index.enable`（默认 `true`）；超大仓库或只想编辑单文件时可关 |
| 性能 | 实测 7756 个文件首次约 **24.7 秒**（后台、不阻塞编辑），之后按 `(mtime,size)` 增量约 **22 毫秒** |

在 Zed 里用「大纲面板」看当前文件结构，用命令面板里的符号跳转搜整个工作区（命令名随 Zed 版本变化，搜 `symbol` 即可）。没有索引时跳转/引用/符号搜索**只看得到已打开文件**，用户会感到"时而能跳时而不能"；索引也是 `function-not-found` 能报出来的前提之一。

> 📷 待补：大纲面板 + 工作区符号搜索结果（docs/images/zed/27-outline-symbols.png）

---

## 7. 诊断与检查 [✅ 当前可用 / 🔧 计划中·P3（强制解析）]

诊断由 `bdl-lsp` 通过标准 LSP `publishDiagnostics` 发出，**Zed 宿主直接渲染**（内联/诊断列表）。扩展自己**不能注入诊断**——这也意味着**远程编译错误进不了诊断**（§5.5）。

### 7.1 诊断码表与默认级别 [✅ 当前可用]

权威来源：`bdl-lsp/docs/DIAGNOSTICS.md`（由 `make diagnostics-write` 从注册表生成，**不要手改**）。下表逐行照抄，**默认级别以本表为准**：

| 诊断码 | 默认级别 | 说明 |
|---|---|---|
| `field-not-in-form` | `warning` | `INPUT … FROM`、`AFTER FIELD` 等引用的字段不在表单 `.per` 里 |
| `file-too-large` | `warning` | 超过解析上限（`limits.maxFileBytes` / `maxFileLines`），已跳过语法检查 |
| `form-duplicate-item` | `warning` | 表单 `ATTRIBUTES` 里重复定义了同名 item |
| `form-layout-tag-undefined` | `warning` | 表单 `LAYOUT` 引用了 `ATTRIBUTES` 未定义的 item tag |
| `form-screen-record-undefined` | `warning` | 表单 `SCREEN RECORD` 引用了未定义的 item 或字段名 |
| `function-not-found` | `warning` | 调用的函数在当前模块及可用模组中找不到定义（**需链接资料**） |
| `globals-file-not-found` | `warning` | `GLOBALS "路径"` 的目标文件找不到 |
| `link-data-invalid` | `warning` | 链接资料格式不合法（JSONL 解析失败、schema 版本过高） |
| `link-data-legacy-dir` | **`hint`** | 链接资料仍在旧目录 `.link/`；可一键迁移到 `.project/`（迁移前先确认） |
| `missing-node` | `warning` | grammar 的 MISSING 节点整簇兜底码（缺 `END IF`、缺逗号等） |
| `parse-timeout` | `warning` | 解析超时（`limits.parseTimeoutMs`），本轮已跳过诊断 |
| `record-member-unknown` | **`off`** | `BY NAME rec.member` 成员不在 RECORD 声明里（**默认关**） |
| `syntax-error` | `warning` | grammar 的 `ERROR` 节点（无法解析的片段） |
| `variable-source-unresolved` | `warning` | 变量使用处查不到任何定义（局部 / 模块级 / GLOBALS 均无） |

> ⚠️ 三个最容易记错的默认值：`link-data-legacy-dir` = **`hint`**、`record-member-unknown` = **`off`**、
> `file-too-large` = **`warning`**。

**动态码** `missing-<kind>`：`kind` 来自 grammar 节点类型，数量随语法版本变化、**无法穷举**；`diagnostics.missing-<kind>` 精确命中单个类型，`missing-node` 作为整簇兜底（注册表对 `missing-` 前缀一律放行）。级别取值：`off` / `error` / `warning` / `information` / `hint`。

**调级的唯一入口**是 `diagnostics`（逐码；未列出的码用默认值，旧的专用键已全部移除）：

```jsonc
{
  "lsp": {
    "bdl-lsp": {
      "settings": {
        "diagnostics": { "variable-source-unresolved": "off", "function-not-found": "hint", "record-member-unknown": "warning" }
      }
    }
  }
}
```

> 0.2.0 生效提示见 §1.3：这段直接写在 `lsp.bdl-lsp.settings` 里即可；**改完必须重启语言服务器**（生效配置只在启动时下发一次）。

> 📷 待补：编辑器里出现诊断（含级别颜色）与诊断列表（docs/images/zed/28-diagnostics.png）

### 7.2 忽略、上限与大文件 [✅ 当前可用（忽略与上限）/ 🔧 计划中·P3（强制解析）]

```jsonc
{ "lsp": { "bdl-lsp": { "settings": { "ignore": {
  "files": ["**/backup/**", "**/tmp/**", "**/*.old.4gl"],
  "fields": ["tmp_*", "zz_*"],
  "forms": ["cust", "**/legacy/per/**"] } } } } }
```

| 键 | 作用 |
|---|---|
| `ignore.files` | **屏蔽该文件的所有诊断，并把它排除出索引**（glob 支持 `**`） |
| `ignore.fields` | 只屏蔽 `field-not-in-form`（按字段名） |
| `ignore.forms` | 屏蔽指定表单相关的校验 |

| 上限键 | 默认 | 作用 |
|---|---|---|
| `limits.maxFileBytes` | `2097152`（2 MB） | 超过则**跳过语法检查**并发 `file-too-large` |
| `limits.maxFileLines` | `20000` | 同上（行数口径） |
| `limits.maxIssues` | `200` | **单文件报告上限**（超出不再报） |
| `limits.parseTimeoutMs` | `2000` | 超过则本轮跳过诊断并发 `parse-timeout` |

**大文件跳过与强制解析**：

- 跳过本身是**设计好的降级**（宁可不报也不卡住编辑器），不是坏了。
- VSCode 侧标题栏有「强制解析当前文件」（上下文 `bdl.parseSkipped`），走自定义请求 `bdl/forceParse`，**后台不限时**（`Timeout 0`），完成后回执并刷新大纲。
- **Zed 侧【🔧 计划中·P3】**：`/bdl-force-parse` 需要服务端先支持 `workspace/executeCommand`（Z-P3-2），在那之前它会明确提示"需要服务端支持"。
- **今天的替代**：临时调大 `limits.parseTimeoutMs`（如 `10000`）或 `maxFileBytes`；用 CLI 单独检查 `bdl-lsp check --max-issues 500 <文件>`；或先用 `ignore.files` 排除噪声大的文件。

> 📷 待补：大文件被跳过时的 `file-too-large` 提示（docs/images/zed/29-file-too-large.png）

---

## 8. 设置参考 [✅ 当前可用 / 🔧 计划中·P3（热更新）]

### 8.1 Zed 设置总表 [✅ 0.2.0 已落地（生效性）/ ✅ 写法]

位置：`lsp.bdl-lsp.settings`（`.zed/settings.json` 或全局 `settings.json`）。
**0.2.0 提醒**：这些键会被扩展合并后从 `initializationOptions` 下发（去掉 `ext`、补轻量档默认），**直接写这里即可**；`initialization_options` 仍是优先级最高的逃生口（§1.3）。**改完必须重启语言服务器**（热更新见 P3 / Z-P3-1）。

**① 下发给 `bdl-lsp` 的键**（与 `internal/config.Settings` 同名，**无 `bdl.` 前缀**）：

| 键 | 类型 | 默认值 | 一句说明 |
|---|---|---|---|
| `generoVersion` / `logLevel` | string | `"2.50"` / `"info"` | 目标 Genero 版本基线；语言服务器日志级别（非 `info` 时扩展同时作为 `serve --log-level <级别>` 参数） |
| `globals.searchPaths` / `perRoots` | string[] | `[]` | GLOBALS 附加解析根（相对工作区根）；`.per` 附加查找根 |
| `diagnostics` | object | `{}` | **逐诊断码调级的唯一入口**；未列出的用默认级别 |
| `builtins.enable` / `paths` / `disable` | bool / string[] / string[] | `true` / `[]` / `[]` | 内置符号表总开关、附加符号 JSON、屏蔽名单 |
| `link.mode` / `dataDir` / `moduleRoots` / `globalModules` | string/string/string[]/string[] | `off` / `.project/link` / `[]` / `["sub","lib","qry"]` | 链接资料三态（`off \| file \| db`，**默认 off**）、目录、模组根、全局可见扁平模组 |
| `schema.mode` / `dataDir` | string | `"off"` / `".project/schema"` | 字段资料三态（**默认 off**）与目录（旧 `.project/.schema` 只读兼容） |
| `index.enable` | bool | `true` | 后台工作区符号索引 |
| `ignore.files` / `fields` / `forms` | string[] | `[]` | 忽略列表（支持 `**`） |
| `format.keywords` / `indentStyle` / `indentSize` | string/string/int | `unchanged` / `auto` / `0` | 关键字大小写（`lower` 也影响补全）、缩进风格与宽度 |
| `limits.maxFileBytes` / `maxFileLines` / `maxIssues` / `parseTimeoutMs` | int | `2097152` / `20000` / `200` / `2000` | 跳过语法检查的字节/行上限、单文件报告上限、解析超时 |

**② 仅 Zed 扩展自用的键**（收在 `ext` 下，**不下发给 LSP**）：

| 键 | 类型 | 默认值 | 一句说明 |
|---|---|---|---|
| `ext.tools.path` | string | `""` | `tiptop` 路径覆盖（0.2.0 起生效）；不写则按 `TIPTOP_PATH` → 工作区 `.bdl-lsp/bin/` → `PATH` 找 |
| `ext.schema.batchSize` / `timeoutSec` | int | `200` / `120` | `schema sync` 分批大小（`0` = 不分批）与每批超时（秒） |
| `ext.prod.oracle.host` / `port` / `service` / `user` | string/int | `1521`，其余空 | 直连采集的 Oracle 连接（**不放密码**） |
| `ext.prod.deploy.host` / `port` / `user` / `region` / `strictHostKey` | string/int/bool | `22` / `"1"` / `true`，其余空 | SSH 主机/端口/账号（**只支持密钥**）；登录后要输入的区（`1` topprod / `2` toptest / `3` topstd / `4` Browser-based）；严格主机密钥校验 |
| `ext.prod.deploy.transport` / `localRoot` / `remoteRoot` | string | `"off"` / `"."` / `""` | 上传方式（`off \| rsync \| scp`，`off` = 关闭上传）、本地根、生产根 |
| `ext.deploy.enable` / `ext.build.enable` | bool | `false` | 仅作配置记录（**扩展与 task 都不读**，Zed 也没有按钮显隐）；是否跑 task 由你自己决定 |
| `ext.build.4gl.preview` / `compile` / `link` | string | 见 §5.3 默认模板 | 4GL 三条命令模板 |
| `ext.build.per.preview` / `compile` / `form` | string | 见 §5.3 默认模板 | Form 三条命令模板 |
| `ext.download.bdlLsp` / `ext.download.tiptop` | string | `"auto"` | 自动下载开关 `auto \| off`（键缺省 = `auto`）。两者都已可用（`tiptop` v0.1.10 起有 Release）。**只在四级本地查找全落空时才下载** |

**③ Zed 宿主键**（不是本扩展的 `settings`，由 Zed 直接消费）：

| 键 | 类型 | 默认值 | 一句说明 |
|---|---|---|---|
| `lsp.bdl-lsp.binary.path` | string | `""` | `bdl-lsp` 路径（写了必须存在）；支持 `~/` 展开 |
| `lsp.bdl-lsp.binary.arguments` | string[] | `[]` | 附加启动参数（一般留空；Zed 自己起 stdio） |
| `lsp.bdl-lsp.binary.env` | object | `{}` | 启动语言服务器的附加环境变量 |
| `lsp.bdl-lsp.initialization_options` | object | 无 | **逃生口**：启动时下发的配置（优先级最高） |
| `languages."Genero BDL".semantic_tokens` | string | `"off"` | 语义高亮开关（`combined` 打开，见 §6.4） |
| `languages."Genero BDL".code_lens` | string | `"off"` | Code Lens 开关（P3 后用，见 §3.2） |
| `languages."Genero Form".semantic_tokens` | string | `"off"` | 同上（语言名必须写全） |

### 8.2 项目级配置 `.bdl-lsp/config.json` [✅ 当前可用（可提交）]

由 `bdl-lsp` 自己读取，**可以提交进 git**（团队共享）。合并优先级（高 → 低）：
**编辑器下发的设置** → **`.bdl-lsp/config.json`** → **内置默认值**；策略是「非零值覆盖」，
所以客户端只下发自己改过的键，不会抹掉团队配置。

```jsonc
// <项目根>/.bdl-lsp/config.json（可提交）
{
  "generoVersion": "2.50",
  "diagnostics": { "record-member-unknown": "warning" },
  "globals": { "searchPaths": ["tiptop/config", "topcust/config"] },
  "perRoots": ["tiptop/aap/per"],
  "schema": { "mode": "file", "dataDir": ".project/schema" },
  "link": { "mode": "file", "dataDir": ".project/link", "moduleRoots": [], "globalModules": ["sub", "lib", "qry"] },
  "ignore": { "files": ["**/backup/**", "**/tmp/**"] } }
```

`link` / `schema` 也接受旧写法 `"enable": true|false`；两者同时出现时 **`mode` 优先**（`mode: "off"` 才关闭）。同目录下还可放 `<项目根>/.bdl-lsp/builtins.json` 覆盖内置符号表（自动发现，2 秒节流热更新）。

### 8.3 环境变量 [✅ 当前可用]

| 变量 | 谁读 | 作用 |
|---|---|---|
| `BDL_LSP_PATH` | **Zed 扩展**（`src/lib.rs`） | `bdl-lsp` 路径（第 2 优先级）；文件不存在会直接报错 |
| `TIPTOP_PATH` | **Zed 扩展**（✅ 0.2.0 已落地，Z-P0-5） | `tiptop` 路径（第 2 优先级）；不写则由工作区 `.bdl-lsp/bin/` 或 `PATH` 兜底。**task 读不到 Zed 设置**，task 里仍需 `PATH` 或绝对路径（§8.4） |
| `BDL_ORA_PASSWORD` | **`tiptop`** | Oracle 密码；优先级高于 `.project/secrets.json` |

> ⚠️ **`bdl-lsp` 服务端不读任何环境变量**；`BDL_LSP_PATH` 是**客户端侧**（扩展）约定，只影响"去哪找可执行文件"。
> ⚠️ task 继承 **Zed 启动时**的环境；外部改了环境变量需重启 Zed 才可见。

### 8.4 task 模板总表与 keymap 绑定 [✅ 0.2.0 已落地（生成脚本）/ ✅ 当前可用（模板可手工建）]

用 `"command": "tiptop"` + `"args": [...]` + `"cwd": "$ZED_WORKTREE_ROOT"`，或 `"command": "bdl-lsp"`；`"save": "current"` 用于上传前保存脏文档。
**变量**：`$ZED_FILE`（绝对路径）、`$ZED_RELATIVE_FILE`（相对工作区根）、`$ZED_RELATIVE_DIR`、
`$ZED_STEM`（无扩展名）、`$ZED_WORKTREE_ROOT`、`$ZED_LANGUAGE`、`${VAR:默认值}`。
**常用字段**：`command` / `args` / `env` / `cwd` / `use_new_terminal` / `allow_concurrent_runs` /
`reveal` / `hide` / `shell` / `show_summary` / `show_command` / `save`（`all|current|none`）/ `tags` / `hooks`。

| label | 命令要点 | 阶段 |
|---|---|---|
| `4gl: 初始化 Zed 工程（生成 .zed 配置）` | 交互式脚本 `scripts/zed/init-workspace.sh`，生成 `.zed/settings.json` / `.zed/tasks.json` / `.zed/bdl-tool.json`（含 `.gitignore` 提示） | ✅ 0.2.0（脚本已入库；这条 task 需按 §2.2 手工加） |
| `4gl: 初始化项目（从生产服务器拉取代码）` | 调 init-project 脚本（Linux/WSL→bash，Windows→PowerShell），终端里跑、可交互输入密码 | ✅ 0.2.0（生成脚本可挂载；init-project 脚本需自备） |
| `4gl: 链接资料：查看状态` | `tiptop link status -root $ZED_WORKTREE_ROOT` | ✅ 当前可用 |
| `4gl: 链接资料：从 CSV 导入` | `tiptop link import -csv <CSV> -root $ZED_WORKTREE_ROOT`（CSV 路径用交互脚本或参数填入） | ✅ 当前可用 |
| `4gl: 链接资料：全量更新` | `tiptop link sync -root $ZED_WORKTREE_ROOT -source golang -host … -port … -service … -user …` | ✅ 当前可用 |
| `4gl: 链接资料：按模组更新` | 同上追加 `-modules <m1,m2>` | ✅ 当前可用 |
| `4gl: 链接资料：更新当前文件` | 同上追加 `-files $ZED_RELATIVE_FILE` | ✅ 当前可用 |
| `4gl: 链接关系（终端清单）` | 打印 MAIN 与链内子文件的路径清单（Code Lens 的替代） | 🔧 计划中·P2 |
| `4gl: 字段资料：查看状态` | `tiptop schema status -root $ZED_WORKTREE_ROOT` | ✅ 当前可用 |
| `4gl: 字段资料：从 CSV 导入` | `tiptop schema import -csv <CSV> -root $ZED_WORKTREE_ROOT` | ✅ 当前可用 |
| `4gl: 字段资料：从数据库同步` | `tiptop schema sync -root $ZED_WORKTREE_ROOT -source golang -host … -service … -user … -batch-size 200 -timeout 120` | ✅ 当前可用 |
| `4gl: 上传当前文件` | `tiptop upload -workspace $ZED_WORKTREE_ROOT -file $ZED_RELATIVE_FILE`，`"save": "current"` | ✅ 当前可用 |
| `4gl: 预演上传` | 同上加 `-dry-run` | ✅ 当前可用 |
| `4gl: 下载当前文件` | `tiptop download -workspace $ZED_WORKTREE_ROOT -file $ZED_RELATIVE_FILE` | ✅ 当前可用（**覆盖本地**，先自行 `git status`） |
| `4gl: 4GL 预演编译 / 编译 / 链接` | `tiptop exec -command "<模板展开>" [-region ..] [-login-profile ..]` | ✅ 当前可用 |
| `4gl: Form 预演编译 / 编译 / 预览画面` | 同上 | ✅ 当前可用 |
| `4gl: 部署预演 / 列出目标` | `tiptop deploy -dry-run` / `tiptop deploy -list` | ✅ 当前可用 |
| `4gl: 迁移项目资料目录（旧目录 → .project/）` | `.zed/bdl/migrate-data.sh`（Windows 用 `.ps1`）：只搬移、绝不覆盖，空旧目录删除 | ✅ 0.2.0 |

可直接复制的 `.zed/tasks.json`（把 `<Oracle主机>` 等占位符换成实际值；或用 `scripts/zed/init-workspace.sh` 自动生成，§2.2）：

```jsonc
[
  {
    "label": "4gl: 链接资料：更新当前文件",
    "command": "tiptop",
    "args": ["link", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang",
             "-host", "<Oracle主机>", "-port", "1521", "-service", "PROD", "-user", "<账号>",
             "-files", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 字段资料：从数据库同步",
    "command": "tiptop",
    "args": ["schema", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang",
             "-host", "<Oracle主机>", "-service", "PROD", "-user", "<账号>",
             "-batch-size", "200", "-timeout", "120"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 上传当前文件",
    "command": "tiptop",
    "args": ["upload", "-workspace", "$ZED_WORKTREE_ROOT", "-file", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "save": "current",
    "reveal": "always"
  },
  {
    "label": "4gl: 4GL 编译",
    "command": "tiptop",
    "args": ["exec", "-workspace", "$ZED_WORKTREE_ROOT", "-file", "$ZED_RELATIVE_FILE",
             "-command", "cd aap/4gl && r.c2 $ZED_STEM", "-region", "1"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "reveal": "always"
  }
]
```

> **提示**：`-command` 里的目录**最稳是写死**（如 `cd aap/4gl && r.c2 $ZED_STEM`）；按当前文件自动取目录请用 Zed 变量 `$ZED_RELATIVE_DIR`（如 `cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM`），**不要写 VSCode 的 `${path}` / `${name}` / `${fullname}`** —— Zed 会把 `$…` 当成自己的 task 变量，未知变量会让整条 task 从 `task: spawn` 列表消失。生成脚本（`scripts/zed/init-workspace.sh`）写出的 exec task 就用 `$ZED_RELATIVE_DIR` / `$ZED_STEM` / `$ZED_FILENAME`。

**取消上一次**：`"use_new_terminal": false` + `"allow_concurrent_runs": true`，重跑即取消上一次。

```jsonc
// keymap.json（把按钮变成快捷键）
{
  "context": "Workspace",
  "bindings": {
    "alt-u": ["task::Spawn", { "task_name": "4gl: 上传当前文件" }],
    "alt-d": ["task::Spawn", { "task_name": "4gl: 下载当前文件" }],
    "alt-b": ["task::Spawn", { "task_name": "4gl: 4GL 编译" }],
    "alt-r": ["task::Spawn", { "task_name": "4gl: 链接资料：更新当前文件" }]
  }
}
```

> 📷 待补：keymap 绑定后按快捷键触发 task（docs/images/zed/30-keymap-bound.png）

### 8.5 slash command 总表 [✅ 0.2.0 已落地（`/bdl-force-parse` 为 🔧 计划中·P3）]

入口是 Zed 的 **Agent 面板**（slash command 只在 Agent 面板里可用，**不在命令面板**）。9 条命令的实现见 `src/slash.rs` + `src/project.rs`，声明在 `extension.toml` 的 `[slash_commands.*]`（`tests/verify-manifest.py` 静态校验一一对应）。

| 名称 | 参数 | 做什么 | 阶段 |
|---|---|---|---|
| `/bdl-env-check` | 无 | 显示生效设置摘要（链接/字段 mode、dataDir、Genero 版本、日志级别）、两个二进制的路径与版本（实跑 `version`）、资料文件是否存在，并打印生效配置原文 | ✅ 0.2.0 |
| `/bdl-link-status` | 无 | 读 `.project/link/links.meta.json` + `links.jsonl`，显示链 / orphan / ambiguous / 缺失文件 / 生成时间 / 来源 / 局部更新 / 链内文件数；**没有资料时给的是引导文案，不是报错** | ✅ 0.2.0 |
| `/bdl-link-chain` | 程序代码 | 读 `links.jsonl`，列出该程序所在的链（MAIN / 模组 / 程序号）与链内文件（最多 30 个，超出折叠）；这是 **Code Lens 落地前的替代视图**，并会说明「链接关系 ≠ 调用关系」 | ✅ 0.2.0 |
| `/bdl-schema-status` | 无 | 读 `.project/schema/tables.json`，显示表数 / 列数 / 导入时间 / 来源 / 原始行数 | ✅ 0.2.0 |
| `/bdl-schema-tables` | 过滤子串 | 列表面（**大小写不敏感子串**，支持 `^前缀` / `后缀$` 锚点，**不是完整正则**，与 VSCode 树视图不同）；一次最多列 **200 行** | ✅ 0.2.0 |
| `/bdl-schema-columns` | 表名 | 读 `.project/schema/tables/<大写表名>.json`，列出 名称 / 类型(长度) / NULL / 说明 | ✅ 0.2.0 |
| `/bdl-deploy-list` | 无 | 实跑 `tiptop deploy --list`（自动补 `--workspace <项目根>`），列出部署目标 | ✅ 0.2.0 |
| `/bdl-deploy-dry-run` | 无 | 实跑 `tiptop deploy --dry-run`（自动补 `--workspace <项目根>`），只打印计划 | ✅ 0.2.0 |
| `/bdl-force-parse` | 无 | 强制解析当前文件；**当前只返回**「需要服务端 `workspace/executeCommand`（PLAN Z-P3-2）+ 三条替代办法」，**尚未可用** | 🔧 计划中·P3 |

**capability**：`extension.toml` 已声明 `[[capabilities]]` —— `process:exec` × 7 个参数形状（`link` / `schema` / `upload` / `download` / `exec` / `deploy` / `version`，command 均为 `"*"`）+ `download_file`（`host = "github.com"`、`path = ["darcyjoven", "**"]`，给 P4 自动下载预留）。首次使用会弹授权；若你在 `granted_extension_capabilities` 里收紧了权限，需要放行**同样形状**，否则 slash command 会提示 capability 错误。

**硬规则**：**会写盘的操作（采集 / 导入 / 同步 / 上传 / 下载 / 部署）不进 slash command**，只给 task；slash command 只做**只读查询**与**只打印的预演**——它就在 Agent 面板里，误触一次可能重算整份资料或覆盖生产文件。

> 📷 待补：Agent 面板里执行 `/bdl-schema-status` 与 `/bdl-env-check` 的输出（docs/images/zed/31-slash-commands.png）

---

## 9. Zed 与 VSCode 的差异（诚实说明） [⬇️ 降级替代 / ❌ 平台不支持]

同一个后端（`bdl-lsp` + `tiptop`）、同一套资料格式与命令参数；**差的全是编辑器容器能力**：`zed_extension_api 0.7.0`（兼容 Zed 0.205.x）里没有树视图、状态栏、输出面板、任意命令注册、诊断注入。

| 能力 | VSCode（0.9.2） | Zed（0.2.0） | 说明 |
|---|---|---|---|
| 语法高亮 | ✅ TextMate | ✅ Tree-sitter | 已对齐（47 项 query 校验全绿） |
| 语言智能（诊断/悬停/跳转/引用/补全/重命名/Code Action/格式化） | ✅ | ✅ | 同一个 `bdl-lsp`，行为一致 |
| 语义高亮 | ✅ 默认开 | ✅ 0.2.0 已提供规则（默认 off；着色 ⚠️ 待实机核实） | 开 `"semantic_tokens": "combined"`；规则文件已随 0.2.0 提供 |
| 诊断渲染位置 | Problems 面板 + 内联 | ✅ 宿主直接渲染（内联/诊断列表） | Zed 无独立 Problems 面板，但诊断可用 |
| **配置是否生效** | ✅ | ✅ 0.2.0 已到达服务端 | Z-P0-3 已修；改完**必须重启语言服务器** |
| **轻量档默认** | ✅ 三开关默认 off | ✅ 0.2.0 扩展补 `mode:"off"` | Z-P0-3 已修，与 VSCode 轻量档对齐 |
| 命令面板注册 | ✅ **33 条**命令 | ❌ **无命令注册 API** | ⬇️ task（写盘/长任务）+ slash command（只读） |
| 侧边栏树视图（链接资料 / 数据库字段） | ✅ **2 个 TreeView** | ❌ **无树视图 API** | ⬇️ 链接用 **Code Lens 挂 MAIN**（P3）；字段用 slash 文本（P1） |
| 树的操作（过滤/勾选/批量/复制列定义） | ✅ | ❌ 无 | ⬇️ 过滤=子串 + `^` / `$` 锚点参数；批量=`-tables`/`-tables-file`；复制=抄文本 |
| 反查引用程序 | ✅ 视图 + 分页 | 🔧 函数级口径 | Zed 不做「引用程序 + 分页」视图 |
| 局部查看链接关系 | ✅ Code Lens（VSCode 侧 P1-8） | 🔧 同一份服务端实现 | 两端共用一份 `textDocument/codeLens` |
| 上传/下载 | ✅ 命令 + **右上角按钮** + 右键 | ✅ task | ⬇️ 按钮 → 命令面板 + keymap |
| 编译/链接/预览（生产端） | ✅ 命令 + 按钮组（`.4gl`/`.per` 不同） | ✅ task → `tiptop exec` | 命令与模板一致；**不自动上传** |
| 整包部署 | ⚠️ 只有 CLI 用法 | ✅ CLI 用法 | 两端都不进扩展 |
| 进度条 + 取消 | ✅ 通知式进度 + 取消 | ❌ 无进度 API | ⬇️ task 终端流式输出 + 重跑取消 |
| 输出面板（`4gl` / `4gl 任务`） | ✅ 2 个 OutputChannel | ❌ 无 | ⬇️ task 终端 + **`zed: open log`** |
| 运行日志落盘（`last-run-*.log`） | ✅ | ❌ | ⬇️ 终端可复制；可选 `tee`（P1） |
| **编译错误进 Problems** | ✅ DiagnosticCollection | ❌ **无诊断注入 API** | **永久差异**：只看终端 |
| 状态栏 | ✅ | ❌ 无 API | **永久差异** |
| 编辑器标题栏 / 右键 / 视图工具栏按钮 | ✅ 多处 | ❌ 无 API | **永久差异**；改用命令面板 + task + keymap |
| `when` 门控 / QuickPick / InputBox / 打开文件对话框 / 剪贴板 | ✅ | ❌ 无 API | ⬇️ 脚本自查并在终端提示、task 终端交互提问（`read` / `Read-Host`）、手动复制 |
| 二进制分发 | ✅ 平台 VSIX 内置 | 🔧 运行时自动下载（P4） | `bdl-lsp` 有 Release；`tiptop` 待建 tag/Release |
| 扩展市场发布 | ✅ 市场（VSCode 侧暂缓） | 🔧 未排期（P5） | 当前用 `zed: install dev extension` |

**永久差异清单（不接受"以后会做"）**：① ❌ 侧边栏 / 树视图；② ❌ 状态栏；③ ❌ 独立输出面板（降级为 task 终端 + `zed: open log`）；④ ❌ 编辑器标题栏 / 右键 / 视图工具栏按钮（降级为命令面板 + task + keymap）；⑤ ❌ 把远程编译错误注入 Problems（只看终端）；⑥ ❌ 在 Zed 侧注册任意命令到命令面板（降级为 task + slash command）。

---

## 10. 常见问题 [✅ 当前可用]

### 10.1 语言服务器没启动 / 状态是红的 [✅ 当前可用]

1. 先看日志：命令面板 → **`zed: open log`**（二进制定位失败、`initialize` 失败都写在这里）。
2. 十有八九是**找不到 `bdl-lsp`**，按 §1.3 的四级顺序自查：

```bash
/path/to/bdl-lsp version
which bdl-lsp          # Windows: where bdl-lsp
```

3. 在 `lsp.bdl-lsp.binary.path` 里写**绝对路径**（最稳）。路径以 `~/` 开头会被扩展展开
   （`HOME` / `USERPROFILE`），但绝对路径更可靠。
4. 报错文案里可能出现过时键名 `bdl.server.path`（历史遗留字符串），**实际要设的是 `lsp.bdl-lsp.binary.path`**；Windows 上确认文件名是 `bdl-lsp.exe`。
5. 首次加载扩展时 Zed 要拉取并编译 tree-sitter grammar，**需要网络**；断网会卡在加载阶段。

### 10.2 没有诊断 [✅ 当前可用]

| 检查项 | 说明 |
|---|---|
| 语言服务器在跑吗 | 状态显示"运行中"；否则先看 §10.1 |
| 语言识别对吗 / 设置写对位置了吗 | `.4gl` / `.global` → **Genero BDL**，`.per` → **Genero Form**；全部配置只在 `lsp.bdl-lsp.settings`（或 `initialization_options`） |
| 诊断码被关了吗 | `diagnostics.<码>: "off"`；`record-member-unknown` **默认就是 off** |
| 文件被忽略了吗 | `ignore.files` 命中会屏蔽该文件**所有**诊断 |
| 文件太大 / 解析超时 | 会出现 `file-too-large` / `parse-timeout`，此时**跳过语法检查**（§7.2） |
| 改完设置没重启 | `initialization_options` 只在启动时下发一次，**必须重启语言服务器** |
| 0.2.0 起生效 | `settings` 会合并下发到服务端；若"改了没反应"，多半是**没重启语言服务器**（§1.3 / §10.7） |

### 10.3 函数全报「找不到定义」 [✅ 当前可用]

先确认三件事：

1. **有链接资料吗？** 没有 `.project/link/links.jsonl` 时 `function-not-found` **一律不报**（宁漏勿误）；检查 `tiptop link status -root .`（无资料时退出码 1）。
2. **索引预热完成了吗？** 该诊断需要工作区索引就绪；刚打开大仓库的前几十秒别下结论。
3. **函数真在"可用模组"里吗？** 可见函数 = 本文件 ∪ 引入的 GLOBALS ∪ **链接文件** ∪ 全局模组（`sub` / `lib` / `qry` 扁平规则）；跨模块调用需要链接资料把它串起来。

```bash
tiptop link status -root .                                                            # 1) 有没有资料
tiptop link import -csv DS.GAL_FILE.csv -root .                                        # 2) 没有就导入
tiptop link sync -root . -source golang -host <主机> -service <服务名> -user <账号>     # 3) 或直连全量
```

之后**不用重启编辑器**（`bdl-lsp` 按 mtime 热重载资料，2 秒节流）。另注意：**外部函数过滤**会把被 ≥3 文件或 ≥5 次调用、全语料无定义的名字视为存在并豁免；
**链接只放大函数可见性，不放大变量**——链接的子文件之间的**变量**仍不可见（有意设计）。

### 10.4 链接资料不刷新 / 改完资料没变化 [✅ 当前可用]

- `bdl-lsp` **只读**资料并按 mtime 热重载（2 秒节流），正常情况下导入/同步后**不需要重启**。
- 先确认**写对了目录**：默认 `.project/link/`；若改了 `link.dataDir`，`tiptop -out` 必须与之一致。
- 旧目录 `.link/` 是**只读兼容**：`tiptop` 不往那儿写，但 `bdl-lsp` 会读（并给 `link-data-legacy-dir` 的 hint），所以"资料看着是旧的"很可能是**旧目录里还有一份**。**0.2.0 起有现成的迁移 task**：`4gl: 迁移项目资料目录（旧目录 → .project/）`（生成脚本产出的 `.zed/bdl/migrate-data.sh` / `.ps1`，只搬移、绝不覆盖，空旧目录顺手删除）；也可以手工迁移：

```bash
mkdir -p .project/link
cp -n .link/links.jsonl .project/link/ 2>/dev/null || true
cp -n .link/links.meta.json .project/link/ 2>/dev/null || true
tiptop link status -root .        # 确认在读新目录
```

- 资料 JSONL 坏了会发 `link-data-invalid`（诊断落在**资料文件**上，不污染源码），此时资料被停用，需重新导入。
- **没有"资料过期告警"**：`maxAgeDays` 已删除，这是**设计如此**（见 §10.5）。

### 10.5 切换分支后资料是旧的 / 没有过期提醒 [✅ 当前可用]

- 资料（`.project/link/`、`.project/schema/`）与工作区文件**解耦**：切分支**不会**自动重采，常见现象是切到老分支后诊断指向错误文件或函数找不到。
- **扩展与后端都不会告警**：链接资料**过期告警已明确不做**（`maxAgeDays` 已删除），`schema` 同理——设计决定，不是遗漏。切分支后请跑一次对应范围的更新，或把资料目录当作「每个分支一份」：

```bash
tiptop link sync -root . -source golang -host <主机> -service <服务名> -user <账号> -files $ZED_RELATIVE_FILE
tiptop link status -root .        # 看生成时间与天数、局部更新 partial 记录
```

### 10.6 部署失败 / 上传失败 [✅ 当前可用]

| 现象 | 处理 |
|---|---|
| 报"区没配置" | 配 `ext.prod.deploy.region`（`1`/`2`/`3`/`4`；`4` 表示不 source profile） |
| `Permission denied (publickey)` | **只支持密钥登录**；先 `ssh <user>@<host>` 通一次，配好 `~/.ssh/config` |
| 老服务器 `no matching host key type` | 用初始化脚本 `--legacy-ssh`，或 `~/.ssh/config` 加 `HostKeyAlgorithms +ssh-rsa`、`PubkeyAcceptedAlgorithms +ssh-rsa` |
| 命令不认识 | `tiptop` 太老（0.1.8 缺 `download` / `-region` / `-login-profile`）；重新 `make build` |
| 上传成功但编译说文件不存在 | 生产根/相对路径映射不对；确认 `remoteRoot` 与 `localRoot`，先 `tiptop upload -dry-run` 看计划 |
| 传上去是旧内容 | task 少了 `"save": "current"`，脏文档没保存 |
| 下载把本地改动覆盖了 | 下载是**覆盖写**，`tiptop` 不备份也不询问；**下载前先 `git status` / 提交** |
| `-file` 被拒绝 | `-file` **必须相对路径**（拒绝绝对路径、盘符、`..` 越界） |
| `-command` 里变量没展开 | task 里的 `$ZED_*` 由 **Zed** 展开；`$(...)` 是**远程 shell** 展开，两者别混；最稳是写死目录 |

### 10.7 设置不生效 [✅ 当前可用]

1. **生效路径（0.2.0）**：`lsp.bdl-lsp.settings` 的键会合并进 `initializationOptions` 下发（§1.3），**直接写这里即可**；`initialization_options` 仍是最高优先级逃生口。
2. **改完没重启**：生效配置只在语言服务器启动时下发一次（含合并后的 `settings`），**改完必须重启语言服务器**。热更新要等服务端 `workspace/configuration`（P3 / Z-P3-1）。
3. **写错位置**：扩展只能读 `lsp.<server>` 这一块（`lsp.bdl-lsp.*`），写别的分类读不到。
4. **写错键名**：下发给 LSP 的键**没有 `bdl.` 前缀**；仅扩展自用的键必须在 `ext` 下。
5. **语言名写错**：`languages` 下必须写 `"Genero BDL"` / `"Genero Form"`，写 `"4gl"` 无效。
6. **与项目级配置的心智**：优先级「编辑器下发 > `.bdl-lsp/config.json` > 默认值」，客户端只下发**非零值**；
   想关掉项目里的启用项，要显式写 `mode: "off"`。
7. **task 读不到设置**：task 里的主机/账号/模板只能写死在 `args` 里，或用生成脚本落文件（§2.2）。

### 10.8 中文与空格路径 [✅ 当前可用]

- **工作区根含中文或空格**：`bdl-lsp` 有 UTF-16 ↔ 字节位置换算（`internal/textpos`），LSP 位置不受影响；但**外部进程与 shell 引用**（`tiptop upload` / `exec`）容易出问题——尽量把项目放**纯 ASCII、无空格**路径（如 `~/tiptop-gp`）。
- `tiptop` 对生产根做 shell 转义；模板里再套一层引号容易转义错位；**分隔符恒为 `/`**（`${path}` 展开也是 `/`），Windows 上不要改成 `\`。
- **编码**：拉代码阶段用 `--from-encoding gbk` / `big5`；换行固定 LF（`text eol=lf`），Windows 改完不产生空白符差异。
- 实机验收里有专门一项「路径含空格与中文」，Windows 尤其要过。

### 10.9 Windows 特殊点 [✅ 当前可用]

| 事项 | 说明 |
|---|---|
| 无 `make` | 用 `powershell -File scripts\build.ps1` 构建 `bdl-lsp` / `tiptop` |
| 可执行文件后缀 | `bdl-lsp.exe`、`tiptop.exe`；扩展按平台自动补后缀 |
| 环境变量 | `$env:BDL_ORA_PASSWORD = "..."`；task 继承 Zed 启动时的环境，改完要重启 Zed |
| `secrets.json` 权限 | Windows **跳过 0600 校验**（Unix 上不是 0600 会直接报错退出） |
| 上传方式 | 无 `rsync` → 走 `scp` 回退（可设 `ext.prod.deploy.transport: "scp"`），稳定性/性能未实测 |
| 组策略禁脚本 | 初始化/生成脚本可能被拦：从终端手动执行命令行 |
| 建议环境 | WSL 与 Remote-WSL 场景建议在 WSL 里跑（功能覆盖更多、更快） |
| 路径与中文 | 见 §10.8；Windows 更敏感，优先用无空格纯 ASCII 路径 |

---

## 附 A. 截图与录屏清单 [✅ 当前可用]

素材统一放 `docs/images/zed/`（目录已存在）。本文档所有 📷 / 🎬 占位与下表一一对应；补齐后把占位替换成 `![说明](images/zed/<文件名>)`。**素材不要出现真实主机、账号、密码和客户代码。**

| # | 类型 | 内容 | 建议文件名 | 章节 |
|---|---|---|---|---|
| 1–2 | 📷 | 扩展面板中显示 4gl-full 已加载；首次打开时自动下载二进制的状态提示 | `01-install-extension-panel.png`、`02-auto-download-status.png` | §1.1、§1.2（P4） |
| 3 | 📷 | `bdl-lsp version` 与 `tiptop version` 输出对照 | `03-version-check.png` | §1.2 |
| 4 | 📷 | `.zed/settings.json` 里配置 bdl-lsp 的完整样子 | `04-settings-json.png` | §1.3 |
| 5 | 📷 | 第一次打开 `.4gl`（语言名、高亮、语言服务器运行中） | `05-first-open.png` | §1.4 |
| 6 | 📷 | 初始化脚本的交互提问（选脚本 / SSH 目标 / 生产根 / 编码） | `06-init-project-prompt.png` | §2.1 |
| 7 | 🎬 | 从生产服务器拉取代码的完整过程与进度 | `07-init-project-run.mp4` | §2.1 |
| 8 | 📷 | 生成后的 `.zed/settings.json`、`tasks.json`、`bdl-tool.json` | `08-zed-config-generated.png` | §2.2（✅ 0.2.0） |
| 9 | 📷 | `tiptop link status` 的中文输出 | `09-link-status.png` | §3.1 |
| 10 | 🎬 | `tiptop link sync` 全量采集的进度输出 | `10-link-sync-progress.mp4` | §3.1 |
| 11 | 📷 | Code Lens 挂在 MAIN 上 | `11-code-lens-main.png` | §3.2（P3） |
| 12 | 📷 | 终端清单里 MAIN 与子文件路径清单 | `12-link-tree-terminal.png` | §3.2（P2） |
| 13 | 📷 | `tiptop schema status` 输出 | `13-schema-status.png` | §4.1 |
| 14 | 🎬 | `schema sync -batch-size 200` 的分批进度 | `14-schema-sync-batch.mp4` | §4.1 |
| 15–16 | 📷 | `DEFINE x LIKE t.col` 悬停显示类型与中文说明；`RECORD LIKE t.*` 悬停展开字段 | `15-hover-column.png`、`16-record-like.png` | §4.2 |
| 17 | 📷 | `/bdl-schema-tables` 返回的表清单文本 | `17-slash-schema-tables.png` | §4.3（✅ 0.2.0） |
| 18 | 📷 | task 里「上传当前文件」的执行输出 | `18-upload-task.png` | §5.2 |
| 19 | 📷 | `tiptop exec` 的编译输出 | `19-build-task.png` | §5.3 |
| 20 | 📷 | `tiptop deploy -dry-run` 的计划输出 | `20-deploy-dry-run.png` | §5.4 |
| 21 | 📷 | `zed: open log` 里的语言服务器日志 | `21-open-log.png` | §5.5 / §10.1 |
| 22 | 📷 | `.4gl` 高亮 + Outline + `.per` LAYOUT 不缩进 | `22-highlight-outline.png` | §6.1 |
| 23 | 🎬 | 跳转定义 / 查找引用 / 补全（含 `r.` 列补全） | `23-navigation.mp4` | §6.2 |
| 24 | 📷 | `.4gl` 格式化前后对比 | `24-format.png` | §6.3 |
| 25–26 | 📷 | 语义高亮**开**（`combined`）与**关**（同一段代码）对比 | `25-semantic-on.png`、`26-semantic-off.png` | §6.4 |
| 27 | 📷 | 大纲面板 + 工作区符号搜索结果 | `27-outline-symbols.png` | §6.5 |
| 28 | 📷 | 编辑器里出现诊断（含级别颜色）与诊断列表 | `28-diagnostics.png` | §7.1 |
| 29 | 📷 | 大文件被跳过时的 `file-too-large` 提示 | `29-file-too-large.png` | §7.2 |
| 30 | 📷 | keymap 绑定后按快捷键触发 task | `30-keymap-bound.png` | §8.4 |
| 31 | 📷 | Agent 面板里执行 `/bdl-schema-status` 与 `/bdl-env-check` | `31-slash-commands.png` | §8.5（✅ 0.2.0） |

占位正文格式统一为：`> 📷 待补：<内容>（docs/images/zed/<建议文件名>）`

---

## 附 B. 事实来源 [✅ 当前可用]

本手册的数字、参数名、默认值与结论均来自下列文件的**实际内容**（逐条核对，未凭印象）：

**Zed 侧（本仓库）**

- `zed-extension/extension.toml` —— 扩展 id `4gl-full`、版本 `0.2.0`、grammar `rev`、`[language_servers.bdl-lsp]` 与 language id 映射（`Genero BDL`→`bdl`，`Genero Form`→`per`）、`[slash_commands.*]`（9 条）与 `[[capabilities]]` 声明
- `zed-extension/src/`（`lib.rs` / `config.rs` / `binary.rs` / `project.rs` / `slash.rs`）—— 二进制定位四级顺序与 `~/` 展开（`binary.rs`）、三层配置合并与轻量档默认（`config.rs`）、资料只读渲染与表名过滤语法（`project.rs`）、slash command 分派与 capability 依赖（`slash.rs`）、`initialization_options` / `workspace_configuration` 下发（`lib.rs`）（§1.2 / §1.3 / §4.3 / §8.5 照此写）
- `zed-extension/docs/PLAN.md` —— 基线、Zed 平台能力边界（§4.1–4.4）、差距矩阵与降级方案（§6 / §8）、阶段任务 P0–P5（§7）、实机验收清单（§11.2）、风险（§12）
- `zed-extension/README.md` —— 能力一览、安装、配置示例、task/slash 列表（口径一致性核对）
- `zed-extension/tests/verify-manifest.py`、`tests/verify-queries.mjs` —— §6.1 的清单/query 校验口径
- `zed-extension/scripts/zed/init-workspace.sh` —— 生成的 `.zed` 三件套 + `.project/deploy/deploy.json` + `.zed/bdl/migrate-data.sh`、最多 22 条 task 的 label/args、不覆盖 settings / 备份 tasks / 不写密码等行为（§2.2 / §8.4 照此写）

**`bdl-lsp`（语言服务）**

- `bdl-lsp/docs/DIAGNOSTICS.md` —— **14 个诊断码与默认级别的权威表**（`link-data-legacy-dir` = hint、`record-member-unknown` = off、`file-too-large` = warning）与动态 `missing-<kind>` 规则；§7.1 逐行照抄
- `bdl-lsp/docs/FEATURES.md` —— 能力与边界（A/B/C/D/F/G 节）、§9 CLI、§10 配置键与默认值、产物格式、`function-not-found` 启用条件（F13）、明确不做 N1–N13（含 N12 重命名不跨文件、N13 无过期告警）
- `bdl-lsp/internal/config/config.go` —— 键名与默认值的**源码依据**：`Settings` 的 json tag（无 `bdl.` 前缀）、`link`/`schema` 的 `enable` 与 `mode` 双入口及 `mode` 优先、客户端未下发时 `SchemaEnabled`/`IndexEnabled` 兜底 `true`、`limits` 默认、配置来源优先级

**`tiptop`（采集与部署 CLI）**

- `tiptop/README.md` —— 快速用法、`link`/`schema`/`deploy`/`upload`/`download`/`exec` 实际命令、密码来源与 `chmod 600`、字典表口径、分批参数
- `tiptop/docs/FEATURES.md` —— 子命令与**全部参数名**（§1–§4）、`-json` 的唯一场景（`deploy`）、进度协议（stderr `进度\t阶段\t详情\ti\tn`）、`.project/` 目录约定与旧布局只读兼容、`secrets.json` 格式与优先级、逐表增量写与安全写入
- `tiptop/main.go` —— 退出码口径（`2` 用法错误）与子命令分派
- `tiptop/internal/execcli/execcli.go` —— `-region` / `-login-profile` 参数与帮助文案、`cd ${path}` 语义
- `tiptop/internal/linkcli/linkcli.go`、`internal/schemacli/schemacli.go` —— 无资料时退出码 `1` 等行为

**`vscode-extension`（参照物：只取可核对的措辞与命令契约，不抄其 UI）**

- `vscode-extension/README.md` —— §1 安装、§2 项目初始化（脚本与参数表、`--dry-run`/`-Update`/编码）、§3 链接/字段资料（导出 SQL、密码、同步命令）、§4 上传编译链接（区号与 profile 映射、命令模板与占位符）、§5 能力清单、§6 我的配置
- `vscode-extension/docs/FEATURES.md` —— §8 部署与远程编译、§10 命令行参考（`tiptop` 参数）、§11.1 设置 3 组 50 键、§11.2 项目级配置、§3 编辑体验 B1–B11、§5.1 诊断码
- `vscode-extension/docs/OPEN-ITEMS.md` —— Zed 相关待确认项（E-01…E-08）、真实环境未验证项（P-01…P-15）、设置重构小决策（S-a…S-f，含「`2 p` 不是笔误」）
- `vscode-extension/scripts/init-project/init-project.sh`、`init-project.ps1` —— 初始化脚本与参数名（§2.1 照其用法写）

> **口径规则**：命令数、设置键数、诊断码、参数名一律以**源码 / 实跑输出**为准。
> VSCode 侧文档自身存在失真（版本头 0.6.2、命令数 31/49、写了从未发送的 `bdl/linkReferences`），
> 本手册只引用能核对的数字。