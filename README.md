# Genero BDL for Zed（`4gl-full`）

Genero BDL（`.4gl` / `.global`）与 Form（`.per`）的 Zed 扩展：Tree-sitter 语法高亮、
outline、括号匹配、缩进、SQL 注入，以及通过 [`bdl-lsp`](https://github.com/darcyjoven/bdl-lsp)
提供的诊断 / 悬停 / 跳转 / 引用 / 补全 / 重命名 / Code Action / 格式化 / 语义高亮；
资料采集、字段资料、上传、下载、编译、链接、预览由 [`tiptop`](https://github.com/darcyjoven/tiptop)
在 task 终端里完成。

> - 扩展 id 为 **`4gl-full`**，与轻量扩展 [`bdl`](https://github.com/darcyjoven/bdl-plugin)（只有 grammar）**可以同时安装**。
> - 完整操作手册：[docs/USER-GUIDE.md](docs/USER-GUIDE.md)。
> - 追平计划与待办（唯一来源）：[docs/PLAN.md](docs/PLAN.md)。
> - 本仓库只放 Zed 交付物；构建缓存、日志、语料等过程产物在本地 `bdl-lsp/artifacts/`。
> - v1 验证平台：**Linux + Windows**（macOS 后续补齐）。

**版本**：扩展 `0.1.1` → 目标 `0.2.0`（追平中，阶段见 [PLAN §7](docs/PLAN.md)）。
后端：`bdl-lsp` **v0.3.15**（四平台 Release；含 executeCommand / Code Lens / workspaceSymbolProvider）· `tiptop` **v0.1.10**（四平台 Release）。

---

## 1. 能力一览

| 能力 | 触发方式 | 状态 |
|---|---|---|
| 语法高亮 | 打开 `.4gl` / `.global` / `.per` | ✅ 300 / 76 个关键字全部覆盖 |
| Outline | 大纲面板 | ✅ 函数 / REPORT / MAIN / TYPE / item / SCREEN RECORD … |
| 括号匹配、缩进 | 编辑时 | ✅ `.per` 的 LAYOUT **绝不缩进** |
| SQL 注入 | `.4gl` 里 `SELECT`/`INSERT`/`UPDATE`/`DELETE` | ✅ 按 SQL 高亮 |
| 诊断 | 编辑时（Problems） | ✅ 14 个静态码 + 动态 `missing-<kind>` |
| 悬停 / 跳转 / 引用 / 补全 / 重命名 / Code Action / 格式化 | Zed 原生命令 | ✅ 由 `bdl-lsp` 提供；重命名只改当前文件，`.per` 不格式化 |
| 语义高亮 | `"semantic_tokens": "combined"` | ✅ `0.2.0`：扩展自带 `semantic_token_rules.json`（8 条规则，带主题回退） |
| 设置生效与轻量档默认 | 自动 | ✅ `0.2.0`：有效配置从 `initializationOptions` 下发，且缺省补 `link/schema mode=off` |
| 链接资料采集 / 导入 / 更新 | task → `tiptop link …` | ✅ 可用 |
| 链接关系查看 | `/bdl-link-chain <代码>`（文本）/ Code Lens 挂在 **MAIN 函数头** | ✅ 文本版可查；✅ Code Lens **服务端已实现**（`bdl-lsp`，开 `"code_lens": "on"` 后可见；**点击行为待 Zed 实机确认**） |
| 字段资料采集 / 同步 | task → `tiptop schema …` | ✅ 可用 |
| 表 / 列清单（无侧边栏树） | slash command 文本列表 | ✅ `0.2.0`：`/bdl-schema-tables`、`/bdl-schema-columns` |
| 上传 / 下载 / 预演上传（单文件） | task → `tiptop upload` / `download` | ✅ 可用 |
| 编译 / 链接 / 预览（生产端执行） | task → `tiptop exec` | ✅ 可用 |
| 整包部署 | task → `tiptop deploy -dry-run / -list` | ✅ 可用（CLI） |
| 只读查询（资料状态、链接关系、部署目标、环境自检） | slash command | ✅ `0.2.0`：9 条 `/bdl-…`（见 §4.2） |
| 工程初始化（生成 `.zed/{settings,tasks,bdl-tool}.json`） | task → `scripts/zed/init-workspace.{sh,ps1}` | ✅ `0.2.0`（交互式提问，不写密码） |
| 二进制自动下载 | 首次打开时 | ✅ `0.2.0`：`bdl-lsp` 与 `tiptop` 都有四平台 Release，本地找不到时按平台自动下载 |
| 编辑器标题栏按钮 / 状态栏 / 侧边栏树 / 输出面板 / Problems 注入 | — | ❌ Zed 无对应 API（永久差异，见 §6） |

---

## 2. 安装

### 2.1 安装扩展

```text
Zed 命令面板 → zed: install dev extension → 选择本仓库目录
```

（扩展注册表发布未排期。）

### 2.2 准备两个二进制

`bdl-lsp`（语言服务器）与 `tiptop`（资料/部署 CLI）二选一：

**① 自动下载【`0.2.0` 起可用：`bdl-lsp` 与 `tiptop` 都是】** —— 四级本地查找全部落空时，扩展按平台从 GitHub Release
下载、解包到扩展目录、设置可执行位，并清掉同前缀的旧版本目录：

| 平台 | 资产 |
|---|---|
| Linux x64 | `bdl-lsp-linux-amd64.tar.gz` |
| macOS Intel / Apple Silicon | `bdl-lsp-darwin-amd64.tar.gz` / `bdl-lsp-darwin-arm64.tar.gz` |
| Windows x64 | `bdl-lsp-windows-amd64.zip` |

- **本地已有二进制时不会下载**（用户装的优先；下载只作第 5 级兜底）。
- 下载过一次后按版本分目录缓存：**常态启动直接复用缓存，不会去查 GitHub**（离线也能用）。
- 状态显示在 Zed 的语言服务器状态里（检查更新 / 下载中 / 失败原因 + 可操作提示）。
- 关闭：`lsp.bdl-lsp.settings.ext.download.bdlLsp = "off"`（键缺省即 `auto`）。
- `tiptop` 的资产命名一致（`tiptop-linux-amd64.tar.gz` / `tiptop-darwin-arm64.tar.gz` / `tiptop-windows-amd64.zip`，附 `SHA256SUMS`；v0.1.10 起）。
- 首次使用会用到 `download_file` capability；若你收紧了 `granted_extension_capabilities`，
  需要放行 `host = "github.com"`、`path = ["darcyjoven", "**"]`。

**② 手工构建（当前可行）**

```bash
# Linux / macOS
cd bdl-lsp && make build            # 产物 artifacts/bin/bdl-lsp
cd tiptop && make build             # 产物 artifacts/bin/tiptop
```

```powershell
# Windows（无 make）
cd bdl-lsp; powershell -File scripts\build.ps1
cd tiptop;  powershell -File scripts\build.ps1
```

**③ 指定已有二进制**（见 §3 的 `binary.path`），或把二进制放进 `PATH`、
或放在工作区的 `.bdl-lsp/bin/` 下。

> 二进制查找顺序（`bdl-lsp` 与 `tiptop` 同一套语义）：
> Zed 设置路径 → 环境变量 `BDL_LSP_PATH` / `TIPTOP_PATH` → 工作区 `.bdl-lsp/bin/` → `PATH`。

---

## 3. 配置（`.zed/settings.json`）

**只需写一处** `lsp.bdl-lsp.settings`：与 `bdl-lsp` 同名的键会下发给语言服务器，
仅本扩展使用的键收在 `ext` 下。

```jsonc
{
  "lsp": {
    "bdl-lsp": {
      "binary": { "path": "", "arguments": [], "env": {} },
      "settings": {
        // —— 下发给 bdl-lsp（无 bdl. 前缀）——
        "generoVersion": "2.50",
        "logLevel": "info",
        "link": { "mode": "off", "dataDir": ".project/link", "moduleRoots": [], "globalModules": ["sub", "lib", "qry"] },
        "schema": { "mode": "off", "dataDir": ".project/schema" },
        "diagnostics": { "record-member-unknown": "warning" },
        "format": { "keywords": "unchanged", "indentStyle": "auto", "indentSize": 0 },
        "ignore": { "files": [], "fields": [], "forms": [] },
        "perRoots": [],
        "limits": { "maxFileBytes": 2097152, "maxFileLines": 20000, "maxIssues": 200, "parseTimeoutMs": 2000 },

        // —— 仅 Zed 扩展使用（不下发给 LSP）——
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
            "per": { "preview": "cd ${path} && fglform -M -W all ${fullname} && rm ${name}.42f", "form": "cd ${path} && r.gf ${name} 2 p" }
          },
          "download": { "bdlLsp": "auto" }
        }
      }
    }
  },
  "languages": {
    "Genero BDL": { "semantic_tokens": "combined" },
    "Genero Form": { "semantic_tokens": "combined" }
  }
}
```

要点：

- `link.mode` / `schema.mode` 三态 `off | file | db`，**默认 `off`（轻量档：不连库、不写工作区）**；导入 CSV 后设 `file`，直连 Oracle 设 `db`。
- `diagnostics` 是逐诊断码调级的**唯一入口**（`off | error | warning | information | hint`）。
- `ext.build.*` 里的占位符与 VSCode 一致，分隔符恒为 `/`：`${path}`（两层，如 `axc/4gl`）、`${fullpath}`（三层）、`${name}`（去扩展名）、`${fullname}`（含扩展名）。
  ✅ **改完重跑一次生成脚本就生效**：`scripts/zed/init-workspace.*` 会回读
  `lsp.bdl-lsp.settings.ext.build.<lang>.<mode>`，把占位符映射成 Zed 变量
  （`${path}`/`${fullpath}` → `$ZED_RELATIVE_DIR`、`${name}` → `$ZED_STEM`、`${fullname}` → `$ZED_FILENAME`）
  写进 `.zed/tasks.json`；没配的条目保持内置默认。也可以直接改 task 里的 `-command`。
- ✅ **上传/下载/部署需要的 `.project/deploy/deploy.json` 由生成脚本产出**（问答里填了生产主机 + 生产根、
  上传方式不是 `off` 时；已存在则写 `deploy.json.bdl-new` 不覆盖）。不用脚本时可手写
  （样例见 [USER-GUIDE §5.4](docs/USER-GUIDE.md)）；`settings.ext.prod.deploy.*` 本身只是记录（PLAN Z-P2-4）。
- 完整键表与示例见 [USER-GUIDE §8](docs/USER-GUIDE.md)。

> ℹ️ **`0.2.0` 起配置已生效**：Zed 的 `lsp.<server>.settings` 只在服务端请求
> `workspace/configuration` 时下发，而 `bdl-lsp` 不发这个请求，所以扩展把
> `lsp.bdl-lsp.initialization_options` ⊕ `settings`（去掉仅扩展自用的 `ext`）
> ⊕ 轻量档默认（`link/schema mode=off`）合并后从 `initializationOptions` 下发。
> **改设置通常不用重启**：Zed 会在启动时**和设置变化时**给服务端发 `workspace/didChangeConfiguration`（payload 就是这块设置），`bdl-lsp` 会热应用并重算诊断。只有换二进制路径/参数才需要重启。
> （此前文档写「必须重启」是错的，2026-10-29 查 Zed 源码后更正，见 PLAN §4.4。）

---

## 4. 命令入口：task 与 slash command

Zed 扩展**无法注册命令到命令面板**，所以：

- **写盘 / 长任务 / 需要交互输入**的操作用 **task**（终端流式输出、可取消）；
- **只读查询**用 **slash command**（Agent 面板）。

### 4.1 task 示例（`.zed/tasks.json`）

```jsonc
[
  {
    "label": "4gl: 链接资料：查看状态",
    "command": "tiptop",
    "args": ["link", "status", "-root", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 链接资料：更新当前文件",
    "command": "tiptop",
    "args": ["link", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang",
             "-host", "10.0.0.10", "-port", "1521", "-service", "PROD", "-user", "APP",
             "-files", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT"
  },
  {
    "label": "4gl: 上传当前文件",
    "command": "tiptop",
    "args": ["upload", "-workspace", "$ZED_WORKTREE_ROOT", "-file", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "save": "current"
  },
  {
    "label": "4gl: 4GL 编译",
    "command": "tiptop",
    "args": ["exec", "-command", "cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM", "-region", "1",
             "-login-profile", "/u1/usr/profile/profile.topprod"],
    "cwd": "$ZED_WORKTREE_ROOT"
  }
]
```

- **不想手写这些 task？** 用仓库里的交互式脚本一次生成（它会提问主机/账号/区/模板，
  然后把值内联进 `.zed/tasks.json`）：

```bash
# 把脚本放进项目里（或直接指向本仓库路径）
mkdir -p .zed/bdl && cp -r <zed-bdl 仓库>/scripts/zed/* .zed/bdl/
bash .zed/bdl/init-workspace.sh          # Windows: pwsh -File .zed\bdl\init-workspace.ps1
```

  然后在 Zed 里 `task: spawn` → `4gl: 初始化 Zed 工程（生成 .zed 配置）` 也行。
  **脚本绝不写密码**：密码放 `<项目根>/.project/secrets.json`（Unix `chmod 600`）
  或环境变量 `BDL_ORA_PASSWORD`。
- 可用变量：`$ZED_FILE`、`$ZED_RELATIVE_FILE`、`$ZED_RELATIVE_DIR`、`$ZED_STEM`、
  `$ZED_WORKTREE_ROOT`、`$ZED_LANGUAGE`、`${VAR:默认值}`。
- ⚠️ **不要把 tiptop/VSCode 的模板占位符 `${path}`/`${name}`/`${fullname}` 写进 task**：
  Zed 会把 `$…`/`${…}` 当成**自己的** task 变量，未知变量会让整条 task 从 `task: spawn`
  列表里消失、或被替换成空串。Zed 里请用 `$ZED_RELATIVE_DIR`（= `${path}`/`${fullpath}`）、
  `$ZED_STEM`（= `${name}`）、`$ZED_FILENAME`（= `${fullname}`）。
- 取消：task 设 `"use_new_terminal": false` + `"allow_concurrent_runs": true`，重跑即可取消上一次。
- 快捷键绑定（`keymap.json`）：

```jsonc
{ "context": "Workspace", "bindings": { "alt-u": ["task::Spawn", { "task_name": "4gl: 上传当前文件" }] } }
```

> 完整 task 总表见 [USER-GUIDE §8.4](docs/USER-GUIDE.md)。

### 4.2 slash command（`0.2.0` 起可用）

| 命令 | 参数 | 说明 |
|---|---|---|
| `/bdl-env-check` | — | 生效设置摘要、`bdl-lsp`/`tiptop` 版本与路径、资料状态；版本低于最低要求时提醒升级。**只看本地、不会触发下载** |
| `/bdl-link-status` | — | 链数 / orphan / ambiguous / 缺失文件 / 生成时间 / 局部更新 |
| `/bdl-link-chain` | 程序代码 | 查该程序属于哪条链、链内有哪些文件（`模组/代码` 或带 `.4gl` 后缀都能写） |
| `/bdl-schema-status` | — | 表数 / 列数 / 导入时间 / 来源 |
| `/bdl-schema-tables` | 过滤（可空） | 表清单（大小写不敏感子串，支持 `^前缀` / `后缀$`） |
| `/bdl-schema-columns` | 表名 | 列清单（名称 / 说明 / 类型 / 长度 / NULL） |
| `/bdl-deploy-list` | — | `tiptop deploy -list` |
| `/bdl-deploy-dry-run` | — | `tiptop deploy -dry-run`（只打印） |
| `/bdl-force-parse` | — | 强制解析当前文件（需服务端 `executeCommand`，PLAN Z-P3-2） |

**会写盘的操作不进 slash command**，只给 task；slash command 只读 `.project/` 资料
和跑 `tiptop` 的只读/预演子命令。过滤语法与 VSCode 树视图的完整正则略有差异（见上表）。

---

## 5. 资料与部署速查

```bash
# 链接资料（tiptop 写，bdl-lsp 只读）
tiptop link import -csv DS.GAL_FILE.csv -root .
tiptop link sync  -root . -source golang -host <主机> -service <服务名> -user <账号>
tiptop link status -root .

# 字段资料
tiptop schema import -csv schema.csv -root .
tiptop schema sync  -root . -source golang -host <主机> -service <服务名> -user <账号> \
                    -batch-size 200 -timeout 120
tiptop schema status -root .

# 上传 / 下载 / 生产端执行
tiptop upload   -workspace . -file aap/4gl/x.4gl
tiptop download -workspace . -file aap/4gl/x.4gl
tiptop exec     -command "cd axc/4gl && c2 x" -region 1

# 整包部署（只打印计划 / 列出目标）
tiptop deploy -dry-run
tiptop deploy -list
```

- 资料目录：`<项目根>/.project/{link,schema,deploy}/`（旧 `.link/`、`.bdl-lsp/` 只读兼容）。
- 数据库密码：环境变量 `BDL_ORA_PASSWORD`，或 `<项目根>/.project/secrets.json`
  （`{"<用户名>":"<密码>"}`，Unix 必须 `chmod 600`）。
- 进度：`tiptop` 把进度写 **stderr**（`进度\t阶段\t详情\ti\tn`），在 task 终端里直接可见。

---

## 6. Zed 与 VSCode 的差异（诚实说明）

| 能力 | VSCode | Zed | 说明 |
|---|---|---|---|
| 语言智能 | ✅ | ✅ | 同一个 `bdl-lsp`，行为一致 |
| 命令面板 | ✅ 33 条 | ⬇️ task + slash command | Zed 无命令注册 API |
| 链接资料视图 | ✅ 侧边栏三级树 | ⬇️ Code Lens 挂 MAIN 函数头 | Zed 无树视图 API；每子文件一条、上限 10 + 纯文本汇总；服务端已实现，点击行为待实机确认 |
| 字段资料视图 | ✅ 树 + 过滤 + 勾选 | ⬇️ slash 文本列表 | 过滤靠正则参数；批量同步用 task |
| 进度条 / 取消 | ✅ 通知栏 | ⬇️ task 终端 + 重跑取消 | — |
| 输出面板 | ✅ `4gl` / `4gl 任务` | ⬇️ task 终端 + `zed: open log` | — |
| 编译错误进 Problems | ✅ | ❌ 永久差异 | 只看终端输出 |
| 编辑器标题栏 / 右键按钮、状态栏 | ✅ | ❌ 永久差异 | 改用命令面板 + task + keymap |
| 二进制分发 | ✅ VSIX 内置 | 🔧 运行时自动下载（计划中） | `bdl-lsp` 已有 Release，`tiptop` 待建 |
| 反查引用 | ✅ 视图分页 | ⬇️ 函数级口径 | 数据来自 LSP 链接资料索引 |

---

## 7. 诊断

14 个静态诊断码（`syntax-error`、`missing-node`、`file-too-large`、`parse-timeout`、
`globals-file-not-found`、`variable-source-unresolved`、`field-not-in-form`、
`form-duplicate-item`、`form-layout-tag-undefined`、`form-screen-record-undefined`、
`function-not-found`、`link-data-invalid`、`link-data-legacy-dir`(hint)）、
`record-member-unknown`(默认 off)，以及动态 `missing-<kind>`。

权威表：`bdl-lsp/docs/DIAGNOSTICS.md`；Zed 侧调级示例与忽略列表见
[USER-GUIDE §7](docs/USER-GUIDE.md)。

---

## 8. 开发与自检

```bash
cd zed-extension
python3 tests/verify-manifest.py        # 清单 17 项（id/版本/grammar rev/语言映射/语义规则/slash 声明）
export PATH="/code/workspace/tree-sitter-per/node_modules/.bin:$PATH"
export HOME=/code/workspace/bdl-lsp/artifacts/home
node tests/verify-queries.mjs           # query 47 项（节点名 / 关键字覆盖 / 真实语料编译）
cargo test                              # 单元测试（配置合并 / ext 剥离 / 轻量档默认 / 资料解析）
python3 tests/verify-init-script.py     # 初始化脚本产物 15 项（task 齐全 / 字段白名单 / 无 ${…} / deploy.json / 迁移 helper / ext.build 覆盖）
python3 tests/verify-docs.py            # 文档契约 9 项（版本三处一致 / 命令与护栏数字对拍 / 无过期引用）
cargo build --release --target wasm32-wasip2
```

CI（`.github/workflows/build.yml`）：wasm 构建 + 魔数校验 + 清单校验 + grammar rev 存在性 + query 校验。

---

## 9. 文档

| 文档 | 内容 |
|---|---|
| [docs/PLAN.md](docs/PLAN.md) | **Zed 侧唯一计划与待办**：基线、平台能力边界、差距矩阵、阶段任务、验收清单、风险 |
| [docs/USER-GUIDE.md](docs/USER-GUIDE.md) | 完整操作手册：安装、初始化、链接/字段资料、上传编译链接、设置总表、排错 |
| [bdl-lsp/docs/FEATURES.md](https://github.com/darcyjoven/bdl-lsp/blob/main/docs/FEATURES.md) | 语言服务能力 |
| [tiptop/docs](https://github.com/darcyjoven/tiptop) | 采集与部署 CLI |
| [vscode-bdl/docs/TODO.md](https://github.com/darcyjoven/vscode-extension/blob/main/docs/TODO.md) | VSCode 侧待办（跨端目标） |

## 许可证

见 [LICENSE](LICENSE)。