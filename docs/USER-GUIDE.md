# Genero BDL for Zed 使用手册

> 适用扩展 `0.1.1`，语言服务器 `bdl-lsp 0.3.0`。  
> Zed 与 VSCode 共用同一个语言服务器和项目配置（`.bdl-lsp/config.json`），
> 差别主要在安装方式、设置写法，以及 Zed 没有“链接资料视图”。

## 目录

1. [安装与配置](#1-安装与配置)
2. [功能总览](#2-功能总览)
3. [编辑与导航](#3-编辑与导航)
4. [诊断与检查](#4-诊断与检查)
5. [表单、GLOBALS 与数据库结构](#5-表单globals-与数据库结构)
6. [链接资料](#6-链接资料)
7. [部署](#7-部署)
8. [设置参考](#8-设置参考)
9. [常见问题](#9-常见问题)

---

## 1. 安装与配置

### 1.1 准备 `bdl-lsp`

扩展不下载二进制。先构建或获取 `bdl-lsp`：

```bash
# Linux / macOS
cd bdl-lsp
source scripts/dev-env.sh   # 仅在受限环境需要
make build
# 产物：artifacts/bin/bdl-lsp
```

Windows 用 `scripts\build.ps1`，产物是 `artifacts\bin\bdl-lsp.exe`。

Zed 查找二进制的顺序：

1. `lsp.bdl-lsp.binary.path`（推荐，最可控）；
2. 环境变量 `BDL_LSP_PATH`；
3. 工作区 `.bdl-lsp/bin/bdl-lsp`；
4. `PATH`。

### 1.2 安装扩展

本地开发安装需要 Rust 的 WASM target：

```bash
rustup target add wasm32-wasip2
```

然后在 Zed 命令面板执行：

```text
zed: install dev extension
```

选择本仓库目录（含 `extension.toml` 的那一层）。发布版可直接在扩展市场
搜索 `4gl-full`，不需要 Rust。

> 📷 **截图位**：`images/zed/01-install.png`  
> 建议内容：`zed: install dev extension` 选中本目录的界面。

### 1.3 配置语言服务器

编辑 `~/.config/zed/settings.json`（Windows 为 Zed 设置文件）：

```json
{
  "lsp": {
    "bdl-lsp": {
      "binary": {
        "path": "/home/you/bdl-lsp/artifacts/bin/bdl-lsp",
        "args": ["--log-level", "info"]
      },
      "settings": {
        "generoVersion": "2.50",
        "diagnostics": {
          "record-member-unknown": "off"
        },
        "format": {
          "keywords": "unchanged",
          "indentStyle": "auto",
          "indentSize": 0
        }
      }
    }
  }
}
```

注意：`settings` 里的字段**不带 `bdl.` 前缀**；它们与 VSCode 配置的
`bdl.*` 是同一组键，只是外层包装不同。

> 📷 **截图位**：`images/zed/02-settings.png`  
> 建议内容：`settings.json` 里 `lsp.bdl-lsp` 的配置段。

### 1.4 第一次打开项目

用 Zed 打开**项目根目录**（含 `.4gl` / `.per` / `.bdl-lsp/` 的那一层），
打开一个 `.4gl`，确认状态栏语言为 **Genero BDL**，语言服务器已启动。

排查：

- `zed: open log` 看 LSP 启动错误；
- 终端运行 `zed --foreground` 看更详细日志；
- 确认 `bdl-lsp` 能执行：`/path/to/bdl-lsp version`。

---

## 2. 功能总览

| 能力 | 触发方式 | 说明 |
|---|---|---|
| 语法高亮 | 打开文件 | Tree-sitter grammar 静态高亮 |
| Outline | 自动 | 函数、MAIN、标签、常量、TYPE、表单 item 等 |
| 括号匹配/缩进 | 自动 | BDL 按块结构；`.per` 的 LAYOUT 不自动改 |
| SQL 高亮 | 自动 | `.4gl` 的 SELECT/INSERT/UPDATE/DELETE |
| 诊断 | 打开、编辑、保存 | 语法、变量、字段、函数等 |
| 悬停 | 鼠标停留 | 来源与定义位置 |
| 跳转定义 | `F12` / `Cmd+Click` | 当前文件、GLOBALS、链接资料 |
| 查找引用 | `Shift+F12` | 可解析的引用 |
| 补全 | 输入时 | 关键字、变量、函数、表名等 |
| 重命名 | `F2` | **只改当前文件** |
| Code Action | `Cmd+.` | 目前只有字段名修复 |
| 格式化 | `Cmd+Shift+I` | 只支持 `.4gl` / `.global` |
| 部署 | `task: spawn` | 调 CLI，上传 + 远程编译 |

Zed 没有 VSCode 的“链接资料”TreeView，也**不使用**语义 token；高亮以
Tree-sitter 的 `highlights.scm` 为准。链接关系用 `bdl-lsp link status`
或反查命令查看。

> 扩展不做类型检查、赋值兼容性检查，也不做跨文件重命名。

---

## 3. 编辑与导航

### 3.1 悬停与跳转

鼠标悬停变量、函数、GLOBALS 符号或表单字段，会显示来源；`F12` 或
`Cmd+Click` 跳转定义；`Shift+F12` 查引用。

> 🎬 **录屏位**：`images/zed/03-hover.gif`  
> 建议内容：悬停一个 GLOBALS 变量显示来源，再跳转。

### 3.2 补全

在语句位置输入关键字、变量或函数名前缀。补全结合当前文件、GLOBALS、
内置符号表；生成链接资料后可补全跨模组函数。

> 🎬 **录屏位**：`images/zed/04-completion.gif`  
> 建议内容：输入 `DIS` 出现 `DISPLAY`，再输入函数名前缀。

### 3.3 重命名与 Code Action

- `F2` 只重命名当前文件内符号；
- `Cmd+.` 打开 Code Action，目前只有“字段不在表单里”的修复建议。

### 3.4 格式化

`Cmd+Shift+I` 或命令面板的格式化。只处理 `.4gl` / `.global`：

```json
{
  "format": {
    "keywords": "unchanged",
    "indentStyle": "auto",
    "indentSize": 0
  }
}
```

- `keywords`：`unchanged` / `upper` / `lower`；
- `indentStyle`：`auto` / `tab` / `space`；
- `indentSize`：0 表示跟随编辑器的 `tab_size`。

`.per` 不做格式化，避免破坏表单布局的空白语义。

> 🎬 **录屏位**：`images/zed/05-format.gif`  
> 建议内容：格式化一段 4GL，展示关键字和缩进变化。

---

## 4. 诊断与检查

### 4.1 检查项与默认级别

| 检查 | 诊断码 | 默认 | 依赖 |
|---|---|---|---|
| 语法错误 | `syntax-error` | warning | 无 |
| 缺少节点 | `missing-<kind>` / `missing-node` | warning | 无 |
| GLOBALS 找不到 | `globals-file-not-found` | warning | 无 |
| 变量无来源 | `variable-source-unresolved` | warning | 无 |
| 字段不在表单 | `field-not-in-form` | warning | 唯一解析到 `.per` |
| 表单重复 item | `form-duplicate-item` | warning | `.per` |
| 布局 tag 未定义 | `form-layout-tag-undefined` | warning | `.per` |
| SCREEN RECORD 未定义 | `form-screen-record-undefined` | warning | `.per` |
| 记录成员未知 | `record-member-unknown` | **off** | RECORD/schema |
| 函数找不到 | `function-not-found` | warning | **链接资料** |
| 链接资料格式错误 | `link-data-invalid` | warning | 链接资料 |
| 链接资料过期 | `link-data-stale` | hint | 链接资料 |
| 文件过大 | `file-too-large` | information | 无 |

要点与 VSCode 相同：

- 变量检查只查来源，不查类型；
- 没有链接资料时 `function-not-found` 整项不启用；
- 字段检查只在表单唯一解析成功时报告；
- 记录成员默认关闭，`LIKE table.*` 需要 schema。

> 📷 **截图位**：`images/zed/03-diagnostics.png`  
> 建议内容：打开一个含未定义变量的 `.4gl`，显示诊断面板与码。

### 4.2 调整级别

唯一入口是 `diagnostics`，键为诊断码：

```json
{
  "lsp": {
    "bdl-lsp": {
      "settings": {
        "diagnostics": {
          "syntax-error": "error",
          "variable-source-unresolved": "warning",
          "record-member-unknown": "off"
        }
      }
    }
  }
}
```

旧专用键（`missingDiagnostics`、`fieldDiagnostics`、
`globals.fileNotFoundDiagnostics` 等）已删除；升级时把值迁到
`diagnostics` 对应码。

### 4.3 忽略文件/字段/表单

```json
{
  "ignore": {
    "files": ["build/**"],
    "fields": ["tmp_*"],
    "forms": ["legacy/**"]
  }
}
```

- `ignore.files`：整份文件不报诊断，并排除出工作区索引；
- `ignore.fields`：只关 `field-not-in-form`；
- `ignore.forms`：关该表单的字段类诊断。

改完 `ignore.files` 后建议执行 `editor: restart language server`，
让索引按新的排除规则重建。

### 4.4 报告上限

`limits.maxIssues` 默认 200；超出的诊断会被截断，避免 UI 卡顿。

---

## 5. 表单、GLOBALS 与数据库结构

### 5.1 表单 `.per`

单文件检查：

- `ATTRIBUTES` 重复 item；
- `LAYOUT` 引用未定义 tag；
- `SCREEN RECORD` 引用未定义 item。

`.4gl` 里的字段检查需要能解析到 `.per`；表单不在同级 `per/` 时：

```json
{ "perRoots": ["forms", "legacy/forms"] }
```

### 5.2 GLOBALS

默认相对当前文件解析；跨层级仓库用：

```json
{ "globals": { "searchPaths": ["config", "tiptop/config"] } }
```

GLOBALS 文件找不到默认 warning；确认是历史遗留可用
`diagnostics.globals-file-not-found = "off"` 或加入 `ignore.files`。

### 5.3 Schema

`RECORD LIKE table.*` 需要 schema 才能展开：

```json
{
  "schema": {
    "enable": true,
    "paths": ["schema/*.sch"]
  }
}
```

没有 schema 时不要强行打开 `record-member-unknown`，否则会大量误报。

---

## 6. 链接资料

链接资料提供跨模块程序/函数索引，保存在 `.link/`。没有它时：

- `function-not-found` 不启用；
- 跨模块补全/跳转/引用不完整；
- `bdl-lsp link status` 无数据。

### 6.1 生成资料

```bash
# 已有 DS.GAL_FILE 导出 CSV
bdl-lsp link import -csv /path/to/gal_file.csv -root .

# 从文件采集
bdl-lsp link sync -root . -source file -file /path/to/gal_file.csv

# 从命令采集（输出 CSV）
bdl-lsp link sync -root . -source command -command 'your-export-command'

# 直连 Oracle
BDL_ORA_PASSWORD=... bdl-lsp link sync -root . -source golang \
  -host db.example.com -service MYDB -user apps
```

首次导入会扫描源码定位 MAIN，几千个文件通常几十秒；终端会显示
`扫描源码 X/Y`。

检查：

```bash
bdl-lsp link status -root .
```

> 📷 **截图位**：`images/zed/08-link-status.png`  
> 建议内容：终端里 `bdl-lsp link status` 的统计输出。

### 6.2 在 Zed 里查看

Zed 没有链接资料视图。可用：

- `bdl-lsp link status -root .` 看数量、过期时间、模组；
- 在代码里用 `Shift+F12` 查当前符号的引用；
- 需要可视化关系时用 VSCode 版，或在终端用 `cmd/link-audit`。

### 6.3 链接配置

```json
{
  "link": {
    "enable": true,
    "dataDir": ".link",
    "moduleRoots": ["src"],
    "globalModules": ["sub", "lib", "qry"],
    "maxAgeDays": 7
  }
}
```

自动同步默认关闭，需要时：

```json
{
  "link": {
    "sync": {
      "enable": true,
      "source": "golang",
      "onStart": true,
      "interval": 0
    }
  }
}
```

密码不放在设置里：`BDL_ORA_PASSWORD` 或 `.link/secrets.json`（0600）。

---

## 7. 部署

Zed 扩展 API 不能直接执行任意命令，部署通过 **Zed task** 调用
`bdl-lsp deploy`。配置与 VSCode 共用 `.bdl-lsp/deploy.json`。

### 7.1 配置 `.bdl-lsp/deploy.json`

```json
{
  "targets": {
    "test": {
      "host": "dev.example.com",
      "user": "genero",
      "remoteRoot": "/u1/app",
      "upload": { "include": ["**/*.4gl", "**/*.per"] },
      "compile": {
        "4gl": "fglcomp -M {file}",
        "per": "fglform {file}"
      }
    }
  },
  "defaultTarget": "test"
}
```

使用 SSH key / agent；不支持在设置里存密码。

### 7.2 添加 `.zed/tasks.json`

```json
[
  {
    "label": "BDL: 部署预演",
    "command": "bdl-lsp deploy -workspace \"$ZED_WORKTREE_ROOT\" -dry-run",
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "always"
  },
  {
    "label": "BDL: 部署当前文件",
    "command": "bdl-lsp deploy -workspace \"$ZED_WORKTREE_ROOT\" \"$ZED_FILE\"",
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "always"
  },
  {
    "label": "BDL: 部署全部",
    "command": "bdl-lsp deploy -workspace \"$ZED_WORKTREE_ROOT\"",
    "use_new_terminal": false,
    "allow_concurrent_runs": false,
    "reveal": "always"
  }
]
```

运行：`Cmd/Ctrl+Shift+P` → `task: spawn` → 选 label。

> 📷 **截图位**：`images/zed/07-deploy-task.png`  
> 建议内容：`task: spawn` 列表和一次“部署预演”的输出。

### 7.3 让 task 找到 `bdl-lsp`

task 走登录 shell 的 `PATH`，与 Zed LSP 的查找路径不同。任选：

- 把二进制目录加入 `~/.zshrc` / `~/.bashrc` 的 `PATH`；
- 软链到 `~/.local/bin/bdl-lsp`；
- 在 task 的 `command` 里写绝对路径。

---

## 8. 设置参考

Zed 的配置写在 `lsp.bdl-lsp.settings` 下；下面只列 `settings` 内部的键，
省略外层包装。项目级 `.bdl-lsp/config.json` 的字段名相同，优先级低于
Zed 设置。

### 8.1 按“要不要改”分类

**第一类：默认即可，基本不用动**

- `diagnostics`：默认 warning，例外见下；
- `format.*`：`unchanged` / `auto` / `0`；
- `limits.*`：大文件、行数、诊断条数、解析超时的安全默认；
- `index.enable` / `schema.enable` / `builtins.enable`：默认开启。

**第二类：不配置就用不了**

- 链接资料：先生成 `.link`，再按需配 `link.*`；
- 部署：`.bdl-lsp/deploy.json` + SSH；
- schema：只有需要展开 `LIKE table.*` 时才配 `schema.paths`；
- 表单/GLOBALS 搜索路径：层级特殊时才配。

**第三类：按项目调整**

- `ignore.*`：生成代码、历史代码；
- `link.moduleRoots` / `globalModules` / `sync.*`：多模组；
- `limits.*`：超大文件或诊断特别多；
- `logLevel`（通过 `binary.args`）：排障。

### 8.2 键总表

**运行**

| 键 | 默认 | 作用 |
|---|---|---|
| `generoVersion` | `2.50` | `2.50`/`3.00`/`4.00` |

二进制路径不在 `settings` 里，而是 `lsp.bdl-lsp.binary.path`。

**诊断与格式化**

| 键 | 默认 | 作用 |
|---|---|---|
| `diagnostics` | `{}` | 按诊断码覆盖级别；唯一诊断入口 |
| `format.keywords` | `unchanged` | `unchanged`/`upper`/`lower`；`lower` 同时让补全的关键字用小写 |
| `format.indentStyle` | `auto` | `auto`/`tab`/`space` |
| `format.indentSize` | `0` | 缩进宽度，0 跟随编辑器 |

**项目解析**

| 键 | 默认 | 作用 |
|---|---|---|
| `index.enable` | `true` | 工作区符号索引 |
| `schema.enable` | `true` | schema 索引开关 |
| `schema.paths` | `[]` | `.sch` 路径/glob |
| `globals.searchPaths` | `[]` | GLOBALS 附加解析根 |
| `perRoots` | `[]` | `.per` 附加解析根 |
| `builtins.enable` | `true` | 内置符号表 |
| `builtins.paths` | `[]` | 项目自定义内置表 |
| `builtins.disable` | `[]` | 禁用的内置符号 |
| `ignore.files` | `[]` | 忽略诊断并排除索引的文件 |
| `ignore.fields` | `[]` | 只关字段诊断的字段 glob |
| `ignore.forms` | `[]` | 关字段类诊断的表单 glob |

**资源保护**

| 键 | 默认 | 作用 |
|---|---|---|
| `limits.maxFileBytes` | `2097152` | 单文件字节上限 |
| `limits.maxFileLines` | `20000` | 单文件行数上限 |
| `limits.maxIssues` | `200` | 单文件诊断上限 |
| `limits.parseTimeoutMs` | `2000` | 解析超时（毫秒） |

**链接资料**

| 键 | 默认 | 作用 |
|---|---|---|
| `link.enable` | `true` | 总开关 |
| `link.dataDir` | `.link` | 资料目录 |
| `link.moduleRoots` | `[]` | 模组根 |
| `link.globalModules` | `["sub","lib","qry"]` | 全局模组名 |
| `link.maxAgeDays` | `7` | 过期阈值（天） |
| `link.sync.enable` | `false` | 自动同步 |
| `link.sync.source` | `golang` | `golang`/`command`/`file` |
| `link.sync.onStart` | `false` | 启动时同步 |
| `link.sync.interval` | `0` | 间隔（秒），0 不定时 |
| `link.sync.command` | `""` | `source=command` 的命令 |
| `link.sync.file` | `""` | `source=file` 的文件 |
| `link.sync.db.host` | `""` | Oracle 主机 |
| `link.sync.db.port` | `1521` | Oracle 端口 |
| `link.sync.db.service` | `""` | Oracle 服务名 |
| `link.sync.db.user` | `""` | Oracle 用户 |
| `link.sync.db.query` | `""` | 自定义查询 |

### 8.3 项目级配置

`.bdl-lsp/config.json` 由 VSCode/Zed 共用：

```json
{
  "generoVersion": "3.00",
  "diagnostics": {
    "record-member-unknown": "warning"
  },
  "globals": { "searchPaths": ["config"] },
  "perRoots": ["forms"],
  "ignore": { "files": ["build/**"] },
  "link": { "moduleRoots": ["src"], "maxAgeDays": 14 }
}
```

---

## 9. 常见问题

### 9.1 语言服务器没启动

- `zed: open log` 看错误；
- `lsp.bdl-lsp.binary.path` 是否指向可执行文件；
- 终端执行 `<path> version` 是否正常；
- Windows 注意 `.exe` 后缀和路径分隔符。

### 9.2 没有诊断

- 语言模式是否为 Genero BDL / Form；
- 文件是否被 `ignore.files` 排除；
- 是否超过 `limits.*`（会有 `file-too-large`）；
- 看 `zed: open log` 是否有解析器/grammar 初始化失败。

### 9.3 函数全报找不到

- 是否生成 `.link/links.jsonl`；
- `bdl-lsp link status -root .` 是否正常；
- 函数是否在可见模组内（`link.globalModules` / `moduleRoots`）。

### 9.4 链接资料不刷新

服务器按资料文件 mtime 自动重载。重新 `link import`/`link sync` 后打开
一个文件即可；仍不生效时执行 `editor: restart language server`。

### 9.5 部署失败

- 先在终端跑 `bdl-lsp deploy -workspace <root> -dry-run`；
- 手动 `ssh user@host` 验证 key/agent；
- 检查 `remoteRoot` 权限和远程编译命令的 `PATH`；
- task 的 `command` 用绝对路径排除 PATH 问题。

### 9.6 旧设置不生效

旧诊断键已删除，迁移到 `diagnostics`：

```json
{
  "diagnostics": {
    "field-not-in-form": "off"
  }
}
```

---

## 附：截图/录屏清单

| 编号 | 文件 | 用在哪 |
|---|---|---|
| 01 | `images/zed/01-install.png` | 1.2 安装 |
| 02 | `images/zed/02-settings.png` | 1.3 配置 |
| 03 | `images/zed/03-hover.gif` | 3.1 悬停/跳转 |
| 04 | `images/zed/04-completion.gif` | 3.2 补全 |
| 05 | `images/zed/05-format.gif` | 3.4 格式化 |
| 06 | `images/zed/03-diagnostics.png` | 4.1 诊断 |
| 07 | `images/zed/07-deploy-task.png` | 7.2 部署 |
| 08 | `images/zed/08-link-status.png` | 6.1 链接状态 |

素材规范见 [`images/zed/README.md`](images/zed/README.md)。
