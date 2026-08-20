extends Control
class_name LevelEditorCanvas

const ArenaFloorScript := preload("res://Scripts/UI/ArenaFloor.gd")
const OverlayScript := preload("res://Scripts/UI/LevelEditorOverlay.gd")

## The placement surface for the level editor (issue 19). Draws the same
## arena a real fight draws — `ArenaFloor` is reused as a child rather than
## redrawn, so "place it here" means the same thing on this screen as it does
## in `BattleView`: same grid, same boundary, same terrain rendering — plus
## (via `LevelEditorOverlay`, a child of that same node) the party deploy
## zone and every enemy placed so far.

signal enemy_placed(index: int)
signal terrain_placed(index: int)
signal party_spawn_moved(index: int)

## Issue 145: `MOVE_PARTY` is the pre-fight deploy screen's mode. The player has
## asked three times to place their party before a fight, and everything it
## needs was already here -- this canvas draws the same arena a real fight
## draws, the same terrain, and the deploy zone -- so the mode is the whole
## addition rather than a second placement surface that could disagree with
## this one about where a thing is.
enum Mode { PLACE_ENEMY, PLACE_TERRAIN, MOVE_PARTY }

## World-space margin around the arena bounds so the boundary line is not
## drawn flush against the canvas edge.
const _MARGIN := 24.0
const _DEFAULT_HAZARD_DAMAGE := 6
const _DEFAULT_HAZARD_DAMAGE_TYPE := CG.DamageType.FIRE
const _MIN_DRAG_WORLD_SIZE := 4.0

var mode: Mode = Mode.PLACE_ENEMY
var current_enemy_id: StringName = &""
var current_enemy_radius: float = 22.0
var current_terrain_kind: Terrain.Kind = Terrain.Kind.WALL

## One entry per placed enemy: {"enemy_id": StringName, "position": Vector2,
## "radius": float}. `radius` is carried here (not re-fetched from Registry
## every redraw) purely so this screen can validate placement with
## `Terrain.point_is_blocked`, which takes a radius, without a second content
## lookup per frame.
var enemy_spawns: Array[Dictionary] = []

## `Terrain.Feature`, same untyped-Array contract as `Encounter.terrain` and
## `CombatState.terrain`.
var terrain: Array = []

## Always populated by the owning screen at construction time — an authored
## room with none would fall back to `CombatSim`'s own centre-of-arena
## default, silently outside the deploy zone this canvas exists to show.
var party_spawns: Array[Vector2] = []

## Issue 145. Empty on the level editor, one name per spawn on the deploy
## screen. **The names are the point of that screen, not decoration**: only one
## class can redirect an enemy and the Warden kills strictly nearest-first, so
## who stands closest decides a great deal, and until now list order decided it
## invisibly. A row of identical dots would place a party without answering the
## only question worth asking.
var party_labels: Array[String] = []

## Radius the party markers draw and grab at. The editor's 6.0 is a map pin;
## the deploy screen passes the real unit radius so spacing on screen is the
## spacing the fight will use.
var party_radius: float = 6.0

var _floor: Node2D = null
var _held_party_index := -1
var _overlay: Node2D = null
var _dragging := false
var _drag_start_world: Vector2 = Vector2.ZERO
var _drag_current_world: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_floor = Node2D.new()
	_floor.set_script(ArenaFloorScript)
	add_child(_floor)
	# A child of _floor, not a sibling — see LevelEditorOverlay's own header
	# comment for why draw order makes this the one that matters.
	_overlay = Node2D.new()
	_overlay.set_script(OverlayScript)
	_overlay.canvas = self
	_floor.add_child(_overlay)
	_relayout()
	if is_inside_tree():
		resized.connect(_relayout)

func _relayout() -> void:
	if _floor == null:
		return
	var layout := compute_layout(size)
	_floor.position = layout.position
	_floor.scale = layout.scale
	_floor.terrain = terrain
	_redraw_all()

func _redraw_all() -> void:
	if _floor != null:
		_floor.queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()

## Split out from `_relayout` for the same reason `BattleView.compute_layout`
static func compute_layout(canvas_size: Vector2) -> Dictionary:
	var fit_half_width := CG.ARENA_HALF_WIDTH + _MARGIN
	var fit_half_height := CG.ARENA_HALF_HEIGHT + _MARGIN
	var fit_width := fit_half_width * 2.0
	var fit_height := fit_half_height * 2.0
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0 or fit_width <= 0.0 or fit_height <= 0.0:
		return {"position": Vector2.ZERO, "scale": Vector2.ONE}
	var scale_factor: float = minf(canvas_size.x / fit_width, canvas_size.y / fit_height)
	var box := Vector2(fit_width, fit_height) * scale_factor
	var offset := (canvas_size - box) * 0.5
	return {
		"position": offset + Vector2(fit_half_width, fit_half_height) * scale_factor,
		"scale": Vector2(scale_factor, scale_factor),
	}

func world_to_local(world: Vector2) -> Vector2:
	return _floor.position + world * _floor.scale.x

func local_to_world(local: Vector2) -> Vector2:
	return (local - _floor.position) / _floor.scale.x

## Public so a test (or the side panel, which knows an id but not a click
## position on its own) can place one without going through `_gui_input`.
func place_enemy(enemy_id: StringName, world_pos: Vector2, radius: float) -> int:
	enemy_spawns.append({"enemy_id": enemy_id, "position": world_pos, "radius": radius})
	if _overlay != null:
		_overlay.queue_redraw()
	var index := enemy_spawns.size() - 1
	enemy_placed.emit(index)
	return index

func remove_enemy(index: int) -> void:
	if index < 0 or index >= enemy_spawns.size():
		return
	enemy_spawns.remove_at(index)
	if _overlay != null:
		_overlay.queue_redraw()

func place_terrain(kind: Terrain.Kind, rect: Rect2) -> int:
	var feature := Terrain.make(kind, rect)
	if kind == Terrain.Kind.HAZARD:
		feature.damage_per_tick = _DEFAULT_HAZARD_DAMAGE
		feature.damage_type = _DEFAULT_HAZARD_DAMAGE_TYPE
	terrain.append(feature)
	if _floor != null:
		_floor.terrain = terrain
	_redraw_all()
	var index := terrain.size() - 1
	terrain_placed.emit(index)
	return index

func remove_terrain(index: int) -> void:
	if index < 0 or index >= terrain.size():
		return
	terrain.remove_at(index)
	if _floor != null:
		_floor.terrain = terrain
	_redraw_all()

## Acceptance criterion 4: a room must not be saveable with an enemy standing
## inside blocking terrain. Reuses `Terrain.point_is_blocked` directly rather
## than re-deriving "is this point inside a wall or pit" — the exact function
## the real simulation's movement code answers the same question with, so
## this screen and a real fight can never disagree about what counts as
## blocked.
func has_blocked_enemy() -> bool:
	for spawn in enemy_spawns:
		if Terrain.point_is_blocked(terrain, spawn.position, spawn.radius):
			return true
	return false

# ---------------------------------------------------------------------------
# Issue 145: moving a party spawn.

## The rightmost x a party member may hold, accounting for its own radius so a
## marker cannot straddle the line it is constrained by. Static and derived from
## `CG` rather than typed, so it cannot drift from the zone the overlay draws or
## from the rule encounter authors follow.
static func clamp_to_deploy_zone(world: Vector2, radius: float) -> Vector2:
	var min_x := -CG.ARENA_HALF_WIDTH + radius
	var max_x := CG.party_deploy_max_x() - radius
	# A radius wider than the zone would invert the range; pin to the zone's
	# right edge rather than returning something outside it.
	if max_x < min_x:
		return Vector2(CG.party_deploy_max_x(), clampf(world.y, -CG.ARENA_HALF_HEIGHT + radius, CG.ARENA_HALF_HEIGHT - radius))
	return Vector2(
		clampf(world.x, min_x, max_x),
		clampf(world.y, -CG.ARENA_HALF_HEIGHT + radius, CG.ARENA_HALF_HEIGHT - radius))

## Index of the party spawn under `world`, or -1. Nearest wins, so overlapping
## markers still resolve to one.
func party_spawn_at(world: Vector2) -> int:
	var best := -1
	var best_distance := party_radius
	for i in party_spawns.size():
		var d := party_spawns[i].distance_to(world)
		if d <= best_distance:
			best_distance = d
			best = i
	return best

func grab_party_spawn(world: Vector2) -> int:
	_held_party_index = party_spawn_at(world)
	return _held_party_index

## Moves the held spawn, clamped into the deploy zone. **Refuses a position
## inside blocking terrain** using `Terrain.point_is_blocked` -- the same
## function the simulation's own movement answers that question with, so this
## screen and a real fight can never disagree about what counts as blocked. A
## refused move keeps the last good position rather than snapping somewhere the
## player did not ask for.
func move_held_party_spawn(world: Vector2) -> bool:
	if _held_party_index < 0 or _held_party_index >= party_spawns.size():
		return false
	var target := clamp_to_deploy_zone(world, party_radius)
	if Terrain.point_is_blocked(terrain, target, party_radius):
		return false
	party_spawns[_held_party_index] = target
	if _overlay != null:
		_overlay.queue_redraw()
	party_spawn_moved.emit(_held_party_index)
	return true

func release_party_spawn() -> void:
	_held_party_index = -1

func held_party_spawn() -> int:
	return _held_party_index

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start_world = local_to_world(event.position)
			_drag_current_world = _drag_start_world
			if mode == Mode.MOVE_PARTY:
				grab_party_spawn(_drag_start_world)
				if _overlay != null:
					_overlay.queue_redraw()
		else:
			if _dragging:
				_finish_drag(local_to_world(event.position))
			_dragging = false
			if mode == Mode.MOVE_PARTY:
				release_party_spawn()
			if _overlay != null:
				_overlay.queue_redraw()
	elif event is InputEventMouseMotion and _dragging:
		_drag_current_world = local_to_world(event.position)
		if mode == Mode.MOVE_PARTY:
			move_held_party_spawn(_drag_current_world)
		if _overlay != null:
			_overlay.queue_redraw()

func _finish_drag(end_world: Vector2) -> void:
	match mode:
		Mode.PLACE_ENEMY:
			if current_enemy_id != &"":
				place_enemy(current_enemy_id, _drag_start_world, current_enemy_radius)
		Mode.PLACE_TERRAIN:
			var rect := _rect_from_corners(_drag_start_world, end_world)
			if rect.size.x >= _MIN_DRAG_WORLD_SIZE and rect.size.y >= _MIN_DRAG_WORLD_SIZE:
				place_terrain(current_terrain_kind, rect)
		Mode.MOVE_PARTY:
			# A click with no motion between press and release still places the
			# held pawn where the pointer ended. Without this a real drag whose
			# motion events were coalesced would grab and drop with no effect,
			# which reads as the screen ignoring the player.
			move_held_party_spawn(end_world)

static func _rect_from_corners(a: Vector2, b: Vector2) -> Rect2:
	var pos := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var extent := Vector2(absf(a.x - b.x), absf(a.y - b.y))
	return Rect2(pos, extent)
