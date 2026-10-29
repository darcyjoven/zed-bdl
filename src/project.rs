//! 读取 `<项目根>/.project/` 下的资料，渲染成 Agent 面板可读的文本。
//!
//! ## 为什么扩展自己读文件
//!
//! Zed 扩展**发不了 LSP 自定义请求**（`Extension` trait 无 `send_request`），
//! 所以拿不到 `bdl/schemaTables` / `bdl/linkTree` 的返回值；而 `.project/` 下的
//! 资料是 `tiptop` 写的**纯文件**、`bdl-lsp` 只读——扩展直接读它是零依赖、
//! 也不会与后端耦合的做法。代价是：这里只能做"资料状态的只读展示"，
//! 真正的语义视图（Code Lens 等）仍然要服务端实现（PLAN Z-P3-3）。
//!
//! 资料格式（权威来源：bdl-lsp/link/link.go、bdl-lsp/internal/schema/schema.go）：
//! - `.project/link/links.meta.json`：schema/generatedAt/source/chains/orphans/ambiguous/
//!   missingFiles/partial/externals…
//! - `.project/link/links.jsonl`：每行一条链 `{schema,program,module,main,files:[[模组,代码]…]}`
//! - `.project/schema/tables.json`：`{schema,importedAt,source,rowsTotal,tables:{名:{name,desc,columns,file}}}`
//! - `.project/schema/tables/<大写表名>.json`：`{table,desc,columns:[{name,desc,type,length,…}]}`

use zed_extension_api as zed;
use zed::serde_json::{Map, Value};

/// 链接资料元数据（tiptop 写，bdl-lsp 只读）。
pub const LINK_META: &str = ".project/link/links.meta.json";
/// 链接资料本体（每行一条链）。
pub const LINKS_JSONL: &str = ".project/link/links.jsonl";
/// 字段资料索引。
pub const SCHEMA_INDEX: &str = ".project/schema/tables.json";
/// 字段资料每表一个文件。
pub const SCHEMA_TABLES_DIR: &str = ".project/schema/tables";

/// 表清单一次最多列多少行（Agent 面板不适合长列表）。
const TABLE_LIMIT: usize = 200;

/// 链接资料状态（`/bdl-link-status`）。
pub fn link_status(worktree: &zed::Worktree) -> String {
    let Some(meta_text) = read_text(worktree, LINK_META) else {
        return format!(
            "还没有链接资料：找不到 {LINK_META}\n\
             \n\
             采集方式（task: spawn → 搜 `4gl:`）：\n\
             - `4gl: 链接资料：从 CSV 导入`（有 DS.GAL_FILE 导出时）\n\
             - `4gl: 链接资料：全量更新`（直连 Oracle 时）\n\
             \n\
             采完之后 `bdl-lsp` 会按 mtime 热重载，不用重启编辑器。"
        );
    };
    let Ok(meta) = zed::serde_json::from_str::<Value>(&meta_text) else {
        return format!("{LINK_META} 不是合法 JSON，可能写了一半；重新采集一次即可。");
    };

    let mut out = String::from("== 链接资料 ==\n");
    push(&mut out, "数据目录", ".project/link");
    push_num(&mut out, "链", &meta, "chains");
    push_num(&mut out, "orphan（无 MAIN）", &meta, "orphans");
    push_num(&mut out, "ambiguous（多 MAIN）", &meta, "ambiguous");
    push_num(&mut out, "缺失文件", &meta, "missingFiles");
    push_str(&mut out, "生成时间", &meta, "generatedAt");
    if let Some(source) = str_of(&meta, "source") {
        let detail = str_of(&meta, "sourceDetail").unwrap_or_default();
        let line = if detail.is_empty() {
            source.to_string()
        } else {
            format!("{source}（{detail}）")
        };
        push(&mut out, "来源", &line);
    }

    if let Some(partial) = meta.get("partial").filter(|v| v.is_object()) {
        let n = partial
            .get("files")
            .and_then(|v| v.as_array())
            .map(|a| a.len())
            .unwrap_or(0);
        push(
            &mut out,
            "局部更新",
            &format!(
                "是（{n} 个文件；generatedAt 不代表全部内容的新鲜度）"
            ),
        );
    }

    if let Some(text) = read_text(worktree, LINKS_JSONL) {
        let stats = parse_links_jsonl(&text);
        push(&mut out, "链内文件", &format!("{} 个（去重后）", stats.len()));
        let bytes = text.len();
        push(
            &mut out,
            "资料文件",
            &format!("{LINKS_JSONL}（{}）", human_bytes(bytes)),
        );
    }

    out.push_str(
        "\n查看某个程序的链接关系：Code Lens（PLAN Z-P3-3）落地后挂在 MAIN 函数头上；\n\
         当前可用替代：task `4gl: 链接关系（终端清单）`（P2）。",
    );
    out
}

/// 字段资料状态（`/bdl-schema-status`）。
pub fn schema_status(worktree: &zed::Worktree) -> String {
    let Some(index) = read_index(worktree) else {
        return format!(
            "还没有字段资料：找不到 {SCHEMA_INDEX}\n\
             \n\
             采集方式（task: spawn → 搜 `4gl:`）：\n\
             - `4gl: 字段资料：从 CSV 导入`（DBA 导出的列清单）\n\
             - `4gl: 字段资料：从数据库同步`（直连 Oracle，分批 200 张/批）"
        );
    };
    let tables = tables_map(&index);
    let columns: usize = tables
        .values()
        .filter_map(|t| t.get("columns").and_then(|v| v.as_u64()))
        .map(|n| n as usize)
        .sum();

    let mut out = String::from("== 字段资料 ==\n");
    push(&mut out, "数据目录", ".project/schema");
    push(&mut out, "表", &tables.len().to_string());
    push(&mut out, "列", &columns.to_string());
    push_str(&mut out, "导入时间", &index, "importedAt");
    push_str(&mut out, "来源", &index, "source");
    push_num(&mut out, "原始行数", &index, "rowsTotal");
    out.push_str(
        "\n查看列清单：`/bdl-schema-columns <表名>`；悬停字段与 `RECORD LIKE t.*` \n\
         的成员校验由 bdl-lsp 直接提供（把 link.mode / schema.mode 设成 file 或 db）。",
    );
    out
}

/// 表清单（`/bdl-schema-tables [过滤]`）。
pub fn schema_tables(worktree: &zed::Worktree, filter: Option<&str>) -> String {
    let Some(index) = read_index(worktree) else {
        return format!("还没有字段资料：找不到 {SCHEMA_INDEX}（先采集一次）。");
    };
    let tables = tables_map(&index);
    let filter = filter.map(str::trim).filter(|f| !f.is_empty());

    let mut names: Vec<String> = tables.keys().cloned().collect();
    names.sort();
    let matched: Vec<&String> = names
        .iter()
        .filter(|name| filter.map_or(true, |f| matches_filter(name.as_str(), f)))
        .collect();

    let mut out = String::new();
    if let Some(f) = filter {
        out.push_str(&format!(
            "== 表清单（过滤：{f}，共 {} / {}）==\n",
            matched.len(),
            names.len()
        ));
    } else {
        out.push_str(&format!("== 表清单（共 {}）==\n", names.len()));
    }

    for name in matched.iter().take(TABLE_LIMIT) {
        let entry = &tables[name.as_str()];
        let desc = str_of(entry, "desc").unwrap_or_default();
        let cols = entry
            .get("columns")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        if desc.is_empty() {
            out.push_str(&format!("{name}  ({cols} 列)\n"));
        } else {
            out.push_str(&format!("{name}  {desc}  ({cols} 列)\n"));
        }
    }
    if matched.len() > TABLE_LIMIT {
        out.push_str(&format!(
            "\n…只显示前 {TABLE_LIMIT} 条，共 {} 条。请加过滤参数收窄（如 `/bdl-schema-tables ^APF`）。",
            matched.len()
        ));
    }
    if matched.is_empty() {
        out.push_str("\n没有匹配的表。过滤是**大小写不敏感子串**，可用 `^前缀` / `后缀$` 两种锚点。\n");
    } else {
        out.push_str(
            "\n过滤语法：大小写不敏感子串；`^APF` = 以 APF 开头；`0$` = 以 0 结尾。\n\
             （VSCode 树视图支持完整正则，Zed 侧 slash command 只做子串 + 两个锚点。）",
        );
    }
    out
}

/// 列清单（`/bdl-schema-columns <表名>`）。
pub fn schema_columns(worktree: &zed::Worktree, table: &str) -> String {
    let table = table.trim();
    if table.is_empty() {
        return "用法：/bdl-schema-columns <表名>".to_string();
    }
    let index = read_index(worktree);
    let upper = table.to_uppercase();
    let rel = format!("{SCHEMA_TABLES_DIR}/{upper}.json");
    let Some(text) = read_text(worktree, &rel) else {
        let hint = index
            .as_ref()
            .and_then(|i| tables_map(i).get(&upper).cloned())
            .and_then(|t| str_of(&t, "file").map(|s| s.to_string()))
            .unwrap_or_else(|| rel.clone());
        return format!(
            "找不到表 {upper} 的资料文件（试过 {rel}，索引里的路径是 {hint}）。\n\
             用 `/bdl-schema-tables` 看有哪些表，或重新采集一次。"
        );
    };
    let Ok(value) = zed::serde_json::from_str::<Value>(&text) else {
        return format!("{rel} 不是合法 JSON。");
    };

    let mut out = format!("== {upper} 的列 ==\n");
    if let Some(desc) = str_of(&value, "desc") {
        out.push_str(&format!("{desc}\n"));
    }
    let cols = value
        .get("columns")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();
    out.push_str(&format!("共 {} 列\n\n", cols.len()));
    for col in &cols {
        let name = str_of(col, "name").unwrap_or("?");
        let ty = str_of(col, "type").unwrap_or("");
        let char_len = col.get("charLength").and_then(|v| v.as_u64()).unwrap_or(0);
        let len = col.get("length").and_then(|v| v.as_u64()).unwrap_or(0);
        let size = if char_len > 0 { char_len } else { len };
        let desc = str_of(col, "desc").unwrap_or("");
        let nullable = col
            .get("nullable")
            .and_then(|v| v.as_bool())
            .unwrap_or(false);
        let null = if nullable { " NULL" } else { "" };
        let size = if size > 0 {
            format!("({size})")
        } else {
            String::new()
        };
        out.push_str(&format!("{name}  {ty}{size}{null}  {desc}\n"));
    }
    out.push_str("\n复制列定义可用 `LIKE 表.列`（VSCode 的「复制列定义」命令在 Zed 上无等价入口）。");
    out
}

/// 从 `links.jsonl` 统计去重后的文件键（`模组/代码`，全小写）。
///
/// 纯函数，便于单测：坏行直接跳过（资料可能是旧格式或写了一半）。
fn parse_links_jsonl(text: &str) -> std::collections::BTreeSet<String> {
    let mut files = std::collections::BTreeSet::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(chain) = zed::serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(list) = chain.get("files").and_then(|v| v.as_array()) else {
            continue;
        };
        for entry in list {
            let Some(pair) = entry.as_array() else { continue };
            let module = pair.first().and_then(|v| v.as_str()).unwrap_or("");
            let code = pair.get(1).and_then(|v| v.as_str()).unwrap_or("");
            if !module.is_empty() || !code.is_empty() {
                files.insert(format!("{}/{}", module.to_lowercase(), code.to_lowercase()));
            }
        }
    }
    files
}

/// 表名过滤：大小写不敏感子串，支持 `^前缀` / `后缀$`。
fn matches_filter(name: &str, filter: &str) -> bool {
    let name = name.to_lowercase();
    let f = filter.to_lowercase();
    let prefix = f.starts_with('^');
    let suffix = f.ends_with('$');
    let core = f.trim_start_matches('^').trim_end_matches('$');
    if core.is_empty() {
        return true;
    }
    let hit = name.contains(core);
    if prefix && !name.starts_with(core) {
        return false;
    }
    if suffix && !name.ends_with(core) {
        return false;
    }
    hit
}

fn read_text(worktree: &zed::Worktree, relative: &str) -> Option<String> {
    worktree.read_text_file(relative).ok()
}

/// 读字段资料索引；顺带兼容 `tables.json` 缺失时的空对象。
fn read_index(worktree: &zed::Worktree) -> Option<Value> {
    let text = read_text(worktree, SCHEMA_INDEX)?;
    zed::serde_json::from_str::<Value>(&text).ok()
}

fn tables_map(index: &Value) -> Map<String, Value> {
    index
        .get("tables")
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default()
}

fn str_of<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key)?.as_str().filter(|s| !s.is_empty())
}

fn push(out: &mut String, label: &str, value: &str) {
    out.push_str(&format!("{label:<14} {value}\n"));
}

fn push_str(out: &mut String, label: &str, value: &Value, key: &str) {
    if let Some(v) = str_of(value, key) {
        push(out, label, v);
    }
}

fn push_num(out: &mut String, label: &str, value: &Value, key: &str) {
    if let Some(n) = value.get(key).and_then(|v| v.as_u64()) {
        push(out, label, &n.to_string());
    }
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
    fn jsonl_parsing_dedupes_and_survives_bad_lines() {
        let text = concat!(
            r#"{"schema":1,"program":"A","files":[["APF","main"],["APF","sub"]]}"#,
            "\n",
            "这不是 JSON\n",
            r#"{"schema":1,"program":"B","files":[["apf","MAIN"],["X","y"]]}"#,
            "\n",
        );
        let files = parse_links_jsonl(text);
        assert_eq!(
            files.into_iter().collect::<Vec<_>>(),
            vec!["apf/main", "apf/sub", "x/y"]
        );
    }

    #[test]
    fn filter_matches_substring_and_anchors() {
        assert!(matches_filter("APF001", "apf"));
        assert!(matches_filter("APF001", "^apf"));
        assert!(!matches_filter("XAPF001", "^apf"));
        assert!(matches_filter("APF001", "001$"));
        assert!(!matches_filter("APF001X", "001$"));
        assert!(matches_filter("APF001", "^APF001$"));
        assert!(!matches_filter("APF001", "^001"));
        assert!(matches_filter("APF001", "^$")); // 只写锚点 = 不过滤
    }

    #[test]
    fn human_bytes_rounds_sensibly() {
        assert_eq!(human_bytes(500), "500 B");
        assert_eq!(human_bytes(2048), "2 KB");
        assert_eq!(human_bytes(3 * 1024 * 1024), "3.0 MB");
    }
}