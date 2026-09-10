# Verify the project is imported, rather than trusting the class cache for it.
#
# Issue 865: a fresh worktree held a current class cache, 3 entries in
# .godot/imported and no terrain_tiles.png.import. The gate printed
# "import pass", then died with an access violation inside RoomLoader.load_room,
# which reads as a defect in the reader's own branch.
param(
    [Parameter(Mandatory = $true)][string] $Repo,
    # Print nothing at all; the caller reports, or re-runs without this to show why.
    [switch] $Quiet
)
$ErrorActionPreference = 'Stop'

## Godot writes one .import sidecar per importable asset; an asset type missing
## from this list is still covered by the dest_files check below once imported.
$IMPORTABLE = @('.png', '.jpg', '.jpeg', '.svg', '.webp', '.ogg', '.wav', '.mp3', '.ttf', '.otf')

## A scan that found nothing would pass on anything, which is the failure this
## file exists to stop wearing a second hat.
$MIN_ASSETS = 100

$importedDir = Join-Path $Repo '.godot\imported'
$assets = @(
    Get-ChildItem -Path $Repo -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.godot' } |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue } |
        Where-Object { $IMPORTABLE -contains $_.Extension.ToLower() }
)

$noSidecar = @()
$noImported = @()
foreach ($asset in $assets) {
    $sidecar = $asset.FullName + '.import'
    if (-not (Test-Path $sidecar)) { $noSidecar += $asset.Name; continue }
    foreach ($m in [regex]::Matches((Get-Content $sidecar -Raw), 'res://\.godot/imported/([^"]+)')) {
        if (-not (Test-Path (Join-Path $importedDir $m.Groups[1].Value))) {
            $noImported += $asset.Name
            break
        }
    }
}

$entries = 0
if (Test-Path $importedDir) { $entries = @(Get-ChildItem $importedDir -File -ErrorAction SilentlyContinue).Count }

if ($Quiet) {
    if ($assets.Count -lt $MIN_ASSETS -or $noSidecar.Count -gt 0 -or $noImported.Count -gt 0) { exit 9 }
    exit 0
}

if ($assets.Count -lt $MIN_ASSETS) {
    Write-Host ("  import     FAIL   (found only {0} importable assets under {1}; expected at least {2})" -f $assets.Count, $Repo, $MIN_ASSETS)
    Write-Host "      The scan itself is broken. It would pass on anything, so it refuses instead."
    exit 9
}

if ($noSidecar.Count -gt 0 -or $noImported.Count -gt 0) {
    Write-Host ("  import     FAIL   (the project is NOT imported: {0} of {1} assets are missing)" -f ($noSidecar.Count + $noImported.Count), $assets.Count)
    if ($noSidecar.Count -gt 0) {
        Write-Host ("      {0} assets have no .import sidecar, first: {1}" -f $noSidecar.Count, (($noSidecar | Select-Object -First 5) -join ', '))
    }
    if ($noImported.Count -gt 0) {
        Write-Host ("      {0} assets have no imported file under .godot/imported ({1} entries there), first: {2}" -f $noImported.Count, $entries, (($noImported | Select-Object -First 5) -join ', '))
    }
    Write-Host "      Every scene and tileset that loads one of these fails, and Godot can die"
    Write-Host "      with an access violation rather than an error. Import first:"
    Write-Host ("        <godot> --headless --import --path `"{0}`"" -f $Repo)
    exit 9
}

Write-Host ("  import     pass   ({0}/{0} assets imported, {1} entries in .godot/imported)" -f $assets.Count, $entries)
exit 0
