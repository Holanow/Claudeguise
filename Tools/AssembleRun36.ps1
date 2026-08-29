# Issue 748: cut the recorded floor to an mp4 and burn the room captions in.
#
#   powershell -ExecutionPolicy Bypass -File Tools\AssembleRun36.ps1
#
# Pass one (FloorRecord + --write-movie) is a separate, slow step. This is the
# assembly, kept apart so captions can be iterated without re-rendering.
param([string] $OutDir = 'D:\Projects\Claudeguise-team\scratch\run36')
$ErrorActionPreference = 'Continue'
$movie = Join-Path $OutDir 'movie.avi'
$final = Join-Path $OutDir 'run36.mp4'
if (-not (Test-Path $movie)) { Write-Host "no movie at $movie"; exit 1 }
$font = 'C\:/Windows/Fonts/georgia.ttf'
if (-not (Test-Path 'C:\Windows\Fonts\georgia.ttf')) { $font = 'C\:/Windows/Fonts/arial.ttf' }

# Measured, not derived: FloorRecord logs Engine.get_frames_drawn() at each
# room's first frame and the movie is 60fps.
$rooms = @(
    @(0.0,    16.02, '1/10  The Narrows, elite'),
    @(16.02,  38.45, '2/10  Chokepoint'),
    @(38.45,  55.60, '3/10  Sellsword'),
    @(55.60,  67.03, '4/10  Horde'),
    @(67.03,  87.62, '5/10  Hazard'),
    @(87.62, 151.77, '6/10  The Rat King  --  three of four go down'),
    @(151.77,164.55, '7/10  Ghoul Den  --  the camp is spent'),
    @(164.55,181.73, '8/10  Room One'),
    @(181.73,196.08, '9/10  Cover'),
    @(196.08,211.00, '10/10  The Warden')
)
$parts = @()
foreach ($r in $rooms) {
    $start = $r[0]; $end = [math]::Min($r[0] + 5.0, $r[1]); $text = $r[2]
    $parts += "drawtext=fontfile='$font':text='$text':fontcolor=white:fontsize=28:box=1:boxcolor=black@0.55:boxborderw=12:x=40:y=40:enable='between(t,$start,$end)'"
}
$filter = $parts -join ','
Write-Host "=== encoding $final"
& ffmpeg -y -i $movie -vf $filter -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac $final
if (Test-Path $final) { Write-Host ("wrote {0} ({1} MB)" -f $final, [math]::Round((Get-Item $final).Length/1MB,1)) }
