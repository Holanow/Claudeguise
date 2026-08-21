# Prints the value every fixture threshold in the suite is actually sitting at,
# so a floor the world has walked up to can be seen before it goes silent.
#
#   powershell -ExecutionPolicy Bypass -File Tools\ThresholdSweep.ps1
#
# It inverts each comparison in place, runs the suite once, harvests the failure
# messages -- which already carry the measured number -- and restores the files
# with `git checkout`. It is NOT part of the gate: computing the headroom costs
# the same as the assertion itself, and any automatic verdict would need a
# headroom threshold, which is one more constant to widen. Read the output.
#
# It refuses on a dirty Tests/ because the restore is `git checkout -- Tests`.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

$dirty = git -C $repo status --porcelain -- Tests
if ($dirty) {
    Write-Host "REFUSING: Tests/ has uncommitted changes and this script restores with git checkout."
    Write-Host $dirty
    exit 2
}

$godot = $env:CLAUDEGUISE_GODOT
if (-not $godot) {
    $godot = "D:\Projects\Claudeguise-team\tools\godot\Godot_v4.7.1-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Host "CANNOT RUN: no Godot at $godot"
    exit 2
}

# A structural check on a list or a rectangle is not a fixture measurement, and
# inverting it only adds noise to the harvest.
$SKIP = 'size\(\) > 0|is_empty|\.x |\.y |position|Palette\.'

$inverted = 0
Get-ChildItem (Join-Path $repo 'Tests') -Filter *.gd | ForEach-Object {
    $text = Get-Content $_.FullName
    # A file that never runs a fight has no emergent quantity to drift.
    if (-not ($text -match 'CombatSim\.(run|step)\(')) { return }
    $out = foreach ($line in $text) {
        if ($line -match 'assert_true\(' -and $line -notmatch $SKIP -and $line -match ' (>=|<=|>|<) ') {
            $script:inverted++
            $op = $Matches[1]
            $flip = @{ '>=' = '<'; '<=' = '>'; '>' = '<='; '<' = '>=' }[$op]
            ([regex]" $([regex]::Escape($op)) ").Replace($line, " $flip ", 1)
        } else {
            $line
        }
    }
    Set-Content -Path $_.FullName -Value $out -Encoding utf8
}

Write-Host "inverted $inverted assertions; running the suite once"

$log = Join-Path $env:TEMP ("claudeguise-sweep-" + [guid]::NewGuid().ToString('N') + ".txt")
cmd /c "`"$godot`" --headless --path `"$repo`" --script res://Tests/run_tests.gd > `"$log`" 2>&1"

git -C $repo checkout -- Tests

Select-String -Path $log -Pattern '^FAIL ' | ForEach-Object { $_.Line }
Write-Host ""
Write-Host "Each line above is an assertion that PASSES today; the message carries the"
Write-Host "measured value beside the threshold it cleared. Rank by the gap."
Remove-Item $log -ErrorAction SilentlyContinue
