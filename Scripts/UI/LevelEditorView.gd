extends Control

const CG := preload("res://Scripts/Core/CG.gd")
const Palette := preload("res://Scripts/Core/Palette.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const Encounter := preload("res://Scripts/Core/Encounter.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
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

var _canvas = null
var _name_edit: LineEdit = null
var _enemy_picker: OptionButton = null
var _terrain_picker: OptionButton = null
var _enemy_list_box: VBoxContainer = null
var _terrain_list_box: VBoxContainer = null
var _status_label: Label = null
var _editor_ui: Control = null

var _test_battle = null
var _test_cfg: RunConfig = null
var _test_encounter: Encounter = null

func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_top", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_right", int(Palette.SPACE_L))
	margin.add_theme_constant_override("margin_bottom", int(Palette.SPACE_L))
	add_child(margin)

	_editor_ui = VBoxContainer.new()
	_editor_ui.add_theme_constant_override("separation", int(Palette.SPACE_M))
	_editor_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_child(_editor_ui)

	_build_header()
	_build_body()

	_canvas.party_spawns = _default_party_spawns()
	_canvas.enemy_placed.connect(func(_i): _rebuild_enemy_list())
	_canvas.terrain_placed.connect(func(_i): _rebuild_terrain_list())

	_populate_enemy_picker()
	_populate_terrain_picker()

func _build_header() -> void:
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", int(Palette.SPACE_M))
	_editor_ui.add_child(top_row)

	var title := Label.new()
	title.text = "Level editor"
	title.add_theme_font_size_override("font_size", Palette.FONT_SIZE_HEADING)
	title.add_theme_color_override("font_color", Palette.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	back_button.pressed.connect(func(): back_requested.emit())
	top_row.add_child(back_button)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	_editor_ui.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name"
	name_label.add_theme_color_override("font_color", Palette.TEXT)
	name_row.add_child(name_label)

	_name_edit = LineEdit.new()
	_name_edit.text = "New Room"
	_name_edit.custom_minimum_size = Vector2(220.0, Palette.TOUCH_TARGET_MIN)
	name_row.add_child(_name_edit)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status_label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	_status_label.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_editor_ui.add_child(_status_label)

func _build_body() -> void:
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", int(Palette.SPACE_M))
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor_ui.add_child(body)

	_canvas = Control.new()
	_canvas.set_script(LevelEditorCanvasScript)
	_canvas.custom_minimum_size = Vector2(400.0, 260.0)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_canvas)
	if not _canvas.is_inside_tree():
		_canvas._ready()

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(280.0, 0.0)
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(side_scroll)

	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", int(Palette.SPACE_S))
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)

	side.add_child(_header_label("Enemies"))
	_enemy_picker = OptionButton.new()
	_enemy_picker.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	side.add_child(_enemy_picker)
	_enemy_list_box = VBoxContainer.new()
	_enemy_list_box.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	side.add_child(_enemy_list_box)

	side.add_child(_header_label("Terrain"))
	_terrain_picker = OptionButton.new()
	_terrain_picker.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	side.add_child(_terrain_picker)
	_terrain_list_box = VBoxContainer.new()
	_terrain_list_box.add_theme_constant_override("separation", int(Palette.SPACE_XS))
	side.add_child(_terrain_list_box)

	var test_button := Button.new()
	test_button.text = "Test room"
	test_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	test_button.pressed.connect(_start_test_fight)
	side.add_child(test_button)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_TARGET_MIN)
	save_button.pressed.connect(_on_save_pressed)
	side.add_child(save_button)

func _header_label(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", Palette.TEXT)
	return label

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
		_enemy_picker.add_item("(no enemies registered)")
		_enemy_picker.disabled = true
		return
	for id in ids:
		var enemy := Registry.get_enemy(id)
		_enemy_picker.add_item(enemy.display_name if enemy != null else String(id))
	_enemy_picker.item_selected.connect(func(idx): _set_current_enemy(ids[idx]))
	_set_current_enemy(ids[0])

func _set_current_enemy(id: StringName) -> void:
	_canvas.current_enemy_id = id
	var enemy := Registry.get_enemy(id)
	_canvas.current_enemy_radius = enemy.radius if enemy != null else 22.0
	_canvas.mode = LevelEditorCanvasScript.Mode.PLACE_ENEMY
	_set_status("Click the arena to place a %s." % (enemy.display_name if enemy != null else String(id)), false)

func _populate_terrain_picker() -> void:
	for k in _TERRAIN_KINDS:
		_terrain_picker.add_item(String(Terrain.Kind.keys()[k]).capitalize())
	_terrain_picker.item_selected.connect(func(idx): _set_current_terrain_kind(_TERRAIN_KINDS[idx]))
	_set_current_terrain_kind(_TERRAIN_KINDS[0])

func _set_current_terrain_kind(kind) -> void:
	_canvas.current_terrain_kind = kind
	_canvas.mode = LevelEditorCanvasScript.Mode.PLACE_TERRAIN
	_set_status("Drag a rectangle to place a %s." % String(Terrain.Kind.keys()[kind]).capitalize(), false)

func _set_status(text: String, is_error: bool) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", Palette.HP_LOW if is_error else Palette.TEXT_DIM)

# ---------------------------------------------------------------------------
# Placed-item lists
# ---------------------------------------------------------------------------

func _rebuild_enemy_list() -> void:
	for child in _enemy_list_box.get_children():
		child.free()
	for i in _canvas.enemy_spawns.size():
		var spawn = _canvas.enemy_spawns[i]
		var pos: Vector2 = spawn.position
		var enemy := Registry.get_enemy(spawn.enemy_id)
		var name := enemy.display_name if enemy != null else String(spawn.enemy_id)
		_enemy_list_box.add_child(_removable_row(
			"%s at (%d, %d)" % [name, int(pos.x), int(pos.y)], _on_remove_enemy.bind(i)))

func _on_remove_enemy(index: int) -> void:
	_canvas.remove_enemy(index)
	_rebuild_enemy_list()

func _rebuild_terrain_list() -> void:
	for child in _terrain_list_box.get_children():
		child.free()
	for i in _canvas.terrain.size():
		var f = _canvas.terrain[i]
		var kind_name := String(Terrain.Kind.keys()[f.kind]).capitalize()
		_terrain_list_box.add_child(_removable_row(
			"%s (%d,%d %dx%d)" % [kind_name, int(f.rect.position.x), int(f.rect.position.y), int(f.rect.size.x), int(f.rect.size.y)],
			_on_remove_terrain.bind(i)))

func _on_remove_terrain(index: int) -> void:
	_canvas.remove_terrain(index)
	_rebuild_terrain_list()

func _removable_row(text: String, on_remove: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Palette.SPACE_S))
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", Palette.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Palette.TEXT)
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
	e.enemy_spawns = _canvas.enemy_spawns
	e.party_spawns = _canvas.party_spawns
	e.terrain = _canvas.terrain
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
	if _canvas.enemy_spawns.is_empty():
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
	_editor_ui.visible = false

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
	_editor_ui.visible = true

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _on_save_pressed() -> void:
	if _canvas.enemy_spawns.is_empty():
		_set_status("Add at least one enemy before saving.", true)
		return
	if _canvas.has_blocked_enemy():
		_set_status("Cannot save: an enemy is standing inside a wall or pit.", true)
		return
	var display_name := _name_edit.text.strip_edges()
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
	for spawn in _canvas.enemy_spawns:
		var pos: Vector2 = spawn.position
		enemies.append({"enemy_id": String(spawn.enemy_id), "x": pos.x, "y": pos.y})
	var spawns := []
	for p in _canvas.party_spawns:
		spawns.append({"x": p.x, "y": p.y})
	var terrain_out := []
	for f in _canvas.terrain:
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
