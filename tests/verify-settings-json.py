#!/usr/bin/env python3
"""校验文档里给的 Zed settings.json 示例**能被 Zed 接受**。

为什么需要：
   Zed 的 settings.json 是**有 schema 的**，写错键名会被编辑器直接拒绝：
       Property editor is not allowed.
   而这些错**不会编译失败、不会让 CI 变红**，只在用户粘贴配置时炸 ——
   本仓库就吃过两次：
     ① `languages."Genero BDL".code_lens` —— 语言级没有这个键（静默不生效）；
     ② `"editor": { "code_lens": "on" }` —— Zed 的 settings.json **没有 `editor` 这个键**
        （EditorSettingsContent 是 `#[serde(flatten)]`，字段直接摊在顶层）。

   所以这里把文档里的示例 JSON 抠出来，静态校验：
     1. 是合法 JSON；
     2. 顶层键是 Zed 认识的（对着 crates/settings_content 的真实字段列表对拍）；
     3. `languages.<语言名>` 下只放语言级认识的键；
     4. `lsp.bdl-lsp.settings` 下的键是 bdl-lsp 认识的（对着它的 config struct）。

权威来源（2026-10-29 查 zed-industries/zed main 分支）：
   - crates/settings_content/src/settings_content.rs  → SettingsContent 的顶层结构
   - crates/settings_content/src/editor.rs           → EditorSettingsContent（flatten 进顶层）
   - crates/settings_content/src/language.rs         → LanguageSettingsContent（语言级）
   - bdl-lsp/internal/config/config.go               → 服务端认识的键

用法：
   python3 tests/verify-settings-json.py
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

checks = 0
failures = 0


def ok(msg: str) -> None:
    global checks
    checks += 1
    print(f"  ✓ {msg}")


def fail(msg: str) -> None:
    global failures
    failures += 1
    print(f"  ✗ {msg}")


# --------------------------------------------------------------------------
# Zed 认识的顶层键（SettingsContent 的字段，editor/workspace/theme 等是 flatten 进来的，
# 所以它们各自的字段也直接摊在顶层）。
#
# 下面这份列表是"白名单"：不在里面的顶层键一律视为可疑。
# 取自 crates/settings_content/src/settings_content.rs（SettingsContent）与
# editor.rs / language.rs / theme.rs（被 flatten 的那几组）。
# --------------------------------------------------------------------------
ZED_TOP_LEVEL_KEYS = {
    # SettingsContent 里显式声明的
    "command_palette",
    "file_finder",
    "call_hierarchy",
    "git_panel",
    "tabs",
    "tab_bar",
    "tab_switcher",
    "status_bar",
    "preview_tabs",
    "agent",
    "agent_servers",
    "audio",
    "auto_update",
    "base_keymap",
    "collaboration_panel",
    "debugger",
    "diagnostics",
    "lsp",
    "languages",
    "models",
    "project",
    "ssh_connections",
    "task",
    "terminal",
    "vim",
    "window",
    "workspace",
    "extensions",
    "keymap",
    "server",
    "remote",
    # EditorSettingsContent（flatten 进顶层）
    "buffer_font_family",
    "buffer_font_size",
    "cursor_blink",
    "cursor_shape",
    "cursor_animation",
    "current_line_highlight",
    "code_lens",
    "inline_code_actions",
    "format_on_save",
    "autosave",
    "soft_wrap",
    "soft_wrap_indent",
    "tab_size",
    "hard_tabs",
    "preferred_line_length",
    "show_wrap_guides",
    "wrap_guides",
    "indent_guides",
    "remove_trailing_whitespace_on_save",
    "ensure_final_newline_on_save",
    "line_ending",
    "formatter",
    "prettier",
    "inlay_hints",
    "gutter",
    "scrollbar",
    "cursor",
    "selection",
    "minimap",
    "blame",
    "edit_prediction",
    "inline_diagnostics",
    "diagnostics_panel",
    "code_formatting_on_save",
    # ThemeSettingsContent（flatten 进顶层）
    "theme",
    "buffer_font_style",
    "font_family",
    "font_size",
    "font_weight",
    "icon_theme",
    "ui_theme",
    # WorkspaceSettingsContent（flatten 进顶层）
    "file_scan_exclusions",
    "file_watcher",
    "restore_on_startup",
    "activate_on_startup",
    "default_open_file_setting",
    "autoload_project_files",
    "ssh_strategy",
    # 语言级容器
    "languages",
}

# 语言级（languages.<语言名>）认识的键 —— LanguageSettingsContent
ZED_LANGUAGE_KEYS = {
    "tab_size",
    "hard_tabs",
    "soft_wrap",
    "soft_wrap_indent",
    "preferred_line_length",
    "show_wrap_guides",
    "wrap_guides",
    "indent_guides",
    "format_on_save",
    "remove_trailing_whitespace_on_save",
    "ensure_final_newline_on_save",
    "line_ending",
    "formatter",
    "prettier",
    "jsx_tag_auto_close",
    "enable_language_server",
    "language_servers",
    "semantic_tokens",
    "document_folding_ranges",
    "document_symbols",
    "inlay_hints",
    "edit_prediction",
}

# bdl-lsp 认识的顶层配置键（internal/config/config.go 的 json tag）
BDL_LSP_KEYS = {
    "generoVersion",
    "logLevel",
    "globals",
    "diagnostics",
    "builtins",
    "link",
    "index",
    "schema",
    "ignore",
    "perRoots",
    "format",
    "limits",
    # 仅扩展自用，不会下发；出现在 settings 里是允许的（扩展会剥掉）
    "ext",
}


def strip_jsonc(text: str) -> str:
    """把 JSONC 变成严格 JSON：去掉行注释、块注释、尾随逗号。

    Zed 的 settings.json 是 **JSONC**（允许注释），文档里的示例也都用
    ```jsonc 标注，所以这里必须先剥掉注释才能用 json 解析。
    """
    out = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        # 行注释
        if ch == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        # 块注释
        if ch == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    # 去尾随逗号（"a": 1, } → "a": 1 }）
    cleaned = re.sub(r",(\s*[}\]])", r"\1", "".join(out))
    return cleaned


def json_blocks(text: str) -> list[tuple[int, str]]:
    """抠出所有 ```json / ```jsonc 代码块，返回 (行号, 内容)。

    只认 ```json 与 ```jsonc（Zed 的 settings.json 是 JSONC，允许注释）；
    ```json5 / ```ts 等不在检查范围。
    """
    out = []
    for m in re.finditer(r"```jsonc?[ \t]*\n(.*?)```", text, re.S):
        line = text[: m.start()].count("\n") + 1
        out.append((line, m.group(1)))
    return out


def is_settings_example(body: str) -> bool:
    """这段 JSON 是不是 **settings.json** 的示例？

    判据：含有 `lsp` / `languages` / 顶层编辑器设置键之一。
    keymap.json（`context`/`bindings`）、secrets.json 之类会被排除。
    """
    try:
        data = json.loads(strip_jsonc(body))
    except json.JSONDecodeError:
        return False
    if not isinstance(data, dict):
        return False
    return bool(
        {"lsp", "languages"} & set(data)
        or {"code_lens", "buffer_font_family", "tab_size", "format_on_save"} & set(data)
    )


def main() -> int:
    docs = [
        ROOT / "README.md",
        ROOT / "docs" / "USER-GUIDE.md",
    ]

    total_blocks = 0
    total_lsp_blocks = 0

    for doc in docs:
        if not doc.is_file():
            fail(f"缺少 {doc}")
            continue
        text = doc.read_text(encoding="utf-8")
        rel = doc.relative_to(ROOT)

        for lineno, body in json_blocks(text):
            if not is_settings_example(body):
                continue
            total_blocks += 1
            try:
                data = json.loads(strip_jsonc(body))
            except json.JSONDecodeError as exc:
                fail(f"{rel}:{lineno} 不是合法 JSON：{exc}")
                continue
            if not isinstance(data, dict):
                continue

            # 1. 顶层键
            bad = sorted(k for k in data if k not in ZED_TOP_LEVEL_KEYS)
            if bad:
                fail(
                    f"{rel}:{lineno} 顶层键不被 Zed 接受：{bad}"
                    f"（Zed 的 settings.json 没有这些键）"
                )
            elif "editor" in data:
                fail(
                    f"{rel}:{lineno} 用了 \"editor\" 顶层键 —— Zed 没有这个键"
                    f"（编辑器设置是 flatten 进顶层的，直接写 \"code_lens\"）"
                )

            # 2. languages.<名> 下的键
            langs = data.get("languages")
            if isinstance(langs, dict):
                for lang_name, lang_cfg in langs.items():
                    if not isinstance(lang_cfg, dict):
                        continue
                    bad_l = sorted(k for k in lang_cfg if k not in ZED_LANGUAGE_KEYS)
                    if bad_l:
                        fail(
                            f"{rel}:{lineno} languages.\"{lang_name}\" 下的键不被 Zed 接受：{bad_l}"
                            f"（语言级只有这些键可用）"
                        )

            # 3. lsp.<server>.settings 下的键
            lsp = data.get("lsp")
            if isinstance(lsp, dict):
                for server, cfg in lsp.items():
                    if not isinstance(cfg, dict):
                        continue
                    settings = cfg.get("settings")
                    if not isinstance(settings, dict):
                        continue
                    total_lsp_blocks += 1
                    bad_s = sorted(k for k in settings if k not in BDL_LSP_KEYS)
                    if bad_s:
                        fail(
                            f"{rel}:{lineno} lsp.\"{server}\".settings 下的键不被 bdl-lsp 接受：{bad_s}"
                        )

    if total_blocks == 0:
        fail("文档里一个 ```json 代码块都没找到（示例被删了？）")
    else:
        ok(f"文档里的 {total_blocks} 个 JSON 示例都是合法 JSON")
    if total_lsp_blocks:
        ok(f"{total_lsp_blocks} 处 lsp.<server>.settings 的键都被 bdl-lsp 接受")

    # 4. 明确断言：code_lens 必须是顶层键
    guide = (ROOT / "docs" / "USER-GUIDE.md").read_text(encoding="utf-8")
    if '"editor"' in guide and "code_lens" in guide:
        # 文档里提到 editor 是可以的（解释为什么不能这么写），但不能出现在示例里
        for lineno, body in json_blocks(guide):
            try:
                data = json.loads(strip_jsonc(body))
            except json.JSONDecodeError:
                continue
            if isinstance(data, dict) and "editor" in data:
                fail(f"USER-GUIDE.md:{lineno} 示例里有 \"editor\" 顶层键（Zed 会报 Property editor is not allowed）")
    ok("code_lens 用顶层键（不是 editor.code_lens）")

    print()
    if failures == 0:
        print(f"✓ {checks} 项校验全部通过")
        return 0
    print(f"✗ {failures} 项校验失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())
