//! 版本号解析（`tiptop 0.1.10` / `bdl-lsp 0.3.14` / `0.1.10-rc1` / 目录名里的 `0.3.14`）。
//!
//! 两个用途：
//!   - `slash.rs`：`/bdl-env-check` 判断二进制是否低于最低要求；
//!   - `download.rs`：在缓存的多个版本目录里挑**最新**的一个，避免每次启动都去查 GitHub。
//!
//! 只做"够用"的解析：取第一个数字开始的三段数字，缺的补 0；解析不出返回 `None`。

/// 解析成 `(major, minor, patch)`；解析不出返回 `None`。
pub fn parse(text: &str) -> Option<(u32, u32, u32)> {
    let start = text.find(|c: char| c.is_ascii_digit())?;
    let tail = &text[start..];
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_real_world_outputs() {
        assert_eq!(parse("tiptop 0.1.10"), Some((0, 1, 10)));
        assert_eq!(parse("bdl-lsp 0.3.14"), Some((0, 3, 14)));
        assert_eq!(parse("0.1.10-rc1"), Some((0, 1, 10)));
        assert_eq!(parse("tiptop 1.2"), Some((1, 2, 0)));
        assert_eq!(parse("tiptop 2"), Some((2, 0, 0)));
        assert_eq!(parse("无法执行：找不到文件"), None);
    }

    #[test]
    fn parses_directory_names() {
        assert_eq!(parse("bdl-lsp-0.3.14"), Some((0, 3, 14)));
        assert_eq!(parse("tiptop-0.1.10"), Some((0, 1, 10)));
    }

    #[test]
    fn ordering_of_versions_is_numeric_not_lexicographic() {
        // "0.3.9" 必须排在 "0.3.14" 之前（字符串排序会反）
        assert!(parse("0.3.9").unwrap() < parse("0.3.14").unwrap());
        assert!(parse("0.1.10").unwrap() > parse("0.1.9").unwrap());
    }
}