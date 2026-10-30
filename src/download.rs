//! 运行时自动下载二进制（PLAN Z-P4-1 / Z-P4-2）。
//!
//! 「无感」优先：用户没有本地 `bdl-lsp` / `tiptop` 时，按平台从 GitHub Release
//! 下载对应资产、解包到扩展工作目录、补可执行位，并清掉旧版本目录。
//!
//! 位置：**排在所有本地查找之后**（`binary.rs` 的四级顺序里作为第 5 级兜底）。
//! 用户已经装好的二进制永远优先，不会因为我们"顺便下载一个新版"而改变行为。
//!
//! 下载来源是一条**链**（按顺序试，第一个成功就用）：
//!
//! ```text
//! bdl-lsp  →  darcyjoven/bdl-lsp   →  darcyjoven/zed-bdl（本扩展自己的 Release）
//! tiptop   →  darcyjoven/tiptop    →  darcyjoven/zed-bdl
//! ```
//!
//! 首选后端各自的 Release（更新更快）；本扩展的 Release 兜底，它把两个后端
//! **配对**发布（release.yml 把实际用的后端 ref 写进 BUILD-INFO.json），
//! 保证"扩展版本 ↔ 后端版本"对得上。
//!
//! 资产命名（与 `bdl-lsp` / `tiptop` / 本扩展的 release.yml 约定一致）：
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
/// **本扩展自己的**仓库（Release 里同时带着两个后端二进制，见 release.yml）。
///
/// 它排在后面：优先用后端各自的 Release（更新更快），本扩展的 Release 兜底
/// —— 它保证"扩展版本 ↔ 后端版本"是配对发布的（release.yml 把两个后端的
/// ref 写进了 BUILD-INFO.json）。
pub const EXT_REPO: &str = "darcyjoven/zed-bdl";

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

/// 某个二进制要从哪些仓库找（按优先级）。
///
/// 抽成函数是为了让"下载链"成为可测的契约，而不是散在调用点的字面量。
fn download_repos(prefix: &str) -> Vec<&'static str> {
    if prefix == LSP_ASSET {
        vec![LSP_REPO, EXT_REPO]
    } else {
        vec![TOOLS_REPO, EXT_REPO]
    }
}

/// 下载 `bdl-lsp`（语言服务器），返回可执行文件的**相对路径**。
pub fn ensure_lsp(
    settings: &Settings,
    server_id: Option<&zed::LanguageServerId>,
) -> Result<String, String> {
    ensure(settings, &download_repos(LSP_ASSET), LSP_ASSET, server_id)
}

/// 下载 `tiptop`（采集/部署 CLI），返回可执行文件的**相对路径**。
///
/// slash command 的调用点拿不到 `LanguageServerId`，所以这里不上报安装状态，
/// 失败信息由命令输出带回。
pub fn ensure_tools(settings: &Settings) -> Result<String, String> {
    ensure(settings, &download_repos(TOOLS_ASSET), TOOLS_ASSET, None)
}

/// 依次尝试各仓库，返回第一个成功的。
///
/// 为什么是链而不是单一仓库：
///   - 首选后端各自的 Release（`bdl-lsp` / `tiptop`）—— 更新更快；
///   - 兜底是本扩展自己的 Release —— 它把两个后端二进制**配对**发布，
///     保证"扩展版本 ↔ 后端版本"对得上（见 release.yml 的 BUILD-INFO.json）。
///
/// 第一个仓库失败（查不到 Release / 没有对应平台的资产 / 下载失败）时，
/// 自动试下一个；全部失败才报错，并把每个仓库的原因都列出来 ——
/// 只报最后一个错会让人以为是网络问题。
fn ensure(
    settings: &Settings,
    repos: &[&str],
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

    // 先看本地缓存：按版本分目录下载过就直接用**最新**的一份。
    // 这样常态启动不需要联网，也不会每次都被 GitHub 的可用性拖住
    // （离线时更不会因为查询失败而报"找不到二进制"）。
    if let Some(cached) = cached_binary(prefix, os) {
        return Ok(cached);
    }

    report(server_id, zed::LanguageServerInstallationStatus::CheckingForUpdate);

    let mut problems: Vec<String> = Vec::new();
    for repo in repos {
        match ensure_from_repo(repo, prefix, &asset_name, os, server_id) {
            Ok(path) => return Ok(path),
            Err(problem) => {
                // 首个仓库失败不必立刻报 Failed（还要试下一个）；
                // 但要让状态显示成"检查中"，避免用户以为卡住了。
                problems.push(problem);
            }
        }
    }

    let msg = format!(
        "{prefix}: 自动下载失败（已尝试 {} 个仓库）：\n  - {}\n\
         \n\
         可手工构建后放到 <工作区>/.bdl-lsp/bin/，或设置 ext.tools.path / lsp.bdl-lsp.binary.path。",
        repos.len(),
        problems.join("\n  - ")
    );
    report(server_id, zed::LanguageServerInstallationStatus::Failed(msg.clone()));
    Err(msg)
}

/// 从**一个**仓库下载二进制。
fn ensure_from_repo(
    repo: &str,
    prefix: &str,
    asset_name: &str,
    os: zed::Os,
    server_id: Option<&zed::LanguageServerId>,
) -> Result<String, String> {
    let release = zed::latest_github_release(
        repo,
        zed::GithubReleaseOptions {
            require_assets: true,
            pre_release: false,
        },
    )
    .map_err(|err| format!("{repo}: 查询 GitHub Release 失败：{err}"))?;

    let asset = release
        .assets
        .iter()
        .find(|a| a.name == asset_name)
        .ok_or_else(|| {
            let have: Vec<&str> = release.assets.iter().map(|a| a.name.as_str()).collect();
            format!(
                "{repo}: Release {} 里没有资产 {asset_name}（实际有：{}）",
                release.version,
                have.join(", ")
            )
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
        return Err(format!("{repo}: 下载 {} 失败：{err}", asset.download_url));
    }
    if let Err(err) = zed::make_file_executable(&binary) {
        return Err(format!("{repo}: 设置可执行位失败（{binary}）：{err}"));
    }

    remove_old_versions(prefix, &version_dir);
    Ok(binary)
}

/// 在扩展目录里找已下载的缓存二进制：只认 `<prefix>-<版本>/<二进制>` 这种目录，
/// 多个版本时取**版本号最大**的一个（数值比较，不是字符串比较）。
fn cached_binary(prefix: &str, os: zed::Os) -> Option<String> {
    cached_binary_in(Path::new("."), prefix, os)
}

/// `cached_binary` 的可测版本：在指定目录里找缓存（测试用临时目录）。
fn cached_binary_in(dir: &Path, prefix: &str, os: zed::Os) -> Option<String> {
    let binary = binary_file_name(prefix, os);
    let entries = std::fs::read_dir(dir).ok()?;
    let mut best: Option<((u32, u32, u32), String)> = None;
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(name) = name.to_str() else { continue };
        let Some(version) = name
            .strip_prefix(&format!("{prefix}-"))
            .and_then(crate::version::parse)
        else {
            continue;
        };
        // 存在性检查要落到 dir 下；返回值仍是**相对路径**（Zed 的扩展工作目录）。
        let candidate = format!("{name}/{binary}");
        if !dir.join(&candidate).is_file() {
            continue;
        }
        if best.as_ref().map(|(v, _)| version > *v).unwrap_or(true) {
            best = Some((version, candidate));
        }
    }
    best.map(|(_, path)| path)
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
    fn cached_binary_picks_newest_version() {
        let base = std::env::temp_dir().join(format!("zed-bdl-cache-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);
        for version in ["0.3.9", "0.3.14"] {
            let dir = base.join(format!("bdl-lsp-{version}"));
            std::fs::create_dir_all(&dir).unwrap();
            std::fs::write(dir.join("bdl-lsp"), b"x").unwrap();
        }
        // 干扰项：不是二进制目录、以及缺二进制的目录
        std::fs::create_dir_all(base.join("tiptop-0.1.10")).unwrap();
        std::fs::create_dir_all(base.join("bdl-lsp-9.9.9")).unwrap();

        let got = cached_binary_in(&base, "bdl-lsp", zed::Os::Linux);
        assert_eq!(got.as_deref(), Some("bdl-lsp-0.3.14/bdl-lsp"));
        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn download_chain_starts_with_backend_repo_and_falls_back_to_own_release() {
        // 下载链的顺序是契约：先要后端自己的 Release（更新更快），
        // 兜底是本扩展的 Release（两个后端配对发布）。
        assert_eq!(
            download_repos(LSP_ASSET),
            vec![LSP_REPO, EXT_REPO],
            "bdl-lsp 应先找 bdl-lsp 仓库，再退回本扩展"
        );
        assert_eq!(
            download_repos(TOOLS_ASSET),
            vec![TOOLS_REPO, EXT_REPO],
            "tiptop 应先找 tiptop 仓库，再退回本扩展"
        );
        // 兜底仓库必须是本扩展自己，否则"扩展 Release 兜底"就落空了
        assert_eq!(EXT_REPO, "darcyjoven/zed-bdl");
    }

    #[test]
    fn own_release_uses_the_same_asset_names_as_backends() {
        // 本扩展的 Release 里带的是**同名**资产（bdl-lsp-<os>-<arch>.<ext>），
        // 所以扩展对"后端 Release"和"本扩展 Release"用同一套 asset_name_for 即可。
        // 这条测试锁住"资产名只由前缀+平台决定"，一旦改名会红。
        use zed::{Architecture::*, Os::*};
        assert_eq!(
            asset_name_for(LSP_ASSET, Linux, X8664).as_deref(),
            Some("bdl-lsp-linux-amd64.tar.gz")
        );
        assert_eq!(
            asset_name_for(TOOLS_ASSET, Linux, X8664).as_deref(),
            Some("tiptop-linux-amd64.tar.gz")
        );
        // 两个仓库用的是同一套资产名 → 同一个 asset_name_for 产出相同结果
        assert_eq!(
            asset_name_for(LSP_ASSET, Mac, Aarch64),
            asset_name_for(LSP_ASSET, Mac, Aarch64)
        );
    }

    #[test]
    fn windows_binary_has_exe_suffix() {
        assert_eq!(binary_file_name("bdl-lsp", zed::Os::Windows), "bdl-lsp.exe");
        assert_eq!(binary_file_name("bdl-lsp", zed::Os::Linux), "bdl-lsp");
    }
}