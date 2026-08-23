# Launch the game, rebuilding the class cache first if it is stale.
#
#   powershell -ExecutionPolicy Bypass -File Tools\play.ps1
#
# To launch one of the instruments instead, use Tools\run.ps1.
. (Join-Path $PSScriptRoot 'ensure_import.ps1')

& $godot --path $repo
