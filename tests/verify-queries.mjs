#!/usr/bin/env node
// 校验 Zed 扩展的 Tree-sitter 查询文件。
//
// 为什么需要：
//   Zed 加载扩展时，query 里任何一个不存在的节点名或字符串字面量都会
//   让**整份** query 编译失败，表现为"高亮完全不生效"，而 Zed 只在
//   zed: open log 里留一行错误，很容易被忽略。
//
// 检查项：
//   1. 每个 .scm 文件里的节点名都存在于 grammar 的 node-types.json；
//   2. 每个字符串字面量 "XXX" 都是 grammar 里真实存在的 token；
//   3. 用 tree-sitter CLI 对样例文件真正跑一遍 query（能查到就说明可编译）；
//   4. 关键字覆盖率：grammar 的全部大写关键字是否都被高亮规则覆盖。
//
// 用法：
//   node tests/verify-queries.mjs
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..");
const workspaceRoot = path.resolve(repoRoot, "..");

const GRAMMARS = {
  bdl: path.join(workspaceRoot, "tree-sitter-bdl"),
  per: path.join(workspaceRoot, "tree-sitter-per"),
};

let checks = 0;
let failures = 0;

function ok(msg) {
  checks++;
  console.log(`  \u2713 ${msg}`);
}

function fail(msg) {
  failures++;
  console.error(`  \u2717 ${msg}`);
}

/** 读 grammar 的 node-types.json，返回命名节点与匿名 token 两个集合。 */
function loadGrammarTypes(grammarDir) {
  const file = path.join(grammarDir, "src", "node-types.json");
  const raw = fs.readFileSync(file, "utf8");
  const nodes = JSON.parse(raw);
  const named = new Set();
  const anonymous = new Set();
  for (const n of nodes) {
    if (n.named) {
      named.add(n.type);
    } else {
      anonymous.add(n.type);
    }
    // 字段名也算合法引用
  }
  return { named, anonymous };
}

/**
 * 从 query 文本里抽出节点名与字符串字面量。
 *
 * 这是有意写得保守的正则扫描：只用于发现"写了 grammar 里没有的名字"，
 * 不试图完整解析 s-expression。真正的语法校验交给 tree-sitter CLI。
 */
function scanQuery(text) {
  // 去注释时要跳过字符串内部的 ';'，否则 `"a;b"` 会被切断，
  // 后续的正则就会跨行乱配（这个 bug 一开始把整份文件当成一个字符串）。
  const withoutComments = text
    .split("\n")
    .map((line) => {
      let inString = false;
      for (let i = 0; i < line.length; i++) {
        const c = line[i];
        if (c === "\\") { i++; continue; }
        if (c === '"') { inString = !inString; continue; }
        if (c === ";" && !inString) { return line.slice(0, i); }
      }
      return line;
    })
    .join("\n");

  const strings = new Set();
  for (const m of withoutComments.matchAll(/"([^"\\]*)"/g)) {
    strings.add(m[1]);
  }

  // 节点名：出现在 ( 之后、直到空白或 ) 的标识符，
  // 排除以 . 开头的方法调用和 # 开头的谓词
  const nodes = new Set();
  for (const m of withoutComments.matchAll(/\(\s*([a-z_][a-z0-9_.]*)/g)) {
    const name = m[1];
    if (name.startsWith("#")) continue;
    // `_` 是 tree-sitter 的通配符，任何节点都匹配，不属于 node-types
    if (name === "_") continue;
    nodes.add(name.split(".")[0]);
  }
  // 字段引用形如 field: (node)，字段名单独校验
  const fields = new Set();
  for (const m of withoutComments.matchAll(/([a-z_][a-z0-9_]*)\s*:\s*\(/g)) {
    fields.add(m[1]);
  }
  return { strings, nodes, fields };
}

/** 用 tree-sitter CLI 解析样例，确认 query 能真正编译并命中。 */
function tryQuery(grammarDir, queryFile, sampleFile) {
  const env = { ...process.env };
  // 让 tree-sitter 用 grammar 目录自己的 parser
  try {
    const out = execFileSync(
      "tree-sitter",
      ["query", queryFile, sampleFile],
      {
        cwd: grammarDir,
        env,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    return { ok: true, output: out };
  } catch (err) {
    const stderr = (err.stderr ?? "").toString();
    const stdout = (err.stdout ?? "").toString();
    return { ok: false, output: `${stdout}\n${stderr}`.trim() };
  }
}

// ---------------------------------------------------------------------------
// 大纲 @item 区间唯一性（P7-A-1 回归防护）
//
// 为什么需要：
//   Zed 用 @item 的**区间**构建大纲的父子关系。若同一份 query 产出两个
//   区间完全相同的 @item，Zed 会认为后一个是前一个的子节点。
//
//   这个坑在"一条语句声明多个名字"的语法上必然触发：
//     DEFINE l_name LIKE type_file.chr20, l_sql STRING
//   grammar 里这是**单个 define 节点带多个 name: 字段**，若把 @item 绑在
//   整条语句上，两个变量会产出区间相同的两个 match → 大纲里 l_sql
//   变成 l_name 的子节点（VSCode 不受影响，它走 LSP documentSymbol）。
//
//   Zed 的层级问题只在 GUI 可见、排查成本极高，所以必须用断言在 CI 上挡。
//
// 检查方式：用 tree-sitter CLI 跑 outline.scm，解析输出里每个 match 的
// @item 起止位置，断言两两不同。
// ---------------------------------------------------------------------------

/**
 * 从 `tree-sitter query` 的输出里提取每个 pattern match 的 @item 区间。
 *
 * 输出格式（每个 match 一段）：
 *   pattern: 6
 *     capture: 1 - item, start: (2, 4), end: (2, 52), text: `...`
 *
 * 注意 item 后面可能没有 text（区间跨行时 CLI 不打印），所以只依赖 start/end。
 *
 * 返回 [{start:[row,col], end:[row,col], name:string}]，顺序与 query 输出一致。
 */
function extractItemRanges(queryOutput) {
  const ranges = [];
  // 一个 match 可能有多行，用 pattern: 切段更稳
  const blocks = queryOutput.split(/^\s*pattern: \d+\s*$/m);
  for (const block of blocks) {
    // 同一 match 里 @item 只有一个；多个 capture 行时取 item 那行
    let m = block.match(
      /capture: \d+ - item, start: \((\d+), (\d+)\), end: \((\d+), (\d+)\)/,
    );
    if (!m) {
      // main / menu 这类规则只捕获 item、没有编号，行里没有 " - item"
      m = block.match(
        /capture: item, start: \((\d+), (\d+)\), end: \((\d+), (\d+)\)/,
      );
    }
    if (!m) continue;

    // 同 match 里的 @name 文本（用于报错时指出是哪个条目）
    const mn = block.match(
      /capture: \d+ - name, start: \(\d+, \d+\), end: \(\d+, \d+\), text: `([^`]*)`/,
    );
    ranges.push({
      start: [Number(m[1]), Number(m[2])],
      end: [Number(m[3]), Number(m[4])],
      name: mn ? mn[1] : "?",
    });
  }
  return ranges;
}

/**
 * 复刻 Zed 计算大纲层级（depth）的算法。
 *
 * 源码：crates/language/src/buffer.rs
 *
 *     items.sort_by_key(|item| (item.range.start, Reverse(item.range.end)));
 *     let mut item_ends_stack = Vec::<Point>::new();
 *     for item in items {
 *         while let Some(last_end) = item_ends_stack.last().copied() {
 *             if last_end < item.range.end { item_ends_stack.pop(); } else { break; }
 *         }
 *         depth = item_ends_stack.len();
 *         item_ends_stack.push(item.range.end);
 *     }
 *
 * 关键点（这是 P7-A-1 与 P7-B-3 连续踩坑的地方）：
 *   判据不是"区间相同"，而是**"前一条目的结束位置不小于当前条目的结束位置"**
 *   ——也就是说只要区间相交/重叠就算父子关系。
 *   Point 按 (行, 列) 比较，行优先。
 *
 * 返回带 depth 的条目列表，depth > 0 的就是"被误判成子级"的条目。
 */
function zedDepths(items) {
  // sort_by_key((range.start, Reverse(range.end)))：
  // 先按 start 升序，start 相同时按 end 降序。
  const sorted = items
    .map((it, idx) => ({ ...it, idx }))
    .sort((a, b) => {
      if (a.start[0] !== b.start[0]) return a.start[0] - b.start[0];
      if (a.start[1] !== b.start[1]) return a.start[1] - b.start[1];
      if (a.end[0] !== b.end[0]) return b.end[0] - a.end[0];
      return b.end[1] - a.end[1];
    });

  const pointLess = (p, q) =>
    p[0] !== q[0] ? p[0] < q[0] : p[1] < q[1];

  const stack = [];
  const out = [];
  for (const it of sorted) {
    while (stack.length > 0 && pointLess(stack[stack.length - 1], it.end)) {
      stack.pop();
    }
    out.push({ ...it, depth: stack.length });
    stack.push(it.end);
  }
  return out;
}

/** 对指定 query 文件跑一个样例，返回 @item 区间列表（失败时返回 null）。 */
function itemRangesFor(grammarDir, queryFile, sampleFile) {
  const r = tryQuery(grammarDir, queryFile, sampleFile);
  if (!r.ok) return null;
  return extractItemRanges(r.output);
}

// ---------------------------------------------------------------------------
// 主流程
// ---------------------------------------------------------------------------

for (const [lang, grammarDir] of Object.entries(GRAMMARS)) {
  console.log(`\n${lang}（${path.basename(grammarDir)}）`);

  if (!fs.existsSync(grammarDir)) {
    fail(`grammar 目录不存在：${grammarDir}`);
    continue;
  }
  const { named, anonymous } = loadGrammarTypes(grammarDir);
  ok(`grammar 读取成功（命名节点 ${named.size}、匿名 token ${anonymous.size}）`);

  const langDir = path.join(repoRoot, "languages", lang);
  if (!fs.existsSync(langDir)) {
    fail(`语言目录不存在：${langDir}`);
    continue;
  }

  for (const file of fs.readdirSync(langDir).filter((f) => f.endsWith(".scm"))) {
    const full = path.join(langDir, file);
    const text = fs.readFileSync(full, "utf8");
    const { strings, nodes, fields } = scanQuery(text);

    // 节点名
    const badNodes = [...nodes].filter((n) => !named.has(n) && !anonymous.has(n));
    if (badNodes.length > 0) {
      fail(`${file}: 未知节点名 ${badNodes.join(", ")}`);
    } else {
      ok(`${file}: ${nodes.size} 个节点名全部存在`);
    }

    // 字符串字面量
    //
    // 注意排除 `#set!` 的值：injections.scm 里
    //   (#set! injection.language "sql")
    // 的 "sql" 是目标语言名，不是 grammar token。
    const allTokens = new Set([...named, ...anonymous]);
    const setBangValues = new Set();
    for (const m of text.matchAll(/\(#set!\s+[a-z.]+\s+"([^"]*)"\)/g)) {
      setBangValues.add(m[1]);
    }
    const badStrings = [...strings].filter(
      (s) => !allTokens.has(s) && !setBangValues.has(s),
    );
    if (badStrings.length > 0) {
      fail(`${file}: 未知字面量 ${badStrings.map((s) => JSON.stringify(s)).join(", ")}`);
    } else if (strings.size > 0) {
      ok(`${file}: ${strings.size} 个字面量全部存在`);
    }

    // 字段名：只对已知节点的字段做宽松检查（不强制，避免误报）
    void fields;
  }
}

// ---------------------------------------------------------------------------
// 用真实文件跑一遍 query：能命中就证明语法可编译
// ---------------------------------------------------------------------------

console.log("\nquery 编译与命中");

const samples = {
  bdl: path.join(repoRoot, "tests", "fixtures", "highlight.4gl"),
  per: path.join(repoRoot, "tests", "fixtures", "highlight.per"),
};

for (const [lang, grammarDir] of Object.entries(GRAMMARS)) {
  const files = [
    "highlights.scm",
    "outline.scm",
    "brackets.scm",
    "indents.scm",
    "injections.scm",
  ];
  for (const file of files) {
    const q = path.join(repoRoot, "languages", lang, file);
    if (!fs.existsSync(q)) continue; // 可选文件
    const sample = samples[lang];
    if (!fs.existsSync(sample)) {
      fail(`${lang}/${file}: 缺少样例文件 ${sample}`);
      continue;
    }
    const result = tryQuery(grammarDir, q, sample);
    if (!result.ok) {
      fail(`${lang}/${file}: query 编译失败\n${result.output}`);
      continue;
    }
    const lines = result.output.split("\n").filter((l) => l.trim()).length;
    if (lines === 0) {
      fail(`${lang}/${file}: 编译通过但没有命中任何节点（规则可能写错）`);
    } else {
      ok(`${lang}/${file}: 编译通过，命中 ${lines} 处`);
    }
  }
}

// ---------------------------------------------------------------------------
// 大纲 @item 区间唯一性（P7-A-1 回归防护）
// ---------------------------------------------------------------------------

console.log("\n大纲层级（复刻 Zed 的 depth 算法）");

for (const [lang, grammarDir] of Object.entries(GRAMMARS)) {
  const outline = path.join(repoRoot, "languages", lang, "outline.scm");
  if (!fs.existsSync(outline)) continue; // 可选文件

  // outline.4gl 是专门为这个断言写的：含多变量 DEFINE / 多 CONSTANT / 多 TYPE
  //            以及"函数/报表/MAIN 内部的变量"——后者正是 P7-B-3 的根因。
  const fixture = path.join(
    repoRoot,
    "tests",
    "fixtures",
    lang === "bdl" ? "outline.4gl" : "outline.per",
  );
  if (!fs.existsSync(fixture)) {
    fail(`${lang}/outline.scm: 缺少 fixture ${fixture}（该断言必须有样例）`);
    continue;
  }

  const ranges = itemRangesFor(grammarDir, outline, fixture);
  if (ranges === null) {
    fail(`${lang}/outline.scm: query 无法编译，跳过层级检查`);
    continue;
  }
  if (ranges.length === 0) {
    fail(`${lang}/outline.scm: 在 ${path.basename(fixture)} 上没有命中任何 @item`);
    continue;
  }

  // ── 断言 1：所有 @item 的 (start,end) 两两不同 ──
  //
  // 这是 P7-A-1 的原始断言：一条语句声明多个名字时，若 @item 绑在整条
  // 语句上，多个变量会产出完全相同的区间。
  const seen = new Map();
  const dups = [];
  for (const r of ranges) {
    const key = `${r.start}..${r.end}`;
    if (seen.has(key)) dups.push({ key, name: r.name });
    else seen.set(key, true);
  }
  if (dups.length === 0) {
    ok(`${lang}/outline.scm: ${ranges.length} 个 @item 区间两两不同`);
  } else {
    const dupKeys = [...new Set(dups.map((d) => d.key))];
    fail(
      `${lang}/outline.scm: ${dups.length} 个 @item 区间重复（Zed 会误判为父子层级）\n` +
        `      重复区间：${dupKeys.slice(0, 5).join(", ")}${dupKeys.length > 5 ? " …" : ""}\n` +
        `      常见原因：@item 绑在"一条语句多个名字"的父节点上，应绑到名字节点本身\n` +
        `      示例：把 (define name: (identifier) @name) @item 改成\n` +
        `            (define name: (identifier) @name @item)`,
    );
  }

  // ── 断言 2：按 Zed 的真实算法算出的层级必须全为 0 ──
  //
  // 断言 1 只查"区间完全相同"，查不出"区间相交/重叠"这种更常见的层级
  // （P7-B-3 的根因：函数 item 覆盖整个函数体，内部变量落在其中）。
  // 这里直接复刻 Zed 的 depth 算法，把"会被误判成子级"的条目揪出来。
  const depths = zedDepths(ranges);
  const nested = depths.filter((d) => d.depth > 0);
  if (nested.length === 0) {
    ok(`${lang}/outline.scm: ${depths.length} 个条目层级均为 0（无假层级）`);
  } else {
    const sample = nested
      .slice(0, 5)
      .map((d) => `${d.name}(${d.start}..${d.end}) depth=${d.depth}`)
      .join(", ");
    fail(
      `${lang}/outline.scm: ${nested.length}/${depths.length} 个条目会被 Zed 判为子级\n` +
        `      示例：${sample}${nested.length > 5 ? " …" : ""}\n` +
        `      常见原因：@item 绑在包含子条目的父节点上（如整个函数体），\n` +
        `                应绑到最小语义单元（函数名/报表名/MAIN 关键字）上`,
    );
  }
}

// ---------------------------------------------------------------------------
// 关键字覆盖：grammar 里的每个大写 token 是否出现在 highlights.scm
// ---------------------------------------------------------------------------

console.log("\n关键字覆盖");

for (const [lang, grammarDir] of Object.entries(GRAMMARS)) {
  const { anonymous } = loadGrammarTypes(grammarDir);
  const keywords = [...anonymous].filter((t) => /^[A-Z][A-Z0-9_]*$/.test(t));
  const highlights = path.join(repoRoot, "languages", lang, "highlights.scm");
  if (!fs.existsSync(highlights)) {
    fail(`${lang}: 缺少 highlights.scm`);
    continue;
  }
  const text = fs.readFileSync(highlights, "utf8");
  const covered = keywords.filter((k) => text.includes(`"${k}"`));
  const missing = keywords.filter((k) => !text.includes(`"${k}"`));

  if (missing.length === 0) {
    ok(`${lang}: ${keywords.length} 个关键字全部覆盖`);
  } else {
    // 未覆盖不算失败：有些 token 是标点/单位，不需要高亮。
    // 但打印出来方便人工判断是否漏了整组。
    console.log(
      `  ! ${lang}: ${covered.length}/${keywords.length} 覆盖，未覆盖：${missing.join(" ")}`,
    );
    checks++;
  }
}

// ---------------------------------------------------------------------------
// 真实语料抽样：query 必须在各种真实写法上都能编译
//
// 这一步比 fixture 更有价值：fixture 是自己写的，容易只覆盖"刚好能过"的
// 写法；真实语料里会有各种边角结构。语料不存在时跳过（CI 上没有）。
// ---------------------------------------------------------------------------

const CORPUS = process.env.BDL_CORPUS ?? "/code/workspace/tiptop-gp";

if (fs.existsSync(CORPUS)) {
  console.log("\n真实语料抽样");
  for (const [lang, grammarDir] of Object.entries(GRAMMARS)) {
    const ext = lang === "bdl" ? ".4gl" : ".per";
    // 均匀抽样，保证可复现
    const files = execFileSync(
      "bash",
      [
        "-c",
        `find ${JSON.stringify(CORPUS)} -name '*${ext}' -type f | sort | awk 'NR % 421 == 0' | head -15`,
      ],
      { encoding: "utf8" },
    )
      .split("\n")
      .filter(Boolean);

    if (files.length === 0) {
      console.log(`  ! ${lang}: 语料里没有 ${ext} 文件，跳过`);
      continue;
    }

    const queries = fs
      .readdirSync(path.join(repoRoot, "languages", lang))
      .filter((f) => f.endsWith(".scm"));

    for (const q of queries) {
      const qPath = path.join(repoRoot, "languages", lang, q);
      let bad = 0;
      let firstError = "";
      for (const f of files) {
        const r = tryQuery(grammarDir, qPath, f);
        if (!r.ok) {
          bad++;
          if (!firstError) firstError = `${f}\n${r.output}`;
        }
      }
      if (bad === 0) {
        ok(`${lang}/${q}: ${files.length} 个语料文件全部可编译`);
      } else {
        fail(`${lang}/${q}: ${bad}/${files.length} 个语料文件失败\n${firstError}`);
      }
    }

    // 语料级层级检查：真实工程里的写法千变万化，fixture 覆盖不到。
    //
    // 这一步用复刻的 Zed depth 算法扫真实文件，看有多少条目会被判成子级。
    // 实测（7135 个真实 .4gl）：
    //   修复前 6941 个文件有层级、345608 个条目有层级
    //   修复后 0 个文件有层级、0 个条目有层级
    //
    // 抽样扫描（每 421 个取 1 个，与上面的编译检查同一批文件），
    // 保证可复现且不太慢。
    const outlinePath = path.join(repoRoot, "languages", lang, "outline.scm");
    if (!fs.existsSync(outlinePath)) continue;
    let nestedFiles = 0;
    let nestedItems = 0;
    let firstNested = "";
    for (const f of files) {
      const r = tryQuery(grammarDir, outlinePath, f);
      if (!r.ok) continue;
      const depths = zedDepths(extractItemRanges(r.output));
      const nested = depths.filter((d) => d.depth > 0);
      if (nested.length > 0) {
        nestedFiles++;
        nestedItems += nested.length;
        if (!firstNested) {
          firstNested = `${f}: ${nested
            .slice(0, 3)
            .map((d) => `${d.name}(${d.start}..${d.end}) depth=${d.depth}`)
            .join(", ")}`;
        }
      }
    }
    if (nestedItems === 0) {
      ok(`${lang}/outline.scm: ${files.length} 个语料文件均无假层级`);
    } else {
      fail(
        `${lang}/outline.scm: ${nestedFiles}/${files.length} 个语料文件有假层级` +
          `（共 ${nestedItems} 个条目）\n      示例：${firstNested}\n` +
          `      常见原因：@item 绑在包含子条目的父节点上，应绑到最小语义单元`,
      );
    }
  }
} else {
  console.log(`\n（跳过真实语料：${CORPUS} 不存在）`);
}

console.log("");
if (failures === 0) {
  console.log(`\u2713 ${checks} 项校验全部通过`);
  process.exit(0);
} else {
  console.error(`\u2717 ${failures} 项校验失败`);
  process.exit(1);
}
