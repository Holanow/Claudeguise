# The gate. Run this before asking for review, and after every merge.
#
#   powershell -ExecutionPolicy Bypass -File Tools\gate.ps1
#
# Exit code 0 means parse, discovery and tests all passed. Anything else means
# stop and read the output.
#
# There is no CI and no remote on this project, so this script is the only
# check there is. It refuses to pass when it cannot run: "the gate crashed" and
# "the gate passed you" must never look the same.

$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot

# Set CLAUDEGUISE_GODOT to override.
#
# The default is the official 4.7.1 build fetched from the GitHub release, kept
# beside the repo rather than inside it: git copies a tracked file into every
# worktree, and this one is 179 MB.
#
# Do not point this at the Steam copy in D:\Games. Both builds behave the same
# for a --script run, so it would work; the standalone one is here so that
# nothing in the loop depends on Steam being installed or running.
# The path is absolute on purpose. Deriving it from $repo works in the main
# checkout and breaks in every worktree, because a worktree lives two levels
# deeper and the relative walk lands somewhere that does not exist. That is the
# classic version of this bug: shared tooling tested only in the main checkout,
# which is the one place nobody works.
$godot = $env:CLAUDEGUISE_GODOT
if (-not $godot) {
    $godot = "D:\Projects\Claudeguise-team\tools\godot\Godot_v4.7.1-stable_win64_console.exe"
}

if (-not (Test-Path $godot)) {
    Write-Host "GATE CANNOT RUN: no Godot at" $godot
    Write-Host "Set CLAUDEGUISE_GODOT to a Godot 4.7 executable and run again."
    Write-Host "This is a failure, not a pass."
    exit 2
}

# Output goes through cmd to a file rather than being piped in PowerShell.
#
# `& $exe 2>&1` looks equivalent and is not: Windows PowerShell wraps each
# stderr line from a native program in an ErrorRecord, and with
# $ErrorActionPreference = 'Stop' the first one terminates this script. The gate
# then exits non-zero having printed a stack trace and none of its own summary,
# so a parse failure and a broken gate produce the same unreadable output. That
# happened on the first run of this file.
# `class_name` needs the editor's class cache, which lives in gitignored .godot/.
# A --script run cannot build it, so it is built here first: without it every file
# fails to parse with an error naming a type rather than the cause.
$import = Join-Path $env:TEMP ("claudeguise-import-" + [guid]::NewGuid().ToString('N') + ".txt")
cmd /c "`"$godot`" --headless --editor --quit --path `"$repo`" > `"$import`" 2>&1"
$cache = Join-Path $repo ".godot\global_script_class_cache.cfg"
if (-not (Test-Path $cache) -or (Get-Item $cache).Length -lt 64) {
    Write-Host "GATE CANNOT RUN: the editor import produced no class cache at"
    Write-Host "  $cache"
    Write-Host "Every class_name would fail to resolve. This is a failure, not a pass."
    exit 4
}
Write-Host ("  import     pass   (class cache {0} bytes)" -f (Get-Item $cache).Length)

$log = Join-Path $env:TEMP ("claudeguise-gate-" + [guid]::NewGuid().ToString('N') + ".txt")
cmd /c "`"$godot`" --headless --path `"$repo`" --script res://Tests/run_tests.gd > `"$log`" 2>&1"
$code = $LASTEXITCODE

Get-Content $log

# A screen whose scene tree is missing renders nothing and still passes: `%Name`
# fails, _ready() aborts, and no assertion looks at the half that never built.
# That happened during the scenes migration -- 78 of these against a green
# 1056/8198 summary. The trunk emits zero, so zero is the bar.
$missing = @(Select-String -Path $log -Pattern 'Node not found' -SimpleMatch)
if ($missing.Count -gt 0) {
    Write-Host ""
    Write-Host ("  scene      FAIL   ($($missing.Count) 'Node not found' during the run)")
    $missing | Select-Object -First 5 | ForEach-Object { Write-Host ("      " + $_.Line.Trim()) }
    Write-Host "  A node the script asked for is not in the tree. The suite cannot see this."
    Remove-Item $log -ErrorAction SilentlyContinue
    Write-Host "GATE FAILED (missing scene nodes)"
    exit 5
}
Write-Host "  scene      pass   (no missing nodes during the run)"
Remove-Item $log -ErrorAction SilentlyContinue

# Comment-to-code ratio. Player's rule, 2026-08-18: no file above 2:1.
#
# Enforced here rather than written on the board, because a posted rule is not a
# control. The list below is the debt that existed when the rule landed. It may
# shrink and must never grow: a file not on it fails immediately, and a file on
# it fails if it gets worse. That is deliberately the opposite ratchet to the one
# issue #144 records, where a cap was widened five times and narrowed never.
$GRANDFATHERED = @{}

$ratioFailures = @()
Get-ChildItem -Path (Join-Path $repo 'Scripts'), (Join-Path $repo 'Tests'), (Join-Path $repo 'Tools') `
    -Recurse -Include *.gd -ErrorAction SilentlyContinue | ForEach-Object {
    $comments = 0
    $codeLines = 0
    foreach ($line in (Get-Content $_.FullName)) {
        $t = $line.Trim()
        if ($t -eq '') { continue }
        if ($t.StartsWith('#')) { $comments++ } else { $codeLines++ }
    }
    if ($codeLines -eq 0) { return }
    $ratio = [math]::Round($comments / $codeLines, 2)
    if ($ratio -le 2.0) { return }

    $rel = $_.FullName.Substring($repo.Length + 1)
    if ($GRANDFATHERED.ContainsKey($rel)) {
        if ($ratio -gt $GRANDFATHERED[$rel]) {
            $ratioFailures += ("{0}  {1}:1, worse than its recorded {2}:1" -f $rel, $ratio, $GRANDFATHERED[$rel])
        }
    } else {
        $ratioFailures += ("{0}  {1}:1  ({2} comment lines over {3} of code)" -f $rel, $ratio, $comments, $codeLines)
    }
}

# Comment BLOCK length. Player's rule, 2026-08-20: no run of comment lines
# longer than MAX_COMMENT_BLOCK.
#
# This is the live control, and the ratio below is not. The ratio cap is at
# 2:1 and the repo sits at 0.26:1, so nothing can fail it -- a rule nobody can
# break is not a rule. The block cap would have caught six blocks on the commit
# it landed with.
#
# The rule it enforces: a comment block keeps its first sentence. Reasoning
# goes in the commit or the issue, where it can be read on demand and cannot
# rot against the code beside it.
$MAX_COMMENT_BLOCK = 10

$blockFailures = @()
Get-ChildItem -Path (Join-Path $repo 'Scripts'), (Join-Path $repo 'Tests'), (Join-Path $repo 'Tools') `
    -Recurse -Include *.gd -ErrorAction SilentlyContinue | ForEach-Object {
    $rel = $_.FullName.Substring($repo.Length + 1)
    $run = 0
    $startLine = 0
    $lineNo = 0
    foreach ($line in (Get-Content $_.FullName)) {
        $lineNo++
        if ($line.Trim().StartsWith('#')) {
            if ($run -eq 0) { $startLine = $lineNo }
            $run++
        } else {
            if ($run -gt $MAX_COMMENT_BLOCK) {
                $blockFailures += ("{0}:{1}  {2} lines" -f $rel, $startLine, $run)
            }
            $run = 0
        }
    }
    if ($run -gt $MAX_COMMENT_BLOCK) {
        $blockFailures += ("{0}:{1}  {2} lines" -f $rel, $startLine, $run)
    }
}

if ($blockFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "  blocks     FAIL   ($($blockFailures.Count) comment block(s) over $MAX_COMMENT_BLOCK lines)"
    foreach ($f in $blockFailures) { Write-Host "      $f" }
    Write-Host "  Keep the first sentence. The rest goes in the commit or the issue."
    Write-Host "GATE FAILED (comment block length)"
    exit 6
}
Write-Host "  blocks     pass   (no comment block over $MAX_COMMENT_BLOCK lines)"

if ($ratioFailures.Count -gt 0) {
    Write-Host ""
    Write-Host "  comments   FAIL   ($($ratioFailures.Count) file(s) over the 2:1 limit)"
    foreach ($f in $ratioFailures) { Write-Host "      $f" }
    Write-Host "  Trim the prose or move it to the issue. If a file is genuinely all"
    Write-Host "  definition and no logic, say so in the pull request and I will record it."
    Write-Host "GATE FAILED (comment ratio)"
    exit 3
}
Write-Host "  comments   pass   (no file over 2:1 that is not recorded debt)"

if ($code -ne 0) {
    Write-Host "GATE FAILED (exit $code)"
    exit $code
}

# Issue 520: one real-click probe, because the headless suite structurally
# cannot run one.
#
# Measured 2026-08-24: a Control added to the tree inside a `--script` run has
# not been laid out, so every rect reads (0,0,0,0) and `push_input` picks
# nothing. So the only place a click through Godot's picking can be checked is
# a windowed run, and if it is not here it is a tool nobody remembers.
#
# What it caught: since #470 the library's first Add sat 11 px below the fold
# of the party screen's Plans scroll, a ScrollContainer clips input as well as
# pixels, and the probe reported the button as inert for a day.
$env:CLAUDEGUISE_GATE = '1'
$probeLog = Join-Path $env:TEMP ("claudeguise-probe-" + [guid]::NewGuid().ToString('N') + ".txt")
& (Join-Path $PSScriptRoot 'run.ps1') PresetLibraryProbe -TimeoutSeconds 240 > $probeLog 2>&1
$probeCode = $LASTEXITCODE
Remove-Item Env:\CLAUDEGUISE_GATE -ErrorAction SilentlyContinue

if ($probeCode -ne 0) {
    Write-Host ""
    Write-Host "  clicks     FAIL   (PresetLibraryProbe exited $probeCode)"
    Get-Content $probeLog | Select-String -Pattern 'PresetLibraryProbe' | ForEach-Object { Write-Host ("      " + $_.Line.Trim()) }
    Remove-Item $probeLog -ErrorAction SilentlyContinue
    Write-Host "  A control the suite cannot reach. This needs a screen, so it needs a window:"
    Write-Host "  a machine with no display cannot run the gate."
    Write-Host "GATE FAILED (real-click probe)"
    exit 7
}
Remove-Item $probeLog -ErrorAction SilentlyContinue
Write-Host "  clicks     pass   (the library's Add lands a row through real picking)"

Write-Host "GATE PASSED"
exit 0
