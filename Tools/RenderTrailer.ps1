# The one command that re-renders the whole trailer. Issue 705.
#
#   powershell -ExecutionPolicy Bypass -File Tools\RenderTrailer.ps1
#
# Two passes: `TrailerCapture.gd` plays real fights and drives the real UI,
# once, in the order `Tools\TrailerBeats.json` names, and writes every
# rendered frame into one `-write-movie` .avi so the audio bus lands in it
# (the movie writer mixes per rendered frame, not in real time -- the only way
# a run slower than real time carries any sound at all). This script's own
# job is the second pass: read the manifest `TrailerCapture` wrote beside that
# .avi, cut each clip's own frame range out of it with ffmpeg, drop a title
# card from the same JSON between acts, and concatenate the result.
#
# Frames and the .avi land outside the repository on purpose -- thousands of
# PNGs and an uncompressed movie are not something this tool commits, and
# `Tools\ENGINEER.md`'s worktree rule is the same reasoning applied to a
# render instead of a branch.
param(
	[string] $OutDir = 'D:\Projects\Claudeguise-team\scratch\teal-trailer',
	[int] $TimeoutSeconds = 3600
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$framesDir = Join-Path $OutDir 'frames'
$movie = Join-Path $OutDir 'movie.avi'
$segDir = Join-Path $OutDir 'segments'
$final = Join-Path $OutDir 'trailer.mp4'
$font = 'C\:/Windows/Fonts/arial.ttf'

if (Test-Path $framesDir) { Remove-Item -Recurse -Force $framesDir }
if (Test-Path $segDir) { Remove-Item -Recurse -Force $segDir }
New-Item -ItemType Directory -Force -Path $framesDir, $segDir | Out-Null

Write-Host "=== pass 1: TrailerCapture, the whole beat sheet, one movie ==="
& (Join-Path $PSScriptRoot 'run.ps1') TrailerCapture -Resolution 1280x720 -FixedFps 60 `
	-WriteMovie $movie -TimeoutSeconds $TimeoutSeconds -ToolArgs @($framesDir)
# Not a hard gate on `$LASTEXITCODE`: Godot's own teardown regularly exits
# non-zero on leaked-RID warnings that have nothing to do with whether the
# clips themselves landed. The manifest and the .avi, checked next, are what
# actually says whether there is anything to assemble.
if ($LASTEXITCODE -ne 0) {
	Write-Host "TrailerCapture exited $LASTEXITCODE -- checking whether it still produced a usable manifest."
}

$manifestPath = Join-Path $framesDir 'manifest.txt'
if (-not (Test-Path $manifestPath)) {
	Write-Host "No manifest at $manifestPath."
	exit 6
}
if (-not (Test-Path $movie)) {
	Write-Host "No movie at $movie -- WriteMovie did not produce a file. Trailer has no audio to cut from."
	exit 6
}

# CLIP <name> frames F1-F2 (n)  movie M1-M2  <detail>  toggles: ...
$clips = @{}
$order = @()
Get-Content $manifestPath | ForEach-Object {
	if ($_ -match '^CLIP\s+(\S+)\s+frames\s+\d+-\d+\s+\(\d+\)\s+movie\s+(\d+)-(\d+)') {
		$name = $matches[1]
		$row = @{ Name = $name; M1 = [int]$matches[2]; M2 = [int]$matches[3] }
		if (-not $clips.ContainsKey($name)) { $clips[$name] = @() }
		$clips[$name] += , $row
		$order += $name
	}
}

$beats = Get-Content (Join-Path $PSScriptRoot 'TrailerBeats.json') -Raw | ConvertFrom-Json

Write-Host "=== pass 2: cutting segments from the movie, ffmpeg ==="
$segments = New-Object System.Collections.Generic.List[string]
$i = 0

# `plan_diff.default` runs the losing arm to its real resolution on purpose
# (see the .gd file) so the outcome itself is real rather than cut off mid
# fight -- which makes it far longer than a shot needs to be. Trimmed to its
# own last seconds so what stays on screen is the loss and the banner, not
# the grind that produced it. No other clip needs this: everything else
# already frames the moment it exists to show.
$trimLastSeconds = @{ 'plan_diff.default' = 20; 'plan_diff.authored' = 16 }

function New-TitleCard([string] $text, [string] $path) {
	$vf = "drawtext=fontfile='$font':text='$text':fontcolor=white:fontsize=64:x=(w-text_w)/2:y=(h-text_h)/2"
	& ffmpeg -y -f lavfi -i "color=c=black:s=1280x720:r=60:d=2" -f lavfi -i "anullsrc=r=48000:cl=stereo" `
		-vf $vf -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $path 2>&1 | Out-Null
}

foreach ($act in $beats) {
	$i++
	$titlePath = Join-Path $segDir ("{0:D3}_title.mp4" -f $i)
	New-TitleCard $act.title $titlePath
	$segments.Add($titlePath)

	foreach ($clipName in $act.clips) {
		# A beat sheet clip may have written several manifest lines --
		# `hands_ab.fast`/`.slow`, `plan_diff.default`/`.authored`, and so on --
		# every one of them belongs in the trailer, in manifest (capture) order.
		$rows = $order | Where-Object { $_ -eq $clipName -or $_.StartsWith("$clipName.") } |
			Select-Object -Unique | ForEach-Object { $clips[$_] } | ForEach-Object { $_ }
		if (-not $rows) {
			Write-Host "No manifest rows for beat sheet clip '$clipName' -- skipping, not faking it."
			continue
		}
		foreach ($row in $rows) {
			$start = $row.M1 / 60.0
			$end = ($row.M2 + 1) / 60.0
			if ($trimLastSeconds.ContainsKey($row.Name) -and ($end - $start) -gt $trimLastSeconds[$row.Name]) {
				$start = $end - $trimLastSeconds[$row.Name]
			}
			$segPath = Join-Path $segDir ("{0:D3}_{1}.mp4" -f $segments.Count, $row.Name)
			& ffmpeg -y -i $movie -ss $start -to $end -r 60 -s 1280x720 `
				-c:v libx264 -pix_fmt yuv420p -ar 48000 -ac 2 -c:a aac $segPath 2>&1 | Out-Null
			$segments.Add($segPath)
		}
	}

	if ($act.end_card) {
		$endPath = Join-Path $segDir ("{0:D3}_end.mp4" -f ($i + 1))
		New-TitleCard $act.end_card $endPath
		$segments.Add($endPath)
	}
}

Write-Host "=== pass 3: concatenating $($segments.Count) segments ==="
$concatList = Join-Path $segDir 'concat.txt'
$segments | ForEach-Object { "file '$($_ -replace "'", "'\''")'" } | Set-Content -Encoding ASCII $concatList
& ffmpeg -y -f concat -safe 0 -i $concatList -c copy $final 2>&1 | Out-Null

if (-not (Test-Path $final)) {
	Write-Host "Concat produced no file at $final."
	exit 7
}
$dur = & ffprobe -v error -show_entries format=duration -of csv=p=0 $final
Write-Host "TRAILER $final ($([math]::Round([double]$dur, 1))s)"
