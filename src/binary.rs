//! 二进制定位。
//!
//! `bdl-lsp` 与 `tiptop` 用同一套查找语义（与 VSCode 插件 `src/server/binary.ts`
//! 对齐）：
//!
//! 1. Zed 设置里的显式路径（`lsp.bdl-lsp.binary.path` / `ext.tools.path`）
//! 2. 环境变量（`BDL_LSP_PATH` / `TIPTOP_PATH`）
//! 3. 工作区下的 `.bdl-lsp/bin/<名字>`
//! 4. `PATH`
//!
//! 显式设置写了但文件不存在时**直接报错**，而不是静默回退——"配了但没生效"
//! 最难查；错误文案给可操作的四条路径。

use std::path::PathBuf;

use zed_extension_api as zed;

use crate::config::Settings;

/// 语言服务器二进制名。
pub const LSP: &str = "bdl-lsp";
/// 采集/部署 CLI 二进制名。
pub const TOOLS: &str = "tiptop";

/// 按平台补 `.exe`。
fn exe_name(base: &str) -> String {
    // wasm 里不能用 std::env::consts::OS，用扩展 API 的平台信息。
    match zed::current_platform().0 {
        zed::Os::Windows => format!("{base}.exe"),
        _ => base.to_string(),
    }
}

/// 解析语言服务器命令。
pub fn resolve_lsp(worktree: &zed::Worktree, settings: &Settings) -> zed::Result<zed::Command> {
    let name = exe_name(LSP);
    let mut args = settings.arguments.clone();
    if !args.iter().any(|a| a == "--log-level" || a == "-log-level") {
        if let Some(level) = settings.log_level() {
            args.push("--log-level".to_string());
            args.push(level);
        }
    }
    let env = settings.env.clone();

    // 1. 显式设置优先
    if let Some(path) = settings.path.as_ref() {
        let expanded = expand_home(path);
        if !PathBuf::from(&expanded).is_file() {
            return Err(format!(
                "{name} 的路径来自 Zed 设置 lsp.bdl-lsp.binary.path，但文件不存在：{path}\n\
                 请检查该设置（支持 ~/ 展开），或清空它改用其它方式。"
            ));
        }
        return Ok(zed::Command {
            command: expanded,
            args,
            env,
        });
    }

    // 2. 环境变量
    if let Some(path) = non_empty_env("BDL_LSP_PATH") {
        let expanded = expand_home(&path);
        if !PathBuf::from(&expanded).is_file() {
            return Err(format!(
                "环境变量 BDL_LSP_PATH 指向的文件不存在：{path}"
            ));
        }
        return Ok(zed::Command {
            command: expanded,
            args,
            env,
        });
    }

    // 3. 工作区 `.bdl-lsp/bin/`
    if let Some(path) = workspace_binary(worktree, &name) {
        return Ok(zed::Command {
            command: path,
            args,
            env,
        });
    }

    // 4. PATH
    if let Some(path) = worktree.which(&name) {
        return Ok(zed::Command {
            command: path,
            args,
            env,
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
         make build            # Linux / macOS\n\
         scripts\\build.ps1     # Windows"
    ))
}

/// 解析 `tiptop` 可执行文件路径（供 slash command / task 生成脚本使用）。
pub fn resolve_tools(worktree: &zed::Worktree, settings: &Settings) -> zed::Result<String> {
    let name = exe_name(TOOLS);

    if let Some(path) = settings.ext_str(&["tools", "path"]) {
        let expanded = expand_home(&path);
        if !PathBuf::from(&expanded).is_file() {
            return Err(format!(
                "tiptop 的路径来自 Zed 设置 lsp.bdl-lsp.settings.ext.tools.path，\
                 但文件不存在：{path}\n请检查该设置（支持 ~/ 展开），或清空它改用其它方式。"
            ));
        }
        return Ok(expanded);
    }

    if let Some(path) = non_empty_env("TIPTOP_PATH") {
        let expanded = expand_home(&path);
        if !PathBuf::from(&expanded).is_file() {
            return Err(format!("环境变量 TIPTOP_PATH 指向的文件不存在：{path}"));
        }
        return Ok(expanded);
    }

    if let Some(path) = workspace_binary(worktree, &name) {
        return Ok(path);
    }

    if let Some(path) = worktree.which(&name) {
        return Ok(path);
    }

    Err(format!(
        "找不到 {name}（资料采集 / 上传 / 编译都依赖它）。\n\
         \n\
         任选一种方式：\n\
         1. 设置 lsp.bdl-lsp.settings.ext.tools.path 为绝对路径；\n\
         2. 设置环境变量 TIPTOP_PATH；\n\
         3. 把二进制放到 <工作区>/.bdl-lsp/bin/{name}；\n\
         4. 把二进制所在目录加入 PATH。\n\
         \n\
         构建方法（在 tiptop 仓库）：\n\
         make build            # Linux / macOS\n\
         scripts\\build.ps1     # Windows"
    ))
}

/// 读一个非空环境变量。
fn non_empty_env(key: &str) -> Option<String> {
    std::env::var(key)
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// 工作区内的 `.bdl-lsp/bin/<name>`，存在则返回绝对路径。
fn workspace_binary(worktree: &zed::Worktree, name: &str) -> Option<String> {
    let candidate = PathBuf::from(worktree.root_path())
        .join(".bdl-lsp")
        .join("bin")
        .join(name);
    if candidate.is_file() {
        Some(candidate.to_string_lossy().to_string())
    } else {
        None
    }
}

/// 展开开头的 `~/`。
///
/// wasm 沙箱里 `HOME` 不一定可见，所以优先用 Zed 传来的 shell 环境变量，
/// 拿不到就按原样返回（用户写绝对路径最稳）。
fn expand_home(path: &str) -> String {
    let trimmed = path.trim();
    if !trimmed.starts_with("~/") {
        return trimmed.to_string();
    }
    for key in ["HOME", "USERPROFILE"] {
        if let Ok(home) = std::env::var(key) {
            if !home.is_empty() {
                return format!("{}/{}", home.trim_end_matches('/'), &trimmed[2..]);
            }
        }
    }
    trimmed.to_string()
}