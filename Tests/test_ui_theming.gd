extends "res://Tests/TestCase.gd"


## Issue 237. **Does a file the player drops in reach the screen?**
##
## The thirteenth built-and-unreachable thing on this project, and the only one
## whose false promise is written down in a file addressed to the player:

const _SCRATCH := "res://Assets/UI/background/%s.png"
const _GENERAL := "res://Assets/UI/background.png"

## The screen, and the flat colour it falls back to with no file present. The
## fallback used to be `Palette.BACKGROUND` for every screen and was asserted as
## a constant; issue 807 made these two screens pages of the ledger, so the
## expectation is per screen and comes from the screen's own call.
var _ELEMENTS := {
	"party_select": [PartySelect, Palette.PAPER_LEAF],
	"floor_map": [FloorMapView, Palette.PAPER_LEAF],
}

## Issue 807 ships real theme files, and every test below writes over one of
## their names. `_remove_scratch` deleted them outright and the suite silently
## destroyed committed art the first time both existed together, so a shipped
## file is moved aside and put back rather than removed.
static var _stashed: Dictionary = {}

static func _stash(path: String) -> void:
	var real := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(real):
		return
	_stashed[path] = FileAccess.get_file_as_bytes(real)

static func _restore(path: String) -> void:
	if not _stashed.has(path):
		return
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	f.store_buffer(_stashed[path])
	f.close()
	_stashed.erase(path)

## A file that cannot be mistaken for anything already in the repository, in a
## colour nothing draws, so a stale one left by a crashed run is obvious.
func _write_scratch(element: String) -> void:
	_stash(_SCRATCH % element)
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
	_restore(_SCRATCH % element)
	UIArt.clear_cache()

## A screen whose tree lives in a `.tscn` cannot be built by setting the script
## on a bare Control -- it gets none of the tree and `_ready()` fails on the
## first `%Name`. Those screens expose `create()`; the ones still built
## imperatively do not, and take the old path unchanged.
func _screen(script) -> Control:
	var node: Control
	if script.has_method("create"):
		node = script.create()
	else:
		node = Control.new()
		node.set_script(script)
	node._ready()
	return node

## The background is the first child, because it has to draw under everything
## else. Read back rather than assumed: `background_node` is what decides which
## class it is, and the screen is what decides where it goes.
func _background_of(screen: Control) -> Node:
	return screen.get_child(0) if screen.get_child_count() > 0 else null

func test_every_screen_draws_a_plain_background_when_no_file_is_dropped_in() -> void:
	## The general file ships since issue 807, so "no file dropped in" has to be
	## made true rather than assumed: it is moved aside and put straight back.
	_stash(_GENERAL)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_GENERAL))
	UIArt.clear_cache()
	for element in _ELEMENTS:
		var screen := _screen(_ELEMENTS[element][0])
		var bg := _background_of(screen)
		assert_true(bg is ColorRect,
			"%s draws a %s with no theme file present, and the shipped game must not change" % [
				element, "nothing" if bg == null else bg.get_class()])
		assert_eq((bg as ColorRect).color, _ELEMENTS[element][1],
			"%s's untouched background is no longer the colour its own call names" % element)
		screen.free()
	_restore(_GENERAL)
	UIArt.clear_cache()

func test_a_dropped_in_background_reaches_every_screen_it_is_promised_for() -> void:
	for element in _ELEMENTS:
		_write_scratch(element)
		var screen := _screen(_ELEMENTS[element][0])
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
	_stash(_GENERAL)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 1.0, 1.0, 1.0))
	img.save_png(ProjectSettings.globalize_path(_GENERAL))
	UIArt.clear_cache()
	var themed := 0
	for element in _ELEMENTS:
		var screen := _screen(_ELEMENTS[element][0])
		if _background_of(screen) is TextureRect:
			themed += 1
		screen.free()
	_restore(_GENERAL)
	UIArt.clear_cache()
	assert_eq(themed, _ELEMENTS.size(),
		"one file is meant to re-skin every screen; %d of %d took it" % [themed, _ELEMENTS.size()])

## The arena floor is the fifth call site and the one that is drawn rather than
## built as a node, so it cannot be checked the same way. `draw_background` is
## what `ArenaFloor._draw` now calls, and the thing worth asserting is that it
## resolves the name the README prints -- `background/arena.png` -- rather than
## falling through to the flat colour with the file sitting on disk.
func test_the_arena_floor_asks_for_the_name_the_readme_prints() -> void:
	_write_scratch("arena")
	assert_eq(UIArt.theme_name(&"background", &"arena"), &"background/arena",
		"background/arena.png is on disk and the lookup does not resolve it")
	## The two lookups must not collapse into each other. Both files ship since
	## issue 807, so the check is that they resolve to DIFFERENT names rather
	## than that the border resolves to nothing.
	assert_ne(UIArt.border_art_name(&"arena"), UIArt.theme_name(&"background", &"arena"),
		"the arena's border and its background must not resolve to each other")
	_remove_scratch("arena")
	assert_eq(UIArt.theme_name(&"background", &"arena"), &"background/arena",
		"the shipped background/arena.png did not come back after the scratch was removed")
