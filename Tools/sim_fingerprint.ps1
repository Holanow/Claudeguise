# The byte-identical proof, taken so that it cannot be taken wrong (issue 529).
#
#   powershell -ExecutionPolicy Bypass -File Tools\sim_fingerprint.ps1
#   ... -Record     # after a change you MEANT to make to the simulation
#
# The old method was "sha256 of SampleFights' output". FOUR things get into that
# hash which the simulation never printed: `ensure_import.ps1`'s banner, which
# appears precisely because swapping files to take the measurement is what
# stales the import cache; two blank lines `run.ps1` writes after the tool; a CR
# on every line, so the answer depends on whose shell normalised it; and, worst,
# NOTHING AT ALL -- `run.ps1` writes through `Write-Host`, which `>` does not
# capture in-process, so the documented pipeline could hash an empty file and
# report both arms identical at e3b0c442. See issue 536.
#
# `SampleFights` hashes its own output from inside and prints `lines:` and
# `fingerprint:`. This script never hashes that output; it reads those two lines,
# and refuses to proceed if it cannot find them or if the run was too short to be
# a real one. A proof that reports success when it measured nothing is worse than
# no proof.
#
# WHAT THIS DOES NOT PROVE. `SampleFights` is a `SceneTree` script over
# `CombatSim` and never instantiates a view, so byte-identity guards SHARED
# CONSTANTS. It cannot catch a view writing into sim state at run time; the
# `*_never_reaches_the_simulation` unit tests are that half.
param(
    [switch] $Record
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ensure_import.ps1')

$recordPath = Join-Path $PSScriptRoot 'sim_fingerprint.txt'

# Everything the simulation reads, and nothing the view does. `Scripts/UI`,
# `Scripts/Art` and `Scripts/Audio` are excluded because the sim never reads
# them -- that is the architecture the whole #500 epic rests on. `SoundBank.gd`
# is read by `BattleView` and by nothing below the presentation layer (#570).
# `SampleFights.gd` is IN the set: the instrument is part of the measurement,
# and editing it moves the output.
## Issue 633: `.tres` counts as source. Content left GDScript in #621 and #628,
## so hashing only `*.gd` would let an edited action or class move no hash while
## the gate printed `sim pass` on a changed simulation.
function Get-SourceHash {
    $files = @()
    foreach ($dir in @('Combat', 'Content', 'Core', 'Floor', 'Plans')) {
        $path = Join-Path $repo "Scripts\$dir"
        if (Test-Path $path) {
            $files += Get-ChildItem -Path $path -Recurse -File -Include *.gd, *.tres
        }
    }
    $files += Get-Item (Join-Path $repo 'Tools\SampleFights.gd')

    # Sorted by path, and the path goes into the digest with the bytes, so a
    # rename or a deletion moves it and not only an edit.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $buffer = New-Object System.IO.MemoryStream
    foreach ($f in ($files | Sort-Object FullName)) {
        $relative = $f.FullName.Substring($repo.Length).Replace('\', '/')
        $name = [System.Text.Encoding]::UTF8.GetBytes("$relative`n")
        $buffer.Write($name, 0, $name.Length)
        $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
        $buffer.Write($bytes, 0, $bytes.Length)
    }
    ($sha.ComputeHash($buffer.ToArray()) | ForEach-Object { $_.ToString('x2') }) -join ''
}

# Runs the tool and returns the digest IT printed. `cmd` redirection rather than
# a PowerShell pipe, for the reason gate.ps1 documents: 5.1 wraps a native
# program's stderr in ErrorRecords and $ErrorActionPreference = 'Stop' then kills
# the caller on the first warning Godot writes.
# The smallest report that could possibly be a real run. Six rooms times ten
# parties times seven lines is well over this; an empty or truncated capture is
# far under it. Issue 536: the failure to refuse was the defect.
$MIN_REPORT_LINES = 200
$script:Refusal = ""

function Get-OutputHash {
    $log = Join-Path $env:TEMP ("claudeguise-sim-" + [guid]::NewGuid().ToString('N') + ".txt")
    cmd /c "`"$godot`" --headless --path `"$repo`" --script res://Tools/SampleFights.gd > `"$log`" 2>&1"
    $captured = if (Test-Path $log) { (Get-Content $log | Measure-Object -Line).Lines } else { 0 }
    $countLine = Select-String -Path $log -Pattern '^lines: ([0-9]+)$' | Select-Object -First 1
    $hashLine = Select-String -Path $log -Pattern '^fingerprint: ([0-9a-f]{64})$' | Select-Object -First 1
    Remove-Item $log -ErrorAction SilentlyContinue

    # A refusal goes in a script variable, never through Write-Output: inside a
    # function that returns a value, Write-Output IS the return value, and the
    # first version of this handed the refusal text back as if it were a hash.
    if ($captured -lt $MIN_REPORT_LINES) {
        $script:Refusal = "captured $captured line(s) from SampleFights, which is not a run"
        return $null
    }
    if (-not $countLine -or -not $hashLine) {
        $script:Refusal = "SampleFights printed no lines:/fingerprint: pair"
        return $null
    }
    $reported = [int]$countLine.Matches[0].Groups[1].Value
    if ($reported -lt $MIN_REPORT_LINES) {
        $script:Refusal = "SampleFights reported only $reported lines of report"
        return $null
    }
    $script:Refusal = ""
    $hashLine.Matches[0].Groups[1].Value
}

$source = Get-SourceHash

if ($Record) {
    $output = Get-OutputHash
    if (-not $output) {
        Write-Output "REFUSING TO HASH: $script:Refusal."
    Write-Output "An empty or truncated capture hashes to e3b0c442 on both arms and reads"
    Write-Output "as 'byte-identical'. That is issue 536, and it is worse than no proof."
        Write-Output "Nothing recorded."
        exit 2
    }
    @(
        "# What the simulation is, and what it produces. Issue 529.",
        "# Re-record with: powershell -File Tools\sim_fingerprint.ps1 -Record",
        "# Both lines move together. A source change with no output change is",
        "# still a change, and the gate makes you say so here.",
        "source: $source",
        "output: $output"
    ) -join "`n" | ForEach-Object {
        # LF and no BOM: git normalises this file anyway, and a recording that
        # looks dirty the moment it is written is one people stop trusting.
        [System.IO.File]::WriteAllText($recordPath, $_ + "`n", (New-Object System.Text.UTF8Encoding $false))
    }
    Write-Output "recorded  source: $source"
    Write-Output "          output: $output"
    exit 0
}

if (-not (Test-Path $recordPath)) {
    Write-Output "No $recordPath. Run this with -Record once to create it."
    exit 2
}
$recorded = @{}
foreach ($line in Get-Content $recordPath) {
    if ($line -match '^(source|output): ([0-9a-f]{64})$') { $recorded[$Matches[1]] = $Matches[2] }
}
if (-not $recorded.ContainsKey('source') -or -not $recorded.ContainsKey('output')) {
    Write-Output "$recordPath is missing a source: or output: line. This is a failure, not a pass."
    exit 2
}

# The fast path, and it is a STRONGER claim than the slow one for a view-only
# change: the simulation's source is byte-for-byte what it was, so its output
# cannot have moved. Costs about a second instead of a hundred.
if ($source -eq $recorded['source']) {
    Write-Output "UNCHANGED  the simulation's own source is byte-identical to the recording"
    exit 0
}

Write-Output "the simulation's source moved; running SampleFights to see whether its output did"
$output = Get-OutputHash
if (-not $output) {
    Write-Output "REFUSING TO HASH: $script:Refusal."
    Write-Output "An empty or truncated capture hashes to e3b0c442 on both arms and reads"
    Write-Output "as 'byte-identical'. That is issue 536, and it is worse than no proof."
    Write-Output "This is a failure, not a pass."
    exit 2
}
if ($output -eq $recorded['output']) {
    Write-Output "SOURCE MOVED, OUTPUT DID NOT."
    Write-Output "  recorded source: $($recorded['source'])"
    Write-Output "  actual source:   $source"
    Write-Output "The output is byte-identical, so this changed nothing the simulation does."
    Write-Output "Record it anyway, or every later run pays for this one again:"
    Write-Output "  powershell -ExecutionPolicy Bypass -File Tools\sim_fingerprint.ps1 -Record"
    exit 1
}
Write-Output "THE SIMULATION'S OUTPUT CHANGED."
Write-Output "  recorded output: $($recorded['output'])"
Write-Output "  actual output:   $output"
Write-Output "If your change was meant to be view-only, this is the defect and it is yours."
Write-Output "If you meant it, record it so the diff carries it:"
Write-Output "  powershell -ExecutionPolicy Bypass -File Tools\sim_fingerprint.ps1 -Record"
exit 1
