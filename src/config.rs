//! 配置读取与下发。
//!
//! ## 为什么需要这一层（2026-10-28 核实的关键事实）
//!
//! Zed 把 `lsp.<server>.settings` 只在**服务端请求 `workspace/configuration`** 时
//! 作为应答下发；而 `bdl-lsp` **从不发这个请求**（配置只认 `initialize` 的
//! `initializationOptions` 与客户端主动的 `workspace/didChangeConfiguration`）。
//! 也就是说：只写 `lsp.bdl-lsp.settings` 等于没写。
//!
//! 所以扩展在启动时把三层合并后从 `initializationOptions` 下发：
//!
//! ```text
//! initialization_options（逃生口，最高）
//!   ⊕ settings（去掉仅扩展自用的 ext）
//!   ⊕ 轻量档默认（link/schema 未配置时补 mode="off"）
//! ```
//!
//! 同一份合并结果也作为 `workspace/configuration` 的应答返回，这样等 `bdl-lsp`
//! 支持 `workspace/configuration`（PLAN Z-P3-1）后无需再改扩展。
//!
//! ## 轻量档默认
//!
//! `bdl-lsp` 的 `LinkEnabled()` / `SchemaEnabled()` 在客户端**未下发**时返回
//! `true`；VSCode 侧靠设置默认值 `mode:"off"` 才实现"轻量档"。我们在这里补同样的
//! 默认值，但**只在用户既没写 `mode` 也没写 `enable` 时**补，避免覆盖显式配置。
//!
//! ## ext 子树
//!
//! 只属于 Zed 扩展的配置（tiptop 路径、生产环境、部署/编译模板）收在
//! `lsp.bdl-lsp.settings.ext` 下，**不下发给 LSP**，服务端也不会因此报错。

use zed_extension_api as zed;

use zed::serde_json::{json, Map, Value};

/// 语言服务器在 `extension.toml` 里注册的 key。
pub const SERVER_ID: &str = "bdl-lsp";

/// 从 Zed 设置解析出的、本扩展关心的全部内容。
pub struct Settings {
    /// 下发给 `bdl-lsp` 的有效配置（已去掉 `ext`、已补轻量档默认）。
    pub lsp: Value,
    /// 仅扩展自用的 `ext` 子树；用户没写时是空对象（不是 null），方便直接取值。
    pub ext: Value,
    /// `lsp.bdl-lsp.binary.arguments`（Zed 原生键）。
    pub arguments: Vec<String>,
    /// `lsp.bdl-lsp.binary.env`（Zed 原生键）。
    pub env: Vec<(String, String)>,
    /// `lsp.bdl-lsp.binary.path`（Zed 原生键）；空串视为未设置。
    pub path: Option<String>,
}

impl Settings {
    /// 语言服务器日志级别；`info` 是 `bdl-lsp` 的默认值，返回 `None` 表示不用加参数。
    pub fn log_level(&self) -> Option<String> {
        let level = self.lsp.get("logLevel")?.as_str()?.trim();
        if level.is_empty() || level == "info" {
            return None;
        }
        Some(level.to_string())
    }

    /// 按路径读 `ext` 里的字符串（如 `["tools","path"]`）。
    pub fn ext_str(&self, path: &[&str]) -> Option<String> {
        let mut cur = &self.ext;
        for key in path {
            cur = cur.get(*key)?;
        }
        let s = cur.as_str()?.trim();
        if s.is_empty() {
            None
        } else {
            Some(s.to_string())
        }
    }
}

/// 读取并合并配置。
pub fn load(worktree: &zed::Worktree) -> Settings {
    let ls = zed::settings::LspSettings::for_worktree(SERVER_ID, worktree).ok();

    let mut user = ls.as_ref().and_then(|s| s.settings.clone());
    let init = ls.as_ref().and_then(|s| s.initialization_options.clone());
    let binary = ls.as_ref().and_then(|s| s.binary.as_ref());

    // ext 优先取 settings.ext，其次取 initialization_options.ext（逃生口也支持）。
    let ext = user
        .as_ref()
        .and_then(|v| v.get("ext"))
        .or_else(|| init.as_ref().and_then(|v| v.get("ext")))
        .cloned()
        .filter(Value::is_object)
        .unwrap_or_else(|| json!({}));

    let mut lsp = Value::Object(Map::new());
    if let Some(ref mut u) = user {
        remove_ext(u);
    }
    merge(&mut lsp, &user.clone().unwrap_or_else(|| json!({})));
    merge(&mut lsp, &init.clone().unwrap_or_else(|| json!({})));
    apply_light_defaults(&mut lsp);

    Settings {
        lsp,
        ext,
        arguments: binary
            .and_then(|b| b.arguments.clone())
            .unwrap_or_default(),
        env: binary
            .and_then(|b| b.env.clone())
            .unwrap_or_default()
            .into_iter()
            .collect(),
        path: binary
            .and_then(|b| b.path.clone())
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty()),
    }
}

/// 深合并：对象逐键递归，其余类型直接覆盖（后写的赢）。
fn merge(base: &mut Value, over: &Value) {
    match (base, over) {
        (Value::Object(base_map), Value::Object(over_map)) => {
            for (key, value) in over_map {
                match base_map.get_mut(key) {
                    Some(slot) => merge(slot, value),
                    None => {
                        base_map.insert(key.clone(), value.clone());
                    }
                }
            }
        }
        (base, over) => *base = over.clone(),
    }
}

/// 去掉仅扩展自用的 `ext`，避免把私货发给语言服务器。
fn remove_ext(value: &mut Value) {
    if let Value::Object(map) = value {
        map.remove("ext");
    }
}

/// 轻量档默认：`link`/`schema` 没有任何显式配置时补 `mode:"off"`。
fn apply_light_defaults(cfg: &mut Value) {
    let Some(map) = cfg.as_object_mut() else {
        return;
    };
    for section in ["link", "schema"] {
        let entry = map.entry(section.to_string()).or_insert_with(|| json!({}));
        if !entry.is_object() {
            *entry = json!({});
        }
        let Some(section_map) = entry.as_object_mut() else {
            continue;
        };
        let has_mode = section_map
            .get("mode")
            .and_then(|v| v.as_str())
            .map(|s| !s.trim().is_empty())
            .unwrap_or(false);
        let has_enable = section_map.contains_key("enable");
        if !has_mode && !has_enable {
            section_map.insert("mode".to_string(), Value::String("off".to_string()));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deep_merge_overrides_scalars_and_keeps_siblings() {
        let mut base = json!({"a": {"b": 1, "c": 2}, "d": 1});
        merge(&mut base, &json!({"a": {"b": 9}, "e": 3}));
        assert_eq!(base, json!({"a": {"b": 9, "c": 2}, "d": 1, "e": 3}));
    }

    #[test]
    fn ext_is_stripped_before_sending() {
        let mut v = json!({"logLevel": "debug", "ext": {"tools": {"path": "/x"}}});
        remove_ext(&mut v);
        assert_eq!(v, json!({"logLevel": "debug"}));
    }

    #[test]
    fn light_defaults_fill_only_when_absent() {
        let mut cfg = json!({});
        apply_light_defaults(&mut cfg);
        assert_eq!(cfg, json!({"link": {"mode": "off"}, "schema": {"mode": "off"}}));

        // 用户显式配置不能被覆盖：mode 优先
        let mut cfg = json!({"link": {"mode": "file"}, "schema": {"enable": true}});
        apply_light_defaults(&mut cfg);
        assert_eq!(cfg, json!({"link": {"mode": "file"}, "schema": {"enable": true}}));
    }
}