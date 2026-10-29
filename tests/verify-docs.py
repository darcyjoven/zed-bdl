#!/usr/bin/env python3
"""校验「文档与实现/护栏」的一致性。

为什么需要：本仓库的文档是**契约**（用户照文档配，扩展照文档实现），
而这轮改动频繁（slash command 8→9、护栏 14→17、task 20→22），
数字一旦漂移就会误导用户。这里把"文档里的声明"与"实际源码/护栏输出"对拍：

  1. 版本号三处一致：extension.toml / Cargo.toml / Cargo.lock 的 zed-bdl 包；
  2. 每条 `[slash_commands.*]` 都出现在 README 与 USER-GUIDE 的命令表里；
  3. README 与 USER-GUIDE 里声明的 slash command **条数**等于实际条数；
  4. PLAN「护栏现状」那行、README 开发小节里的清单/初始化脚本项数等于实跑数；
  5. README / USER-GUIDE 里不再出现已废弃的命令名与配置键
     （`bdl-lsp link` / `bdl-lsp deploy` / `link.maxAgeDays` / `link.sync.*` / `cmd/link-audit`）；
     PLAN 除外——它有一行专门在讲"不许出现这些串"。

用法：
  python3 tests/verify-docs.py
"""
from __future__ import annotations

import re
import subprocess
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


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def run_checker(script: str) -> int:
    """跑另一个护栏脚本，返回它报告的项数（解析 `✓ N 项校验全部通过`）。"""
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tests" / script)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=str(ROOT),
    )
    match = re.search(r"(\d+) 项校验全部通过", proc.stdout)
    if not match:
        raise RuntimeError(f"{script} 没输出项数（rc={proc.returncode}）：\n{proc.stdout[-800:]}")
    return int(match.group(1))


def main() -> int:
    manifest = tomllib.load(open(ROOT / "extension.toml", "rb"))
    cargo = tomllib.load(open(ROOT / "Cargo.toml", "rb"))
    lock_text = read("Cargo.lock")

    # 1. 版本三处一致
    ext_version = manifest.get("version")
    cargo_version = cargo.get("package", {}).get("version")
    lock_match = re.search(
        r'\[\[package\]\]\nname = "zed-bdl"\nversion = "([^"]+)"', lock_text
    )
    lock_version = lock_match.group(1) if lock_match else None
    if ext_version and ext_version == cargo_version == lock_version:
        ok(f"版本三处一致：{ext_version}（extension.toml / Cargo.toml / Cargo.lock）")
    else:
        fail(
            "版本不一致：extension.toml="
            f"{ext_version!r} Cargo.toml={cargo_version!r} Cargo.lock={lock_version!r}"
        )

    readme = read("README.md")
    guide = read("docs/USER-GUIDE.md")
    plan = read("docs/PLAN.md")

    # 2/3. slash command：声明 ↔ 文档
    declared = sorted(manifest.get("slash_commands", {}) or {})
    missing = [name for name in declared if f"`/{name}`" not in readme]
    if missing:
        fail(f"README 的命令表缺少：{missing}")
    else:
        ok(f"README 列出了全部 {len(declared)} 条 slash command")

    missing = [name for name in declared if f"`/{name}`" not in guide]
    if missing:
        fail(f"USER-GUIDE 的命令表缺少：{missing}")
    else:
        ok(f"USER-GUIDE 列出了全部 {len(declared)} 条 slash command")

    # README 里「N 条 `/bdl-…`」这类声明
    stated = re.findall(r"(\d+) 条 `/bdl-…`", readme)
    bad = [n for n in stated if int(n) != len(declared)]
    if bad:
        fail(f"README 写的 slash command 条数 {bad} 与实际 {len(declared)} 不符")
    else:
        ok(f"README 声明的条数与实现一致（{len(declared)}）")

    # USER-GUIDE 的「N 条命令的实现见 src/slash.rs」
    stated = re.findall(r"(\d+) 条命令的实现见", guide)
    bad = [n for n in stated if int(n) != len(declared)]
    if bad:
        fail(f"USER-GUIDE 写的命令条数 {bad} 与实际 {len(declared)} 不符")
    else:
        ok(f"USER-GUIDE 声明的条数与实现一致（{len(declared)}）")

    # 4. 护栏项数：PLAN「护栏现状」那一行 + README 开发小节
    manifest_items = run_checker("verify-manifest.py")
    init_items = run_checker("verify-init-script.py")

    line = next((l for l in plan.splitlines() if "护栏现状：" in l), None)
    if line is None:
        fail("PLAN 里找不到『护栏现状：』那行")
    else:
        nums = dict(re.findall(r"(清单|init-script|query|cargo test)\D{0,4}\*{0,2}(\d+)\*{0,2}", line))
        want = {"清单": manifest_items, "init-script": init_items}
        problems = [f"{k} 文档={nums.get(k)} 实际={v}" for k, v in want.items() if str(nums.get(k)) != str(v)]
        if problems:
            fail(f"PLAN『护栏现状』数字不符：{problems}（行：{line.strip()}）")
        else:
            ok(f"PLAN『护栏现状』与实跑一致（清单 {manifest_items} / init-script {init_items}）")

    for pattern, actual, label in (
        (r"# 清单 (\d+) 项", manifest_items, "README 清单项数"),
        (r"# 初始化脚本产物 (\d+) 项", init_items, "README init-script 项数"),
    ):
        found = re.findall(pattern, readme)
        bad = [n for n in found if int(n) != actual]
        if bad:
            fail(f"{label} 写 {bad}，实际 {actual}")
        else:
            ok(f"{label} 与实跑一致（{actual}）")

    # 5. 废弃命令/配置：README 与 USER-GUIDE 里不允许出现
    stale = [
        "bdl-lsp link",
        "bdl-lsp deploy",
        "link.maxAgeDays",
        "link.sync.",
        "cmd/link-audit",
    ]
    hits = []
    for doc_name, text in (("README.md", readme), ("docs/USER-GUIDE.md", guide)):
        for needle in stale:
            for lineno, doc_line in enumerate(text.splitlines(), 1):
                if needle in doc_line:
                    hits.append(f"{doc_name}:{lineno} 含 {needle!r}")
    if hits:
        for hit in hits:
            fail(f"过期引用：{hit}")
    else:
        ok("README / USER-GUIDE 无过期命令与配置键")

    print()
    if failures == 0:
        print(f"\u2713 {checks} 项校验全部通过")
        return 0
    print(f"\u2717 {failures} 项校验失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())