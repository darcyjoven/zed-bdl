#!/usr/bin/env python3
"""校验 `.zed` 初始化脚本（scripts/zed/init-workspace.*）的实际输出。

为什么需要：
  1. 生成的 `.zed/tasks.json` 里如果混进 tiptop/VSCode 的模板占位符
     `${path}` / `${name}` / `${fullname}`，Zed 会把它们当**自己的 task 变量**，
     未知变量会让整条 task 从 `task: spawn` 列表里消失（或被替换成空串），
     而脚本本身"看起来没问题"——所以必须对**产物**断言，而不是读脚本源码。
  2. 生成的三份 JSON 必须合法；`settings.json` 已存在时不能被覆盖（写 `.bdl-new`）。

检查项：
  1. `bash scripts/zed/init-workspace.sh <tmp>` 在空目录里能跑通（`</dev/null` 走默认值）；
  2. `.zed/{settings.json,tasks.json,bdl-tool.json}` 都是合法 JSON；
  3. 20 条固定 task 的 label 齐全；任何 args 里不含 `${`；
  4. 6 条 exec task 的 `-command` 用 Zed 变量（$ZED_RELATIVE_DIR / $ZED_STEM / $ZED_FILENAME）；
  5. `settings.json` 的 `link.mode` / `schema.mode` 是 `off`（轻量档），且不含密码类键；
  6. 再跑一次（settings.json 已存在）→ 原文件字节不变，另生成 `.zed/settings.json.bdl-new`；
  7. 有 `pwsh` 时同样跑 PowerShell 版并断言前 3 项（没有就跳过，并打印说明）。

用法：
  python3 tests/verify-init-script.py
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SH = ROOT / "scripts" / "zed" / "init-workspace.sh"
PS1 = ROOT / "scripts" / "zed" / "init-workspace.ps1"

EXPECTED_LABELS = [
    "4gl: 链接资料：查看状态",
    "4gl: 链接资料：从 CSV 导入",
    "4gl: 链接资料：全量更新",
    "4gl: 链接资料：按模组更新",
    "4gl: 链接资料：更新当前文件",
    "4gl: 字段资料：查看状态",
    "4gl: 字段资料：从 CSV 导入",
    "4gl: 字段资料：从数据库同步",
    "4gl: 上传当前文件",
    "4gl: 预演上传",
    "4gl: 下载当前文件",
    "4gl: 4GL 预演编译",
    "4gl: 4GL 编译",
    "4gl: 4GL 链接",
    "4gl: Form 预演编译",
    "4gl: Form 编译",
    "4gl: Form 预览画面",
    "4gl: 部署预演",
    "4gl: 列出部署目标",
    "4gl: 部署（整包，需确认）",
]

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


def run_generator(root: Path, shell: str) -> str:
    """跑一次生成脚本，返回 stdout+stderr（供排查）。"""
    if shell == "bash":
        cmd = ["bash", str(SH), str(root)]
    else:
        cmd = ["pwsh", "-NoProfile", "-File", str(PS1), str(root)]
    proc = subprocess.run(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=str(root),
        env={**os.environ, "ZED_WORKTREE_ROOT": str(root)},
    )
    return proc.stdout


def find_secret_keys(value, path=""):
    """递归找真正的密码**值**字段；`passwordFile`/`envVar` 这类指针不算。"""
    hits = []
    if isinstance(value, dict):
        for key, item in value.items():
            here = f"{path}.{key}" if path else key
            if key.lower() in {"password", "passwd", "pwd", "ora_password"} and item:
                hits.append(here)
            hits.extend(find_secret_keys(item, here))
    elif isinstance(value, list):
        for i, item in enumerate(value):
            hits.extend(find_secret_keys(item, f"{path}[{i}]"))
    return hits


def check_products(root: Path, shell: str) -> None:
    zed = root / ".zed"
    try:
        settings = json.loads((zed / "settings.json").read_text(encoding="utf-8"))
        tasks = json.loads((zed / "tasks.json").read_text(encoding="utf-8"))
        tool = json.loads((zed / "bdl-tool.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"[{shell}] 生成的三份 JSON 读不出/不合法：{exc}")
        return
    ok(f"[{shell}] .zed/{{settings,tasks,bdl-tool}}.json 都是合法 JSON")

    labels = [t.get("label") for t in tasks]
    missing = [x for x in EXPECTED_LABELS if x not in labels]
    if missing:
        fail(f"[{shell}] 缺少 task：{missing}")
    else:
        ok(f"[{shell}] 20 条固定 task label 齐全")

    bad = [
        (t.get("label"), a)
        for t in tasks
        for a in t.get("args", [])
        if isinstance(a, str) and "${" in a
    ]
    if bad:
        for label, arg in bad:
            fail(f"[{shell}] {label} 的 args 里含 Zed 解析不了的占位符：{arg!r}")
    else:
        ok(f"[{shell}] 所有 args 都不含 `${{`（tiptop 模板占位符已改成 Zed 变量）")

    execs = [t for t in tasks if t.get("args", [None])[0] == "exec"]
    if len(execs) != 6:
        fail(f"[{shell}] exec task 数量应为 6，实际 {len(execs)}")
    else:
        wanted = ("$ZED_RELATIVE_DIR", "$ZED_STEM", "$ZED_FILENAME")
        holder = [t["label"] for t in execs if not any(w in t["args"][2] for w in wanted)]
        if holder:
            fail(f"[{shell}] 这些 exec task 没用 Zed 变量：{holder}")
        else:
            ok(f"[{shell}] 6 条 exec task 都用了 Zed 变量（$ZED_RELATIVE_DIR/$ZED_STEM/$ZED_FILENAME）")
        no_region = [t["label"] for t in execs if "-region" not in t["args"]]
        if no_region:
            fail(f"[{shell}] 这些 exec task 缺 -region：{no_region}")
        else:
            ok(f"[{shell}] 6 条 exec task 都带 -region")

    s = settings.get("lsp", {}).get("bdl-lsp", {}).get("settings", {})
    modes = (s.get("link", {}).get("mode"), s.get("schema", {}).get("mode"))
    if modes == ("off", "off"):
        ok(f"[{shell}] 轻量档：link.mode / schema.mode = off")
    else:
        fail(f"[{shell}] link/schema mode 应为 off/off，实际 {modes}")

    hits = find_secret_keys(settings) + find_secret_keys(tool)
    if hits:
        fail(f"[{shell}] 生成的文件里出现密码字段：{hits}")
    else:
        ok(f"[{shell}] 不含密码字段（只写 secrets.json / BDL_ORA_PASSWORD 的指针）")


def main() -> int:
    if not SH.is_file():
        fail(f"缺少 {SH.relative_to(ROOT)}")
        return 1

    with tempfile.TemporaryDirectory(prefix="bdl-init-") as tmp:
        root = Path(tmp)
        out = run_generator(root, "bash")
        if not (root / ".zed" / "tasks.json").is_file():
            fail("bash 版没有生成 .zed/tasks.json；输出见下")
            print(out[-2000:])
            return 1
        ok("bash 版在空目录里跑通并生成 .zed/ 三份文件")
        check_products(root, "bash")

        # 幂等/保护：settings.json 已存在时不覆盖
        before = (root / ".zed" / "settings.json").read_bytes()
        run_generator(root, "bash")
        after = (root / ".zed" / "settings.json").read_bytes()
        if before == after and (root / ".zed" / "settings.json.bdl-new").is_file():
            ok("第二次运行：settings.json 未被覆盖，另写了 .bdl-new")
        else:
            fail("第二次运行：settings.json 被覆盖或没写 .bdl-new")

    if PS1.is_file() and shutil.which("pwsh"):
        with tempfile.TemporaryDirectory(prefix="bdl-init-ps-") as tmp:
            root = Path(tmp)
            out = run_generator(root, "pwsh")
            if not (root / ".zed" / "tasks.json").is_file():
                fail("PowerShell 版没有生成 .zed/tasks.json；输出见下")
                print(out[-2000:])
            else:
                ok("PowerShell 版在空目录里跑通")
                check_products(root, "pwsh")
    else:
        print("  \u26a0 未找到 pwsh：跳过 PowerShell 版实跑（CI 的 ubuntu/windows runner 上有 pwsh，会在 CI 覆盖）")

    print()
    if failures == 0:
        print(f"\u2713 {checks} 项校验全部通过")
        return 0
    print(f"\u2717 {failures} 项校验失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())