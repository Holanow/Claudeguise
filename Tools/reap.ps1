# Kill Godot processes that have outlived any honest gate run.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File Tools\reap.ps1
#   ... -Minutes 5     # more aggressive
#   ... -WhatIf        # list without killing
#
# MANAGER-OWNED. Not part of the game and not part of the gate.
#
# Why this exists, twice over on 2026-08-13:
#
# A gate run takes two to four minutes. Processes were found alive at 31, 33 and
# 56 minutes, one of them burning 372 CPU-seconds -- spinning, not idle. With
# four sessions each launching headless Godot, they pile up, contend for the
# machine, and every session's runs get slower, which makes each session launch
# more of them.
#
# The damage is worse than slowness. A session cannot tell a contended run from a
# real failure: swift reported "trunk is red" from a run under load, then could
# not reproduce it and had to withdraw the claim. **A hung process does not just
# waste time, it manufactures false test results.** That is the same class of
# problem as an instrument that measures the wrong thing, which has cost this
# project more than any bug.
#
# Deliberately conservative: it only kills what is older than the threshold, so a
# live run is never interrupted. Default 15 minutes is roughly five times the
# longest honest run.

param(
    [int]$Minutes = 15,
    [switch]$WhatIf
)

$now = Get-Date
$stale = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like 'Godot*' } |
    Where-Object {
        # A process whose StartTime cannot be read is not one to guess about.
        $start = $null
        try { $start = $_.StartTime } catch { }
        $start -and (($now - $start).TotalMinutes -gt $Minutes)
    }

if (-not $stale) {
    Write-Host "No Godot process older than $Minutes minutes. Nothing to reap."
    exit 0
}

foreach ($p in $stale) {
    $age = [int](($now - $p.StartTime).TotalMinutes)
    $cpu = [int]$p.CPU
    if ($WhatIf) {
        Write-Host ("would kill {0} ({1}) age {2}m cpu {3}s" -f $p.Id, $p.ProcessName, $age, $cpu)
        continue
    }
    try {
        Stop-Process -Id $p.Id -Force -ErrorAction Stop
        Write-Host ("killed {0} ({1}) age {2}m cpu {3}s" -f $p.Id, $p.ProcessName, $age, $cpu)
    } catch {
        Write-Host ("could not kill {0}: {1}" -f $p.Id, $_.Exception.Message)
    }
}
