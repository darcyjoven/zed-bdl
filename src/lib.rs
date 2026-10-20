//! Genero BDL / Form 的 Zed 扩展。
//!
//! 职责很窄：告诉 Zed 用哪个可执行文件启动 `bdl-lsp`。
//! 语法高亮、outline、缩进都在 `languages/*/` 的 query 里，
//! 不在 Rust 侧实现。
//!
//! 二进制定位顺序（与 VSCode 扩展的语义一致，见 vscode-extension/src/server/binary.ts）：
//!   1. Zed 设置 `lsp.bdl-lsp.binary.path`
//!   2. 环境变量 `BDL_LSP_PATH`
//!   3. 工作区下的 `.bdl-lsp/bin/<name>`
//!   4. `PATH` 中的 `bdl-lsp`
//!
//! 拿不到就返回带可操作提示的错误，而不是静默失败——Zed 会把它显示在
//! 语言服务器状态里，用户能立刻知道该配什么。

use std::path::PathBuf;

use zed_extension_api as zed;

/// 语言服务器在 extension.toml 里注册的 key。
const SERVER_ID: &str = "bdl-lsp";

/// 二进制文件名（按平台补后缀）。
fn binary_name() -> &'static str {
    // Zed 扩展编译成 wasm，不能用 std::env::consts::OS；
    // 用扩展 API 提供的当前平台信息。
    match zed::current_platform().0 {
        zed::Os::Windows => "bdl-lsp.exe",
        _ => "bdl-lsp",
    }
}

struct BdlExtension;

/// 从 Zed 设置里取 `lsp.bdl-lsp.binary.*`。
///
/// 读设置失败不算致命：用户可以只用环境变量或 PATH。
fn settings_for(worktree: &zed::Worktree) -> Option<zed::settings::LspSettings> {
    zed::settings::LspSettings::for_worktree(SERVER_ID, worktree).ok()
}

/// 在 PATH 里找可执行文件，找不到返回 `None`。
fn which(worktree: &zed::Worktree, name: &str) -> Option<String> {
    worktree.which(name)
}

/// 工作区内的 `.bdl-lsp/bin/<name>`，存在则返回绝对路径。
fn workspace_binary(worktree: &zed::Worktree, name: &str) -> Option<String> {
    let root = worktree.root_path();
    let candidate = PathBuf::from(&root).join(".bdl-lsp").join("bin").join(name);
    if candidate.is_file() {
        Some(candidate.to_string_lossy().to_string())
    } else {
        None
    }
}

impl BdlExtension {
    /// 解析出要执行的命令。
    fn resolve(&self, worktree: &zed::Worktree) -> zed::Result<zed::Command> {
        let settings = settings_for(worktree);
        let name = binary_name();

        // 1. 显式设置优先：用户写了就一定用它，即使文件不存在也要报错，
        //    否则"配了但没生效"会非常难查。
        if let Some(binary) = settings.as_ref().and_then(|s| s.binary.as_ref()) {
            if let Some(path) = binary.path.as_ref().filter(|p| !p.trim().is_empty()) {
                let expanded = expand_home(path);
                if !PathBuf::from(&expanded).is_file() {
                    return Err(format!(
                        "bdl.server.path 指向的文件不存在：{path}\n\
                         请检查 Zed 设置 lsp.bdl-lsp.binary.path"
                    ));
                }
                return Ok(zed::Command {
                    command: expanded,
                    args: binary.arguments.clone().unwrap_or_default(),
                    env: binary.env.clone().unwrap_or_default().into_iter().collect(),
                });
            }
        }

        // 2. 环境变量
        if let Some(path) = std::env::var("BDL_LSP_PATH")
            .ok()
            .filter(|p| !p.trim().is_empty())
        {
            let expanded = expand_home(&path);
            if !PathBuf::from(&expanded).is_file() {
                return Err(format!(
                    "环境变量 BDL_LSP_PATH 指向的文件不存在：{path}"
                ));
            }
            return Ok(zed::Command {
                command: expanded,
                args: Vec::new(),
                env: Default::default(),
            });
        }

        // 3. 工作区内的 .bdl-lsp/bin
        if let Some(path) = workspace_binary(worktree, name) {
            return Ok(zed::Command {
                command: path,
                args: Vec::new(),
                env: Default::default(),
            });
        }

        // 4. PATH
        if let Some(path) = which(worktree, name) {
            return Ok(zed::Command {
                command: path,
                args: Vec::new(),
                env: Default::default(),
            });
        }

        Err(format!(
            "找不到 {name}。\n\
             \n\
             任选一种方式让 Zed 找到它：\n\
             1. 设置 lsp.bdl-lsp.binary.path 为绝对路径；\n\
             2. 设置环境变量 BDL_LSP_PATH；\n\
             3. 把二进制放到 <工作区>/.bdl-lsp/bin/{name}；\n\
             4. 把二进制所在目录加入 PATH。\n\
             \n\
             构建方法（在 bdl-lsp 仓库）：\n\
             make build            # Linux\n\
             scripts\\build.ps1     # Windows"
        ))
    }
}

impl zed::Extension for BdlExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<zed::Command> {
        self.resolve(worktree)
    }

    /// 把 Zed 侧的设置透传给 LSP 的 `initializationOptions`。
    ///
    /// bdl-lsp 目前从 `workspace/didChangeConfiguration` 读配置，
    /// 但客户端重启前的那一次握手用 initializationOptions 更直接。
    fn language_server_initialization_options(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<Option<zed::serde_json::Value>> {
        let settings = settings_for(worktree);
        Ok(settings.and_then(|s| s.initialization_options))
    }

    /// 把 Zed 设置里的 `lsp.bdl-lsp.settings` 作为工作区配置下发。
    fn language_server_workspace_configuration(
        &mut self,
        _language_server_id: &zed::LanguageServerId,
        worktree: &zed::Worktree,
    ) -> zed::Result<Option<zed::serde_json::Value>> {
        let settings = settings_for(worktree);
        Ok(settings.and_then(|s| s.settings))
    }
}

/// 展开开头的 `~/`。
///
/// wasm 里 `std::env::var("HOME")` 不可靠，所以这里用 Zed 传来的
/// shell 环境变量；拿不到就不展开，保持原样（用户写绝对路径更稳）。
fn expand_home(path: &str) -> String {
    let trimmed = path.trim();
    if !trimmed.starts_with("~/") {
        return trimmed.to_string();
    }
    // 优先 HOME（Linux/macOS），回退 USERPROFILE（Windows）
    for key in ["HOME", "USERPROFILE"] {
        if let Ok(home) = std::env::var(key) {
            if !home.is_empty() {
                return format!("{}/{}", home.trim_end_matches('/'), &trimmed[2..]);
            }
        }
    }
    trimmed.to_string()
}

zed::register_extension!(BdlExtension);
