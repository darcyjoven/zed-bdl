#!/usr/bin/env python3
"""校验 Zed 扩展的清单文件。

为什么需要：
  extension.toml 里的 `id` / `schema_version` / `grammars` / `language_servers`
  写错时，Zed 安装扩展会直接失败或语言服务器静默不启动，报错信息也很含糊
  （常见的是 "failed to load extension"）。这里把能静态校验的项目提前拦下。

检查项：
  1. schema_version 必须是 1；
  2. 每个 grammar 有 repository + rev，且 rev 形如 40 位 SHA；
  3. 每个 languages/<dir>/config.toml 的 name 唯一；
  4. language_servers[*].languages 里提到的语言名都真实存在；
  5. language_servers[*].language_ids 的 key 是已声明的语言名；
  6. 每个 language 的 grammar 字段都能在 [grammars] 里找到；
  7. 每个 language 目录必须至少有 config.toml 与 highlights.scm。

用法：
  python3 tests/verify-manifest.py
"""
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

checks = 0
failures = 0


def ok(msg: str) -> None:
    global checks
    checks += 1
    print(f"  \u2713 {msg}")


def fail(msg: str) -> None:
    global failures
    failures += 1
    print(f"  \u2717 {msg}")


def main() -> int:
    try:
        manifest = tomllib.load(open(ROOT / "extension.toml", "rb"))
    except FileNotFoundError:
        fail("找不到 extension.toml")
        return 1
    except tomllib.TOMLDecodeError as exc:
        fail(f"extension.toml 不是合法 TOML：{exc}")
        return 1

    ok("extension.toml 是合法 TOML")

    # 1. schema_version
    if manifest.get("schema_version") == 1:
        ok("schema_version = 1")
    else:
        fail(f"schema_version 必须是 1，实际 {manifest.get('schema_version')!r}")

    # id 不能是保留字，也不能带空格
    ext_id = manifest.get("id", "")
    if re.fullmatch(r"[a-z0-9]([a-z0-9-]*[a-z0-9])?", ext_id):
        ok(f"id 合法：{ext_id}")
    else:
        fail(f"id 不合法（需小写字母/数字/连字符）：{ext_id!r}")

    for field in ("name", "version", "repository", "authors", "description"):
        if manifest.get(field):
            ok(f"有 {field}")
        else:
            fail(f"缺少 {field}")

    # 2. grammars
    grammars = manifest.get("grammars", {})
    if not grammars:
        fail("没有声明任何 [grammars.*]")
    for name, g in grammars.items():
        repo = g.get("repository", "")
        rev = g.get("rev", "")
        if not repo.startswith(("https://", "http://", "file://")):
            fail(f"grammar {name} 的 repository 不是 URL：{repo!r}")
            continue
        if not re.fullmatch(r"[0-9a-f]{40}", rev):
            fail(f"grammar {name} 的 rev 不是 40 位 SHA：{rev!r}")
            continue
        ok(f"grammar {name}: {repo} @ {rev[:8]}")

    # 3. languages/<dir>/config.toml
    lang_root = ROOT / "languages"
    if not lang_root.is_dir():
        fail("没有 languages/ 目录")
        return 1

    declared: dict[str, str] = {}
    for d in sorted(lang_root.iterdir()):
        if not d.is_dir():
            continue
        cfg_path = d / "config.toml"
        if not cfg_path.is_file():
            fail(f"languages/{d.name}/ 缺少 config.toml")
            continue
        try:
            cfg = tomllib.load(open(cfg_path, "rb"))
        except tomllib.TOMLDecodeError as exc:
            fail(f"languages/{d.name}/config.toml 不是合法 TOML：{exc}")
            continue

        name = cfg.get("name")
        if not name:
            fail(f"languages/{d.name}/config.toml 缺少 name")
            continue
        if name in declared:
            fail(f"语言名重复：{name!r}（{declared[name]} 与 {d.name}）")
            continue
        declared[name] = d.name

        # 6. grammar 引用
        grammar = cfg.get("grammar")
        if grammar not in grammars:
            fail(f"languages/{d.name} 引用了未声明的 grammar {grammar!r}")
        else:
            ok(f"languages/{d.name}: name={name!r} grammar={grammar!r}")

        # 7. 必备 query
        if not (d / "highlights.scm").is_file():
            fail(f"languages/{d.name}/ 缺少 highlights.scm")

        # path_suffixes 不能带点
        for suffix in cfg.get("path_suffixes", []):
            if suffix.startswith("."):
                fail(f"languages/{d.name}: path_suffixes 不能带前导点：{suffix!r}")

    if declared:
        ok(f"共 {len(declared)} 个语言：{', '.join(sorted(declared))}")

    # 4/5. language_servers
    servers = manifest.get("language_servers", {})
    for ls_name, ls in servers.items():
        if not ls.get("name"):
            fail(f"language_servers.{ls_name} 缺少 name")
        langs = ls.get("languages", [])
        if not langs:
            fail(f"language_servers.{ls_name} 没有 languages")
        for lang in langs:
            if lang not in declared:
                fail(
                    f"language_servers.{ls_name}.languages 里的 {lang!r} "
                    f"没有对应的 languages/*/config.toml（已声明：{sorted(declared)}）"
                )
        ids = ls.get("language_ids", {})
        for key, value in ids.items():
            if key not in langs:
                fail(
                    f"language_servers.{ls_name}.language_ids 的 key {key!r} "
                    f"不在 languages 列表里"
                )
            # LSP languageId 惯例是小写字母/数字
            if not re.fullmatch(r"[a-zA-Z0-9_.-]+", str(value)):
                fail(
                    f"language_servers.{ls_name}.language_ids[{key!r}] 不是合法 languageId："
                    f"{value!r}"
                )
        ok(f"language_servers.{ls_name}: {langs}")

    print()
    if failures == 0:
        print(f"\u2713 {checks} 项校验全部通过")
        return 0
    print(f"\u2717 {failures} 项校验失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())
