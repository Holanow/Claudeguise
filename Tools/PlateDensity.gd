extends Node

## The worst tick, not an average one. ArenaSpill samples three ticks of two
## rooms; this samples EVERY tick of every pickable room and reports the tick
## where the most text overprinted, which is the regime a watching player
## complains about.
##
## SAMPLING MOMENT: the top of each frame, before BattleView's own `_process`
## runs, so the plates and floaters read here are the ones the previous frame
## actually drew. Nothing here touches `state.rng` or `CombatSim`.
##
## Three collision classes, because they are three different row searches:
## plate vs plate (`UnitView.plate_ranks`), floater vs floater
## (`BattleView._floater_stagger_offset`), and plate vs floater, which NOTHING
## de-collides. Exits 0 always; it is an instrument, not a gate.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const SpillScript := preload("res://Tools/ArenaSpill.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

const OUT_DIR := "res://Screenshots"
const SEED := 0x2A
const LEGIBLE_ALPHA := 0.35

## Real seconds per simulated second. The fight, the floater lifetimes and the
## fade all run off `delta`, so this is uniform and changes nothing but the
## wall clock.
const TIME_SCALE := 8.0

var _battle: Node = null
var _runs: Array = []
var _run_index := 0
var _last_tick := -1
var _shot_pending := false

var _room: Dictionary = {}
var _rooms: Array = []

func _ready() -> void:
	Offscreen.hide_window(self)
	DisplayOptions.set_enabled(&"name_plates", true)
	DisplayOptions.set_enabled(&"damage_numbers", true)
	Engine.time_scale = TIME_SCALE
	var class_ids := Registry.all_class_ids()
	var encounters := Registry.pickable_encounter_ids()
	if class_ids.is_empty() or encounters.is_empty():
		printerr("PlateDensity: no content registered")
		get_tree().quit(1)
		return
	for enc in encounters:
		for party_ids in ScreenSweepScript.sweep_parties(class_ids):
			_runs.append({"encounter": enc, "party": party_ids})
	print("PlateDensity: %d runs over %d pickable rooms, every tick sampled"
		% [_runs.size(), encounters.size()])
	print("arena %.0f x %.0f world units, DISPLAY_SCALE %.2f, %d plate rows"
		% [CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0,
			UnitView.DISPLAY_SCALE, UnitView.PLATE_ROWS.size()])
	_start_run()

func _start_run() -> void:
	var run: Dictionary = _runs[_run_index]
	var cfg := RunConfig.new()
	cfg.party = _party(run["party"])
	cfg.encounter_id = run["encounter"]
	cfg.seed = SEED
	_room = {
		"id": String(run["encounter"]),
		"party": "-".join(PackedStringArray(run["party"])),
		"ticks": 0, "skipped": 0,
		"max_plates": 0, "plate_pairs": 0, "cross_pairs": 0, "floater_pairs": 0,
		"exhausted": 0,
		"tightest": Vector2(1e9, 1e9), "tightest_tick": 0, "tightest_n": 0,
		"worst": 0, "worst_tick": 0, "worst_lines": [],
	}
	_last_tick = -1
	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), Registry.get_class_def(cid).display_name))
	return out

func _process(_delta: float) -> void:
	if _battle == null or _shot_pending:
		return
	var state = _battle.state
	if state == null:
		return
	if state.tick != _last_tick:
		if _last_tick >= 0 and state.tick > _last_tick + 1:
			_room["skipped"] += state.tick - _last_tick - 1
		_last_tick = state.tick
		_sample(state)
	if state.outcome != CombatState.Outcome.UNRESOLVED:
		_finish_run()

func _finish_run() -> void:
	_shot_pending = true
	_rooms.append(_room)
	_print_room(_room)
	_run_index += 1
	if _run_index < _runs.size():
		_shot_pending = false
		_start_run()
		return
	_report()
	get_tree().quit(0)

func _sample(state) -> void:
	var arena: Node2D = _battle.get_node("Arena")
	var plates := SpillScript.plate_rects(state)
	var floaters := _legible_floaters(arena)

	_room["ticks"] += 1
	_room["max_plates"] = maxi(_room["max_plates"], plates.size())

	var ranks := UnitView.plate_ranks(state.units)
	var last_row := UnitView.PLATE_ROWS.size() - 1
	for id in ranks:
		if int(ranks[id]) >= last_row:
			_room["exhausted"] += 1

	var box := _body_box(state)
	if box.size.x * box.size.y < _room["tightest"].x * _room["tightest"].y and _live(state) >= 4:
		_room["tightest"] = box.size
		_room["tightest_tick"] = state.tick
		_room["tightest_n"] = _live(state)

	var lines: Array = []
	var pp := _pairs(plates, plates, "plate/plate", lines)
	var cp := _pairs(plates, floaters, "plate/floater", lines)
	var ff := _pairs(floaters, floaters, "floater/floater", lines)
	_room["plate_pairs"] += pp
	_room["cross_pairs"] += cp
	_room["floater_pairs"] += ff
	if pp + cp + ff > _room["worst"]:
		_room["worst"] = pp + cp + ff
		_room["worst_tick"] = state.tick
		_room["worst_lines"] = lines.slice(0, 6)

## Every overlapping pair between two lists of labelled rects; `a == b` means
## the list against itself, and each pair is counted once either way.
func _pairs(a: Array, b: Array, kind: String, lines: Array) -> int:
	var same := a == b
	var count := 0
	for i in a.size():
		var from := i + 1 if same else 0
		for j in range(from, b.size()):
			var hit: Rect2 = (a[i]["rect"] as Rect2).intersection(b[j]["rect"])
			if hit.size.x <= 0.0 or hit.size.y <= 0.0:
				continue
			count += 1
			if lines.size() < 12:
				lines.append("%s: \"%s\" x \"%s\", %.0f x %.0f px"
					% [kind, _name_of(a[i]), _name_of(b[j]), hit.size.x, hit.size.y])
	return count

static func _name_of(entry: Dictionary) -> String:
	return String(entry.get("name", entry.get("text", "?")))

func _legible_floaters(arena: Node2D) -> Array:
	var out: Array = []
	for entry in SpillScript.floater_rects(arena):
		if float(entry["alpha"]) >= LEGIBLE_ALPHA:
			out.append(entry)
	return out

static func _live(state) -> int:
	var n := 0
	for u in state.units:
		if u.alive:
			n += 1
	return n

## The tightest box the living bodies fit in, in ARENA-local pixels, which is
## the space the plates have to share.
static func _body_box(state) -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for u in state.units:
		if not u.alive:
			continue
		var at := UnitView.drawn_position(u, state.units)
		lo = lo.min(at)
		hi = hi.max(at)
	if hi.x < lo.x:
		return Rect2()
	return Rect2(lo, hi - lo)

func _print_room(r: Dictionary) -> void:
	print("")
	print("=== %s / %s : %d ticks sampled, %d skipped ===" % [r["id"], r["party"], r["ticks"], r["skipped"]])
	print("  max plates up at once %d | rows exhausted %d plate-ticks" % [r["max_plates"], r["exhausted"]])
	print("  tightest body box %.0f x %.0f px at tick %d with %d alive"
		% [r["tightest"].x, r["tightest"].y, r["tightest_tick"], r["tightest_n"]])
	print("  collisions summed over every tick: plate/plate %d, plate/floater %d, floater/floater %d"
		% [r["plate_pairs"], r["cross_pairs"], r["floater_pairs"]])
	print("  worst tick %d with %d overlapping pairs:" % [r["worst_tick"], r["worst"]])
	for line in r["worst_lines"]:
		print("      %s" % line)

func _report() -> void:
	var pp := 0
	var cp := 0
	var ff := 0
	var ticks := 0
	var ex := 0
	var worst := {}
	for r in _rooms:
		pp += int(r["plate_pairs"])
		cp += int(r["cross_pairs"])
		ff += int(r["floater_pairs"])
		ticks += int(r["ticks"])
		ex += int(r["exhausted"])
		if worst.is_empty() or int(r["worst"]) > int(worst["worst"]):
			worst = r
	print("")
	print("TOTALS over %d runs, %d ticks: plate/plate %d, plate/floater %d, floater/floater %d, rows exhausted %d"
		% [_rooms.size(), ticks, pp, cp, ff, ex])
	if not worst.is_empty():
		print("WORST TICK anywhere: %s tick %d, %d overlapping pairs"
			% [worst["id"], worst["worst_tick"], worst["worst"]])
