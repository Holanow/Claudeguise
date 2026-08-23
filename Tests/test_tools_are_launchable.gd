extends "res://Tests/TestCase.gd"


## Every runnable instrument must be launchable by the only means that works.

## Issue 472: on Godot 4.7.1 `--script res://Tools/X.gd` where X extends Node
## does not run it -- `_ready` never fires and the process hangs having printed
## only the engine banner, which is indistinguishable from a tool that found
## nothing. A one-node `.tscn` is what gives it a tree.
const TOOLS_DIR := "res://Tools"

## The base classes a script needs a scene for. `SceneTree` is the exception:
## Godot installs it as the main loop, so `--script` runs it correctly.
const NEEDS_A_SCENE := ["Node", "Node2D", "Node3D", "Control", "CanvasLayer"]


func test_every_runnable_tool_has_a_scene() -> void:
	var offenders: Array[String] = []
	for path in _tool_scripts():
		if not _is_runnable(FileAccess.get_file_as_string(path)):
			continue
		var scene := path.replace(".gd", ".tscn")
		if not FileAccess.file_exists(scene):
			offenders.append("%s has no %s" % [path, scene.get_file()])
		elif not FileAccess.get_file_as_string(scene).contains(path):
			offenders.append("%s does not name %s" % [scene, path.get_file()])
	assert_eq(offenders, [] as Array[String],
		"these would hang under --script and have no scene to launch instead:\n  %s"
			% "\n  ".join(offenders))


func test_no_scenetree_tool_has_a_scene() -> void:
	# The other way to launch the wrong thing. A `SceneTree` script in a `.tscn`
	# is not a node and the scene cannot instantiate it.
	var offenders: Array[String] = []
	for path in _tool_scripts():
		if _extends_of(FileAccess.get_file_as_string(path)) != "SceneTree":
			continue
		if FileAccess.file_exists(path.replace(".gd", ".tscn")):
			offenders.append(path)
	assert_eq(offenders, [] as Array[String],
		"a SceneTree script cannot be a scene's node:\n  %s" % "\n  ".join(offenders))


func test_the_guard_fires_on_the_shape_that_hangs() -> void:
	# The negative half. A Node with a `_ready` is a tool; a Node with only
	# static helpers is a library and needs no scene, which is the distinction
	# `Tools/IconsOverlay.gd` sits on.
	assert_true(_is_runnable("extends Node\n\nfunc _ready() -> void:\n\tpass\n"),
		"a Node with _ready is a tool and must be flagged without a scene")
	assert_true(_is_runnable("extends Node2D\n\nfunc _ready() -> void:\n\tpass\n"),
		"the base class is not only Node")
	assert_false(_is_runnable("extends SceneTree\n\nfunc _init() -> void:\n\tpass\n"),
		"a SceneTree script runs under --script and must not be flagged")
	assert_false(_is_runnable("extends Node2D\nclass_name X\n\nfunc _draw() -> void:\n\tpass\n"),
		"a drawing library with no _ready is not a tool")
	assert_false(_is_runnable("extends RefCounted\n\nfunc _ready() -> void:\n\tpass\n"),
		"a RefCounted is never in a tree")


## A script that is meant to be launched: it derives from a node type and has a
## `_ready` for the engine to call.
func _is_runnable(source: String) -> bool:
	if not NEEDS_A_SCENE.has(_extends_of(source)):
		return false
	return source.contains("func _ready(")


func _extends_of(source: String) -> String:
	for line in source.split("\n"):
		var text := line.strip_edges().trim_prefix("﻿")
		if text.begins_with("extends "):
			return text.trim_prefix("extends ").strip_edges()
	return ""


func _tool_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TOOLS_DIR)
	if dir == null:
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("%s/%s" % [TOOLS_DIR, name])
	return out
