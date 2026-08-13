extends "res://Tests/TestCase.gd"

## Every scene in the project loads and its script is attached.
##
## MANAGER-OWNED, and it is the check that stops the most embarrassing failure
## this project can have: a green suite next to a window that shows nothing. The
## test suite never opens a scene unless something makes it, and a .tscn with a
## broken ext_resource path loads as an empty node with no error anyone reads.
##
## It does not prove the screen renders. Nothing automated here does. The
## screenshot in the pull request is what proves that.

const SCENES := [
	"res://Scenes/Main.tscn",
	"res://Scenes/PartySelect.tscn",
	"res://Scenes/Battle.tscn",
]

const EXPECTED_SCRIPT := {
	"res://Scenes/Main.tscn": "res://Scripts/UI/Main.gd",
	"res://Scenes/PartySelect.tscn": "res://Scripts/UI/PartySelect.gd",
	"res://Scenes/Battle.tscn": "res://Scripts/UI/BattleView.gd",
}


func test_every_scene_loads() -> void:
	for path in SCENES:
		var packed := load(path) as PackedScene
		assert_not_null(packed, "%s did not load as a PackedScene" % path)
		if packed != null:
			assert_true(packed.can_instantiate(), "%s cannot be instantiated" % path)


func test_every_scene_root_keeps_its_script() -> void:
	# The failure this catches: an ext_resource path that no longer exists. The
	# scene still loads, the root node still appears, and the behaviour is
	# simply gone. Checking the state rather than the file text means a rename
	# somewhere else fails here rather than at runtime.
	for path in SCENES:
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var state := packed.get_state()
		var found := ""
		for i in state.get_node_property_count(0):
			if state.get_node_property_name(0, i) == &"script":
				var s = state.get_node_property_value(0, i)
				if s != null:
					found = s.resource_path
		assert_eq(found, EXPECTED_SCRIPT[path], "%s root script" % path)


func test_the_main_scene_setting_points_at_a_real_scene() -> void:
	# project.godot naming a scene that does not exist gives a blank window on
	# launch and nothing in the log that says why.
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_ne(main_scene, "", "application/run/main_scene is unset")
	assert_true(SCENES.has(main_scene), "main scene %s is not one of the project's scenes" % main_scene)
	assert_not_null(load(main_scene), "main scene %s does not load" % main_scene)
