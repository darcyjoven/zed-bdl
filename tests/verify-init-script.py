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
  3. 21 条固定 task 的 label 齐全；任何 args 里不含 `${`；
  4. 6 条 exec task 的 `-command` 用 Zed 变量（$ZED_RELATIVE_DIR / $ZED_STEM / $ZED_FILENAME）；
  5. `settings.json` 的 `link.mode` / `schema.mode` 是 `off`（轻量档），且不含密码类键；
  6. 再跑一次（settings.json 已存在）→ 原文件字节不变，另生成 `.zed/settings.json.bdl-new`；
  7. 填了生产环境 → 生成 `.project/deploy/deploy.json`，再跑一次同样不覆盖；
  8. 迁移 helper 能搬旧资料目录，且**绝不覆盖**已存在的目标文件；
  9. `ext.build.*` 覆盖生效（回读并映射成 Zed 变量，未配置的保持默认）；
  10. 有 `pwsh` 时同样跑 PowerShell 版并断言同样的产物（没有就跳过，并打印说明）。

★ **核心项数 vs 总项数**（重要）：
   第 10 项只在装了 pwsh 的机器上跑（CI 的 runner 自带，本地不一定有），
   所以**总项数会随环境变化**（CI 25 项 / 本地 15 项）。
   文档里的护栏数字必须与**环境无关**，因此脚本把 pwsh 的那部分单独记为
   "额外项"，输出里同时给出**核心项数**（恒定 15）——
   `verify-docs.py` 对拍的就是这个核心项数。
   （2026-10-29 踩过这个坑：CI 报"文档=15 实际=25"，根因是把总项数当契约。）

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
    "4gl: 迁移项目资料目录（旧目录 → .project/）",
]

checks = 0
failures = 0
# extra_checks 只统计**依赖环境**的那部分（PowerShell 版实跑）。
#
# 为什么单独记：bash 版的检查项数是**固定**的，而 pwsh 版只在装了 pwsh 的机器上
# 才跑（CI 的 ubuntu/windows runner 自带 pwsh；本地开发机不一定有）。
# 早先把总项数直接写在文档里当契约，于是同一份代码在 CI 上是 25 项、本地是 15 项，
# 文档里的数字两边都对不上 —— 这是**护栏设计缺陷**，不是文档写错。
#
# 现在改成：**核心项数（bash）恒定**，pwsh 的额外项单独报。
#   - `verify-docs.py` 对拍的核心数字 = 核心项数（不含 pwsh 额外项）；
#   - 本地没 pwsh 时与 CI 有 pwsh 时，这个数字**完全一致**，文档只需要维护一个数。
extra_checks = 0


def ok(msg: str) -> None:
    global checks
    checks += 1
    print(f"  \u2713 {msg}")


def ok_extra(msg: str) -> None:
    """环境相关的额外检查项（PowerShell 版实跑）；不计入核心项数。"""
    global extra_checks, checks
    extra_checks += 1
    checks += 1
    print(f"  \u2713 {msg}")


def fail(msg: str) -> None:
    global failures
    failures += 1
    print(f"  \u2717 {msg}")


def run_generator(root: Path, shell: str, answers: str | None = None) -> str:
    """跑一次生成脚本，返回 stdout+stderr（供排查）。

    answers=None 时 stdin 是 /dev/null（走全部默认值）；给了就按提问顺序喂答案。
    """
    if shell == "bash":
        cmd = ["bash", str(SH), str(root)]
    else:
        cmd = ["pwsh", "-NoProfile", "-File", str(PS1), str(root)]
    proc = subprocess.run(
        cmd,
        input=answers,
        stdin=subprocess.DEVNULL if answers is None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        cwd=str(root),
        env={**os.environ, "ZED_WORKTREE_ROOT": str(root)},
    )
    return proc.stdout


# 交互提问顺序（两个脚本一致）：
#   项目根 / bdl-lsp / tiptop / ora.host / ora.port / ora.service / ora.user
#   / prod.host / prod.port / prod.user / region / remoteRoot / localRoot / transport / init-project
PROD_ANSWERS = "\n" * 7 + "10.0.0.10\n22\nappuser\n1\n/u1/topprod\n.\nrsync\n\n"


def check_deploy_json(root: Path, shell: str, extra: bool = False) -> None:
    """有生产环境时，脚本应生成 tiptop 能读的 .project/deploy/deploy.json。"""
    mark = ok_extra if extra else ok
    path = root / ".project/deploy/deploy.json"
    if not path.is_file():
        fail(f"[{shell}] 填了生产环境但没生成 .project/deploy/deploy.json")
        return
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"[{shell}] deploy.json 不是合法 JSON：{exc}")
        return
    target = data.get("targets", {}).get("prod", {})
    problems = []
    if target.get("host") != "10.0.0.10":
        problems.append(f"host={target.get('host')!r}")
    if target.get("remoteRoot") != "/u1/topprod":
        problems.append(f"remoteRoot={target.get('remoteRoot')!r}")
    if target.get("upload", {}).get("mode") != "rsync":
        problems.append(f"upload.mode={target.get('upload', {}).get('mode')!r}")
    tpl = target.get("compile", {}).get("4gl", "")
    if "{file}" not in tpl:
        problems.append(f"compile.4gl 缺少 {{file}}：{tpl!r}")
    if problems:
        fail(f"[{shell}] deploy.json 字段不对：{problems}")
    else:
        mark(f"[{shell}] 生成 .project/deploy/deploy.json（host/remoteRoot/upload.mode/compile.{{file}} 都对）")


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


def check_products(root: Path, shell: str, extra: bool = False) -> None:
    """断言生成产物。

    extra=True 时（PowerShell 版）这些项算**环境相关的额外项**，
    不计入核心项数 —— 否则文档里的护栏数字会随"本机有没有 pwsh"漂移。
    """
    mark = ok_extra if extra else ok
    zed = root / ".zed"
    try:
        settings = json.loads((zed / "settings.json").read_text(encoding="utf-8"))
        tasks = json.loads((zed / "tasks.json").read_text(encoding="utf-8"))
        tool = json.loads((zed / "bdl-tool.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"[{shell}] 生成的三份 JSON 读不出/不合法：{exc}")
        return
    mark(f"[{shell}] .zed/{{settings,tasks,bdl-tool}}.json 都是合法 JSON")

    labels = [t.get("label") for t in tasks]
    missing = [x for x in EXPECTED_LABELS if x not in labels]
    if missing:
        fail(f"[{shell}] 缺少 task：{missing}")
    else:
        mark(f"[{shell}] 21 条固定 task label 齐全")

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
        mark(f"[{shell}] 所有 args 都不含 `${{`（tiptop 模板占位符已改成 Zed 变量）")

    execs = [t for t in tasks if t.get("args", [None])[0] == "exec"]
    if len(execs) != 6:
        fail(f"[{shell}] exec task 数量应为 6，实际 {len(execs)}")
    else:
        wanted = ("$ZED_RELATIVE_DIR", "$ZED_STEM", "$ZED_FILENAME")
        holder = [t["label"] for t in execs if not any(w in t["args"][2] for w in wanted)]
        if holder:
            fail(f"[{shell}] 这些 exec task 没用 Zed 变量：{holder}")
        else:
            mark(f"[{shell}] 6 条 exec task 都用了 Zed 变量（$ZED_RELATIVE_DIR/$ZED_STEM/$ZED_FILENAME）")
        no_region = [t["label"] for t in execs if "-region" not in t["args"]]
        if no_region:
            fail(f"[{shell}] 这些 exec task 缺 -region：{no_region}")
        else:
            mark(f"[{shell}] 6 条 exec task 都带 -region")

    # 字段白名单：Zed 的 task schema（docs/tasks.md）。生成脚本写错字段名时
    # Zed 不会报错，只会"这条 task 的行为不对"，必须静态拦下。
    allowed = {
        "label", "command", "args", "env", "cwd", "use_new_terminal",
        "allow_concurrent_runs", "reveal", "hide", "shell", "show_summary",
        "show_command", "save", "tags", "hooks",
    }
    enum_checks = {
        "save": {"all", "current", "none"},
        "reveal": {"always", "no_focus", "never"},
        "hide": {"never", "always", "on_success"},
    }
    field_problems = []
    for task in tasks:
        unknown = sorted(set(task) - allowed)
        if unknown:
            field_problems.append(f"{task.get('label')}: 未知字段 {unknown}")
        for key, values in enum_checks.items():
            if key in task and task[key] not in values:
                field_problems.append(f"{task.get('label')}: {key}={task[key]!r} 不在 {sorted(values)}")
        for required in ("label", "command", "cwd"):
            if required not in task:
                field_problems.append(f"{task.get('label')}: 缺 {required}")
    if field_problems:
        for problem in field_problems:
            fail(f"[{shell}] task 字段不合法：{problem}")
    else:
        mark(f"[{shell}] {len(tasks)} 条 task 的字段都在 Zed schema 白名单内（save/reveal/hide 取值也合法）")

    s = settings.get("lsp", {}).get("bdl-lsp", {}).get("settings", {})
    modes = (s.get("link", {}).get("mode"), s.get("schema", {}).get("mode"))
    if modes == ("off", "off"):
        mark(f"[{shell}] 轻量档：link.mode / schema.mode = off")
    else:
        fail(f"[{shell}] link/schema mode 应为 off/off，实际 {modes}")

    hits = find_secret_keys(settings) + find_secret_keys(tool)
    if hits:
        fail(f"[{shell}] 生成的文件里出现密码字段：{hits}")
    else:
        mark(f"[{shell}] 不含密码字段（只写 secrets.json / BDL_ORA_PASSWORD 的指针）")


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

    # 场景二：填了生产环境 → 生成 deploy.json；再跑一次 → 不覆盖、写 .bdl-new
    with tempfile.TemporaryDirectory(prefix="bdl-init-prod-") as tmp:
        root = Path(tmp)
        run_generator(root, "bash", PROD_ANSWERS)
        check_deploy_json(root, "bash")
        before = (root / ".project/deploy/deploy.json").read_bytes()
        run_generator(root, "bash", PROD_ANSWERS)
        after = (root / ".project/deploy/deploy.json").read_bytes()
        new_file = root / ".project/deploy/deploy.json.bdl-new"
        if before == after and new_file.is_file():
            ok("第二次运行：deploy.json 未被覆盖，另写了 .bdl-new")
        else:
            fail("第二次运行：deploy.json 被覆盖或没写 .bdl-new")

    # 场景三：迁移 helper（.zed/bdl/migrate-data.sh）真的能搬旧资料、且不覆盖已有文件
    with tempfile.TemporaryDirectory(prefix="bdl-init-mig-") as tmp:
        base = Path(tmp)
        gen = base / "gen"
        gen.mkdir()
        run_generator(gen, "bash")
        helper = gen / ".zed/bdl/migrate-data.sh"
        if not helper.is_file():
            fail("生成脚本没有产出 .zed/bdl/migrate-data.sh")
        else:
            ok("生成脚本产出 .zed/bdl/migrate-data.sh")
            proj = base / "proj"
            (proj / ".link").mkdir(parents=True)
            (proj / ".link/links.jsonl").write_text('{"schema":1}\n', encoding="utf-8")
            (proj / ".link/links.meta.json").write_text('{"generatedAt":"x"}\n', encoding="utf-8")
            (proj / ".project/.schema/tables").mkdir(parents=True)
            (proj / ".project/.schema/tables/X.json").write_text('{"table":"X"}\n', encoding="utf-8")
            (proj / ".bdl-lsp").mkdir()
            (proj / ".bdl-lsp/deploy.json").write_text('{"targets":{}}\n', encoding="utf-8")
            # 目标已存在 → 必须保留原内容（绝不覆盖）
            (proj / ".project/schema").mkdir(parents=True)
            (proj / ".project/schema/tables.json").write_text('{"keep":true}\n', encoding="utf-8")

            proc = subprocess.run(
                ["bash", str(helper), str(proj)],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                cwd=str(proj),
            )
            moved_ok = (proj / ".project/link/links.jsonl").is_file() and (
                proj / ".project/schema/tables/X.json"
            ).is_file() and (proj / ".project/deploy/deploy.json").is_file()
            kept = (proj / ".project/schema/tables.json").read_text(encoding="utf-8")
            legacy_gone = not (proj / ".link").exists()
            if proc.returncode != 0 or not moved_ok or not legacy_gone:
                fail(f"迁移 helper 失败（rc={proc.returncode}）：{proc.stdout[-500:]}")
            elif "keep" not in kept:
                fail(f"迁移 helper 覆盖了已存在的 .project/schema/tables.json：{kept!r}")
            else:
                ok("迁移 helper：旧目录搬入 .project/、空目录删除、已存在的目标文件未被覆盖")

    # 场景四：ext.build.* 覆盖 → 生成脚本应回读并映射成 Zed 变量（PLAN Z-P2-4 ②）
    with tempfile.TemporaryDirectory(prefix="bdl-init-build-") as tmp:
        root = Path(tmp)
        (root / ".zed").mkdir(parents=True)
        (root / ".zed/settings.json").write_text(
            json.dumps(
                {
                    "lsp": {
                        "bdl-lsp": {
                            "settings": {
                                "ext": {
                                    "build": {
                                        "4gl": {
                                            "compile": "cd ${path} && mycc -M ${name}",
                                            "link": "mylink ${fullname}",
                                        },
                                        "per": {"form": "cd ${fullpath} && myform ${name} 2 p"},
                                    }
                                }
                            }
                        }
                    }
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )
        run_generator(root, "bash")
        try:
            tasks = json.loads((root / ".zed/tasks.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            fail(f"[bash] ext.build 场景：tasks.json 不合法：{exc}")
            tasks = []
        by_label = {t.get("label"): t.get("args", []) for t in tasks}
        expect = {
            "4gl: 4GL 编译": "cd $ZED_RELATIVE_DIR && mycc -M $ZED_STEM",
            "4gl: 4GL 链接": "mylink $ZED_FILENAME",
            "4gl: Form 预览画面": "cd $ZED_RELATIVE_DIR && myform $ZED_STEM 2 p",
            # 没配的那条必须保持内置默认
            "4gl: 4GL 预演编译": "cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM",
        }
        problems = []
        for label, want in expect.items():
            args = by_label.get(label, [])
            got = args[2] if len(args) > 2 else None
            if got != want:
                problems.append(f"{label}: {got!r} != {want!r}")
        leftover = [a for args in by_label.values() for a in args if isinstance(a, str) and "${" in a]
        if problems:
            fail(f"[bash] ext.build 覆盖未生效：{problems}")
        elif leftover:
            fail(f"[bash] ext.build 场景仍残留 ${{…}}：{leftover}")
        else:
            ok("[bash] ext.build.* 覆盖生效（映射成 Zed 变量，未配置的保持默认）")

    if PS1.is_file() and shutil.which("pwsh"):
        with tempfile.TemporaryDirectory(prefix="bdl-init-ps-") as tmp:
            root = Path(tmp)
            out = run_generator(root, "pwsh")
            if not (root / ".zed" / "tasks.json").is_file():
                fail("PowerShell 版没有生成 .zed/tasks.json；输出见下")
                print(out[-2000:])
            else:
                ok_extra("PowerShell 版在空目录里跑通")
                check_products(root, "pwsh", extra=True)
        with tempfile.TemporaryDirectory(prefix="bdl-init-ps-prod-") as tmp:
            root = Path(tmp)
            run_generator(root, "pwsh", PROD_ANSWERS)
            check_deploy_json(root, "pwsh", extra=True)
    else:
        print("  \u26a0 未找到 pwsh：跳过 PowerShell 版实跑（CI 的 ubuntu/windows runner 上有 pwsh，会在 CI 覆盖）")

    print()
    if failures == 0:
        print(f"\u2713 {checks} 项校验全部通过")
        if extra_checks:
            print(
                f"  （其中核心 {checks - extra_checks} 项 + PowerShell 额外 {extra_checks} 项；"
                f"文档里的护栏数字对拍用**核心**项数）"
            )
        else:
            print(f"  （核心 {checks} 项；本机没有 pwsh，PowerShell 版由 CI 覆盖）")
        return 0
    print(f"\u2717 {failures} 项校验失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())