# Kill Godot processes that have outlived any honest gate run.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File Tools\reap.ps1 -Id 1234
#   ... -Id 1234,5678  # kill exactly these, whatever their age. PREFER THIS.
#   ... -WhatIf        # list without killing
#   ... -Minutes 5     # age sweep, MACHINE-WIDE, more aggressive than the default
#
# MANAGER-OWNED. Not part of the game and not part of the gate.
#
# ---------------------------------------------------------------------------
# READ THIS BEFORE THE AGE SWEEP. Added 2026-08-17 after it went wrong.
#
# **The age sweep has no notion of whose process it is killing.** It matches
# every Godot on the machine older than the threshold. `-Minutes 5` during a
# normal working session will kill other people's live editors and gate runs.
#
# That happened. sable's own render hung, `Stop-Process` on the two ids it had
# already identified was refused by the permission layer, so it fell back to
# `-Minutes 5` -- and took out rook's parked editor and another session's editor
# along with its own hang. sable disclosed it unprompted and was right about the
# cause: for a hang you caused yourself, the age sweep is the pattern-kill that
# `ENGINEER.md` forbids, wearing a nicer name. The gap was this file's, not
# sable's -- the doc offered a machine-wide hammer as the safe alternative to
# `taskkill` and offered nothing surgical.
#
# So: **if you know the id, pass `-Id`.** It ignores the age threshold, because
# a process you can name is one you have already decided about. The age sweep is
# for the case nobody can name -- an orphan with no session left to own it.
# ---------------------------------------------------------------------------
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
    [int[]]$Id = @(),
    [int]$Minutes = 15,
    [switch]$WhatIf
)

$now = Get-Date

# -Id: surgical. Kills exactly what you name, at any age, and refuses anything
# that is not a Godot process so a mistyped id cannot take out your shell.
if ($Id.Count -gt 0) {
    foreach ($wanted in $Id) {
        $p = Get-Process -Id $wanted -ErrorAction SilentlyContinue
        if (-not $p) {
            Write-Host ("no process {0} -- already gone" -f $wanted)
            continue
        }
        if ($p.ProcessName -notlike 'Godot*') {
            Write-Host ("REFUSED {0}: it is '{1}', not a Godot process" -f $p.Id, $p.ProcessName)
            continue
        }
        $age = 0
        try { $age = [int]((($now - $p.StartTime)).TotalMinutes) } catch { }
        if ($WhatIf) {
            Write-Host ("would kill {0} ({1}) age {2}m" -f $p.Id, $p.ProcessName, $age)
            continue
        }
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Host ("killed {0} ({1}) age {2}m" -f $p.Id, $p.ProcessName, $age)
        } catch {
            Write-Host ("could not kill {0}: {1}" -f $p.Id, $_.Exception.Message)
        }
    }
    exit 0
}

Write-Host ("AGE SWEEP: every Godot on this machine older than {0} minutes, regardless of whose." -f $Minutes)
Write-Host "If you know the process id, Ctrl-C and use -Id instead."

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
