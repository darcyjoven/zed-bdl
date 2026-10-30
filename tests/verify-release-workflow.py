#!/usr/bin/env python3
"""校验 .github/workflows/release.yml 与扩展实现的一致性。

为什么需要：
   发布流水线里的**资产名**必须和扩展运行时解析的名字**完全一致**。
   对不上时不会编译失败、也不会 CI 变红，只在用户装扩展时炸：
   "Release 里没有资产 bdl-lsp-linux-amd64.tar.gz" —— 而且是用户看到的第一个故障。

   同类问题本仓库已经吃过一次（2026-10-29：护栏项数随环境漂移导致 CI 与本地
   对不上）。这里的对策是：**凡是"两边必须一致"的字符串，都写进护栏**。

检查项：
   1. release.yml 是合法 YAML，触发器含 `push: tags: v*`；
   2. 矩阵覆盖 4 个平台（linux/darwin×2/windows × amd64）；
   3. 每个平台产出的**后端资产名**（bdl-lsp-*/tiptop-*）与 src/download.rs
      的 `asset_name_for` 规则一致（Windows 用 .zip，其余用 .tar.gz）；
   4. 本扩展自己的 Release 也带**同名**资产（扩展的下载链把它当兜底仓库，
      见 src/download.rs 的 download_repos）；
   5. 扩展 wasm 的产物名与 Cargo.toml 的包名一致（wasm32-wasip2 会把 `-`
      规范化成 `_`）；
   6. release.yml 里没有硬编码的版本号（版本必须来自 tag）。

用法：
   python3 tests/verify-release-workflow.py
"""
from __future__ import annotations

import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"

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


def main() -> int:
    if not WORKFLOW.is_file():
        fail(f"缺少 {WORKFLOW.relative_to(ROOT)}")
        return 1

    text = WORKFLOW.read_text(encoding="utf-8")

    # 1. YAML 合法 + 触发器
    try:
        import yaml
    except ImportError:
        print("  ⚠ 缺少 pyyaml，跳过 YAML 结构校验（只做文本校验）")
        yaml = None

    matrix = None
    if yaml is not None:
        try:
            data = yaml.safe_load(text)
        except Exception as exc:  # noqa: BLE001
            fail(f"release.yml 不是合法 YAML：{exc}")
            return 1
        ok("release.yml 是合法 YAML")
        # pyyaml 按 YAML 1.1 把裸 `on` 解析成 True
        trig = data.get("on", data.get(True))
        if not isinstance(trig, dict):
            fail("release.yml 里找不到触发器")
            return 1
        tags = (trig.get("push") or {}).get("tags") or []
        if "v*" in tags:
            ok("触发器含 push: tags: v*（打 tag 即发布）")
        else:
            fail(f"触发器的 tag 模式应含 'v*'，实际 {tags}")
        if "workflow_dispatch" in trig:
            ok("支持 workflow_dispatch 手动触发")
        else:
            fail("缺少 workflow_dispatch（无法手动重跑发布）")
        jobs = data.get("jobs") or {}
        for needed in ("prepare", "build", "release"):
            if needed not in jobs:
                fail(f"缺少 job：{needed}")
        else:
            ok("有 prepare / build / release 三个 job")
        build = jobs.get("build") or {}
        matrix = ((build.get("strategy") or {}).get("matrix") or {}).get("include") or []
        if not matrix:
            fail("build job 没有 matrix")
        else:
            got = {(m.get("os"), m.get("arch")) for m in matrix}
            want = {
                ("linux", "amd64"),
                ("darwin", "amd64"),
                ("darwin", "arm64"),
                ("windows", "amd64"),
            }
            if got == want:
                ok(f"矩阵覆盖 4 个平台/架构组合：{sorted(got)}")
            else:
                fail(f"矩阵平台不对：期望 {sorted(want)}，实际 {sorted(got)}")

    # 2. 资产名：workflow 产出的 vs 扩展解析的
    #    扩展的规则（src/download.rs 的 asset_name_for）：
    #      <prefix>-<linux|darwin|windows>-<amd64|arm64>.<tar.gz|zip>
    #      Windows 用 .zip，其余用 .tar.gz。
    os_arch = matrix or [
        {"os": "linux", "arch": "amd64"},
        {"os": "darwin", "arch": "amd64"},
        {"os": "darwin", "arch": "arm64"},
        {"os": "windows", "arch": "amd64"},
    ]
    expected: set[str] = set()
    for m in os_arch:
        o, a = m.get("os"), m.get("arch")
        ext = "zip" if o == "windows" else "tar.gz"
        expected.add(f"bdl-lsp-{o}-{a}.{ext}")
        expected.add(f"tiptop-{o}-{a}.{ext}")

    # workflow 里必须能看到这些名字的**模板**（用 matrix 变量拼出来）。
    for prefix in ("bdl-lsp", "tiptop"):
        if f"{prefix}-${{{{ matrix.os }}}}-${{{{ matrix.arch }}}}.tar.gz" in text:
            ok(f"workflow 用 matrix 变量拼出 {prefix}-<os>-<arch>.tar.gz")
        else:
            fail(f"workflow 里找不到 {prefix}-<os>-<arch>.tar.gz 的拼装")

    if "bdl-lsp-windows-amd64.zip" in text and "tiptop-windows-amd64.zip" in text:
        ok("Windows 资产用 .zip（与扩展的 asset_name_for 一致）")
    else:
        fail("Windows 资产名应为 bdl-lsp-windows-amd64.zip / tiptop-windows-amd64.zip")

    # 3. 扩展自己的 Release 也带同名资产（下载链兜底用）
    download_rs = (ROOT / "src" / "download.rs").read_text(encoding="utf-8")
    if "EXT_REPO" in download_rs and "darcyjoven/zed-bdl" in download_rs:
        ok("扩展把本仓库登记为下载兜底仓库（EXT_REPO）")
    else:
        fail("src/download.rs 里找不到 EXT_REPO（下载兜底仓库）")
    for name in ("bdl-lsp-${{ matrix.os }}-${{ matrix.arch }}", "tiptop-${{ matrix.os }}-${{ matrix.arch }}"):
        if name in text:
            ok(f"本扩展的 Release 也带 {name}（兜底同名资产）")
        else:
            fail(f"本扩展的 Release 应也带 {name}")

    # 4. wasm 产物名与 Cargo 包名一致
    cargo = tomllib.load(open(ROOT / "Cargo.toml", "rb"))
    pkg = cargo["package"]["name"]
    wasm_name = pkg.replace("-", "_") + ".wasm"
    if wasm_name in text:
        ok(f"wasm 产物名与 Cargo 包名一致（{wasm_name}）")
    else:
        fail(f"wasm 产物名应为 {wasm_name}")

    # 4b. wasm 必须在**独立的 job** 里编，不能放在四平台矩阵里。
    #     wasm32-wasip2 的产物与目标平台无关；放进矩阵会在 Windows 上
    #     用 PowerShell 跑 bash 语法而失败（2026-10-30 实跑踩过：
    #     release workflow 的 windows/amd64 job 挂在"构建扩展 wasm"）。
    if yaml is not None:
        jobs = data.get("jobs") or {}
        wasm_job = jobs.get("wasm")
        if wasm_job is None:
            fail("缺少 wasm job（wasm32-wasip2 产物与平台无关，应单独编）")
        else:
            ok("有独立的 wasm job")
            build_jobs = jobs.get("build") or {}
            build_steps = " ".join(s.get("name", "") for s in build_jobs.get("steps", []))
            if "wasm" in build_steps.lower():
                fail("build job 里还有 wasm 相关步骤（应只在独立的 wasm job 里编）")
            else:
                ok("四平台 job 里不再编 wasm（避免 Windows 的 shell 差异）")
            # wasm job 必须用 bash（xxd/head 等是 bash 工具）
            wasm_steps = wasm_job.get("steps") or []
            shells = {s.get("shell", "bash") for s in wasm_steps if s.get("run")}
            if shells == {"bash"}:
                ok("wasm job 的脚本都用 bash")
            else:
                fail(f"wasm job 应全用 bash，实际 {shells}")

    # 4c. BUILD-INFO.json 只能有**一份**（放 wasm job 里）。
    #     download-artifact 的 merge-multiple 会让同名文件互相覆盖：
    #     四个平台各出一份 → 只剩最后一份，"target" 字段还会只剩一个平台。
    if yaml is not None:
        jobs = data.get("jobs") or {}
        wasm_job = jobs.get("wasm") or {}
        wasm_step_names = " ".join(s.get("name", "") for s in wasm_job.get("steps", []))
        build_job = jobs.get("build") or {}
        build_step_names = " ".join(s.get("name", "") for s in build_job.get("steps", []))
        if "BUILD-INFO" in wasm_step_names:
            ok("BUILD-INFO.json 在 wasm job 里出（平台无关，只一份）")
        else:
            fail("BUILD-INFO.json 应在 wasm job 里出（放四平台里会互相覆盖）")
        if "BUILD-INFO" in build_step_names:
            fail("build job 里还有 BUILD-INFO.json（会与 wasm job 的那份互相覆盖）")
        else:
            ok("四平台 job 里不再出 BUILD-INFO.json（避免同名覆盖）")

    # 4d. 发布前必须校验"四个平台的产物都在"——少一个就红，
    #     别让 Release 静默缺件（用户下到某个平台才发现没有二进制）。
    if yaml is not None:
        release_job = (data.get("jobs") or {}).get("release") or {}
        release_text = " ".join(s.get("run", "") for s in release_job.get("steps", []))
        if "缺少发布产物" in release_text:
            ok("发布前校验四个平台产物齐全（缺件即红）")
        else:
            fail("发布前应校验产物齐全（缺件即红）")

    # 4e. 每个 job 用到的**相对路径**，必须在该 job 里 checkout 过。
    #     2026-10-30 实跑踩过：wasm job 读 `../bdl-lsp/main.go` 写 BUILD-INFO.json，
    #     但那个 job 根本没 checkout bdl-lsp → 文件不存在 → job 红。
    #     这类错只在 CI 上暴露（本地没有 actions/checkout 的目录结构）。
    #
    # 4f. upload-artifact 的归档结构由**搜索路径的最小公共祖先（LCA）**决定。
    #     多路径上传时，LCA 之外的目录会保留在归档里 —— 下载后找不到文件。
    #     2026-10-30 实跑踩过：wasm artifact 传
    #     `zed-extension/target/.../zed_bdl.wasm` + `zed-extension/BUILD-INFO.json`，
    #     LCA 是 `zed-extension`，wasm 于是以 `target/wasm32-wasip2/release/…`
    #     的形态进归档，release job 找不到它 → 红。
    #     ⇒ 上传前必须先摊平到同一个目录（本次用 `staging/`）。
    if yaml is not None:
        problems: list[str] = []
        for jn, job in (data.get("jobs") or {}).items():
            checked_out: set[str] = set()
            for step in job.get("steps") or []:
                with_ = step.get("with") or {}
                # actions/checkout 的 path（缺省是仓库根）
                if "checkout" in str(step.get("uses", "")):
                    checked_out.add(with_.get("path", "").strip("/"))
                run = step.get("run") or ""
                # 找出脚本里引用的 ../<dir>/… 与 <dir>/… 相对路径
                for m in re.finditer(r"(?:\.\./)?([A-Za-z0-9_.-]+)/[A-Za-z0-9_.-]+\.(?:go|mod|toml|json)", run):
                    d = m.group(1)
                    if d in (
                        "target",
                        "dist",
                        "src",
                        "scripts",
                        "tests",
                        "languages",
                        "docs",
                        "staging",  # job 内部的暂存目录（上传前摊平产物用）
                    ):
                        continue  # 本仓库自己的目录
                    if d not in checked_out and d not in ("bdl-lsp", "tiptop", "zed-extension"):
                        problems.append(f"{jn}.{step.get('name','?')} 引用了 {d}/ 但该 job 没 checkout {d}")
                if d := re.search(r"needs\.prepare\.outputs\.(\w+)", ""):
                    pass
            # 单独检查：run 里出现 ../bdl-lsp/ 或 ../tiptop/ 时，该 job 必须 checkout 过
            for step in job.get("steps") or []:
                run = step.get("run") or ""
                for repo in ("bdl-lsp", "tiptop"):
                    if re.search(rf"\.\./{repo}/", run) and repo not in checked_out:
                        problems.append(
                            f"{jn}.{step.get('name','?')} 读了 ../{repo}/ 但该 job 没 checkout {repo}"
                        )
        if problems:
            for p in problems:
                fail(p)
        else:
            ok("每个 job 用到的外部仓库都 checkout 过")

    # 4f. upload-artifact 的 LCA 检查：多路径上传时，归档内会保留 LCA 之外的目录。
    #     要求每个 upload 步骤的路径都在**同一个目录**下（或只有一个路径）。
    #
    #     注意：**通配符**（`dist/*.tar.gz`）展开后仍在 LCA 之下，是平铺的；
    #     只有**具体文件路径**（`a/b/c.wasm`）才会把 `b/` 带进归档。
    #     所以这里只对"含通配符的路径"与"不同目录"报警。
    if yaml is not None:
        lca_problems: list[str] = []
        for jn, job in (data.get("jobs") or {}).items():
            for step in job.get("steps") or []:
                if "upload-artifact" not in str(step.get("uses", "")):
                    continue
                raw = (step.get("with") or {}).get("path") or ""
                paths = [p.strip().rstrip("/") for p in raw.splitlines() if p.strip()]
                if not paths:
                    continue
                dirs = {p.rsplit("/", 1)[0] if "/" in p else "" for p in paths}
                if len(dirs) > 1:
                    lca_problems.append(
                        f"{jn}.{step.get('name','?')} 的 upload 路径跨了多个目录 {sorted(dirs)}"
                        f"（LCA 之外的目录会进归档，下载后找不到文件）"
                    )
                # 单路径且是具体文件（不含通配符）→ 它的父目录会成为 LCA，
                # 归档里就是平铺的一个文件，**没有问题**；只有路径里还带子目录
                # （如 a/b/c.wasm）才会保留层级。用通配符或目录路径最稳。
                for p in paths:
                    if "*" in p:
                        continue
                    depth = p.count("/")
                    if depth >= 2:
                        lca_problems.append(
                            f"{jn}.{step.get('name','?')} 的 upload 路径 {p} 带 {depth} 层目录"
                            f"（LCA 之外的层级会留在归档里）—— 请先摊平到同一目录"
                        )
        if lca_problems:
            for p in lca_problems:
                fail(p)
        else:
            ok("upload-artifact 的路径不会把子目录带进归档")

    # 5. 版本必须来自 tag，不能硬编码
    if "${{ needs.prepare.outputs.version }}" in text or "${VERSION}" in text:
        ok("版本号来自 tag（不硬编码）")
    else:
        fail("版本号应来自 tag / workflow 输出，不能硬编码")

    print()
    if failures == 0:
        print(f"✓ {checks} 项校验全部通过")
        return 0
    print(f"✗ {failures} 项校验失败")
    return 1


if __name__ == "__main__":
    sys.exit(main())
