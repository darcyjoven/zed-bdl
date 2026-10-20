# BDL for Zed

Genero BDL（`.4gl` / `.global`）与 Form（`.per`）的 Zed 扩展：语法高亮、outline、
括号匹配、缩进，以及通过 [`bdl-lsp`](https://github.com/darcyjoven/bdl-lsp) 提供的
跳转 / 引用 / 悬停 / 诊断。

> 扩展 id 为 **`4gl-full`**，与轻量扩展 [`bdl`](https://github.com/darcyjoven/bdl-plugin)
> （只有 grammar、没有 LSP）共存，两者可以同时安装。
> 本仓库只放 Zed 交付物；计划、测试脚本、过程记录统一在本地 `bdl-lsp` 仓库。
> v1 验证平台：**Linux + Windows**（macOS 后续补齐）。

## 能力

| 能力 | 说明 |
|---|---|
| 语法高亮 | 由 grammar 关键字表驱动，BDL 300 个关键字 / `.per` 76 个，全部覆盖 |
| Outline | BDL：函数、报表、MAIN、标签、常量、TYPE、模块级 DEFINE；`.per`：item、SCREEN RECORD、表、菜单、动作 |
| 括号匹配 | `(` `)` / `[` `]` / `{` `}` |
| 缩进 | BDL 按块结构（`IF`/`WHILE`/`FOR`/`FUNCTION`…）；`.per` **不动 LAYOUT** |
| SQL 注入 | `.4gl` 里 `SELECT`/`INSERT`/`UPDATE`/`DELETE` 的 `sql_body` 按 SQL 高亮 |
| LSP | 跳转、引用、悬停、文档/工作区符号、语法诊断（依赖 `bdl-lsp`） |

## 前置：准备 `bdl-lsp`

扩展**不下载**二进制（自动下载暂不排期），需要你自己构建一次：

```bash
# Linux
cd bdl-lsp
source scripts/dev-env.sh      # 沙箱/无 root 环境才需要
make build                     # 产物：artifacts/bin/bdl-lsp
```

```powershell
# Windows（无需 make）
cd bdl-lsp
powershell -ExecutionPolicy Bypass -File scripts\build.ps1
# 产物：artifacts\bin\bdl-lsp.exe
```

然后任选一种方式让 Zed 找到它（按优先级）：

| 优先级 | 方式 | 配置 |
|---|---|---|
| 1 | Zed 设置 | `lsp.bdl-lsp.binary.path` 指向绝对路径 |
| 2 | 环境变量 | `BDL_LSP_PATH=/path/to/bdl-lsp` |
| 3 | 工作区内 | 放在 `<工作区>/.bdl-lsp/bin/bdl-lsp`（Windows 为 `bdl-lsp.exe`） |
| 4 | PATH | 把二进制所在目录加入 `PATH` |

Zed 设置示例（`~/.config/zed/settings.json`）：

```json
{
  "lsp": {
    "bdl-lsp": {
      "binary": {
        "path": "/home/you/bdl-lsp/artifacts/bin/bdl-lsp",
        "args": ["--log-level", "debug"]
      },
      "settings": {
        "generoVersion": "2.50",
        "missingDiagnostics": "warning"
      }
    }
  }
}
```

`settings` 会作为 `workspace/didChangeConfiguration` 的内容下发给服务器，
字段与 VSCode 扩展的 `bdl.*` 一致。

## 安装

1. 安装 Rust 与 `wasm32-wasip2` target：

   ```bash
   rustup target add wasm32-wasip2
   ```

2. Zed 命令面板执行 `zed: install dev extension`，选择本目录。

3. 打开一个 `.4gl` 或 `.per` 文件，检查状态栏是否显示语言为
   **Genero BDL** / **Genero Form**，以及语言服务器是否启动。

排查用 `zed: open log`；需要更详细的日志时从终端以 `zed --foreground` 启动。

## 与 VSCode 扩展的关系

两者共享同一个 `bdl-lsp` 与同一套配置字段，区别只在客户端：

| | VSCode（`vscode-bdl`） | Zed（本仓库） |
|---|---|---|
| 语言 id | `bdl` / `per` | `Genero BDL` / `Genero Form`（映射为 `bdl` / `per` 发给 LSP） |
| 高亮来源 | TextMate 语法（脚本从 grammar 生成） | Tree-sitter query |
| 配置位置 | `bdl.*` 设置项 | `lsp.bdl-lsp.settings` |

## 开发

```bash
# 编译检查
cargo check --target wasm32-wasip2

# 发布构建（Zed 实际加载的是这个）
cargo build --release --target wasm32-wasip2

# 清单校验（extension.toml / languages/*/config.toml 一致性）
python3 tests/verify-manifest.py

# query 校验（节点名/字面量是否存在、能否编译、关键字覆盖率）
# 需要两个 grammar 仓库与本仓库并列，且 tree-sitter CLI 在 PATH
node tests/verify-queries.mjs
```

`tests/verify-queries.mjs` 会检查：

1. 每个 `.scm` 里的节点名都存在于 grammar 的 `src/node-types.json`；
2. 每个字符串字面量都是真实 token（`#set!` 的值除外）；
3. 用 `tree-sitter query` 对 `tests/fixtures/` 的样例真正编译一遍并统计命中数；
4. grammar 的全部大写关键字是否都被 `highlights.scm` 覆盖。

第 3 步能挡住"query 语法正确但规则写错、一条都匹配不上"这种最难查的情况。

### 修改 query 时的注意事项

- **节点名必须精确**。Zed 编译 query 时只要有一个未知节点名，**整份文件**
  都会被丢弃，高亮全没，而界面上不会报错。
- **字段绑定有类型约束**。`name: (name)` 这种写法在某些节点上会报
  `Impossible pattern`（例如 `.per` 的 `menu_group`，其 `name` 字段实际是
  `identifier | 关键字` 的联合）。改完务必跑一次校验脚本。
- **LAYOUT 段不许缩进**。`.per` 的布局列位置有屏幕坐标语义，
  `languages/per/indents.scm` 刻意不为 `(layout)` 声明 `@indent`。

## 已知限制

- 扩展 API 不支持任意命令，部署/编译只能用 `.zed/tasks.json` 调用
  `bdl-lsp deploy`（P5，尚未实现）。
- 自动下载 `bdl-lsp` 暂不排期，二进制需要自备。
- 未在 Zed 里实测（本机无图形界面）；已用 `cargo check/build --target wasm32-wasip2`
  与 query 编译校验覆盖可自动化的部分。

## 许可

MIT，见 [LICENSE](LICENSE)。
