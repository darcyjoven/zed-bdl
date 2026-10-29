#!/usr/bin/env bash
# =============================================================================
# 4gl-full / zed-bdl —— Zed 工程初始化脚本（交互式，Linux / macOS / WSL）
#
# 用途
#   在 Zed 里通过 task（或普通终端）跑本脚本，交互式提问后生成/更新项目里的三件套：
#     <项目根>/.zed/settings.json     —— lsp.bdl-lsp 配置（含扩展自用的 ext.*）
#     <项目根>/.zed/tasks.json        —— "4gl:" 开头的 task 模板（写盘 / 长任务的入口）
#     <项目根>/.zed/bdl-tool.json     —— 本次输入值的记录（便于下次重跑）
#
#   为什么需要它：Zed 扩展不能注册命令到命令面板（见 docs/PLAN.md §4、§5.3），
#   写盘 / 长任务的入口是 .zed/tasks.json；而 Zed 的 task **读不到 Zed 设置**，
#   所以要在终端里把值问清楚、内联进 tasks.json。
#
# 用法
#   bash scripts/zed/init-workspace.sh [项目根]
#   项目根默认取：第 1 个位置参数 > $ZED_WORKTREE_ROOT > 当前工作目录。
#   每项都给默认值，**回车即用默认值**；也可以把脚本放进项目里（路径参数化）。
#
#   放进项目的 task（可选）：
#     { "label": "4gl: 初始化 Zed 工程（生成 .zed 配置）",
#       "command": "bash", "args": ["scripts/zed/init-workspace.sh"],
#       "cwd": "$ZED_WORKTREE_ROOT" }
#
# 安全
#   * 本脚本**绝不询问、也绝不写入密码**。密码放 <项目根>/.project/secrets.json
#     （Unix 需 chmod 600）或环境变量 BDL_ORA_PASSWORD，两者都由 tiptop 读取。
#   * .zed/settings.json 已存在时**不覆盖**：建议内容写到 .zed/settings.json.bdl-new，
#     并提示手工合并 lsp.bdl-lsp.settings 那一段。
#   * .zed/tasks.json 已存在时**先备份** .zed/tasks.json.bak（已存在则加时间戳）再写。
#   * .zed/bdl-tool.json 是脚本自己的输入记录，直接覆盖。
#   * 所有生成的 JSON 用 heredoc + 占位符替换生成；有 python3 时写前写后各校验一次。
#   * 写盘前还会断言 tasks.json 里**不含** ${...}（Zed 的 task 变量语法）；生成结果一律 LF 行尾。
#
# 兼容：bash 3.2+（macOS 自带）/ Linux / WSL。python3 可选（用于读回上次的值 + 校验 JSON）。
# =============================================================================

set -u

# ---------------------------------------------------------------------------
# 输出小工具（提示语走 stderr，结果走 stdout，便于 `printf ... | bash script` 喂输入）
# ---------------------------------------------------------------------------

info()    { printf '%s\n' "$*"; }
warn()    { printf '提示：%s\n' "$*" >&2; }
err()     { printf '错误：%s\n' "$*" >&2; }
die()     { err "$*"; exit 1; }
section() { printf '\n== %s\n' "$*"; }

# ask <提示> [默认值]
#   结果放全局 $ANS；空输入（直接回车）或输入流结束（EOF）都回落默认值。
ask() {
    local prompt="$1" def="${2-}" ans=""
    if [ -n "$def" ]; then
        printf '%s [%s]: ' "$prompt" "$def" >&2
    else
        printf '%s [留空]: ' "$prompt" >&2
    fi
    IFS= read -r ans || ans=""
    if [ -z "$ans" ]; then ans="$def"; fi
    ANS="$ans"
}

# 端口：必须是 1-65535 的十进制数字，否则回落默认值。
ask_port() {
    local prompt="$1" def="$2"
    ask "$prompt" "$def"
    case "$ANS" in
        '' | *[!0-9]*) ANS="$def" ;;
    esac
    # 去掉前导零，避免 [ -lt ] 把 08 当八进制解析
    while [ "${ANS#0}" != "$ANS" ] && [ -n "${ANS#0}" ]; do ANS="${ANS#0}"; done
    if [ "${#ANS}" -gt 5 ] || [ "$ANS" -lt 1 ] || [ "$ANS" -gt 65535 ]; then
        warn "端口必须是 1-65535 的数字，已用默认值 $def。"
        ANS="$def"
    fi
}

# 登录区：1=topprod / 2=toptest / 3=topstd / 4=Browser-based
ask_region() {
    local def="${1:-1}"
    ask "登录区（1=topprod / 2=toptest / 3=topstd / 4=Browser-based）" "$def"
    case "$ANS" in
        1 | 2 | 3 | 4) : ;;
        *) warn "登录区只能是 1/2/3/4，已用默认值 $def。"; ANS="$def" ;;
    esac
}

# 上传方式：off（不上传）/ rsync / scp
ask_transport() {
    local def="${1:-off}" v=""
    ask "上传方式（off=不上传 / rsync / scp）" "$def"
    v=$(printf '%s' "$ANS" | tr '[:upper:]' '[:lower:]')
    case "$v" in
        off | rsync | scp) ANS="$v" ;;
        *) warn "上传方式只能是 off / rsync / scp，已用默认值 off。"; ANS="off" ;;
    esac
}

# JSON 字符串转义（反斜杠、双引号、控制字符）。值只经参数替换进模板，不再二次展开。
json_escape() {
    local s="${1-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\r'/\\r}
    s=${s//$'\n'/\\n}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

# fill_template <模板> <token1> <值1> [<token2> <值2> ...]
fill_template() {
    local out="$1"; shift
    while [ "$#" -ge 2 ]; do
        out=${out//$1/"$2"}   # 替换串加引号：值里的 / " \ 都按字面插入
        shift 2
    done
    printf '%s' "$out"
}

# 有 python3 时：写盘前校验内存里的字符串是合法 JSON
validate_json_string() {
    local label="$1" content="$2"
    command -v python3 >/dev/null 2>&1 || return 0
    if printf '%s' "$content" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        return 0
    fi
    err "$label 生成的内容不是合法 JSON（已放弃写盘）。"
    return 1
}

# 有 python3 时：写盘后校验文件是合法 JSON
validate_json_file() {
    local f="$1"
    if ! command -v python3 >/dev/null 2>&1; then
        info "  （无 python3，跳过 JSON 校验）：$f"
        return 0
    fi
    if python3 -c 'import json,sys; json.load(open(sys.argv[1],encoding="utf-8"))' "$f" 2>/dev/null; then
        info "  JSON 校验通过：$f"
    else
        warn "JSON 校验失败，请检查：$f"
        return 1
    fi
}

write_file() {
    local path="$1" content="$2"
    mkdir -p "$(dirname "$path")" || die "无法创建目录：$(dirname "$path")"
    if ! printf '%s\n' "$content" > "$path"; then
        die "写入失败：$path"
    fi
    info "写了 $path"
}

# ---------------------------------------------------------------------------
# 0. 项目根：位置参数 > $ZED_WORKTREE_ROOT > 当前目录（再交互确认）
# ---------------------------------------------------------------------------

ROOT=""
resolve_root() {
    local candidate="$1" p="" tilde="~"
    [ -n "$candidate" ] || candidate="$(pwd)"
    # 交互 read 不会展开 ~，这里自己展开成 $HOME
    # （用变量拼 case 模式，避免 shellcheck SC2088 的"引号里的 ~ 不展开"误报）
    case "$candidate" in
        "$tilde") candidate="$HOME" ;;
        "$tilde"/*) candidate="$HOME/${candidate#"$tilde"/}" ;;
    esac
    [ -d "$candidate" ] || die "项目根不存在或不是目录：$candidate"
    p=$(cd "$candidate" && pwd -P) || die "无法进入项目根：$candidate"
    [ -n "$p" ] || die "无法解析项目根：$candidate"
    ROOT="$p"
}

# ---------------------------------------------------------------------------
# 读回上次的 .zed/bdl-tool.json（有 python3 才做），作为本次提问的默认值
# ---------------------------------------------------------------------------

load_prev_values() {
    command -v python3 >/dev/null 2>&1 || return 0
    [ -f "$TOOL_JSON" ] || return 0
    python3 - "$TOOL_JSON" 2>/dev/null <<'PY' || true
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)

def g(*keys):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return ""
        cur = cur[k]
    return "" if cur is None else str(cur)

rows = [
    ("prev_bdl_lsp", ("bdlLsp", "binaryPath")),
    ("prev_tiptop", ("tiptop", "binaryPath")),
    ("prev_ora_host", ("oracle", "host")),
    ("prev_ora_port", ("oracle", "port")),
    ("prev_ora_service", ("oracle", "service")),
    ("prev_ora_user", ("oracle", "user")),
    ("prev_prod_host", ("prod", "host")),
    ("prev_prod_port", ("prod", "port")),
    ("prev_prod_user", ("prod", "user")),
    ("prev_region", ("prod", "region")),
    ("prev_remote_root", ("prod", "remoteRoot")),
    ("prev_local_root", ("prod", "localRoot")),
    ("prev_transport", ("prod", "transport")),
    ("prev_init_script", ("initProject", "script")),
]
for name, keys in rows:
    print("%s\t%s" % (name, g(*keys)))
PY
}

prev_bdl_lsp=""; prev_tiptop=""
prev_ora_host=""; prev_ora_port=""; prev_ora_service=""; prev_ora_user=""
prev_prod_host=""; prev_prod_port=""; prev_prod_user=""; prev_region=""
prev_remote_root=""; prev_local_root=""; prev_transport=""; prev_init_script=""

# ---------------------------------------------------------------------------
# 提问
# ---------------------------------------------------------------------------

section "4gl-full / zed-bdl —— Zed 工程初始化（交互式）"
info "回车 = 使用 [ ] 里的默认值。本脚本不会询问密码，也不会写入任何密码。"

arg_root="${1-}"
candidate="${arg_root:-${ZED_WORKTREE_ROOT:-$(pwd)}}"
ask "项目根" "$candidate"
resolve_root "$ANS"
PROJECT_ROOT="$ROOT"
info "项目根：$PROJECT_ROOT"

ZED_DIR="$PROJECT_ROOT/.zed"
SETTINGS_JSON="$ZED_DIR/settings.json"
SETTINGS_NEW="$ZED_DIR/settings.json.bdl-new"
TASKS_JSON="$ZED_DIR/tasks.json"
TOOL_JSON="$ZED_DIR/bdl-tool.json"

# 读回上次的值（缺文件 / 无 python3 时全是空串）
while IFS=$'\t' read -r _k _v; do
    case "$_k" in
        prev_bdl_lsp) prev_bdl_lsp="$_v" ;;
        prev_tiptop) prev_tiptop="$_v" ;;
        prev_ora_host) prev_ora_host="$_v" ;;
        prev_ora_port) prev_ora_port="$_v" ;;
        prev_ora_service) prev_ora_service="$_v" ;;
        prev_ora_user) prev_ora_user="$_v" ;;
        prev_prod_host) prev_prod_host="$_v" ;;
        prev_prod_port) prev_prod_port="$_v" ;;
        prev_prod_user) prev_prod_user="$_v" ;;
        prev_region) prev_region="$_v" ;;
        prev_remote_root) prev_remote_root="$_v" ;;
        prev_local_root) prev_local_root="$_v" ;;
        prev_transport) prev_transport="$_v" ;;
        prev_init_script) prev_init_script="$_v" ;;
    esac
done < <(load_prev_values)

if [ -f "$TOOL_JSON" ]; then
    info "发现上次的记录 $TOOL_JSON，回车即沿用上次的值。"
fi

section "1/4 二进制路径"
ask "bdl-lsp 二进制路径（空 = 走 PATH / 工作区 .bdl-lsp/bin/；也可稍后手填 lsp.bdl-lsp.binary.path）" "$prev_bdl_lsp"
BDL_LSP_PATH="$ANS"
ask "tiptop 二进制路径（空 = 走 PATH / 工作区 .bdl-lsp/bin/；脚本会写进 ext.tools.path）" "$prev_tiptop"
TIPTOP_PATH="$ANS"

section "2/4 Oracle 连接（用于直连采集；全部留空 = 只用 CSV 导入）"
warn "这里只问账号。密码请放 .project/secrets.json 或环境变量 BDL_ORA_PASSWORD。"
ask "Oracle 主机" "$prev_ora_host"
ORA_HOST="$ANS"
ask_port "Oracle 端口" "${prev_ora_port:-1521}"
ORA_PORT="$ANS"
ask "Oracle 服务名（service）" "$prev_ora_service"
ORA_SERVICE="$ANS"
ask "Oracle 账号" "$prev_ora_user"
ORA_USER="$ANS"

section "3/4 生产环境（用于上传 / 编译；可全部留空，之后再填）"
ask "SSH 主机" "$prev_prod_host"
PROD_HOST="$ANS"
ask_port "SSH 端口" "${prev_prod_port:-22}"
PROD_PORT="$ANS"
ask "SSH 账号" "$prev_prod_user"
PROD_USER="$ANS"
ask_region "${prev_region:-1}"
REGION="$ANS"
ask "生产根（如 /u1/topprod）" "$prev_remote_root"
REMOTE_ROOT="$ANS"
ask "本地根（相对项目根，默认 .）" "${prev_local_root:-.}"
LOCAL_ROOT="$ANS"
[ -n "$LOCAL_ROOT" ] || LOCAL_ROOT="."
ask_transport "${prev_transport:-off}"
TRANSPORT="$ANS"

section "4/4 init-project 脚本（可留空 = 不生成这条 task）"
ask "init-project 脚本路径（.sh 或 .ps1；空 = 跳过「初始化项目」task）" "$prev_init_script"
INIT_SCRIPT="$ANS"

# 区 → login-profile（区 4 = Browser-based，不传 -login-profile）
case "$REGION" in
    1) LOGIN_PROFILE="/u1/usr/profile/profile.topprod" ;;
    2) LOGIN_PROFILE="/u1/usr/profile/profile.toptest" ;;
    3) LOGIN_PROFILE="/u1/usr/profile/profile.topstd" ;;
    *) LOGIN_PROFILE="" ;;
esac

# exec 的公共参数（-region 必有；-login-profile 除区 4 外加）
EXEC_FLAGS="\"-region\", \"$REGION\""
if [ -n "$LOGIN_PROFILE" ]; then
    EXEC_FLAGS="$EXEC_FLAGS, \"-login-profile\", \"$LOGIN_PROFILE\""
fi

# ---------------------------------------------------------------------------
# 模板（<<'JSON' 单引号定界符 = 原样保留 $ZED_* 等变量，供 Zed 在执行前替换）
#
# ★ 注意：exec 任务里**不能**写 tiptop/VSCode 的模板占位符 ${path} / ${name}：
#   Zed 会把 $… / ${…} 当成**自己的 task 变量**，未知变量不会原样传给 tiptop——
#   要么整条 task 被 task: spawn 列表过滤掉，要么被替换成空串，远端命令直接跑错。
#   所以这里用 Zed 变量表达同样的含义（tiptop 收到的是已经展开的命令）：
#     ${path} / ${fullpath}  →  $ZED_RELATIVE_DIR   当前文件所在目录（相对工作区根）
#     ${name}                →  $ZED_STEM           去扩展名
#     ${fullname}            →  $ZED_FILENAME       含扩展名
#   自己改模板时请沿用这套 Zed 变量。
# ---------------------------------------------------------------------------

# shellcheck disable=SC2016  # 模板里的 $ZED_* 是给 Zed 的，不是给本脚本
SETTINGS_TMPL=$(cat <<'JSON'
{
  "lsp": {
    "bdl-lsp": {
      "binary": { "path": "@@BINARY_PATH@@", "arguments": [], "env": {} },
      "settings": {
        "generoVersion": "2.50",
        "logLevel": "info",
        "link": { "mode": "off", "dataDir": ".project/link", "moduleRoots": [], "globalModules": ["sub", "lib", "qry"] },
        "schema": { "mode": "off", "dataDir": ".project/schema" },
        "ignore": { "files": [], "fields": [], "forms": [] },
        "perRoots": [],
        "limits": { "maxFileBytes": 2097152, "maxFileLines": 20000, "maxIssues": 200, "parseTimeoutMs": 2000 },
        "ext": {
          "tools": { "path": "@@TIPTOP_PATH@@" },
          "schema": { "batchSize": 200, "timeoutSec": 120 },
          "prod": {
            "oracle": { "host": "@@ORA_HOST@@", "port": @@ORA_PORT@@, "service": "@@ORA_SERVICE@@", "user": "@@ORA_USER@@" },
            "deploy": { "host": "@@PROD_HOST@@", "port": @@PROD_PORT@@, "user": "@@PROD_USER@@", "region": "@@REGION@@", "strictHostKey": true, "transport": "@@TRANSPORT@@", "localRoot": "@@LOCAL_ROOT@@", "remoteRoot": "@@REMOTE_ROOT@@" }
          },
          "deploy": { "enable": false },
          "build": { "enable": false }
        }
      }
    }
  },
  "languages": {
    "Genero BDL": { "semantic_tokens": "combined" },
    "Genero Form": { "semantic_tokens": "combined" }
  }
}
JSON
)

# shellcheck disable=SC2016
TASKS_TMPL=$(cat <<'JSON'
[
  {
    "label": "4gl: 链接资料：查看状态",
    "command": "@@TIPTOP@@",
    "args": ["link", "status", "-root", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 链接资料：从 CSV 导入",
    "command": "@@TIPTOP@@",
    "args": ["link", "import", "-csv", "<CSV 绝对路径>", "-root", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 链接资料：全量更新",
    "command": "@@TIPTOP@@",
    "args": ["link", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang", "-host", "@@ORA_HOST@@", "-port", "@@ORA_PORT@@", "-service", "@@ORA_SERVICE@@", "-user", "@@ORA_USER@@"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 链接资料：按模组更新",
    "command": "@@TIPTOP@@",
    "args": ["link", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang", "-host", "@@ORA_HOST@@", "-port", "@@ORA_PORT@@", "-service", "@@ORA_SERVICE@@", "-user", "@@ORA_USER@@", "-modules", "lib,sub,qry"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 链接资料：更新当前文件",
    "command": "@@TIPTOP@@",
    "args": ["link", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang", "-host", "@@ORA_HOST@@", "-port", "@@ORA_PORT@@", "-service", "@@ORA_SERVICE@@", "-user", "@@ORA_USER@@", "-files", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 字段资料：查看状态",
    "command": "@@TIPTOP@@",
    "args": ["schema", "status", "-root", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 字段资料：从 CSV 导入",
    "command": "@@TIPTOP@@",
    "args": ["schema", "import", "-csv", "<CSV 绝对路径>", "-root", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 字段资料：从数据库同步",
    "command": "@@TIPTOP@@",
    "args": ["schema", "sync", "-root", "$ZED_WORKTREE_ROOT", "-source", "golang", "-host", "@@ORA_HOST@@", "-port", "@@ORA_PORT@@", "-service", "@@ORA_SERVICE@@", "-user", "@@ORA_USER@@", "-batch-size", "200", "-timeout", "120"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 上传当前文件",
    "command": "@@TIPTOP@@",
    "args": ["upload", "-workspace", "$ZED_WORKTREE_ROOT", "-file", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "save": "current",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 预演上传",
    "command": "@@TIPTOP@@",
    "args": ["upload", "-workspace", "$ZED_WORKTREE_ROOT", "-file", "$ZED_RELATIVE_FILE", "-dry-run"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "save": "current",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 下载当前文件",
    "command": "@@TIPTOP@@",
    "args": ["download", "-workspace", "$ZED_WORKTREE_ROOT", "-file", "$ZED_RELATIVE_FILE"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  },
  {
    "label": "4gl: 4GL 预演编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 4GL 编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 4GL 链接",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "r.l2 $ZED_STEM", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: Form 预演编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "cd $ZED_RELATIVE_DIR && fglform -M -W all $ZED_FILENAME && rm $ZED_STEM.42f", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: Form 编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "cd $ZED_RELATIVE_DIR && fglform -M -W all $ZED_FILENAME && mv $ZED_STEM.42f ../42f/ && gsform -M -W all -i -import $ZED_FILENAME && mv $ZED_STEM.4fd ../4fd/", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: Form 预览画面",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "cd $ZED_RELATIVE_DIR && r.gf $ZED_STEM 2 p", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 部署预演",
    "command": "@@TIPTOP@@",
    "args": ["deploy", "-workspace", "$ZED_WORKTREE_ROOT", "-dry-run"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 列出部署目标",
    "command": "@@TIPTOP@@",
    "args": ["deploy", "-workspace", "$ZED_WORKTREE_ROOT", "-list"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 部署（整包，需确认）",
    "command": "@@TIPTOP@@",
    "args": ["deploy", "-workspace", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  }@@INIT_TAIL@@
]
JSON
)

TOOL_TMPL=$(cat <<'JSON'
{
  "version": 1,
  "generatedAt": "@@GENERATED_AT@@",
  "generator": "@@GENERATOR@@",
  "projectRoot": "@@PROJECT_ROOT@@",
  "bdlLsp": { "binaryPath": "@@BINARY_PATH@@" },
  "tiptop": { "binaryPath": "@@TIPTOP_PATH@@" },
  "oracle": { "host": "@@ORA_HOST@@", "port": @@ORA_PORT@@, "service": "@@ORA_SERVICE@@", "user": "@@ORA_USER@@" },
  "prod": { "host": "@@PROD_HOST@@", "port": @@PROD_PORT@@, "user": "@@PROD_USER@@", "region": "@@REGION@@", "remoteRoot": "@@REMOTE_ROOT@@", "localRoot": "@@LOCAL_ROOT@@", "transport": "@@TRANSPORT@@" },
  "initProject": { "script": "@@INIT_SCRIPT@@" },
  "generated": { "settings": "@@SETTINGS_REL@@", "tasks": "@@TASKS_REL@@", "tool": "@@TOOL_REL@@" },
  "secrets": { "passwordFile": ".project/secrets.json", "envVar": "BDL_ORA_PASSWORD" },
  "note": "本文件只记录本次输入值，不含密码；删掉它下次就会回到内置默认值。"
}
JSON
)

# 可选的「初始化项目」task（追加在数组末尾，避免额外的逗号处理）
INIT_TAIL=""
if [ -n "$INIT_SCRIPT" ]; then
    case "$INIT_SCRIPT" in
        *.ps1) INIT_CMD="pwsh"; INIT_ARGS="[\"-File\", \"$(json_escape "$INIT_SCRIPT")\"]" ;;
        *)     INIT_CMD="bash"; INIT_ARGS="[\"$(json_escape "$INIT_SCRIPT")\"]" ;;
    esac
    # shellcheck disable=SC2016  # $ZED_WORKTREE_ROOT 是给 Zed 的
    printf -v INIT_TAIL ',\n  {\n    "label": "4gl: 初始化项目（从生产服务器拉取代码）",\n    "command": "%s",\n    "args": %s,\n    "cwd": "$ZED_WORKTREE_ROOT",\n    "use_new_terminal": false,\n    "reveal": "always"\n  }' "$INIT_CMD" "$INIT_ARGS"
fi

# ---------------------------------------------------------------------------
# 替换占位符 → 三份 JSON
# ---------------------------------------------------------------------------

E_BDL_LSP=$(json_escape "$BDL_LSP_PATH")
E_TIPTOP=$(json_escape "$TIPTOP_PATH")
E_ORA_HOST=$(json_escape "$ORA_HOST")
E_ORA_SERVICE=$(json_escape "$ORA_SERVICE")
E_ORA_USER=$(json_escape "$ORA_USER")
E_PROD_HOST=$(json_escape "$PROD_HOST")
E_PROD_USER=$(json_escape "$PROD_USER")
E_REMOTE_ROOT=$(json_escape "$REMOTE_ROOT")
E_LOCAL_ROOT=$(json_escape "$LOCAL_ROOT")
E_INIT_SCRIPT=$(json_escape "$INIT_SCRIPT")

# tiptop 路径为空时 task 里直接写 "tiptop"（走 PATH）
if [ -n "$TIPTOP_PATH" ]; then
    TIPTOP_CMD="$TIPTOP_PATH"
else
    TIPTOP_CMD="tiptop"
fi
E_TIPTOP_CMD=$(json_escape "$TIPTOP_CMD")

# settings 若已存在就不覆盖，改写到 .bdl-new
SETTINGS_REL=".zed/settings.json"
if [ -f "$SETTINGS_JSON" ]; then
    SETTINGS_REL=".zed/settings.json.bdl-new"
fi

SETTINGS_OUT=$(fill_template "$SETTINGS_TMPL" \
    '@@BINARY_PATH@@' "$E_BDL_LSP" \
    '@@TIPTOP_PATH@@' "$E_TIPTOP" \
    '@@ORA_HOST@@' "$E_ORA_HOST" \
    '@@ORA_PORT@@' "$ORA_PORT" \
    '@@ORA_SERVICE@@' "$E_ORA_SERVICE" \
    '@@ORA_USER@@' "$E_ORA_USER" \
    '@@PROD_HOST@@' "$E_PROD_HOST" \
    '@@PROD_PORT@@' "$PROD_PORT" \
    '@@PROD_USER@@' "$E_PROD_USER" \
    '@@REGION@@' "$REGION" \
    '@@TRANSPORT@@' "$TRANSPORT" \
    '@@LOCAL_ROOT@@' "$E_LOCAL_ROOT" \
    '@@REMOTE_ROOT@@' "$E_REMOTE_ROOT")

TASKS_OUT=$(fill_template "$TASKS_TMPL" \
    '@@TIPTOP@@' "$E_TIPTOP_CMD" \
    '@@ORA_HOST@@' "$E_ORA_HOST" \
    '@@ORA_PORT@@' "$ORA_PORT" \
    '@@ORA_SERVICE@@' "$E_ORA_SERVICE" \
    '@@ORA_USER@@' "$E_ORA_USER" \
    '@@EXEC_FLAGS@@' "$EXEC_FLAGS" \
    '@@INIT_TAIL@@' "$INIT_TAIL")

# 兜底断言（见 docs/PLAN.md R12）：Zed 会把 $… / ${…} 当成**自己的** task 变量，
# 未知变量会让整条 task 从 task: spawn 列表消失、或被替换成空串。
# 模板里只允许 Zed 变量（$ZED_RELATIVE_DIR / $ZED_STEM / $ZED_FILENAME 等），
# 一旦生成结果里出现 ${…}，宁可不写盘。
# shellcheck disable=SC2016  # 下面就是要匹配字面量 ${（故意的），不是漏写展开
case "$TASKS_OUT" in
    *'${'*)
        err "tasks.json 里出现了 \${...} 占位符（Zed 会把它当成自己的 task 变量）。已放弃写盘。"
        err "请改用 \$ZED_RELATIVE_DIR / \$ZED_STEM / \$ZED_FILENAME。"
        exit 1
        ;;
esac

TOOL_OUT=$(fill_template "$TOOL_TMPL" \
    '@@GENERATED_AT@@' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '@@GENERATOR@@' "$(json_escape "$0")" \
    '@@PROJECT_ROOT@@' "$(json_escape "$PROJECT_ROOT")" \
    '@@BINARY_PATH@@' "$E_BDL_LSP" \
    '@@TIPTOP_PATH@@' "$E_TIPTOP" \
    '@@ORA_HOST@@' "$E_ORA_HOST" \
    '@@ORA_PORT@@' "$ORA_PORT" \
    '@@ORA_SERVICE@@' "$E_ORA_SERVICE" \
    '@@ORA_USER@@' "$E_ORA_USER" \
    '@@PROD_HOST@@' "$E_PROD_HOST" \
    '@@PROD_PORT@@' "$PROD_PORT" \
    '@@PROD_USER@@' "$E_PROD_USER" \
    '@@REGION@@' "$REGION" \
    '@@REMOTE_ROOT@@' "$E_REMOTE_ROOT" \
    '@@LOCAL_ROOT@@' "$E_LOCAL_ROOT" \
    '@@TRANSPORT@@' "$TRANSPORT" \
    '@@INIT_SCRIPT@@' "$E_INIT_SCRIPT" \
    '@@SETTINGS_REL@@' "$SETTINGS_REL" \
    '@@TASKS_REL@@' ".zed/tasks.json" \
    '@@TOOL_REL@@' ".zed/bdl-tool.json")

# ---------------------------------------------------------------------------
# 写盘（先校验内存内容，再写，再校验文件）
# ---------------------------------------------------------------------------

section "写盘"

validate_json_string "settings.json" "$SETTINGS_OUT" || die "settings.json 生成失败，未写任何文件。"
validate_json_string "tasks.json" "$TASKS_OUT" || die "tasks.json 生成失败，未写任何文件。"
validate_json_string "bdl-tool.json" "$TOOL_OUT" || die "bdl-tool.json 生成失败，未写任何文件。"

mkdir -p "$ZED_DIR" || die "无法创建目录：$ZED_DIR"

if [ -f "$SETTINGS_JSON" ]; then
    write_file "$SETTINGS_NEW" "$SETTINGS_OUT"
    warn "已存在 $SETTINGS_JSON —— 没有覆盖它，建议内容写到了 $SETTINGS_NEW。"
    warn "请手工合并：把 $SETTINGS_NEW 里 lsp.bdl-lsp.settings 那一段并进 settings.json，其余键保留你现有的。"
    warn "合并完可以删掉 $SETTINGS_NEW。"
else
    write_file "$SETTINGS_JSON" "$SETTINGS_OUT"
fi

if [ -f "$TASKS_JSON" ]; then
    TASKS_BAK="$TASKS_JSON.bak"
    if [ -f "$TASKS_BAK" ]; then
        TASKS_BAK="$TASKS_JSON.bak.$(date +%Y%m%d-%H%M%S)"
    fi
    cp "$TASKS_JSON" "$TASKS_BAK" || die "备份失败：$TASKS_JSON"
    info "已备份：$TASKS_BAK"
fi
write_file "$TASKS_JSON" "$TASKS_OUT"
write_file "$TOOL_JSON" "$TOOL_OUT"

validate_json_file "$SETTINGS_JSON" || true
if [ "$SETTINGS_REL" = ".zed/settings.json.bdl-new" ]; then
    validate_json_file "$SETTINGS_NEW" || true
fi
validate_json_file "$TASKS_JSON" || true
validate_json_file "$TOOL_JSON" || true

# ---------------------------------------------------------------------------
# 提示
# ---------------------------------------------------------------------------

section "本次取值"
info "bdl-lsp 二进制：${BDL_LSP_PATH:-（空，走 PATH / 工作区 .bdl-lsp/bin/）}"
info "tiptop 二进制：${TIPTOP_PATH:-（空，走 PATH / 工作区 .bdl-lsp/bin/）}"
info "Oracle：${ORA_HOST:-（空）}:${ORA_PORT}/service=${ORA_SERVICE:-（空）} user=${ORA_USER:-（空）}（密码不在文件里）"
info "生产：${PROD_HOST:-（空）}:${PROD_PORT} user=${PROD_USER:-（空）} region=${REGION} remoteRoot=${REMOTE_ROOT:-（空）} localRoot=$LOCAL_ROOT transport=$TRANSPORT"
if [ -n "$LOGIN_PROFILE" ]; then
    info "exec login-profile：$LOGIN_PROFILE"
else
    info "exec login-profile：区 4（Browser-based）不传"
fi

warn "若填了 Oracle 连接：link.mode / schema.mode 仍写作 off（轻量档）。"
warn "  * 用 CSV 导入资料后，把 .zed/settings.json 里的 link.mode / schema.mode 改成 \"file\"；"
warn "  * 要直连库采集，改成 \"db\"。改完 settings 需要重启 bdl-lsp。"
warn "「4gl: 链接资料：从 CSV 导入」/「4gl: 字段资料：从 CSV 导入」里的 <CSV 绝对路径> 是占位符，跑之前要改成你的 CSV 路径。"
warn "「4gl: 链接资料：按模组更新」里的 -modules lib,sub,qry 是示例，按需改成你的全局模组名。"

cat <<'EOF'

== 下一步
1) 在 Zed 里装上本扩展：命令面板 extension: install dev extension（选本仓库目录），
   或等扩展市场发布后再装。
2) 准备二进制：bdl-lsp / tiptop 放进 PATH，或工作区 .bdl-lsp/bin/；
   也可以手填 .zed/settings.json 的 lsp.bdl-lsp.binary.path、settings.ext.tools.path。
3) 在 Zed 里跑 task: spawn（命令面板），列表里找 "4gl:" 开头的任务；
   常用的建议绑 keymap，例如：
     { "context": "Workspace", "bindings": { "alt-u": ["task::Spawn", { "task_name": "4gl: 上传当前文件" }] } }
4) 资料模式：默认 "off"（轻量档，不连库、不写工作区）；
   * 只用 CSV 导入 → 导入后在 .zed/settings.json 把 link.mode / schema.mode 改成 "file"；
   * 直连 Oracle 采集 → 改成 "db"。
   改完记得重启 bdl-lsp（Zed 的 lsp command selector → restart），设置只在服务器启动时下发。
5) 密码**不在**本脚本里、也不在生成的文件里：
   写 <项目根>/.project/secrets.json（内容 {"<用户名>":"<密码>"}，Unix 必须 chmod 600），
   或用环境变量 BDL_ORA_PASSWORD。tiptop 只从这两处取密码。
6) .gitignore 建议：.zed/settings.json（含主机/账号）、.project/secrets.json；
   .zed/tasks.json 与 .zed/bdl-tool.json 不含密码，可以提交。
7) 本脚本自己不在生成的 tasks.json 里。想以后在 Zed 里一键重跑，先把脚本放进项目：
     mkdir -p .zed/bdl && cp -r <zed-bdl 仓库>/scripts/zed/* .zed/bdl/
   然后手工加一条 task：
   { "label": "4gl: 初始化 Zed 工程（生成 .zed 配置）",
     "command": "bash", "args": [".zed/bdl/init-workspace.sh"],
     "cwd": "$ZED_WORKTREE_ROOT" }
   （Windows 用 "command": "pwsh", "args": ["-File", ".zed\\bdl\\init-workspace.ps1"]）
8) 改 exec 的命令模板时**只用 Zed 变量**：$ZED_RELATIVE_DIR（当前文件目录）、
   $ZED_STEM（去扩展名）、$ZED_FILENAME（含扩展名）。
   不要写 ${path}/${name}/${fullname} —— 那是 VSCode 侧插件的模板占位符，
   Zed 会当成自己的 task 变量处理（未知变量会让整条 task 从 task: spawn 列表消失）。
EOF

info ""
info "完成。"