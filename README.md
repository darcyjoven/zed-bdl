# BDL for Zed

Genero BDL（`.4gl` / `.global`）与 Form（`.per`）的 Zed 扩展。

> 状态：仓库已初始化，功能开发按 [`bdl-lsp/docs/PLAN.md`](https://github.com/darcyjoven/bdl-lsp/blob/main/docs/PLAN.md) 推进。
> 本仓库只保留 Zed 交付物；计划、测试脚本、过程记录统一在 `bdl-lsp` 仓库。

## 计划中的能力

- Tree-sitter 高亮、outline、brackets、SQL 注入、缩进
- 通过 `bdl-lsp` 提供跳转、引用、悬停、格式化、字段校验
- 首次使用时从 GitHub Release 下载对应平台的 LSP 二进制
- 部署/编译通过 `bdl-lsp deploy` CLI + `.zed/tasks.json`（Zed 扩展 API 不支持任意命令）

## 本地开发（待实现后补全）

1. 安装 Rust + `wasm32-wasip2` target（Zed 会为 grammar 准备 wasi-sdk）。
2. 在 Zed 中执行 `zed: install dev extension`，选择本目录。
3. 查看 Zed 日志（`zed: open log`）排查。

## 许可

MIT，见 [LICENSE](LICENSE)。
