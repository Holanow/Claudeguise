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
    [switch] $Record,
    # Issue 648: a non-blocking pre-commit reminder cannot afford SampleFights'
    # ~90s. Compares only Get-SourceHash against the recorded source: line and
    # never runs the tool -- a false OK is possible (source moved, output
    # didn't) but a false stale reading is not, which is the safe direction
    # for a reminder rather than a gate.
    [switch] $SourceOnly
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
## Issue 821: EVERY file in these directories is source, rather than a list of
## extensions. An allow-list lost `.tres` in #633 and `.tscn` in #680, both
## times because content moved to a file type nobody added to it; the sim/view
## separation is carried by these directories, never by the extension.
$SOURCE_DIRS = @('Combat', 'Content', 'Core', 'Floor', 'Plans', 'Rooms')

## Godot writes these next to a script when the EDITOR opens the project, and
## `.gitignore` excludes both. Hashing them would make the fingerprint differ
## between a fresh clone and an editor tree, which is a defect, not a guard.
$GENERATED_SIDECARS = @('.uid', '.import')

function Get-SourceHash {
    $files = @()
    foreach ($dir in $SOURCE_DIRS) {
        $path = Join-Path $repo "Scripts\$dir"
        if (Test-Path $path) {
            # Enumerated then filtered: `-Exclude` with `-Recurse` is unreliable
            # in PowerShell 5.1.
            $files += Get-ChildItem -Path $path -Recurse -File |
                Where-Object { $GENERATED_SIDECARS -notcontains $_.Extension }
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

# Issue 725: the `source:` line written to the record is this, not the bare
# real-source hash -- it folds the recorded `output:` value in too, so a
# hand-edited or merge-mangled output line moves this digest even when no
# source file did, and the fast path below (which never runs SampleFights)
# catches it on the very next check instead of trusting it until source moves.
function Get-RecordDigest {
    param([string] $RealSource, [string] $Output)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$RealSource`n$Output")
    ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
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

# Issue 648: -Record used to hash the working tree with no check that it was
# the tree that ships. Excludes the record file itself -- writing it is always
# in flight while recording, and #648 says as much.
function Test-SourceDirty {
    $paths = $SOURCE_DIRS | ForEach-Object { "Scripts/$_" }
    $paths += 'Tools/SampleFights.gd'
    $status = & git -C $repo status --porcelain -- $paths
    return @($status | Where-Object { $_ -ne '' }).Count -gt 0
}

$source = Get-SourceHash

if ($SourceOnly) {
    if (-not (Test-Path $recordPath)) {
        Write-Output "No $recordPath."
        exit 2
    }
    $recordedSource = $null
    $recordedOutput = $null
    foreach ($line in Get-Content $recordPath) {
        if ($line -match '^source: ([0-9a-f]{64})$') { $recordedSource = $Matches[1] }
        if ($line -match '^output: ([0-9a-f]{64})$') { $recordedOutput = $Matches[1] }
    }
    if (-not $recordedSource -or -not $recordedOutput) {
        Write-Output "$recordPath is missing a source: or output: line."
        exit 2
    }
    if ((Get-RecordDigest $source $recordedOutput) -eq $recordedSource) {
        Write-Output "UNCHANGED"
        exit 0
    }
    Write-Output "SOURCE MOVED, OR ITS RECORDED OUTPUT LINE WAS EDITED (not run: -SourceOnly never calls SampleFights)"
    exit 1
}

if ($Record) {
    if (Test-SourceDirty) {
        Write-Output "REFUSING TO RECORD: the hashed source has uncommitted changes."
        Write-Output "A record taken now describes a tree nobody can check out (issue 648)."
        Write-Output "Commit the source first, then record against the committed tree."
        Write-Output "Nothing recorded."
        exit 2
    }
    $output = Get-OutputHash
    if (-not $output) {
        Write-Output "REFUSING TO HASH: $script:Refusal."
    Write-Output "An empty or truncated capture hashes to e3b0c442 on both arms and reads"
    Write-Output "as 'byte-identical'. That is issue 536, and it is worse than no proof."
        Write-Output "Nothing recorded."
        exit 2
    }
    $commit = (& git -C $repo rev-parse HEAD).Trim()
    $digest = Get-RecordDigest $source $output
    @(
        "# What the simulation is, and what it produces. Issue 529.",
        "# Re-record with: powershell -File Tools\sim_fingerprint.ps1 -Record",
        "# Both lines move together. A source change with no output change is",
        "# still a change, and the gate makes you say so here.",
        "# commit: the source tree this was taken against (issue 648), informational only.",
        "# source: real source hash folded with output (issue 725), not the bare hash.",
        "source: $digest",
        "output: $output",
        "commit: $commit"
    ) -join "`n" | ForEach-Object {
        # LF and no BOM: git normalises this file anyway, and a recording that
        # looks dirty the moment it is written is one people stop trusting.
        [System.IO.File]::WriteAllText($recordPath, $_ + "`n", (New-Object System.Text.UTF8Encoding $false))
    }
    Write-Output "recorded  source: $digest  (real source: $source)"
    Write-Output "          output: $output"
    Write-Output "          commit: $commit"
    exit 0
}

if (-not (Test-Path $recordPath)) {
    Write-Output "No $recordPath. Run this with -Record once to create it."
    exit 2
}
# Issue 677: a union merge (never configure one on this file) would silently
# pair one branch's source: with the other's output:. Refuse on ANY duplicate
# key or conflict marker rather than taking the last of each, which is what
# made that pairing silent in the first place.
$recorded = @{}
$duplicateKeys = @()
foreach ($line in Get-Content $recordPath) {
    if ($line.StartsWith('<<<<<<<') -or $line.StartsWith('=======') -or $line.StartsWith('>>>>>>>')) {
        Write-Output "$recordPath has an unresolved merge conflict marker. This is a failure, not a pass."
        exit 2
    }
    if ($line -match '^(source|output): ([0-9a-f]{64})$') {
        if ($recorded.ContainsKey($Matches[1])) { $duplicateKeys += $Matches[1] }
        $recorded[$Matches[1]] = $Matches[2]
    }
}
if ($duplicateKeys.Count -gt 0) {
    Write-Output ("$recordPath has more than one '{0}:' line. Refusing rather than taking the" -f ($duplicateKeys -join ', '))
    Write-Output "last -- that is exactly how a union merge would pair one tree's source with"
    Write-Output "another's output (issue 677). Re-record against the merge result."
    exit 2
}
if (-not $recorded.ContainsKey('source') -or -not $recorded.ContainsKey('output')) {
    Write-Output "$recordPath is missing a source: or output: line. This is a failure, not a pass."
    exit 2
}

# The fast path, and it is a STRONGER claim than the slow one for a view-only
# change: the simulation's source is byte-for-byte what it was AND the
# recorded output line is exactly what was hashed in alongside it at record
# time (issue 725), so neither can have moved. Costs about a second instead
# of a hundred, and it is what catches a hand-edited or merge-mangled output:
# line immediately rather than only the next time source moves.
if ((Get-RecordDigest $source $recorded['output']) -eq $recorded['source']) {
    Write-Output "UNCHANGED  the simulation's own source is byte-identical to the recording"
    exit 0
}

Write-Output "the simulation's source moved, or its recorded output line was edited outside a -Record run; running SampleFights to check"
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
    Write-Output "  recorded digest: $($recorded['source'])"
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
