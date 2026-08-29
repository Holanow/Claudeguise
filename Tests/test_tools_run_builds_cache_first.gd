extends "res://Tests/TestCase.gd"


## Issue 715. A fresh worktree has no `.godot/` class cache; a raw `godot
## --headless` call against it hangs indefinitely (confirmed: >25s on a plain
## `--script` run with no scene at all, and `--check-only` alone does not
## catch it -- it exits 0 in well under a second regardless of cache state).
## `Tools/run.ps1` already avoids the whole failure by building the cache
## before it ever invokes godot, and by bounding its own launch with a
## timeout and a reap. This guards that ordering from regressing silently.

const RUN := "res://Tools/run.ps1"


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _first_index(text: String, needle: String) -> int:
	var i := text.find(needle)
	assert_true(i >= 0, "expected to find '%s' in %s" % [needle, RUN])
	return i


## `ensure_import.ps1` is what builds the missing class cache (issue 472's
## fix); it has to run before the first godot invocation or that invocation
## can hit the unresolved-identifier hang this issue is about.
func test_ensure_import_runs_before_any_godot_invocation() -> void:
	var text := _text(RUN)
	var dotSource := _first_index(text, ". (Join-Path $PSScriptRoot 'ensure_import.ps1')")
	var firstGodotCall := _first_index(text, '"`"$godot`"')
	assert_true(dotSource < firstGodotCall,
		"ensure_import.ps1 must be dot-sourced before the first godot call, or a fresh " +
		"worktree's missing class cache reaches godot unbuilt")


## The `--check-only` preflight (issue 618) is a syntax check, not a class
## resolution check -- it exits 0 in well under a second even with the class
## cache missing (measured). It still has to run before the real launch, so
## a genuine parse error is caught fast; it just cannot substitute for
## ensure_import.ps1 running first.
func test_check_only_runs_before_the_real_launch() -> void:
	var text := _text(RUN)
	var checkOnly := _first_index(text, "--check-only")
	var realLaunch := _first_index(text, "[System.Diagnostics.Process]::Start")
	assert_true(checkOnly < realLaunch,
		"--check-only must run before the timed launch, or a parse error pays the full budget")


## The real launch is timeout-bounded and reaped rather than left to the wall
## clock -- the third layer, in case the first two somehow do not apply.
func test_the_real_launch_is_timeout_bounded_and_reaped() -> void:
	var text := _text(RUN)
	assert_true(text.contains("WaitForExit($TimeoutSeconds"),
		"the launch must be bounded by -TimeoutSeconds, not left to run forever")
	assert_true(text.contains("reap.ps1") and text.contains("-not $finished"),
		"a launch that outlives its budget must be reaped, not merely reported")
