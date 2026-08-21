# Launch the game, rebuilding the class cache first if it is stale.
#
#   powershell -ExecutionPolicy Bypass -File Tools\play.ps1
#
# A blind playtester hit a blank grey screen with no on-screen error: the
# console said `Could not find type "UnitCard"`. `.godot/` is gitignored and
# holds the global class cache, and a `--path` run rebuilds imports but NOT
# that cache -- so every new `class_name` fails to resolve until an editor
# import runs. The screen that fails is simply absent, which is why nothing
# says so.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

$godot = $env:CLAUDEGUISE_GODOT
if (-not $godot) {
    $godot = "D:\Projects\Claudeguise-team\tools\godot\Godot_v4.7.1-stable_win64_console.exe"
}
if (-not (Test-Path $godot)) {
    Write-Host "No Godot at $godot. Set CLAUDEGUISE_GODOT and run again."
    exit 2
}

$cache = Join-Path $repo ".godot\global_script_class_cache.cfg"

# Stale means: absent, or older than the newest script declaring a class_name.
$needsImport = -not (Test-Path $cache)
if (-not $needsImport) {
    $cacheTime = (Get-Item $cache).LastWriteTimeUtc
    $newest = Get-ChildItem -Path (Join-Path $repo 'Scripts') -Recurse -Include *.gd |
        Where-Object { (Select-String -Path $_.FullName -Pattern '^class_name ' -Quiet) } |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($newest -and $newest.LastWriteTimeUtc -gt $cacheTime) {
        $needsImport = $true
        Write-Host ("class cache is older than {0}" -f $newest.Name)
    }
}

if ($needsImport) {
    Write-Host "Rebuilding the class cache (about a minute the first time)..."
    $log = Join-Path $env:TEMP ("claudeguise-play-import-" + [guid]::NewGuid().ToString('N') + ".txt")
    cmd /c "`"$godot`" --headless --editor --quit --path `"$repo`" > `"$log`" 2>&1"
    Remove-Item $log -ErrorAction SilentlyContinue
    if (-not (Test-Path $cache) -or (Get-Item $cache).Length -lt 64) {
        Write-Host "The import produced no class cache at $cache."
        Write-Host "The game would start on a blank screen. Not launching."
        exit 4
    }
    Write-Host ("class cache rebuilt, {0} bytes" -f (Get-Item $cache).Length)
}

& $godot --path $repo
