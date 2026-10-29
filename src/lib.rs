//! Genero BDL / Form 的 Zed 扩展。
//!
//! 职责：
//! 1. 告诉 Zed 用哪个可执行文件启动 `bdl-lsp`（[`binary`]）；
//! 2. 把用户的 Zed 设置合并成有效配置并从 `initializationOptions` 下发（[`config`]）；
//! 3. 提供只读的 slash command（[`slash`]，Agent 面板 `/bdl-…`）。
//!
//! 语法高亮、outline、缩进是 `languages/*/` 的 query，不在 Rust 侧实现；
//! 写盘 / 长任务 / 需要交互的操作用项目 `.zed/tasks.json` 的 task（见 `docs/USER-GUIDE.md`）。
//!
//! ## 为什么配置不走 `settings` 通道（2026-10-28 核实）
//!
//! Zed 的 `lsp.<server>.settings` 只在服务端请求 `workspace/configuration` 时下发，
//! 而 `bdl-lsp` 不发这个请求。因此这里把
//! `initialization_options ⊕ settings(去掉 ext) ⊕ 轻量档默认`
//! 合并后从 `initializationOptions` 下发（见 [`config`] 的模块注释）；
//! 同一份值也作为 `workspace/configuration` 的应答返回，便于以后无缝生效。

mod binary;
mod config;
mod download;
mod project;
mod slash;

use zed_extension_api as zed;

struct BdlExtension;

impl zed::Extension for BdlExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<zed::Command> {
        let settings = config::load(worktree);
        binary::resolve_lsp(worktree, &settings, Some(language_server_id))
    }

    /// 启动时下发的有效配置。
    ///
    /// 这是 Zed 上**唯一**能保证到达 `bdl-lsp` 的通道；改配置需要重启语言服务器
    /// （服务端支持 `workspace/configuration` 之前，见 PLAN Z-P3-1）。
    fn language_server_initialization_options(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<Option<zed::serde_json::Value>> {
        let settings = config::load(worktree);
        Ok(Some(settings.lsp))
    }

    /// 同一份有效配置，作为 `workspace/configuration` 的应答。
    ///
    /// `bdl-lsp` 目前不请求它，但服务端一旦支持（PLAN Z-P3-1），这里就自然生效。
    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<Option<zed::serde_json::Value>> {
        let settings = config::load(worktree);
        Ok(Some(settings.lsp))
    }

    /// slash command：Agent 面板里输入 `/bdl-…`。
    ///
    /// 名字与 `extension.toml` 的 `[slash_commands.*]` 必须一一对应，
    /// 由 `tests/verify-manifest.py` 静态校验。
    fn run_slash_command(
        &self,
        command: zed::SlashCommand,
        args: Vec<String>,
        worktree: Option<&zed::Worktree>,
    ) -> zed::Result<zed::SlashCommandOutput> {
        slash::run(&command.name, &args, worktree)
    }
}

zed::register_extension!(BdlExtension);