# Run Godot's importer until import_check.ps1 agrees, bounded, or say why not.
#
# Issue 888: one --import pass is not always enough on a cold worktree, so every
# fresh worktree failed its first gate run and the engineer had to know to
# re-run it. Exits 0 when the project is imported, 9 when it is not.
param(
    [Parameter(Mandatory = $true)][string] $Repo,
    [Parameter(Mandatory = $true)][string] $Godot,
    [int] $MaxPasses = 5
)
$ErrorActionPreference = 'Stop'

$check = Join-Path $PSScriptRoot 'import_check.ps1'
$importedDir = Join-Path $Repo '.godot\imported'

$before = -1
$log = $null
for ($pass = 1; $pass -le $MaxPasses; $pass++) {
    if ($log) { Remove-Item $log -ErrorAction SilentlyContinue }
    $log = Join-Path $env:TEMP ("claudeguise-import-" + [guid]::NewGuid().ToString('N') + ".txt")
    cmd /c "`"$Godot`" --headless --import --path `"$Repo`" > `"$log`" 2>&1"
    $rc = $LASTEXITCODE

    & $check -Repo $Repo -Quiet
    if ($LASTEXITCODE -eq 0) {
        Remove-Item $log -ErrorAction SilentlyContinue
        if ($pass -gt 1) { Write-Host ("  import     converged on pass {0} of {1}" -f $pass, $MaxPasses) }
        exit 0
    }

    $after = 0
    if (Test-Path $importedDir) { $after = @(Get-ChildItem $importedDir -File -ErrorAction SilentlyContinue).Count }
    Write-Host ("  import     pass {0} of {1} left it incomplete (godot exit {2}, {3} files in .godot/imported)" -f $pass, $MaxPasses, $rc, $after)

    ## A pass that imported nothing new will not do better if it is repeated.
    if ($after -eq $before) {
        Write-Host "      That pass imported nothing new, so another would not either. Stopping early."
        break
    }
    $before = $after
}

Write-Host ("      The importer did not converge. Its last output is at {0}" -f $log)
exit 9
