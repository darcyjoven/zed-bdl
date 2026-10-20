# BDL for Zed

Genero BDL（`.4gl` / `.global`）与 Form（`.per`）的 Zed 扩展。

> 状态：仓库已初始化，功能开发按 `bdl-lsp/docs/PLAN.md` 推进。扩展 id 计划为 `bdl-full`，与轻量 `bdl-plugin` 共存。
> 远程仓库：`git@github.com:darcyjoven/zed-bdl.git`（本地目录仍叫 `zed-extension/`）。
> 本仓库只保留 Zed 交付物；计划、测试脚本、过程记录统一在本地 `bdl-lsp` 仓库。
> v1 验证平台：**Linux + Windows**（Zed 已有官方 Windows 版本；仍需实测扩展加载与 LSP 启动）。

## 计划中的能力

- Tree-sitter 高亮、outline、brackets、SQL 注入、缩进
- 通过 `bdl-lsp` 提供跳转、引用、悬停、格式化、字段校验（目标 Genero 2.50–5.0）
- 首次使用时从 `bdl-lsp` Release 自动下载对应平台的 LSP 二进制（无感安装）
- 部署/编译通过 `bdl-lsp deploy` CLI + `.zed/tasks.json`（Zed 扩展 API 不支持任意命令）

## 本地开发（待实现后补全）

1. 安装 Rust + `wasm32-wasip2` target（Zed 会为 grammar 准备 wasi-sdk）。
2. 在 Zed 中执行 `zed: install dev extension`，选择本目录。
3. 查看 Zed 日志（`zed: open log`）排查。

## 许可

MIT，见 [LICENSE](LICENSE)。
