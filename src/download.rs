//! 运行时自动下载二进制（PLAN Z-P4-1 / Z-P4-2）。
//!
//! 「无感」优先：用户没有本地 `bdl-lsp` / `tiptop` 时，按平台从 GitHub Release
//! 下载对应资产、解包到扩展工作目录、补可执行位，并清掉旧版本目录。
//!
//! 位置：**排在所有本地查找之后**（`binary.rs` 的四级顺序里作为第 5 级兜底）。
//! 用户已经装好的二进制永远优先，不会因为我们"顺便下载一个新版"而改变行为。
//!
//! 资产命名（与 `bdl-lsp/.github/workflows/release.yml` 约定一致）：
//!
//! ```text
//! bdl-lsp-linux-amd64.tar.gz     bdl-lsp-darwin-amd64.tar.gz
//! bdl-lsp-darwin-arm64.tar.gz    bdl-lsp-windows-amd64.zip
//! ```
//!
//! 关闭方式：`lsp.bdl-lsp.settings.ext.download.bdlLsp` / `.tiptop` 设为 `"off"`。
//!
//! capability：`download_file`（`extension.toml` 里已声明 host=github.com、
//! path=["darcyjoven","**"]）；没有该授权时这里会拿到宿主返回的错误，文案原样带回。

use std::path::Path;

use zed_extension_api as zed;

use crate::config::Settings;

/// `bdl-lsp` 的 GitHub 仓库。
pub const LSP_REPO: &str = "darcyjoven/bdl-lsp";
/// `tiptop` 的 GitHub 仓库。
pub const TOOLS_REPO: &str = "darcyjoven/tiptop";

/// 资产名前缀（= 二进制名，与 release.yml 里一致）。
const LSP_ASSET: &str = "bdl-lsp";
const TOOLS_ASSET: &str = "tiptop";

/// 当前平台对应的资产名；不支持的平台返回 `None`。
pub fn asset_name_for(prefix: &str, os: zed::Os, arch: zed::Architecture) -> Option<String> {
    let os = match os {
        zed::Os::Linux => "linux",
        zed::Os::Mac => "darwin",
        zed::Os::Windows => "windows",
    };
    let arch = match arch {
        zed::Architecture::X8664 => "amd64",
        zed::Architecture::Aarch64 => "arm64",
        // 32 位 x86 与其它架构没有发布产物。
        zed::Architecture::X86 => return None,
    };
    let ext = if os == "windows" { "zip" } else { "tar.gz" };
    Some(format!("{prefix}-{os}-{arch}.{ext}"))
}

/// 下载 `bdl-lsp`（语言服务器），返回可执行文件的**相对路径**。
pub fn ensure_lsp(
    settings: &Settings,
    server_id: Option<&zed::LanguageServerId>,
) -> Result<String, String> {
    ensure(settings, LSP_REPO, LSP_ASSET, server_id)
}

/// 下载 `tiptop`（采集/部署 CLI），返回可执行文件的**相对路径**。
///
/// slash command 的调用点拿不到 `LanguageServerId`，所以这里不上报安装状态，
/// 失败信息由命令输出带回。
pub fn ensure_tools(settings: &Settings) -> Result<String, String> {
    ensure(settings, TOOLS_REPO, TOOLS_ASSET, None)
}

fn ensure(
    settings: &Settings,
    repo: &str,
    prefix: &str,
    server_id: Option<&zed::LanguageServerId>,
) -> Result<String, String> {
    if download_disabled(settings, prefix) {
        return Err(format!("{prefix}: 自动下载已在设置里关闭（ext.download.* = off）。"));
    }

    let (os, arch) = zed::current_platform();
    let Some(asset_name) = asset_name_for(prefix, os, arch) else {
        return Err(format!(
            "{prefix}: 当前平台（{os:?}/{arch:?}）没有发布产物，请手工构建并指定路径。"
        ));
    };

    report(server_id, zed::LanguageServerInstallationStatus::CheckingForUpdate);

    let release = zed::latest_github_release(
        repo,
        zed::GithubReleaseOptions {
            require_assets: true,
            pre_release: false,
        },
    )
    .map_err(|err| {
        let msg = format!("{prefix}: 查询 GitHub Release 失败：{err}");
        report(server_id, zed::LanguageServerInstallationStatus::Failed(msg.clone()));
        msg
    })?;

    let asset = release
        .assets
        .iter()
        .find(|a| a.name == asset_name)
        .ok_or_else(|| {
            let have: Vec<&str> = release.assets.iter().map(|a| a.name.as_str()).collect();
            let msg = format!(
                "{prefix}: Release {} 里没有资产 {asset_name}（实际有：{}）",
                release.version,
                have.join(", ")
            );
            report(server_id, zed::LanguageServerInstallationStatus::Failed(msg.clone()));
            msg
        })?;

    // 按版本分目录，便于"同版本复用 + 旧版本清理"。
    let version_dir = format!("{prefix}-{}", release.version);
    let binary = format!("{version_dir}/{}", binary_file_name(prefix, os));
    let reusable = std::fs::metadata(&binary)
        .map(|meta| meta.is_file())
        .unwrap_or(false);
    if reusable {
        return Ok(binary);
    }

    report(server_id, zed::LanguageServerInstallationStatus::Downloading);
    let file_type = if matches!(os, zed::Os::Windows) {
        zed::DownloadedFileType::Zip
    } else {
        zed::DownloadedFileType::GzipTar
    };
    if let Err(err) = zed::download_file(&asset.download_url, &version_dir, file_type) {
        let msg = format!(
            "{prefix}: 下载 {} 失败：{err}\n\
             可手工构建后放到 <工作区>/.bdl-lsp/bin/，或设置 ext.tools.path / lsp.bdl-lsp.binary.path。",
            asset.download_url
        );
        report(server_id, zed::LanguageServerInstallationStatus::Failed(msg.clone()));
        return Err(msg);
    }
    if let Err(err) = zed::make_file_executable(&binary) {
        let msg = format!("{prefix}: 设置可执行位失败（{binary}）：{err}");
        report(server_id, zed::LanguageServerInstallationStatus::Failed(msg.clone()));
        return Err(msg);
    }

    remove_old_versions(prefix, &version_dir);
    Ok(binary)
}

/// 是否在设置里关掉了自动下载。
fn download_disabled(settings: &Settings, prefix: &str) -> bool {
    let key = if prefix == LSP_ASSET { "bdlLsp" } else { "tiptop" };
    settings
        .ext_str(&["download", key])
        .map(|v| v.eq_ignore_ascii_case("off"))
        .unwrap_or(false)
}

/// 清掉同前缀的旧版本目录（尽力而为，失败不影响使用）。
fn remove_old_versions(prefix: &str, keep: &str) {
    let Ok(entries) = std::fs::read_dir(".") else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        if name == keep || !name.starts_with(&format!("{prefix}-")) {
            continue;
        }
        if Path::new(name).is_dir() {
            let _ = std::fs::remove_dir_all(name);
        }
    }
}

/// Windows 上资产里的二进制名带 `.exe`。
fn binary_file_name(prefix: &str, os: zed::Os) -> String {
    match os {
        zed::Os::Windows => format!("{prefix}.exe"),
        _ => prefix.to_string(),
    }
}

/// 上报安装状态（没有 id 时静默跳过）。
fn report(server_id: Option<&zed::LanguageServerId>, status: zed::LanguageServerInstallationStatus) {
    if let Some(id) = server_id {
        zed::set_language_server_installation_status(id, &status);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn asset_names_match_release_workflow() {
        use zed::{Architecture::*, Os::*};
        assert_eq!(
            asset_name_for(LSP_ASSET, Linux, X8664).as_deref(),
            Some("bdl-lsp-linux-amd64.tar.gz")
        );
        assert_eq!(
            asset_name_for(LSP_ASSET, Mac, Aarch64).as_deref(),
            Some("bdl-lsp-darwin-arm64.tar.gz")
        );
        assert_eq!(
            asset_name_for(TOOLS_ASSET, Windows, X8664).as_deref(),
            Some("tiptop-windows-amd64.zip")
        );
        assert_eq!(asset_name_for(LSP_ASSET, Linux, X86), None);
    }

    #[test]
    fn windows_binary_has_exe_suffix() {
        assert_eq!(binary_file_name("bdl-lsp", zed::Os::Windows), "bdl-lsp.exe");
        assert_eq!(binary_file_name("bdl-lsp", zed::Os::Linux), "bdl-lsp");
    }
}