# Launch one instrument, the way that instrument has to be launched.
#
#   powershell -ExecutionPolicy Bypass -File Tools\run.ps1 ScreenSweep
#   ... ScreenSweep -Resolution 844x390
#   ... SampleFights -TimeoutSeconds 900
#
# Issue 472: on Godot 4.7.1, `--script res://Tools/X.gd` where X extends Node
# does NOT run it. `_ready` never fires, nothing is written, and the process
# hangs until it is killed, having printed only the engine banner. A hang and a
# tool that legitimately found nothing look identical from outside, which is how
# it survived. A `SceneTree` script is unaffected: Godot installs that as the
# main loop.
#
# So the choice of invocation is not the caller's to make, and no in-tool
# watchdog can catch it -- the tool never executes a line of its own code. The
# budget has to be enforced from out here.
#
# Issue 478: `--headless` has no renderer, so `frame_post_draw` never fires and
# a capture tool waits for a frame that cannot arrive. Three sessions hit that
# in one night, one of them burning 650 seconds of CPU. `-Headless` is refused
# for anything with a scene rather than started and left to the wall clock.
param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $Tool,
    [int] $TimeoutSeconds = 300,
    [string] $Resolution = '1280x720',
    [switch] $Headless,
    # Passed to the tool after `--`, where it reads them with
    # `OS.get_cmdline_user_args()`. Empty by default, so no existing launch changes.
    [string[]] $ToolArgs = @(),
    # `--fixed-fps N` makes the engine report a delta of exactly 1/N every frame,
    # including to the particle system, which nothing inside a tool can reach.
    # A frame recorder needs it; everything else should leave it at 0.
    [int] $FixedFps = 0,
    # `--write-movie <path.avi>` records the audio bus per rendered frame rather
    # than in real time, which is the only way a capture running at a tenth of
    # real time can carry sound. Empty by default, so no existing launch changes.
    [string] $WriteMovie = ''
)
. (Join-Path $PSScriptRoot 'ensure_import.ps1')

$name = [System.IO.Path]::GetFileNameWithoutExtension(($Tool -replace '^res://Tools/', ''))
$scene = Join-Path $PSScriptRoot "$name.tscn"
$script = Join-Path $PSScriptRoot "$name.gd"

if (-not (Test-Path $script)) {
    Write-Host "No Tools\$name.gd. Did you mean one of these?"
    Get-ChildItem -Path $PSScriptRoot -Filter "*$name*.gd" | ForEach-Object { Write-Host "  $($_.BaseName)" }
    exit 3
}

# A one-node scene is how a Node tool gets a tree to run in. Every runnable one
# in this directory ships one, and Tests\test_tools_are_launchable.gd fails the
# gate if a new one does not.
if (Test-Path $scene) {
    if ($Headless) {
        Write-Host "$name draws frames, and --headless has no renderer."
        Write-Host "RenderingServer.frame_post_draw would never fire and the run would hang"
        Write-Host "rather than fail (issue 478). Drop -Headless: the window is moved off the"
        Write-Host "desktop by Offscreen.hide_window, so it does not take over the machine."
        exit 3
    }
    $godotArgs = @('--path', $repo, '--resolution', $Resolution)
    if ($FixedFps -gt 0) { $godotArgs += @('--fixed-fps', "$FixedFps") }
    if ($WriteMovie -ne '') {
        $movieDir = Split-Path -Parent $WriteMovie
        if ($movieDir -and -not (Test-Path $movieDir)) {
            New-Item -ItemType Directory -Force -Path $movieDir | Out-Null
        }
        $godotArgs += @('--write-movie', $WriteMovie)
    }
    $godotArgs += "res://Tools/$name.tscn"
    if ($ToolArgs.Count -gt 0) { $godotArgs += '--'; $godotArgs += $ToolArgs }
} else {
    $extends = (Get-Content $script -TotalCount 1) -replace '^﻿', ''
    if ($extends.Trim() -ne 'extends SceneTree') {
        Write-Host "Tools\$name.gd is '$($extends.Trim())' and has no Tools\$name.tscn."
        Write-Host "Launching it with --script would hang silently (issue 472). Give it a"
        Write-Host "one-node scene, or make it a SceneTree script. Not launching."
        exit 3
    }
    $godotArgs = @('--headless', '--path', $repo, '--script', "res://Tools/$name.gd")
}

Write-Host ("running {0} ({1}s budget): {2}" -f $name, $TimeoutSeconds, ($godotArgs -join ' '))
# `System.Diagnostics.Process` rather than `Start-Process -PassThru`, whose
# ExitCode stays null after the timed WaitForExit and reports every clean run as
# a failure.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $godot
# `.Arguments`, not `.ArgumentList`: Windows PowerShell 5.1 is on .NET Framework
# and has no ArgumentList, where the call fails with "method on a null-valued
# expression". Every argument is quoted because the repo path can hold spaces.
$psi.Arguments = ($godotArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$proc = [System.Diagnostics.Process]::Start($psi)
# Read both pipes on background tasks: a full pipe buffer blocks the child, and
# a tool that has been blocked by its own reader looks exactly like a hang.
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()
$finished = $proc.WaitForExit($TimeoutSeconds * 1000)

if (-not $finished) {
    # By the id this script started, never by image name: every other session's
    # Godot runs under the same name.
    & (Join-Path $PSScriptRoot 'reap.ps1') -Id $proc.Id | Out-Null
    Write-Host $outTask.Result
    Write-Host $errTask.Result
    Write-Host ""
    Write-Host "$name PRODUCED NO RESULT AND WAS KILLED after $TimeoutSeconds seconds."
    Write-Host "This is a hang, not a measurement. Do not report it as 'found nothing'."
    exit 5
}

Write-Host $outTask.Result
Write-Host $errTask.Result
$code = $proc.ExitCode
if ($code -ne 0) { Write-Host "$name exited $code." }
exit $code
