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
$log = Join-Path $env:TEMP ("claudeguise-gate-" + [guid]::NewGuid().ToString('N') + ".txt")
cmd /c "`"$godot`" --headless --path `"$repo`" --script res://Tests/run_tests.gd > `"$log`" 2>&1"
$code = $LASTEXITCODE

Get-Content $log
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

if ($code -eq 0) {
    Write-Host "GATE PASSED"
} else {
    Write-Host "GATE FAILED (exit $code)"
}
exit $code
