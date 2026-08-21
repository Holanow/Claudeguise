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
# Stale means: absent, or older than the newest thing an import would pick up.
#
# Scripts alone is not enough. A blind playtester launched into a flat empty
# window for over two minutes and assumed the app had hung: the class cache was
# current, so this skipped the import, and Godot then imported a newly baked PNG
# at startup with nothing drawn. Assets and scenes count too.
$needsImport = -not (Test-Path $cache)
if (-not $needsImport) {
    $cacheTime = (Get-Item $cache).LastWriteTimeUtc
    $newest = $null
    foreach ($dir in @('Scripts', 'Assets', 'Scenes')) {
        $path = Join-Path $repo $dir
        if (-not (Test-Path $path)) { continue }
        $candidate = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -ne '.import' } |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
        if ($candidate -and (-not $newest -or $candidate.LastWriteTimeUtc -gt $newest.LastWriteTimeUtc)) {
            $newest = $candidate
        }
    }
    if ($newest -and $newest.LastWriteTimeUtc -gt $cacheTime) {
        $needsImport = $true
        Write-Host ("import is older than {0}" -f $newest.Name)
    }
}
if ($needsImport) {
    Write-Host "Importing (about a minute the first time). The game will not start until this finishes."
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
