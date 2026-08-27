extends Node

## Issue 671: a staged fight, filmed. Not a real match watched in the hope that
## the interesting thing happens -- a composition, a pair of spawn lines, a seed
## and a tick range, so the same three seconds come out the same every run.
##
## Record with `Tools/run.ps1 StagedFight -WriteMovie <path.avi> -FixedFps 60`.
## Godot's movie writer records EVERY rendered frame from process start, so the
## clip opens on a few engine start-up frames; this prints the frame index the
## requested tick begins at, and ffmpeg trims to it.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

## A 60Hz display against a 15Hz simulation, the ratio `InterpShot` measures.
@export var frames_per_tick: int = 4

@export var party: Array[StringName] = [&"warrior", &"priest"]
@export var party_at: Array[Vector2] = []
## One entry per enemy: `{"enemy_id": &"goblin", "position": Vector2(120, -40)}`.
@export var enemies: Array[Dictionary] = [
	{"enemy_id": &"goblin", "position": Vector2(160.0, -60.0)},
	{"enemy_id": &"goblin", "position": Vector2(160.0, 60.0)},
]
## Terrain and nothing else is taken from this room; spawns are the fields above.
@export var room: StringName = &""
@export var fight_seed: int = 0x2A
@export var from_tick: int = 0
@export var to_tick: int = 120
@export var label: String = "staged"
## Prints the drawn state of every body each frame, for telling a view-side
## difference between two takes from a simulation-side one.
@export var trace: bool = false

var _view: Node2D = null
var _frames := 0
var _capture_started_at := -1
var _done := false

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("StagedFight: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	_read_args()
	if not _build():
		get_tree().quit(2)
		return
	## Fast-forward without yielding, so no frame is rendered for a skipped tick.
	while _view.state.tick < from_tick and _view.state.outcome == CombatState.Outcome.UNRESOLVED:
		_step()
	print("StagedFight: %s, seed %d, from tick %d to %d, %d frames per tick" % [
		label, fight_seed, from_tick, to_tick, frames_per_tick])
	print("StagedFight: party %s vs %s" % [_ids(party), _enemy_ids()])

func _process(_delta: float) -> void:
	if _done or _view == null:
		return
	if _capture_started_at < 0:
		_capture_started_at = _frames
		print("StagedFight: capture begins at rendered frame %d, tick %d" % [
			_capture_started_at, _view.state.tick])
	_frames += 1
	_step()
	if trace:
		_trace()
	if _view.state.tick >= to_tick or _view.state.outcome != CombatState.Outcome.UNRESOLVED:
		_finish()

## The view's own clock, driven by hand: its `_process` spends real time, which
## would make the recording unrepeatable.
func _step() -> void:
	_view._process(CG.TICK_SECONDS / float(frames_per_tick))

func _finish() -> void:
	_done = true
	var captured := _frames - _capture_started_at
	print("StagedFight: captured %d frames, ticks %d..%d, outcome %d" % [
		captured, from_tick, _view.state.tick, _view.state.outcome])
	print("StagedFight: trim with ffmpeg from frame %d (%.3fs at 60fps)" % [
		_capture_started_at, float(_capture_started_at) / 60.0])
	get_tree().quit(0)

## Drawn position and wind-up per body, which is what a recorded frame shows.
func _trace() -> void:
	var parts := PackedStringArray()
	for id in _view._unit_views.keys():
		var body = _view._unit_views[id]
		var u: CombatUnit = _view.state.unit(id)
		parts.append("%d@%.2f,%.2f%s" % [id, body.position.x, body.position.y,
			"" if u == null or u.current_action == &"" else ("/" + String(u.current_action))])
	print("TRACE %d tick=%d %s" % [_frames, _view.state.tick, " ".join(parts)])

# ---------------------------------------------------------------------------

func _build() -> bool:
	var pawns: Array[PawnData] = []
	for i in party.size():
		var cid: StringName = party[i]
		if ClassLibrary.get_class_def(cid) == null:
			printerr("StagedFight: no such class '%s'" % cid)
			return false
		pawns.append(PawnFactory.make_starter_pawn(cid, StringName("p%d" % i), String(cid)))
	if pawns.is_empty():
		printerr("StagedFight: the party is empty")
		return false

	var encounter = _encounter()
	if encounter == null:
		return false
	var cfg := RunConfig.new()
	cfg.party = pawns
	cfg.seed = fight_seed
	_view = BATTLE_SCENE.instantiate()
	add_child(_view)
	_view.begin_with_encounter(cfg, encounter)
	_view.set_process(false)
	return true

## Built here rather than looked up: a staged shot places its own bodies, and
## `Registry` has no encounter with them in it.
func _encounter():
	var e := RoomData.new()
	e.id = &"staged"
	e.display_name = "Staged"
	if room != &"":
		var base = RoomLibrary.get_room(room)
		if base == null:
			printerr("StagedFight: no such room '%s'" % room)
			return null
		e.cells = base.cells.duplicate()
	for spawn in enemies:
		var enemy_id: StringName = spawn.get("enemy_id", &"")
		if EnemyLibrary.get_enemy(enemy_id) == null:
			printerr("StagedFight: no such enemy '%s'" % enemy_id)
			return null
		e.enemy_spawns.append({"enemy_id": enemy_id, "position": spawn.get("position", Vector2.ZERO)})
	e.party_spawns = party_at.duplicate() if not party_at.is_empty() else _default_party_line(party.size())
	return e

## A column on the left, evenly spread, when the caller does not place them.
func _default_party_line(n: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var span := 130.0
	var top := -span * float(n - 1) * 0.5
	for i in n:
		out.append(Vector2(-350.0, top + span * float(i)))
	return out

# ---------------------------------------------------------------------------
# `--` arguments, so one scene films every shot without being edited.

func _read_args() -> void:
	for raw in OS.get_cmdline_user_args():
		var arg := String(raw)
		var split := arg.find("=")
		if split <= 0:
			continue
		var key := arg.substr(0, split)
		var value := arg.substr(split + 1)
		match key:
			"party": party = _string_names(value)
			"party_at": party_at = _points(value)
			"enemies": enemies = _spawns(value)
			"room": room = StringName(value)
			"seed": fight_seed = int(value)
			"from": from_tick = int(value)
			"to": to_tick = int(value)
			"fpt": frames_per_tick = maxi(1, int(value))
			"label": label = value
			"trace": trace = value == "1"
			_: printerr("StagedFight: ignoring unknown argument '%s'" % key)

func _string_names(value: String) -> Array[StringName]:
	var out: Array[StringName] = []
	for part in value.split(",", false):
		out.append(StringName(part.strip_edges()))
	return out

## `x,y;x,y`.
func _points(value: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for part in value.split(";", false):
		var xy := part.split(",", false)
		if xy.size() == 2:
			out.append(Vector2(float(xy[0]), float(xy[1])))
	return out

## `goblin@120,-40;ghoul@160,50`.
func _spawns(value: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for part in value.split(";", false):
		var at := part.find("@")
		if at <= 0:
			continue
		var xy := part.substr(at + 1).split(",", false)
		if xy.size() != 2:
			continue
		out.append({
			"enemy_id": StringName(part.substr(0, at).strip_edges()),
			"position": Vector2(float(xy[0]), float(xy[1])),
		})
	return out

func _ids(ids: Array[StringName]) -> String:
	var parts := PackedStringArray()
	for i in ids:
		parts.append(String(i))
	return ", ".join(parts)

func _enemy_ids() -> String:
	var parts := PackedStringArray()
	for spawn in enemies:
		parts.append(String(spawn.get("enemy_id", &"")))
	return ", ".join(parts)
