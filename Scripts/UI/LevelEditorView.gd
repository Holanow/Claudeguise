extends Control
class_name LevelEditorView

const LevelEditorCanvasScript := preload("res://Scripts/UI/LevelEditorCanvas.gd")

## Issue 19: author a room the generator can draw from, without leaving the
## editor to find out whether it plays well.
##
## OWNER: kite.
##
## Rooms are hand-written GDScript today, `Registry.all_encounter_ids()`
## names five of them, and that is the whole pool the floor generator picks
## a fight from. This is not a convenience tool on top of that — it is the
## thing that makes "procedural" mean something, per the issue's own framing.
##
## Save format agreed with dace on the board before this was built against
## it (see TEAM_LOG.md, kite's block): `res://Assets/Rooms/<id>.json`, one
## `Encounter` per file, enum fields written as their string name so the
## file survives either enum being reordered. `_encounter_dict` below is
## that exact shape. **What Save does not yet do: reach the generator.**
## `Registry` has no loader for these files — that half is dace's
## (`Scripts/Content/**`, not touched here) and has not landed. The file
## this screen writes is real and sits in the agreed place; nothing reads it
## back yet. Said plainly rather than claimed, because a save button that
## looks finished and is not reachable from anywhere else is exactly the
## "worked and did not meet" failure the retrospective is about.
##
## Testing needs none of that: `_start_test_fight` builds an in-memory
## `Encounter` straight from the canvas and hands it to a real `BattleView`
## via `begin_with_encounter` (added to that file for this issue), so a room
## is playable the instant it is placed, saved or not.

signal back_requested

const ROOMS_DIR := "res://Assets/Rooms"
const MAX_TEST_PARTY := 4

const _TERRAIN_KINDS: Array = [
	Terrain.Kind.WALL, Terrain.Kind.PILLAR, Terrain.Kind.HAZARD, Terrain.Kind.PIT,
]

var _test_battle = null
var _test_cfg: RunConfig = null
var _test_encounter: Encounter = null

## `new()` gives a bare Control with none of the tree. The whole editor chrome --
## header, name field, canvas slot and the side panel's pickers and buttons -- is
## in `Scenes/LevelEditor.tscn`; only the placed-item rows are built here.
static func create() -> LevelEditorView:
	return (load("res://Scenes/LevelEditor.tscn") as PackedScene).instantiate()

func _ready() -> void:
	theme = AppTheme.shared()
	# Issue 237. One line instead of three, and the point is not the two lines:
	# `Assets/UI/README.md` promises the player that dropping in
	# `background/level_editor.png` (or `background.png` for every screen at once)
	# re-skins this screen, and until this call existed it did nothing at all.
	# With no file present `background_node` returns exactly the ColorRect this
	# replaced, in exactly this colour, so nothing shipped changes.
	#
	# Moved to index 0 rather than appended: it has to draw under the scene's own
	# chrome, and `add_child` puts it last.
	var background := UIArt.background_node(&"level_editor", Palette.BACKGROUND)
	add_child(background)
	move_child(background, 0)

	%BackButton.pressed.connect(func(): back_requested.emit())
	%TestButton.pressed.connect(_start_test_fight)
	%SaveButton.pressed.connect(_on_save_pressed)

	# The canvas is a bare Control in the scene and takes its script here: it is
	# the one child whose behaviour the scene cannot carry, and `_ready()` has to
	# be called by hand because this screen is often built outside a live tree.
	%Canvas.set_script(LevelEditorCanvasScript)
	%Canvas._ready()
	%Canvas.party_spawns = _default_party_spawns()
	%Canvas.enemy_placed.connect(func(_i): _rebuild_enemy_list())
	%Canvas.terrain_placed.connect(func(_i): _rebuild_terrain_list())

	_populate_enemy_picker()
	_populate_terrain_picker()

# ---------------------------------------------------------------------------
# Bestiary and terrain pickers
# ---------------------------------------------------------------------------

## Registry has no `all_enemy_ids()` (only `all_class_ids`/`all_encounter_ids`/
## `all_equipment_ids`) — proposed to dace on the board as the clean fix.
## Until it lands, this derives the bestiary from every enemy id already used
## by a registered encounter, which is every enemy that exists today (five
## enemies, five encounters between them, checked directly against
## `floor1_enemies.gd`). The gap: an enemy Registry knows about but no
## encounter has ever spawned would not appear here. Documented rather than
## silently accepted.
func _bestiary_ids() -> Array[StringName]:
	var seen := {}
	for encounter_id in Registry.all_encounter_ids():
		var enc := Registry.get_encounter(encounter_id)
		if enc == null:
			continue
		for spawn in enc.enemy_spawns:
			var id: StringName = spawn.get("enemy_id", &"")
			if id != &"":
				seen[id] = true
	var out: Array[StringName] = []
	for k in seen.keys():
		out.append(k)
	out.sort()
	return out

func _populate_enemy_picker() -> void:
	var ids := _bestiary_ids()
	if ids.is_empty():
		%EnemyPicker.add_item("(no enemies registered)")
		%EnemyPicker.disabled = true
		return
	for id in ids:
		var enemy := Registry.get_enemy(id)
		%EnemyPicker.add_item(enemy.display_name if enemy != null else String(id))
	%EnemyPicker.item_selected.connect(func(idx): _set_current_enemy(ids[idx]))
	_set_current_enemy(ids[0])

func _set_current_enemy(id: StringName) -> void:
	%Canvas.current_enemy_id = id
	var enemy := Registry.get_enemy(id)
	%Canvas.current_enemy_radius = enemy.radius if enemy != null else 22.0
	%Canvas.mode = LevelEditorCanvasScript.Mode.PLACE_ENEMY
	_set_status("Click the arena to place a %s." % (enemy.display_name if enemy != null else String(id)), false)

func _populate_terrain_picker() -> void:
	for k in _TERRAIN_KINDS:
		%TerrainPicker.add_item(String(Terrain.Kind.keys()[k]).capitalize())
	%TerrainPicker.item_selected.connect(func(idx): _set_current_terrain_kind(_TERRAIN_KINDS[idx]))
	_set_current_terrain_kind(_TERRAIN_KINDS[0])

func _set_current_terrain_kind(kind) -> void:
	%Canvas.current_terrain_kind = kind
	%Canvas.mode = LevelEditorCanvasScript.Mode.PLACE_TERRAIN
	_set_status("Drag a rectangle to place a %s." % String(Terrain.Kind.keys()[kind]).capitalize(), false)

func _set_status(text: String, is_error: bool) -> void:
	%StatusLabel.text = text
	%StatusLabel.add_theme_color_override("font_color", Palette.HP_LOW if is_error else Palette.TEXT_DIM)

# ---------------------------------------------------------------------------
# Placed-item lists
# ---------------------------------------------------------------------------

func _rebuild_enemy_list() -> void:
	for child in %EnemyListBox.get_children():
		child.free()
	for i in %Canvas.enemy_spawns.size():
		var spawn = %Canvas.enemy_spawns[i]
		var pos: Vector2 = spawn.position
		var enemy := Registry.get_enemy(spawn.enemy_id)
		var name := enemy.display_name if enemy != null else String(spawn.enemy_id)
		%EnemyListBox.add_child(_removable_row(
			"%s at (%d, %d)" % [name, int(pos.x), int(pos.y)], _on_remove_enemy.bind(i)))

func _on_remove_enemy(index: int) -> void:
	%Canvas.remove_enemy(index)
	_rebuild_enemy_list()

func _rebuild_terrain_list() -> void:
	for child in %TerrainListBox.get_children():
		child.free()
	for i in %Canvas.terrain.size():
		var f = %Canvas.terrain[i]
		var kind_name := String(Terrain.Kind.keys()[f.kind]).capitalize()
		%TerrainListBox.add_child(_removable_row(
			"%s (%d,%d %dx%d)" % [kind_name, int(f.rect.position.x), int(f.rect.position.y), int(f.rect.size.x), int(f.rect.size.y)],
			_on_remove_terrain.bind(i)))

func _on_remove_terrain(index: int) -> void:
	%Canvas.remove_terrain(index)
	_rebuild_terrain_list()

func _removable_row(text: String, on_remove: Callable) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var remove_button := Button.new()
	remove_button.text = "Remove"
	remove_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	remove_button.pressed.connect(on_remove)
	row.add_child(remove_button)
	return row

# ---------------------------------------------------------------------------
# Deploy zone / test party
# ---------------------------------------------------------------------------

## Inside `CG.party_deploy_max_x()` by a margin, in the same four-slot column
## shape `floor1_encounters.gd`'s own `_PARTY_SPAWNS` uses. Always written —
## an authored room with an empty `party_spawns` falls back to
## `CombatSim`'s centre-of-arena default, silently outside the zone this
## screen exists to show respected.
func _default_party_spawns() -> Array[Vector2]:
	var x := CG.party_deploy_max_x() - 40.0
	return [Vector2(x, -195.0), Vector2(x, -65.0), Vector2(x, 65.0), Vector2(x, 195.0)]

## One of each real class, up to the party size cap — a representative party
## for testing a room's shape, not a choice the player makes here (that is
## PartySelect's job for a real run). Same technique PartySelect's own roster
## and `Tools/PlaytestRun.gd`'s BALANCED_PARTY already use.
func _test_party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	var ids := Registry.all_class_ids()
	for i in mini(ids.size(), MAX_TEST_PARTY):
		var cls_id: StringName = ids[i]
		var cls := Registry.get_class_def(cls_id)
		if cls == null:
			continue
		out.append(PawnFactory.make_starter_pawn(cls_id, cls_id, cls.display_name))
	return out

func _build_encounter(id: StringName, display_name: String) -> Encounter:
	var e := Encounter.new()
	e.id = id
	e.display_name = display_name
	e.enemy_spawns = %Canvas.enemy_spawns
	e.party_spawns = %Canvas.party_spawns
	e.terrain = %Canvas.terrain
	return e

# ---------------------------------------------------------------------------
# Test fight — the feature rook named as the one that matters most
# ---------------------------------------------------------------------------

## Builds a real `Encounter` from whatever is on the canvas right now and
## fights it through a real `BattleView`, added as a child of this screen
## rather than routed through `Main` — the player never leaves the editor,
## which is the whole point per the issue: "is this room any good" is not
## answerable by looking at it.
func _start_test_fight() -> void:
	if _test_battle != null:
		return
	if %Canvas.enemy_spawns.is_empty():
		_set_status("Add at least one enemy before testing.", true)
		return
	_test_encounter = _build_encounter(&"level_editor_test", "Test Room")
	_test_cfg = RunConfig.new()
	_test_cfg.party = _test_party()
	_test_cfg.seed = randi()

	var packed: PackedScene = load("res://Scenes/Battle.tscn")
	_test_battle = packed.instantiate()
	add_child(_test_battle)
	# Same guard InspectPanel/PartyCard already use: add_child alone only
	# calls _ready() once the parent is inside a live SceneTree.
	if not _test_battle.is_inside_tree():
		_test_battle._ready()
	_test_battle.back_requested.connect(_end_test_fight)
	_test_battle.restart_requested.connect(func(): _test_battle.begin_with_encounter(_test_cfg, _test_encounter))
	_test_battle.begin_with_encounter(_test_cfg, _test_encounter)
	%EditorUI.visible = false

## `BattleView`'s own back button reads "Change party" — accurate on the real
## battle screen, not quite here (there is no party to change, this returns
## to editing). Left as-is rather than parameterising a label on a file two
## screens share for one word of copy; noted rather than silently shipped.
func _end_test_fight() -> void:
	if _test_battle == null:
		return
	remove_child(_test_battle)
	_test_battle.queue_free()
	_test_battle = null
	%EditorUI.visible = true

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	if %Canvas.enemy_spawns.is_empty():
		_set_status("Add at least one enemy before saving.", true)
		return
	if %Canvas.has_blocked_enemy():
		_set_status("Cannot save: an enemy is standing inside a wall or pit.", true)
		return
	var display_name: String = %NameEdit.text.strip_edges()
	if display_name.is_empty():
		display_name = "New Room"
	var id := "authored_%s" % display_name.to_snake_case()
	var dict := _encounter_dict(id, display_name)

	var dir_err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOMS_DIR))
	if dir_err != OK and dir_err != ERR_ALREADY_EXISTS:
		_set_status("Save failed: could not create %s (%s)." % [ROOMS_DIR, error_string(dir_err)], true)
		return
	var path := "%s/%s.json" % [ROOMS_DIR, id]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Save failed: could not open %s (%s)." % [path, error_string(FileAccess.get_open_error())], true)
		return
	file.store_string(JSON.stringify(dict, "\t"))
	file.close()
	_set_status(
		"Saved %s. The generator cannot use it yet — Registry has no loader for authored rooms until dace's half of issue 19 lands." % path,
		false)

## The format posted to TEAM_LOG.md and agreed with dace before this screen
## was built against it. Pure and side-effect free on purpose: a test can
## check the exact shape without touching a file.
func _encounter_dict(id: String, display_name: String) -> Dictionary:
	var enemies := []
	for spawn in %Canvas.enemy_spawns:
		var pos: Vector2 = spawn.position
		enemies.append({"enemy_id": String(spawn.enemy_id), "x": pos.x, "y": pos.y})
	var spawns := []
	for p in %Canvas.party_spawns:
		spawns.append({"x": p.x, "y": p.y})
	var terrain_out := []
	for f in %Canvas.terrain:
		terrain_out.append({
			"kind": Terrain.Kind.keys()[f.kind],
			"x": f.rect.position.x,
			"y": f.rect.position.y,
			"w": f.rect.size.x,
			"h": f.rect.size.y,
			"damage_per_tick": f.damage_per_tick,
			"damage_type": CG.DamageType.keys()[f.damage_type],
		})
	return {
		"id": id,
		"display_name": display_name,
		"enemy_spawns": enemies,
		"party_spawns": spawns,
		"terrain": terrain_out,
	}
