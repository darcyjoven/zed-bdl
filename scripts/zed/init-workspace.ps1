#Requires -Version 5.1
# =============================================================================
# 4gl-full / zed-bdl —— Zed 工程初始化脚本（交互式，Windows / PowerShell 5.1+）
#
# 用途
#   在 Zed 里通过 task（或普通终端）跑本脚本，交互式提问后生成/更新项目里的三件套：
#     <项目根>\.zed\settings.json     —— lsp.bdl-lsp 配置（含扩展自用的 ext.*）
#     <项目根>\.zed\tasks.json        —— "4gl:" 开头的 task 模板（写盘 / 长任务的入口）
#     <项目根>\.zed\bdl-tool.json     —— 本次输入值的记录（便于下次重跑）
#
#   为什么需要它：Zed 扩展不能注册命令到命令面板（见 docs\PLAN.md §4、§5.3），
#   写盘 / 长任务的入口是 .zed\tasks.json；而 Zed 的 task **读不到 Zed 设置**，
#   所以要在终端里把值问清楚、内联进 tasks.json。
#
#   本脚本与同目录的 init-workspace.sh 行为等价（仅平台相关文案/命令不同）。
#
# 用法
#   pwsh -File .zed\bdl\init-workspace.ps1 [项目根]
#   （Windows PowerShell 5.1 也可以：powershell -ExecutionPolicy Bypass -File scripts\zed\init-workspace.ps1 [项目根]）
#   项目根默认取：第 1 个位置参数 > $env:ZED_WORKTREE_ROOT > 当前工作目录。
#   每项都给默认值，**回车即用默认值**（Read-Host 直接回车 = 空串 = 默认值；
#   标准输入被重定向 / 读不到（EOF）时同样回落默认值）。
#
#   放进项目的 task（可选）：
#     { "label": "4gl: 初始化 Zed 工程（生成 .zed 配置）",
#       "command": "pwsh", "args": ["-File", ".zed\\bdl\\init-workspace.ps1"],
#       "cwd": "$ZED_WORKTREE_ROOT" }
#
# 安全
#   * 本脚本**绝不询问、也绝不写入密码**。密码放 <项目根>\.project\secrets.json
#     （Windows 不校验文件权限；Unix 需 chmod 600）或环境变量 BDL_ORA_PASSWORD，
#     两者都由 tiptop 读取。
#   * .zed\settings.json 已存在时**不覆盖**：建议内容写到 .zed\settings.json.bdl-new，
#     并提示手工合并 lsp.bdl-lsp.settings 那一段。
#   * .zed\tasks.json 已存在时**先备份** .zed\tasks.json.bak（已存在则加时间戳）再写。
#   * .zed\bdl-tool.json 是脚本自己的输入记录，直接覆盖。
#   * 生成的 JSON 用单引号 here-string + 占位符替换生成；写前写后各用 ConvertFrom-Json 校验一次。
#   * 写盘前还会断言 tasks.json 里**不含** ${...}（Zed 的 task 变量语法）；生成结果一律 LF 行尾。
#
# 编码：本文件保存为 **UTF-8（带 BOM）+ CRLF** —— Windows PowerShell 5.1 只有见到 BOM
#       才会按 UTF-8 读 .ps1，否则会把中文 label 按系统 ANSI 码页解码成乱码；
#       CRLF 与仓库 .gitattributes 的 `*.ps1 text eol=crlf` 一致。
# 兼容：Windows PowerShell 5.1 与 PowerShell 7（pwsh）都可以跑。
#       读回上次的 .zed\bdl-tool.json 用 ConvertFrom-Json，不需要 python3。
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 输出小工具（提示语也走主机输出，便于 `echo '' | pwsh -File ...` 喂输入）
# ---------------------------------------------------------------------------

function Write-Info([string]$Message) { Write-Host $Message }
function Write-Warn([string]$Message) { Write-Host ("提示：" + $Message) -ForegroundColor Yellow }
function Write-Section([string]$Message) { Write-Host ''; Write-Host ("== " + $Message) }

# Ask <提示> [默认值]：结果作为返回值；空输入或读取失败（EOF）都回落默认值。
function Ask([string]$Prompt, [string]$Default = '') {
    $suffix = ' [留空]: '
    if (-not [string]::IsNullOrEmpty($Default)) { $suffix = ' [' + $Default + ']: ' }
    $ans = ''
    try {
        $ans = Read-Host ($Prompt + $suffix)
    } catch {
        $ans = ''
    }
    if ([string]::IsNullOrEmpty($ans)) { return $Default }
    return $ans
}

# 端口：必须是 1-65535 的十进制数字，否则回落默认值（与 bash 版同样先剥前导零）。
function Ask-Port([string]$Prompt, [int]$Default) {
    $raw = Ask $Prompt ([string]$Default)
    # 非纯数字（含空串）：静默回落默认值，与 bash 的 case 分支一致
    if ($raw -notmatch '^[0-9]+$') { return $Default }
    $trimmed = $raw.TrimStart('0')
    if ([string]::IsNullOrEmpty($trimmed)) { $trimmed = '0' }
    $v = 0
    if (($trimmed.Length -gt 5) -or (-not [int]::TryParse($trimmed, [ref]$v)) -or ($v -lt 1) -or ($v -gt 65535)) {
        Write-Warn ("端口必须是 1-65535 的数字，已用默认值 " + $Default + "。")
        return $Default
    }
    return $v
}

# 登录区：1=topprod / 2=toptest / 3=topstd / 4=Browser-based
function Ask-Region([string]$Default = '1') {
    $raw = Ask '登录区（1=topprod / 2=toptest / 3=topstd / 4=Browser-based）' $Default
    if (@('1', '2', '3', '4') -contains $raw) { return $raw }
    Write-Warn ("登录区只能是 1/2/3/4，已用默认值 " + $Default + "。")
    return $Default
}

# 上传方式：off（不上传）/ rsync / scp
function Ask-Transport([string]$Default = 'off') {
    $raw = (Ask '上传方式（off=不上传 / rsync / scp）' $Default).ToLowerInvariant()
    if (@('off', 'rsync', 'scp') -contains $raw) { return $raw }
    Write-Warn '上传方式只能是 off / rsync / scp，已用默认值 off。'
    return 'off'
}

# JSON 字符串转义（反斜杠、双引号、控制字符）。值只经 String.Replace 进模板，不再二次展开。
function ConvertTo-JsonText([string]$Value) {
    if ($null -eq $Value) { return '' }
    $Value = $Value.Replace([string]'\', [string]'\\')
    $Value = $Value.Replace([string]'"', [string]'\"')
    $Value = $Value.Replace([string]"`r", [string]'\r')
    $Value = $Value.Replace([string]"`n", [string]'\n')
    $Value = $Value.Replace([string]"`t", [string]'\t')
    return $Value
}

# Fill-Template <模板> <hashtable>：把 @@TOKEN@@ 按字面替换成转义好的值。
# 按 token 长度从长到短替换，避免一个 token 是另一个 token 前缀时的误替换。
function Fill-Template([string]$Template, [hashtable]$Tokens) {
    $out = $Template
    $keys = @($Tokens.Keys) | Sort-Object -Property Length -Descending
    foreach ($key in $keys) {
        $out = $out.Replace([string]$key, [string]$Tokens[$key])
    }
    # 生成的 JSON 一律用 LF 行尾：与 bash 版写出的字节一致，
    # 也符合仓库 .gitattributes 的 `* text=auto eol=lf`（避免 Windows 上提交后反复改动）。
    return $out.Replace([string]"`r`n", [string]"`n")
}

# 写盘前：内存里的字符串是合法 JSON 吗？
function Test-JsonText([string]$Text) {
    try {
        $null = $Text | ConvertFrom-Json
        return $true
    } catch {
        return $false
    }
}

# 写盘后：文件是合法 JSON 吗？（自校验；失败只提示，保留文件供人工查看）
function Assert-JsonFile([string]$Path) {
    try {
        $null = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Info ("  JSON 校验通过：" + $Path)
        return $true
    } catch {
        Write-Warn ("JSON 校验失败，请检查：" + $Path + " —— " + $_.Exception.Message)
        return $false
    }
}

# 写 UTF-8 **无 BOM**（JSON 不带 BOM 最干净，与 bash 版的 printf 写盘一致）
function Write-Utf8NoBom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $enc = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    try {
        [System.IO.File]::WriteAllText($Path, $Content + "`n", $enc)
    } catch {
        Write-Host ('错误：写入失败：' + $Path + ' —— ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    Write-Info ("写了 " + $Path)
}

# 写 UTF-8 **带 BOM**：只有 .ps1 需要（Windows PowerShell 5.1 没有 BOM 会把中文按
# ANSI 码页解码成乱码）；生成的 JSON 一律无 BOM（见上）。
function Write-Utf8Bom([string]$Path, [string]$Content) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $enc = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $true
    try {
        [System.IO.File]::WriteAllText($Path, $Content + "`r`n", $enc)
    } catch {
        Write-Host ('错误：写入失败：' + $Path + ' —— ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    Write-Info ("写了 " + $Path)
}

# ---------------------------------------------------------------------------
# 0. 项目根：位置参数 > $env:ZED_WORKTREE_ROOT > 当前目录（再交互确认）
# ---------------------------------------------------------------------------

function Resolve-Root([string]$Path) {
    if ([string]::IsNullOrEmpty($Path)) { throw '项目根为空。' }
    $p = $Path
    if ($p -eq '~') {
        $p = $HOME
    } elseif ($p.StartsWith('~/') -or $p.StartsWith('~\')) {
        $p = Join-Path $HOME $p.Substring(2)
    }
    if (-not [System.IO.Path]::IsPathRooted($p)) {
        $p = Join-Path (Get-Location).ProviderPath $p
    }
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        throw ('项目根不存在或不是目录：' + $p)
    }
    return (Get-Item -LiteralPath $p).FullName
}

# ---------------------------------------------------------------------------
# 读回上次的 .zed\bdl-tool.json（用 ConvertFrom-Json），作为本次提问的默认值
# 文件不存在 / 不是合法 JSON / 类型不对：一律忽略，绝不报错中断。
# ---------------------------------------------------------------------------

function Get-Prev([string]$Path, [string]$Default = '') {
    if ($null -eq $prev) { return $Default }
    $cur = $prev
    foreach ($k in $Path.Split('.')) {
        if ($null -eq $cur) { return $Default }
        $prop = $cur.PSObject.Properties[$k]
        if ($null -eq $prop) { return $Default }
        $cur = $prop.Value
    }
    if ($null -eq $cur) { return $Default }
    return [string]$cur
}

# 旧记录里的端口（可能被手工改坏）：解析失败就回落默认值，绝不抛异常。
function Get-PrevPort([string]$Path, [int]$Default) {
    $raw = Get-Prev $Path ''
    $v = 0
    if ([int]::TryParse($raw, [ref]$v)) { return $v }
    return $Default
}

$prev = $null

# ---------------------------------------------------------------------------
# 提问
# ---------------------------------------------------------------------------

Write-Section '4gl-full / zed-bdl —— Zed 工程初始化（交互式）'
Write-Info '回车 = 使用 [ ] 里的默认值。本脚本不会询问密码，也不会写入任何密码。'

$candidate = $ProjectRoot
if ([string]::IsNullOrEmpty($candidate)) { $candidate = $env:ZED_WORKTREE_ROOT }
if ([string]::IsNullOrEmpty($candidate)) { $candidate = (Get-Location).ProviderPath }
$answer = Ask '项目根' $candidate
try {
    $root = Resolve-Root $answer
} catch {
    Write-Host ('错误：' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
Write-Info ('项目根：' + $root)

$zedDir = Join-Path $root '.zed'
$settingsJson = Join-Path $zedDir 'settings.json'
$settingsNew = Join-Path $zedDir 'settings.json.bdl-new'
$tasksJson = Join-Path $zedDir 'tasks.json'
$toolJson = Join-Path $zedDir 'bdl-tool.json'

# 读回上次的值（缺文件 / 内容坏掉时全是空串）
if (Test-Path -LiteralPath $toolJson -PathType Leaf) {
    try {
        $prev = (Get-Content -LiteralPath $toolJson -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        $prev = $null
    }
    Write-Info ('发现上次的记录 ' + $toolJson + '，回车即沿用上次的值。')
}

Write-Section '1/4 二进制路径'
$bdlLspPath = Ask 'bdl-lsp 二进制路径（空 = 走 PATH / 工作区 .bdl-lsp\bin\；也可稍后手填 lsp.bdl-lsp.binary.path）' (Get-Prev 'bdlLsp.binaryPath')
$tiptopPath = Ask 'tiptop 二进制路径（空 = 走 PATH / 工作区 .bdl-lsp\bin\；脚本会写进 ext.tools.path）' (Get-Prev 'tiptop.binaryPath')

Write-Section '2/4 Oracle 连接（用于直连采集；全部留空 = 只用 CSV 导入）'
Write-Warn '这里只问账号。密码请放 .project\secrets.json 或环境变量 BDL_ORA_PASSWORD。'
$oraHost = Ask 'Oracle 主机' (Get-Prev 'oracle.host')
$oraPort = Ask-Port 'Oracle 端口' (Get-PrevPort 'oracle.port' 1521)
$oraService = Ask 'Oracle 服务名（service）' (Get-Prev 'oracle.service')
$oraUser = Ask 'Oracle 账号' (Get-Prev 'oracle.user')

Write-Section '3/4 生产环境（用于上传 / 编译；可全部留空，之后再填）'
$prodHost = Ask 'SSH 主机' (Get-Prev 'prod.host')
$prodPort = Ask-Port 'SSH 端口' (Get-PrevPort 'prod.port' 22)
$prodUser = Ask 'SSH 账号' (Get-Prev 'prod.user')
$region = Ask-Region (Get-Prev 'prod.region' '1')
$remoteRoot = Ask '生产根（如 /u1/topprod）' (Get-Prev 'prod.remoteRoot')
$localRoot = Ask '本地根（相对项目根，默认 .）' (Get-Prev 'prod.localRoot' '.')
if ([string]::IsNullOrEmpty($localRoot)) { $localRoot = '.' }
$transport = Ask-Transport (Get-Prev 'prod.transport' 'off')

Write-Section '4/4 init-project 脚本（回车 = 用仓库自带的；填路径 = 用你自己的）'
# 默认用**仓库自带的** scripts/init-project/init-project.ps1 —— 它与 VSCode 侧是同一套
# （从生产服务器拉代码）。以前这里默认留空、让用户自己填路径，结果生成的 task
# 指向一个**并不存在**的文件，点下去必然失败。
$defaultInitScript = ''
# 找仓库自带的 init-project。**必须覆盖两种常见布局**：
#   A. 在仓库里跑：<repo>/scripts/zed/init-workspace.ps1
#   B. 脚本被拷进项目后跑：<proj>/.zed/bdl/init-workspace.ps1
#        （这时上面那些相对路径全都落空 —— 踩过的坑：默认值变空 → 不生成 task，
#          而用户看到的是"[留空]"，完全不知道为什么）
foreach ($cand in @(
    (Join-Path $PSScriptRoot 'init-project/init-project.ps1'),
    (Join-Path $PSScriptRoot '../init-project/init-project.ps1'),
    (Join-Path $PSScriptRoot '../../scripts/init-project/init-project.ps1'),
    (Join-Path (Join-Path $zedDir 'bdl') 'init-project/init-project.ps1'),
    (Join-Path (Join-Path $root 'scripts') 'init-project/init-project.ps1'),
    (Join-Path (Join-Path (Join-Path $root '.zed') 'bdl') 'init-project/init-project.ps1')
)) {
    if (Test-Path -LiteralPath $cand) { $defaultInitScript = (Resolve-Path -LiteralPath $cand).Path; break }
}
if ([string]::IsNullOrEmpty($defaultInitScript)) {
    Write-Warn '找不到仓库自带的 init-project 脚本（找过多个位置都没命中）。'
    Write-Warn '  * 回车会**跳过**「初始化项目」task；'
    Write-Warn '  * 要用它请填脚本的绝对路径，例如 <zed-bdl 仓库>/scripts/init-project/init-project.ps1。'
}
$initScript = Ask 'init-project 脚本路径（回车=用仓库自带；填 .sh/.ps1 路径=用你自己的；填 skip=不生成这条 task）' $defaultInitScript
if ($initScript -eq 'skip' -or $initScript -eq 'none') { $initScript = '' }

# 区 → login-profile（区 4 = Browser-based，不传 -login-profile）
$loginProfile = ''
switch ($region) {
    '1' { $loginProfile = '/u1/usr/profile/profile.topprod' }
    '2' { $loginProfile = '/u1/usr/profile/profile.toptest' }
    '3' { $loginProfile = '/u1/usr/profile/profile.topstd' }
}

# exec 的公共参数（-region 必有；-login-profile 除区 4 外加）
$execFlags = '"-region", "' + $region + '"'
if (-not [string]::IsNullOrEmpty($loginProfile)) {
    $execFlags = $execFlags + ', "-login-profile", "' + $loginProfile + '"'
}

# ---------------------------------------------------------------------------
# 模板（@' ... '@ 单引号 here-string = 原样保留 $ZED_* 等变量，供 Zed 在执行前替换）
#
# ★ 注意：exec 任务里**不能**写 tiptop/VSCode 的模板占位符 ${path} / ${name} / ${fullname}：
#   Zed 会把 $… / ${…} 当成**自己的 task 变量**，未知变量不会原样传给 tiptop——
#   要么整条 task 被 task: spawn 列表过滤掉，要么被替换成空串，远端命令直接跑错。
#   所以这里用 Zed 变量表达同样的含义（tiptop 收到的是已经展开的命令）：
#     ${path} / ${fullpath}  →  $ZED_RELATIVE_DIR   当前文件所在目录（相对工作区根）
#     ${name}                →  $ZED_STEM           去扩展名
#     ${fullname}            →  $ZED_FILENAME       含扩展名
#   自己改模板时请沿用这套 Zed 变量。
#   下面三份模板全部用单引号 here-string（@' … '@）：PowerShell 不会在里面插值，
#   所以 $ZED_* 是**字面量**写进 JSON 的（这一点已用 grep 静态核对）。
# ---------------------------------------------------------------------------

$settingsTmpl = @'
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
  },
  "code_lens": "on"
}
'@

$tasksTmpl = @'
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
    "args": ["exec", "-command", "@@CMD_4GL_PREVIEW@@", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 4GL 编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "@@CMD_4GL_COMPILE@@", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: 4GL 链接",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "@@CMD_4GL_LINK@@", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: Form 预演编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "@@CMD_PER_PREVIEW@@", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: Form 编译",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "@@CMD_PER_COMPILE@@", @@EXEC_FLAGS@@],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "allow_concurrent_runs": true,
    "reveal": "always"
  },
  {
    "label": "4gl: Form 预览画面",
    "command": "@@TIPTOP@@",
    "args": ["exec", "-command", "@@CMD_PER_FORM@@", @@EXEC_FLAGS@@],
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
  },
  {
    "label": "4gl: 迁移项目资料目录（旧目录 → .project/）",
    "command": "pwsh",
    "args": ["-File", ".zed/bdl/migrate-data.ps1", "$ZED_WORKTREE_ROOT"],
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  }@@INIT_TAIL@@
]
'@

$toolTmpl = @'
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
'@

# tiptop 的部署配置（<项目根>/.project/deploy/deploy.json）。
# 为什么生成脚本要写它：VSCode 插件会按设置合成这份文件（src/deployconfig.ts 的
# ensureDeployConfig），Zed 侧没有任何东西读 ext.prod.deploy.*，而 tiptop 的
# upload / download / deploy 都只认这份文件——不生成它就没有配置可读（PLAN Z-P2-4）。
# 只在「生产主机 + 生产根都填了」且上传方式不是 off 时生成；已存在时写
# deploy.json.bdl-new（与 settings.json 同一策略，不覆盖）。
$deployTmpl = @'
{
  "defaultTarget": "prod",
  "targets": {
    "prod": {
      "host": "@@PROD_HOST@@",
      "port": @@PROD_PORT@@,
      "user": "@@PROD_USER@@",
      "remoteRoot": "@@REMOTE_ROOT@@",
      "localRoot": "@@LOCAL_ROOT@@",
      "strictHostKey": true,
      "region": "@@REGION@@",
      "upload": {
        "mode": "@@TRANSPORT@@",
        "fallback": "scp",
        "include": ["**/*.4gl", "**/*.per"]
      },
      "compile": {
        "4gl": "fglcomp -M {file}",
        "per": "fglform {file}"
      }
    }
  }
}
'@

# 迁移 helper（生成的 .zed/bdl/migrate-data.ps1）。
# 把旧布局资料搬进 .project/{link,schema,deploy}/；只搬移、绝不覆盖。
$migrateTmpl = @'
#Requires -Version 5.1
# 4gl 资料目录迁移（由 zed-bdl 的 scripts/zed/init-workspace.ps1 生成）。
#
# 用法：pwsh -File .zed\bdl\migrate-data.ps1 [项目根]
# 规则：只搬移、绝不覆盖；目标已存在就跳过并明确打印。

param([string]$Root = '.')

$ErrorActionPreference = 'Stop'
Push-Location $Root
$script:moved = 0
$script:skipped = 0

function Move-DataFile([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { return }
    if (Test-Path -LiteralPath $To) {
        Write-Host ('跳过（目标已存在）：' + $From + '  ->  ' + $To)
        $script:skipped++
        return
    }
    $dir = Split-Path -Parent $To
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Move-Item -LiteralPath $From -Destination $To
    Write-Host ('搬移：' + $From + '  ->  ' + $To)
    $script:moved++
}

Move-DataFile '.link/links.jsonl' '.project/link/links.jsonl'
Move-DataFile '.link/links.meta.json' '.project/link/links.meta.json'
Move-DataFile '.project/.schema/tables.json' '.project/schema/tables.json'

if ((Test-Path -LiteralPath '.project/.schema/tables' -PathType Container) -and
    -not (Test-Path -LiteralPath '.project/schema/tables')) {
    New-Item -ItemType Directory -Path '.project/schema' -Force | Out-Null
    Move-Item -LiteralPath '.project/.schema/tables' -Destination '.project/schema/tables'
    Write-Host '搬移目录：.project/.schema/tables  ->  .project/schema/tables'
    $script:moved++
}

Move-DataFile '.project/deploy.json' '.project/deploy/deploy.json'
Move-DataFile '.bdl-lsp/deploy.json' '.project/deploy/deploy.json'

foreach ($d in @('.link', '.project/.schema', '.bdl-lsp')) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
    if (@(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) {
        Remove-Item -LiteralPath $d
        Write-Host ('已删除空目录：' + $d)
    } else {
        Write-Host ('保留（还有其它文件）：' + $d)
    }
}

Write-Host ''
Write-Host ('完成：搬移 ' + $script:moved + ' 项，跳过 ' + $script:skipped + ' 项。')
Write-Host 'bdl-lsp 按 mtime 热重载资料，无需重启；旧的 link-data-legacy-dir 提示会随之消失。'
Write-Host 'secrets.json 不参与迁移：它本来就在 <项目根>/.project/secrets.json。'
Pop-Location
'@

# 可选的「初始化项目」task（追加在数组末尾，避免额外的逗号处理）。
# .ps1 → pwsh -File <路径>（与 bash 版一致，后缀判断区分大小写）；
# 其它（.sh / .cmd / 无后缀）→ bash <路径>，与 bash 版一致。
$initTail = ''
if (-not [string]::IsNullOrEmpty($initScript)) {
    # ★ 脚本会被**拷进项目** .zed/bdl/init-project/，task 里写**项目内的绝对路径**。
    #   原因：用户填的路径（尤其是相对路径或 .ps1）不一定解析得到 ——
    #   之前生成的 task 指向一个不存在的文件，点下去必然失败。
    $projInitDir = Join-Path $zedDir 'bdl/init-project'
    New-Item -ItemType Directory -Force -Path $projInitDir | Out-Null

    if (Test-Path -LiteralPath $initScript -PathType Container) {
        Copy-Item -Recurse -Force -Path (Join-Path $initScript '*') -Destination $projInitDir -ErrorAction SilentlyContinue
    } else {
        Copy-Item -Force -LiteralPath $initScript -Destination $projInitDir -ErrorAction SilentlyContinue
    }
    # init-project.ps1 用 $PSScriptRoot 找 templates/ 与 detect-encoding.py，必须同目录
    $srcDir = Split-Path -Parent $initScript
    if (Test-Path (Join-Path $srcDir 'templates')) {
        Copy-Item -Recurse -Force -Path (Join-Path $srcDir 'templates') -Destination $projInitDir -ErrorAction SilentlyContinue
    }
    if (Test-Path (Join-Path $srcDir 'detect-encoding.py')) {
        Copy-Item -Force -Path (Join-Path $srcDir 'detect-encoding.py') -Destination $projInitDir -ErrorAction SilentlyContinue
    }

    # ★ 必须显式传「本地目录」= $ZED_WORKTREE_ROOT（当前项目根）。
    #   脚本自己的默认是 `$HOME\projects\<远根名>`（如 C:\Users\xxx\projects\topprod）——
    #   那是给"命令行随便跑"用的，在 Zed 的 task 里会让人以为配错了
    #   （VSCode 侧的默认就是工作区根，见 vscode-extension/src/initproject.ts:142,214）。
    #
    #   还要带「增量更新」：目标 = 项目根**总是已存在**，不带 -Update 会在 confirm
    #   之后被 "目标已存在" 挡下（init-project.ps1:314-316）。
    #   -Update 只影响那个守卫与显示文案，不改变取数规则。
    if ($initScript.EndsWith('.ps1', [System.StringComparison]::Ordinal)) {
        $initCmd = 'pwsh'
        $foundInit = Join-Path $projInitDir 'init-project.ps1'
        # $ZED_WORKTREE_ROOT 留给 Zed 展开（这里必须原样写）
        $initArgs = '["-File", "' + (ConvertTo-JsonText $foundInit) + '", "-Dest", "$ZED_WORKTREE_ROOT", "-Update"]'
    } else {
        $initCmd = 'bash'
        $foundInit = Join-Path $projInitDir 'init-project.sh'
        $initArgs = '["' + (ConvertTo-JsonText $foundInit) + '", "--dest", "$ZED_WORKTREE_ROOT", "--update"]'
    }
    $initTailTmpl = @'
,
  {
    "label": "4gl: 初始化项目（从生产服务器拉取代码）",
    "command": "@@INIT_CMD@@",
    "args": @@INIT_ARGS@@,
    "cwd": "$ZED_WORKTREE_ROOT",
    "use_new_terminal": false,
    "reveal": "always"
  }
'@
    $initTail = $initTailTmpl.Replace('@@INIT_CMD@@', $initCmd).Replace('@@INIT_ARGS@@', $initArgs)
}

# ---------------------------------------------------------------------------
# 替换占位符 → 三份 JSON
# ---------------------------------------------------------------------------

# tiptop 路径为空时 task 里直接写 "tiptop"（走 PATH）
$tiptopCmd = 'tiptop'
if (-not [string]::IsNullOrEmpty($tiptopPath)) { $tiptopCmd = $tiptopPath }

$eBdlLsp = ConvertTo-JsonText $bdlLspPath
$eTiptop = ConvertTo-JsonText $tiptopPath
$eTiptopCmd = ConvertTo-JsonText $tiptopCmd
$eOraHost = ConvertTo-JsonText $oraHost
$eOraService = ConvertTo-JsonText $oraService
$eOraUser = ConvertTo-JsonText $oraUser
$eProdHost = ConvertTo-JsonText $prodHost
$eProdUser = ConvertTo-JsonText $prodUser
$eRemoteRoot = ConvertTo-JsonText $remoteRoot
$eLocalRoot = ConvertTo-JsonText $localRoot
$eInitScript = ConvertTo-JsonText $initScript

# ext.build.* 模板：回读已有的 .zed/settings.json（Z-P2-4 ②）
# task 读不到 Zed 设置，"改模板"要重跑本脚本；读不到/没配 → 内置默认模板。
function Get-BuildTemplate([string]$Lang, [string]$Mode) {
    if (-not (Test-Path -LiteralPath $settingsJson -PathType Leaf)) { return '' }
    try {
        $data = Get-Content -LiteralPath $settingsJson -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return ''
    }
    $node = $data
    foreach ($key in @('lsp', 'bdl-lsp', 'settings', 'ext', 'build', $Lang, $Mode)) {
        if ($null -eq $node) { return '' }
        $prop = $node.PSObject.Properties[$key]
        if (-not $prop) { return '' }
        $node = $prop.Value
    }
    if ($node -is [string] -and $node.Trim()) { return $node.Trim() }
    return ''
}

# tiptop 模板占位符 → Zed task 变量（单引号里 $ 是字面量，不会被 PS 插值）
function ConvertFrom-TiptopTemplate([string]$Template) {
    return $Template.Replace('${fullpath}', '$ZED_RELATIVE_DIR').Replace('${path}', '$ZED_RELATIVE_DIR').Replace('${fullname}', '$ZED_FILENAME').Replace('${name}', '$ZED_STEM')
}

# settings 若已存在就不覆盖，改写到 .bdl-new
$settingsRel = '.zed/settings.json'
if (Test-Path -LiteralPath $settingsJson -PathType Leaf) {
    $settingsRel = '.zed/settings.json.bdl-new'
}

$settingsOut = Fill-Template $settingsTmpl @{
    '@@BINARY_PATH@@' = $eBdlLsp
    '@@TIPTOP_PATH@@' = $eTiptop
    '@@ORA_HOST@@'    = $eOraHost
    '@@ORA_PORT@@'    = $oraPort
    '@@ORA_SERVICE@@' = $eOraService
    '@@ORA_USER@@'    = $eOraUser
    '@@PROD_HOST@@'   = $eProdHost
    '@@PROD_PORT@@'   = $prodPort
    '@@PROD_USER@@'   = $eProdUser
    '@@REGION@@'      = $region
    '@@TRANSPORT@@'   = $transport
    '@@LOCAL_ROOT@@'  = $eLocalRoot
    '@@REMOTE_ROOT@@' = $eRemoteRoot
}

$cmd4glPreview = 'cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM'
$cmd4glCompile = 'cd $ZED_RELATIVE_DIR && r.c2 $ZED_STEM'
$cmd4glLink = 'r.l2 $ZED_STEM'
$cmdPerPreview = 'cd $ZED_RELATIVE_DIR && fglform -M -W all $ZED_FILENAME && rm $ZED_STEM.42f'
$cmdPerCompile = 'cd $ZED_RELATIVE_DIR && fglform -M -W all $ZED_FILENAME && mv $ZED_STEM.42f ../42f/ && gsform -M -W all -i -import $ZED_FILENAME && mv $ZED_STEM.4fd ../4fd/'
$cmdPerForm = 'cd $ZED_RELATIVE_DIR && r.gf $ZED_STEM 2 p'
$buildOverrides = 0
foreach ($pair in @(
        @{ Lang = '4gl'; Mode = 'preview'; Var = 'cmd4glPreview' },
        @{ Lang = '4gl'; Mode = 'compile'; Var = 'cmd4glCompile' },
        @{ Lang = '4gl'; Mode = 'link'; Var = 'cmd4glLink' },
        @{ Lang = 'per'; Mode = 'preview'; Var = 'cmdPerPreview' },
        @{ Lang = 'per'; Mode = 'compile'; Var = 'cmdPerCompile' },
        @{ Lang = 'per'; Mode = 'form'; Var = 'cmdPerForm' }
    )) {
    $custom = Get-BuildTemplate $pair.Lang $pair.Mode
    if (-not [string]::IsNullOrEmpty($custom)) {
        $mapped = ConvertFrom-TiptopTemplate $custom
        Set-Variable -Name $pair.Var -Value $mapped
        $buildOverrides++
        Write-Info ('ext.build.' + $pair.Lang + '.' + $pair.Mode + ' 覆盖了默认模板：' + $mapped)
    }
}
if ($buildOverrides -eq 0) {
    Write-Info 'ext.build.* 未配置：exec task 用内置默认模板'
}

$tasksOut = Fill-Template $tasksTmpl @{
    '@@TIPTOP@@'      = $eTiptopCmd
    '@@ORA_HOST@@'    = $eOraHost
    '@@ORA_PORT@@'    = $oraPort
    '@@ORA_SERVICE@@' = $eOraService
    '@@ORA_USER@@'    = $eOraUser
    '@@EXEC_FLAGS@@'  = $execFlags
    '@@CMD_4GL_PREVIEW@@' = $cmd4glPreview
    '@@CMD_4GL_COMPILE@@' = $cmd4glCompile
    '@@CMD_4GL_LINK@@'    = $cmd4glLink
    '@@CMD_PER_PREVIEW@@' = $cmdPerPreview
    '@@CMD_PER_COMPILE@@' = $cmdPerCompile
    '@@CMD_PER_FORM@@'    = $cmdPerForm
    '@@INIT_TAIL@@'   = $initTail
}

$toolOut = Fill-Template $toolTmpl @{
    '@@GENERATED_AT@@' = ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))
    '@@GENERATOR@@'    = (ConvertTo-JsonText $PSCommandPath)
    '@@PROJECT_ROOT@@' = (ConvertTo-JsonText $root)
    '@@BINARY_PATH@@'  = $eBdlLsp
    '@@TIPTOP_PATH@@'  = $eTiptop
    '@@ORA_HOST@@'     = $eOraHost
    '@@ORA_PORT@@'     = $oraPort
    '@@ORA_SERVICE@@'  = $eOraService
    '@@ORA_USER@@'     = $eOraUser
    '@@PROD_HOST@@'    = $eProdHost
    '@@PROD_PORT@@'    = $prodPort
    '@@PROD_USER@@'    = $eProdUser
    '@@REGION@@'       = $region
    '@@REMOTE_ROOT@@'  = $eRemoteRoot
    '@@LOCAL_ROOT@@'   = $eLocalRoot
    '@@TRANSPORT@@'    = $transport
    '@@INIT_SCRIPT@@'  = $eInitScript
    '@@SETTINGS_REL@@' = $settingsRel
    '@@TASKS_REL@@'    = '.zed/tasks.json'
    '@@TOOL_REL@@'     = '.zed/bdl-tool.json'
}

$deployDir = Join-Path (Join-Path $root '.project') 'deploy'
$deployJson = Join-Path $deployDir 'deploy.json'
$deployNew = Join-Path $deployDir 'deploy.json.bdl-new'
$makeDeploy = $false
if ((-not [string]::IsNullOrEmpty($prodHost)) -and (-not [string]::IsNullOrEmpty($remoteRoot)) -and ($transport -ne 'off')) {
    $makeDeploy = $true
    $deployOut = Fill-Template $deployTmpl @{
        '@@PROD_HOST@@'   = $eProdHost
        '@@PROD_PORT@@'   = $prodPort
        '@@PROD_USER@@'   = $eProdUser
        '@@REMOTE_ROOT@@' = $eRemoteRoot
        '@@LOCAL_ROOT@@'  = $eLocalRoot
        '@@REGION@@'      = $region
        '@@TRANSPORT@@'   = $transport
    }
}

# ---------------------------------------------------------------------------
# 写盘（先校验内存内容，再写，再校验文件）
# ---------------------------------------------------------------------------

Write-Section '写盘'

$failed = @()
foreach ($pair in @(
        @{ Name = 'settings.json'; Text = $settingsOut },
        @{ Name = 'tasks.json'; Text = $tasksOut },
        @{ Name = 'bdl-tool.json'; Text = $toolOut }
    )) {
    if (-not (Test-JsonText $pair.Text)) { $failed += $pair.Name }
}
if ($failed.Count -gt 0) {
    Write-Host ('错误：' + ($failed -join '、') + ' 生成的内容不是合法 JSON（已放弃写盘）。') -ForegroundColor Red
    exit 1
}

# 兜底断言（见 docs\PLAN.md R12）：Zed 会把 $… / ${…} 当成**自己的** task 变量，
# 未知变量会让整条 task 从 task: spawn 列表消失、或被替换成空串。
# 模板里只允许 Zed 变量（$ZED_RELATIVE_DIR / $ZED_STEM / $ZED_FILENAME 等），
# 一旦生成结果里出现 ${…}，宁可不写盘。
if ($tasksOut.Contains('${')) {
    Write-Host '错误：tasks.json 里出现了 ${...} 占位符（Zed 会把它当成自己的 task 变量）。已放弃写盘。' -ForegroundColor Red
    Write-Host '      请改用 $ZED_RELATIVE_DIR / $ZED_STEM / $ZED_FILENAME。' -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $zedDir -PathType Container)) {
    New-Item -ItemType Directory -Path $zedDir -Force | Out-Null
}

if (Test-Path -LiteralPath $settingsJson -PathType Leaf) {
    Write-Utf8NoBom $settingsNew $settingsOut
    Write-Warn ('已存在 ' + $settingsJson + ' —— 没有覆盖它，建议内容写到了 ' + $settingsNew + '。')
    Write-Warn ('请手工合并：把 ' + $settingsNew + ' 里 lsp.bdl-lsp.settings 那一段并进 settings.json，其余键保留你现有的。')
    Write-Warn ('合并完可以删掉 ' + $settingsNew + '。')
} else {
    Write-Utf8NoBom $settingsJson $settingsOut
}

if (Test-Path -LiteralPath $tasksJson -PathType Leaf) {
    $tasksBak = $tasksJson + '.bak'
    if (Test-Path -LiteralPath $tasksBak -PathType Leaf) {
        $tasksBak = $tasksJson + '.bak.' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    }
    try {
        Copy-Item -LiteralPath $tasksJson -Destination $tasksBak -Force
    } catch {
        Write-Host ('错误：备份失败：' + $tasksJson + ' —— ' + $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
    Write-Info ('已备份：' + $tasksBak)
}
Write-Utf8NoBom $tasksJson $tasksOut
Write-Utf8NoBom $toolJson $toolOut

if ($makeDeploy) {
    if (-not (Test-JsonText $deployOut)) {
        Write-Host '错误：deploy.json 生成的内容不是合法 JSON（已放弃写盘）。' -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $deployDir -PathType Container)) {
        New-Item -ItemType Directory -Path $deployDir -Force | Out-Null
    }
    if (Test-Path -LiteralPath $deployJson -PathType Leaf) {
        Write-Utf8NoBom $deployNew $deployOut
        Write-Warn ('已存在 ' + $deployJson + ' —— 没有覆盖它，建议内容写到了 ' + $deployNew + '。')
        Write-Warn ('tiptop 的 upload / download / deploy 只认 ' + $deployJson + '，请手工合并后再跑。')
    } else {
        Write-Utf8NoBom $deployJson $deployOut
    }
    $null = Assert-JsonFile $deployJson
} else {
    Write-Info '未生成 .project/deploy/deploy.json（生产主机/生产根为空，或上传方式为 off）'
    Write-Info '  → 上传/下载/部署 需要它：重跑本脚本并填生产环境 + 选 rsync/scp，或手写（格式见 docs/USER-GUIDE.md §5.4）'
}

# 迁移 helper：放进项目的 .zed\bdl\，供 task「4gl: 迁移项目资料目录」调用
$migratePath = Join-Path (Join-Path $zedDir 'bdl') 'migrate-data.ps1'
Write-Utf8Bom $migratePath $migrateTmpl

# 把**本脚本自己**也装进项目 .zed\bdl\ —— 这样以后可以直接在项目里重跑，
# 而且那时 init-project 就在**同级目录**（.zed\bdl\init-project\），能直接找到。
# 以前只装 migrate-data.ps1，用户按提示手工拷 scripts\zed\* 进来，
# 结果从项目里重跑时 init-project 搜不到（默认值变空 → 不生成「初始化项目」task）。
$selfDst = Join-Path (Join-Path $zedDir 'bdl') 'init-workspace.ps1'
$selfAbs = $PSCommandPath
if (-not [string]::IsNullOrEmpty($selfAbs) -and (Test-Path -LiteralPath $selfAbs)) {
    $selfAbsFull = (Resolve-Path -LiteralPath $selfAbs).Path
    if ($selfAbsFull -ne $selfDst) {
        Copy-Item -Force -LiteralPath $selfAbs -Destination $selfDst -ErrorAction SilentlyContinue
    }
}

$null = Assert-JsonFile $settingsJson
if ($settingsRel -eq '.zed/settings.json.bdl-new') { $null = Assert-JsonFile $settingsNew }
$null = Assert-JsonFile $tasksJson
$null = Assert-JsonFile $toolJson

# ---------------------------------------------------------------------------
# 提示
# ---------------------------------------------------------------------------

function Show-Default([string]$Value, [string]$Empty = '（空）') {
    if ([string]::IsNullOrEmpty($Value)) { return $Empty }
    return $Value
}

Write-Section '本次取值'
Write-Info ('bdl-lsp 二进制：' + (Show-Default $bdlLspPath '（空，走 PATH / 工作区 .bdl-lsp\bin\）'))
Write-Info ('tiptop 二进制：' + (Show-Default $tiptopPath '（空，走 PATH / 工作区 .bdl-lsp\bin\）'))
Write-Info ('Oracle：' + (Show-Default $oraHost) + ':' + $oraPort + '/service=' + (Show-Default $oraService) + ' user=' + (Show-Default $oraUser) + '（密码不在文件里）')
Write-Info ('生产：' + (Show-Default $prodHost) + ':' + $prodPort + ' user=' + (Show-Default $prodUser) + ' region=' + $region + ' remoteRoot=' + (Show-Default $remoteRoot) + ' localRoot=' + $localRoot + ' transport=' + $transport)
if ([string]::IsNullOrEmpty($loginProfile)) {
    Write-Info 'exec login-profile：区 4（Browser-based）不传'
} else {
    Write-Info ('exec login-profile：' + $loginProfile)
}

Write-Warn '若填了 Oracle 连接：link.mode / schema.mode 仍写作 off（轻量档）。'
Write-Warn '  * 用 CSV 导入资料后，把 .zed\settings.json 里的 link.mode / schema.mode 改成 "file"；'
Write-Warn '  * 要直连库采集，改成 "db"。改完一般**不用重启**（Zed 会推 didChangeConfiguration，bdl-lsp 热应用）；只有改 binary.path / arguments 才要重启。'
Write-Warn '「4gl: 链接资料：从 CSV 导入」/「4gl: 字段资料：从 CSV 导入」里的 <CSV 绝对路径> 是占位符，跑之前要改成你的 CSV 路径。'
Write-Warn '「4gl: 链接资料：按模组更新」里的 -modules lib,sub,qry 是示例，按需改成你的全局模组名。'

Write-Host @'

== 下一步
1) 在 Zed 里装上本扩展：命令面板 extension: install dev extension（选本仓库目录），
   或等扩展市场发布后再装。
2) 准备二进制：bdl-lsp / tiptop 放进 PATH，或工作区 .bdl-lsp\bin\；
   也可以手填 .zed\settings.json 的 lsp.bdl-lsp.binary.path、settings.ext.tools.path。
3) 在 Zed 里跑 task: spawn（命令面板），列表里找 "4gl:" 开头的任务；
   常用的建议绑 keymap，例如：
     { "context": "Workspace", "bindings": { "alt-u": ["task::Spawn", { "task_name": "4gl: 上传当前文件" }] } }
4) 资料模式：默认 "off"（轻量档，不连库、不写工作区）；
   * 只用 CSV 导入 → 导入后在 .zed\settings.json 把 link.mode / schema.mode 改成 "file"；
   * 直连 Oracle 采集 → 改成 "db"。
   改完**一般不用重启**（Zed 会推 workspace/didChangeConfiguration，bdl-lsp 热应用并重算诊断）；
   只有改 binary.path / arguments（进程启动参数）才需要重启（命令面板 editor: restart language server）。
5) 密码**不在**本脚本里、也不在生成的文件里：
   写 <项目根>\.project\secrets.json（内容 {"<用户名>":"<密码>"}；
   Windows 不校验文件权限，Unix 必须 chmod 600），或用环境变量 BDL_ORA_PASSWORD。
   tiptop 只从这两处取密码。
6) .gitignore 建议：.zed\settings.json（含主机/账号）、.project\secrets.json；
   .zed\tasks.json 与 .zed\bdl-tool.json 不含密码，可以提交。
7) 本脚本自己不在生成的 tasks.json 里。想以后在 Zed 里一键重跑，先把脚本放进项目：
     New-Item -ItemType Directory -Force .zed\bdl | Out-Null
     Copy-Item <zed-bdl 仓库>\scripts\zed\* .zed\bdl\
   然后手工加一条 task：
   { "label": "4gl: 初始化 Zed 工程（生成 .zed 配置）",
     "command": "pwsh", "args": ["-File", ".zed\\bdl\\init-workspace.ps1"],
     "cwd": "$ZED_WORKTREE_ROOT" }
   （Linux / WSL 用 "command": "bash", "args": [".zed/bdl/init-workspace.sh"]）
8) 改 exec 的命令模板时**只用 Zed 变量**：$ZED_RELATIVE_DIR（当前文件目录）、
   $ZED_STEM（去扩展名）、$ZED_FILENAME（含扩展名）。
   不要写 ${path}/${name}/${fullname} —— 那是 VSCode 侧插件的模板占位符，
   Zed 会当成自己的 task 变量处理（未知变量会让整条 task 从 task: spawn 列表消失）。
'@

Write-Info ''
Write-Info '完成。'
