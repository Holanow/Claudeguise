extends "res://Tests/TestCase.gd"


## Issue 237. **Does a file the player drops in reach the screen?**
##
## The thirteenth built-and-unreachable thing on this project, and the only one
## whose false promise is written down in a file addressed to the player:
## `Assets/UI/README.md` said dropping in `background.png` themes every screen,
## and `background_node` had zero call sites outside `Tests/` and `Tools/`.
##
## `test_art.gd` already checks that the README's names and the call sites agree,
## and it does it by searching `Scripts/UI/*.gd` for the literal `&"name"`. That
## is the right check for *documentation drift* and it is the wrong one for
## *reachability*: a screen that holds the string and never calls the function
## passes it, which is the exact shape of the defect. sable wrote it and named
## the limit; this is the other half.
##
## So these build each screen through its own `_ready()`, with a real PNG on
## disk, and ask what the screen actually put in its tree.
##
## **The negative case is the load-bearing one.** With no file present every
## screen must still hold a plain `ColorRect` in `Palette.BACKGROUND` -- the
## shipped game is meant to be pixel-identical, and a test that only checks the
## themed case would pass a change that themed every screen bright red by
## default.

const _SCRATCH := "res://Assets/UI/background/%s.png"
var _ELEMENTS := {
	"party_select": PartySelect,
	"deploy": DeployView,
	"floor_map": FloorMapView,
	"level_editor": LevelEditorView,
}

## A file that cannot be mistaken for anything already in the repository, in a
## colour nothing draws, so a stale one left by a crashed run is obvious.
func _write_scratch(element: String) -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 0.0, 1.0, 1.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Assets/UI/background"))
	img.save_png(ProjectSettings.globalize_path(_SCRATCH % element))
	# UIArt memoises every lookup in a static dictionary, so a file written after
	# the first miss is invisible until this is called. Found by writing the file
	# and watching the screen stay flat -- the same silence a player dropping art
	# into a running editor would get.
	UIArt.clear_cache()

func _remove_scratch(element: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_SCRATCH % element))
	UIArt.clear_cache()

## A screen whose tree has moved into a `.tscn` builds through its own
## `create()`; `set_script` on a bare Control gives one of those none of its
## tree, which is a half-built screen that would still pass this test. Read off
## the script rather than listed per screen, so a screen converted later is
## picked up here without anybody remembering to edit this list.
func _screen(script) -> Control:
	for method in script.get_script_method_list():
		if method.name == "create":
			var made: Control = script.create()
			made._ready()
			return made
	var node := Control.new()
	node.set_script(script)
	node._ready()
	return node

## The background is the first child, because it has to draw under everything
## else. Read back rather than assumed: `background_node` is what decides which
## class it is, and the screen is what decides where it goes.
func _background_of(screen: Control) -> Node:
	return screen.get_child(0) if screen.get_child_count() > 0 else null

func test_every_screen_draws_a_plain_background_when_no_file_is_dropped_in() -> void:
	for element in _ELEMENTS:
		assert_false(FileAccess.file_exists(_SCRATCH % element),
			"%s.png is on disk before this test wrote one -- a previous run crashed" % element)
	for element in _ELEMENTS:
		var screen := _screen(_ELEMENTS[element])
		var bg := _background_of(screen)
		assert_true(bg is ColorRect,
			"%s draws a %s with no theme file present, and the shipped game must not change" % [
				element, "nothing" if bg == null else bg.get_class()])
		assert_eq((bg as ColorRect).color, Palette.BACKGROUND,
			"%s's untouched background is no longer Palette.BACKGROUND" % element)
		screen.free()

func test_a_dropped_in_background_reaches_every_screen_it_is_promised_for() -> void:
	for element in _ELEMENTS:
		_write_scratch(element)
		var screen := _screen(_ELEMENTS[element])
		var bg := _background_of(screen)
		var kind := "nothing" if bg == null else bg.get_class()
		_remove_scratch(element)
		assert_true(bg is TextureRect,
			("Assets/UI/background/%s.png was on disk and the screen drew a %s. " +
			"That is the promise Assets/UI/README.md makes to the player.") % [element, kind])
		assert_true((bg as TextureRect).texture != null,
			"%s built a TextureRect with no texture in it" % element)
		screen.free()
	for element in _ELEMENTS:
		assert_false(FileAccess.file_exists(_SCRATCH % element),
			"%s.png survived its own cleanup" % element)

## The general file, which is the one the README leads with -- *"drop in
## background.png and every screen is re-skinned at once"*. Separate from the
## specific names above because it is a different lookup level, and because the
## specific one passing says nothing about it.
func test_the_general_background_file_reaches_every_screen_at_once() -> void:
	var path := "res://Assets/UI/background.png"
	assert_false(FileAccess.file_exists(path), "background.png is on disk before this test wrote one")
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 1.0, 1.0, 1.0))
	img.save_png(ProjectSettings.globalize_path(path))
	UIArt.clear_cache()
	var themed := 0
	for element in _ELEMENTS:
		var screen := _screen(_ELEMENTS[element])
		if _background_of(screen) is TextureRect:
			themed += 1
		screen.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	UIArt.clear_cache()
	assert_eq(themed, _ELEMENTS.size(),
		"one file is meant to re-skin every screen; %d of %d took it" % [themed, _ELEMENTS.size()])

## The arena floor is the fifth call site and the one that is drawn rather than
## built as a node, so it cannot be checked the same way. `draw_background` is
## what `ArenaFloor._draw` now calls, and the thing worth asserting is that it
## resolves the name the README prints -- `background/arena.png` -- rather than
## falling through to the flat colour with the file sitting on disk.
func test_the_arena_floor_asks_for_the_name_the_readme_prints() -> void:
	assert_eq(UIArt.theme_name(&"background", &"arena"), &"",
		"a theme file survived a previous run")
	_write_scratch("arena")
	assert_eq(UIArt.theme_name(&"background", &"arena"), &"background/arena",
		"background/arena.png is on disk and the lookup does not resolve it")
	assert_eq(UIArt.border_art_name(&"arena"), &"",
		"the arena's border and its background must not resolve to each other")
	_remove_scratch("arena")
	assert_eq(UIArt.theme_name(&"background", &"arena"), &"",
		"background/arena.png survived its own cleanup")
