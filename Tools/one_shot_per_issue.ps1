# One tracked screenshot per issue. Player's ruling, 2026-09-10 (issue 854):
# "Why don't we track one screenshot per issue that shows the result."
#
# Reads `git ls-files`, so untracked probe leftovers do not count and a staged
# file does. A name with no issue number in it is legacy and is only counted,
# never failed on: the rule cannot be applied to a file that belongs to no issue.
#
# Exit 0 pass, 9 fail, 2 cannot run.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

Push-Location $repo
try {
    $tracked = @(git ls-files Screenshots)
} finally {
    Pop-Location
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "  oneshot    CANNOT RUN (git ls-files failed in $repo)"
    exit 2
}

# `wren_412_library_open.png`, `issue440_defaults_off.png`, `ledger807/after.png`.
$byIssue = @{}
$unnumbered = 0
foreach ($f in $tracked) {
    $rel = $f.Substring('Screenshots/'.Length)
    $key = $null
    if ($rel -match '^[A-Za-z]+[0-9]?_(\d{2,4})_') { $key = $Matches[1] }
    elseif ($rel -match '^issue[_-]?(\d{2,4})') { $key = $Matches[1] }
    elseif ($rel -match '^[A-Za-z]+(\d{2,4})/') { $key = $Matches[1] }
    if ($null -eq $key) { $unnumbered++; continue }
    if (-not $byIssue.ContainsKey($key)) { $byIssue[$key] = @() }
    $byIssue[$key] += $f
}

$dupes = @($byIssue.Keys | Where-Object { $byIssue[$_].Count -gt 1 } | Sort-Object)
if ($dupes.Count -gt 0) {
    Write-Host ""
    Write-Host "  oneshot    FAIL   ($($dupes.Count) issue(s) with more than one tracked screenshot)"
    foreach ($k in $dupes) {
        Write-Host ("      issue {0}: {1} files" -f $k, $byIssue[$k].Count)
        foreach ($f in ($byIssue[$k] | Sort-Object)) { Write-Host "        $f" }
    }
    Write-Host "  Keep the one that shows the finished result and delete the rest."
    Write-Host "  Probe output belongs in user://probe, not in Screenshots/."
    exit 9
}

Write-Host ("  oneshot    pass   ({0} issue(s), one screenshot each; {1} legacy file(s) with no issue number)" -f $byIssue.Count, $unnumbered)
exit 0
