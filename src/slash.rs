//! Slash command（Agent 面板 `/bdl-…`）。
//!
//! Zed 扩展**不能注册命令到命令面板**（`Extension` trait 无该 API），
//! slash command 是"只读短查询"的入口；会写盘 / 长任务 / 需要交互输入的操作
//! 一律走 task（见 `docs/USER-GUIDE.md` §8.4）。
//!
//! 约定：
//! - 名称必须与 `extension.toml` 的 `[slash_commands.*]` 一一对应；
//!   `tests/verify-manifest.py` 会静态校验 `SLASH_COMMANDS` 与清单是否一致
//!   （写错的后果是"编译通过、命令静默不响应"）。
//! - 这里只读 `.project/` 资料、跑 `tiptop`/`bdl-lsp` 的**只读子命令**；
//!   不写任何文件。

use zed_extension_api as zed;

use crate::binary;
use crate::config;
use crate::project;

/// 与 `extension.toml` 的 `[slash_commands.*]` 一一对应（校验脚本会读这里）。
pub const SLASH_COMMANDS: &[&str] = &[
    "bdl-env-check",
    "bdl-link-status",
    "bdl-link-chain",
    "bdl-schema-status",
    "bdl-schema-tables",
    "bdl-schema-columns",
    "bdl-deploy-list",
    "bdl-deploy-dry-run",
    "bdl-force-parse",
];

/// 执行一条 slash command。
pub fn run(
    command: &str,
    args: &[String],
    worktree: Option<&zed::Worktree>,
) -> Result<zed::SlashCommandOutput, String> {
    // 清单与实现的一致性由 verify-manifest.py 静态校验；这里再做一次运行时兜底，
    // 避免"声明了但没实现"时走进 default 分支给出含糊错误。
    if !SLASH_COMMANDS.contains(&command) {
        return Err(format!(
            "未知的 slash command：/{command}（已实现：{}）",
            SLASH_COMMANDS.join(", ")
        ));
    }
    // 唯一不需要项目（worktree）的命令：它只返回"当前还不能用 + 替代办法"。
    if command == "bdl-force-parse" {
        return Ok(output(
            "强制解析当前文件需要语言服务器提供 `workspace/executeCommand`\n\
             （PLAN Z-P3-2，尚未落地）。\n\
             \n\
             当前替代办法（任选）：\n\
             1. 改一下文件并保存，让后台解析重新跑一次；\n\
             2. 在终端跑 `bdl-lsp check <文件>` 看语法问题；\n\
             3. 等 P3 落地后本命令自动可用。"
                .to_string(),
        ));
    }
    let worktree = worktree.ok_or_else(|| {
        format!(
            "/{command} 需要一个已打开的项目（worktree）；\n\
             请先在 Zed 里打开包含 .4gl 的项目目录。"
        )
    })?;
    let settings = config::load(worktree);

    let text = match command {
        "bdl-env-check" => env_check(worktree, &settings),
        "bdl-link-status" => project::link_status(worktree),
        "bdl-link-chain" => {
            let Some(code) = args.first() else {
                return Ok(output(
                    "用法：/bdl-link-chain <程序代码>（如 axmt620；也可写 模组/代码 或带 .4gl 后缀）\n\
                     这是链接关系视图的替代：看某个程序在 links.jsonl 里属于哪条链、链内有哪些文件。"
                        .to_string(),
                ));
            };
            project::link_chain(worktree, code)
        }
        "bdl-schema-status" => project::schema_status(worktree),
        "bdl-schema-tables" => project::schema_tables(worktree, args.first().map(|s| s.as_str())),
        "bdl-schema-columns" => {
            let Some(table) = args.first() else {
                return Ok(zed::SlashCommandOutput {
                    text: "用法：/bdl-schema-columns <表名>（表名大写小写都可以）".to_string(),
                    sections: Vec::new(),
                });
            };
            project::schema_columns(worktree, table)
        }
        "bdl-deploy-list" => cli(&settings, worktree, &["deploy", "--list"]),
        "bdl-deploy-dry-run" => cli(&settings, worktree, &["deploy", "--dry-run"]),
        other => return Err(format!("未知的 slash command：/{other}")),
    };

    Ok(output(text))
}

/// 统一的返回包装（sections 留给以后做高亮分区）。
fn output(text: String) -> zed::SlashCommandOutput {
    zed::SlashCommandOutput {
        text,
        sections: Vec::new(),
    }
}

/// `/bdl-env-check`：把"生效了什么、二进制在哪、资料有没有"一次列清。
fn env_check(worktree: &zed::Worktree, settings: &config::Settings) -> String {
    let mut out = String::from("== 4gl 环境自检 ==\n");
    push(&mut out, "项目根", &worktree.root_path());
    push(
        &mut out,
        "链接资料",
        &format!(
            "mode={}  dataDir={}",
            str_at(&settings.lsp, &["link", "mode"]).unwrap_or("off(默认)"),
            str_at(&settings.lsp, &["link", "dataDir"]).unwrap_or(".project/link")
        ),
    );
    push(
        &mut out,
        "字段资料",
        &format!(
            "mode={}  dataDir={}",
            str_at(&settings.lsp, &["schema", "mode"]).unwrap_or("off(默认)"),
            str_at(&settings.lsp, &["schema", "dataDir"]).unwrap_or(".project/schema")
        ),
    );
    push(
        &mut out,
        "Genero 版本",
        str_at(&settings.lsp, &["generoVersion"]).unwrap_or("2.50(默认)"),
    );
    push(
        &mut out,
        "日志级别",
        str_at(&settings.lsp, &["logLevel"]).unwrap_or("info(默认)"),
    );

    // 二进制：路径 + 版本（版本用只读子命令实跑）
    let mut warnings = Vec::new();
    match binary::resolve_tools(worktree, settings) {
        Ok(path) => {
            let version = cli_text(&path, &["version"]);
            push(&mut out, "tiptop", &format!("{path}  [{version}]"));
            if let Some(warn) = version_warning("tiptop", &version, MIN_TIPTOP) {
                warnings.push(warn);
            }
        }
        Err(err) => push(&mut out, "tiptop", &format!("找不到：{err}")),
    }
    match binary::resolve_lsp(worktree, settings, None) {
        Ok(cmd) => {
            let version = cli_text(&cmd.command, &["version"]);
            push(&mut out, "bdl-lsp", &format!("{}  [{version}]", cmd.command));
            if let Some(warn) = version_warning("bdl-lsp", &version, MIN_BDL_LSP) {
                warnings.push(warn);
            }
        }
        Err(err) => push(&mut out, "bdl-lsp", &format!("找不到：{err}")),
    }

    // Z-P4-4：版本兼容提示（只在低于最低要求时提醒，不做硬拦）。
    if !warnings.is_empty() {
        out.push('\n');
        for warn in &warnings {
            out.push_str(&format!("⚠️ {warn}\n"));
        }
    }

    // 资料是否存在（只判断文件，不解析全部内容）
    push(
        &mut out,
        "链接资料文件",
        &exists(worktree, project::LINK_META),
    );
    push(
        &mut out,
        "字段资料文件",
        &exists(worktree, project::SCHEMA_INDEX),
    );

    out.push_str("\n生效配置（下发给 bdl-lsp 的 initializationOptions）：\n");
    out.push_str(&settings.lsp.to_string());
    out.push_str(
        "\n\n提示：`lsp.bdl-lsp.settings` 里的内容会合并到这里；`ext` 子树不下发给服务端。\n\
         改配置后需要重启语言服务器（等 PLAN Z-P3-1 落地才支持热更新）。",
    );
    out
}

/// 调 `tiptop` 的只读/预演子命令，把 stdout 原样返回。
fn cli(settings: &config::Settings, worktree: &zed::Worktree, args: &[&str]) -> String {
    let tools = match binary::resolve_tools(worktree, settings) {
        Ok(path) => path,
        Err(err) => return format!("{err}\n\n（该命令需要 tiptop。）"),
    };
    let mut full: Vec<&str> = args.to_vec();
    let root_owned = worktree.root_path();
    if args.first() == Some(&"deploy") {
        full.extend_from_slice(&["--workspace", &root_owned]);
    }
    match zed::process::Command::new(&tools)
        .args(full.iter().copied())
        .output()
    {
        Ok(output) => render_output(&output),
        Err(err) => format!(
            "执行 {tools} 失败：{err}\n\
             \n\
             如果提示 capability，请在 Zed 设置里放行本扩展的 process:exec：\n\
             `\"granted_extension_capabilities\": [{{\"kind\": \"process:exec\", \"command\": \"*\", \"args\": [\"**\"]}}]`"
        ),
    }
}

/// 跑一个只读子命令并返回单行摘要（失败时给出简短原因）。
fn cli_text(bin: &str, args: &[&str]) -> String {
    match zed::process::Command::new(bin)
        .args(args.iter().copied())
        .output()
    {
        Ok(output) => {
            let text = render_output(&output);
            text.lines().next().unwrap_or("(无输出)").to_string()
        }
        Err(err) => format!("无法执行：{err}"),
    }
}

fn render_output(output: &zed::process::Output) -> String {
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let mut text = String::new();
    if stdout.trim().is_empty() && stderr.trim().is_empty() {
        text.push_str("(没有输出)");
    } else {
        if !stdout.trim().is_empty() {
            text.push_str(stdout.trim_end());
        }
        if !stderr.trim().is_empty() {
            if !text.is_empty() {
                text.push('\n');
            }
            text.push_str("--- stderr ---\n");
            text.push_str(stderr.trim_end());
        }
    }
    if output.status != Some(0) {
        text.push_str(&format!("\n\n退出码：{:?}", output.status));
    }
    text
}

/// 最低要求：`bdl-lsp` 0.3.13（更旧的版本没有 0.3.2 起移出到 tiptop 的命令语义与
/// `link.mode` 三态；本扩展的配置键按 0.3.13+ 的形状下发）。
const MIN_BDL_LSP: (u32, u32, u32) = (0, 3, 13);
/// 最低要求：`tiptop` 0.1.10（更旧的版本缺 `download`、`-region`、`-login-profile`）。
const MIN_TIPTOP: (u32, u32, u32) = (0, 1, 10);

/// 从 `version` 输出里解析版本号（`tiptop 0.1.10` / `bdl-lsp 0.3.14` / `0.1.10-rc1`）。
fn parse_version(output: &str) -> Option<(u32, u32, u32)> {
    let start = output.find(|c: char| c.is_ascii_digit())?;
    let tail = &output[start..];
    let mut numbers = Vec::new();
    for part in tail.split(|c: char| !c.is_ascii_digit()).take(3) {
        if part.is_empty() {
            break;
        }
        numbers.push(part.parse::<u32>().ok()?);
    }
    match numbers.len() {
        0 => None,
        1 => Some((numbers[0], 0, 0)),
        2 => Some((numbers[0], numbers[1], 0)),
        _ => Some((numbers[0], numbers[1], numbers[2])),
    }
}

/// 低于最低要求时返回一句提醒（无法解析版本就不提醒）。
fn version_warning(name: &str, output: &str, min: (u32, u32, u32)) -> Option<String> {
    let got = parse_version(output)?;
    if got >= min {
        return None;
    }
    Some(format!(
        "{name} {}.{}.{} 低于最低要求 {}.{}.{}：更旧的版本缺 `download` / `-region` / `-login-profile` \n\
         或 `link.mode` 三态等能力，建议升级（删掉旧二进制后扩展会自动下载最新版，或设置 ext.tools.path）。",
        got.0, got.1, got.2, min.0, min.1, min.2
    ))
}

fn exists(worktree: &zed::Worktree, relative: &str) -> String {
    match worktree.read_text_file(relative) {
        Ok(text) => format!("有（{relative}，{}）", human_bytes(text.len())),
        Err(_) => format!("没有（{relative}）"),
    }
}

fn str_at<'a>(value: &'a zed::serde_json::Value, path: &[&str]) -> Option<&'a str> {
    let mut cur = value;
    for key in path {
        cur = cur.get(*key)?;
    }
    cur.as_str().filter(|s| !s.is_empty())
}

fn push(out: &mut String, label: &str, value: &str) {
    out.push_str(&format!("{label:<16} {value}\n"));
}

fn human_bytes(bytes: usize) -> String {
    const KB: usize = 1024;
    const MB: usize = 1024 * KB;
    if bytes >= MB {
        format!("{:.1} MB", bytes as f64 / MB as f64)
    } else if bytes >= KB {
        format!("{:.0} KB", bytes as f64 / KB as f64)
    } else {
        format!("{bytes} B")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_version_handles_real_outputs() {
        assert_eq!(parse_version("tiptop 0.1.10"), Some((0, 1, 10)));
        assert_eq!(parse_version("bdl-lsp 0.3.14"), Some((0, 3, 14)));
        assert_eq!(parse_version("0.1.10-rc1"), Some((0, 1, 10)));
        assert_eq!(parse_version("tiptop 1.2"), Some((1, 2, 0)));
        assert_eq!(parse_version("无法执行：找不到文件"), None);
    }

    #[test]
    fn version_warning_only_below_minimum() {
        assert!(version_warning("tiptop", "tiptop 0.1.8", MIN_TIPTOP).is_some());
        assert!(version_warning("tiptop", "tiptop 0.1.10", MIN_TIPTOP).is_none());
        assert!(version_warning("bdl-lsp", "bdl-lsp 0.3.13", MIN_BDL_LSP).is_none());
        assert!(version_warning("bdl-lsp", "bdl-lsp 0.3.9", MIN_BDL_LSP).is_some());
        // 解析不出就不打扰用户
        assert!(version_warning("bdl-lsp", "无法执行：没有这个文件", MIN_BDL_LSP).is_none());
    }
}
