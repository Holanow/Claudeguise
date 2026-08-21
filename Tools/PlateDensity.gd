extends Node

## The worst tick, not an average one. ArenaSpill samples three ticks of two
## rooms; this samples EVERY tick of every pickable room and reports the tick
## where the most text overprinted, which is the regime a watching player
## complains about.
##
## SAMPLING MOMENT: the top of each frame, before BattleView's own `_process`
## runs, so the plates and floaters read here are the ones the previous frame
## actually drew. Nothing here touches `state.rng` or `CombatSim`.

## Three collision classes, because they were three different row searches:
## plate vs plate, floater vs floater, and plate vs floater. Exits 0 always; it
## is an instrument, not a gate.

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
		"plates": 0, "on_other_body": 0,
		"reads_as_wrong": 0, "reads_as_nobody": 0,
		"home_reads_as_wrong": 0, "home_reads_as_nobody": 0, "moved": 0,
		"b_wrong": 0, "b_nobody": 0, "b_home_wrong": 0, "b_home_nobody": 0,
		"tether_px": [], "tether_crossings": 0, "tether_crosses_a_body": 0,
		"dist": [], "travel": [], "worst_dist": 0.0, "worst_dist_line": "",
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

	var ranks := UnitView.plate_ranks(state.units, state)
	var last_row := UnitView.PLATE_ROWS.size() - 1
	for id in ranks:
		if int(ranks[id]) >= last_row:
			_room["exhausted"] += 1

	_sample_ownership(state)

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

## Issue 440: where a plate ends up RELATIVE TO ITS OWNER. Which pawn a reader
## would say it names, how far it travelled from its home row to get there, and
## the same question asked of the home row so the row search can be told apart
## from the offset every plate carries.
func _sample_ownership(state) -> void:
	var layout := UnitView.plate_layout(state)
	for u in state.units:
		if not u.alive or not layout.has(u.id):
			continue
		var chip: Rect2 = layout[u.id]
		var at: Vector2 = chip.get_center()
		var own := UnitView.drawn_position(u, state.units)
		var dist := at.distance_to(own)
		var home: Rect2 = UnitView.plate_rect(u, state.units, 0)
		var travel := at.distance_to(home.get_center())
		_room["plates"] += 1
		_room["dist"].append(dist)
		_room["travel"].append(travel)
		if travel > 1.0:
			_room["moved"] += 1
		for other in state.units:
			if other.id == u.id or not other.alive:
				continue
			var hit := chip.intersection(body_box_of(other, state.units))
			if hit.size.x > 0.0 and hit.size.y > 0.0:
				_room["on_other_body"] += 1
		var reads_as = reader_owner(chip, state)
		if reads_as == null:
			_room["reads_as_nobody"] += 1
		elif reads_as.id != u.id:
			_room["reads_as_wrong"] += 1
		var home_reads = reader_owner(home, state)
		if home_reads == null:
			_room["home_reads_as_nobody"] += 1
		elif home_reads.id != u.id:
			_room["home_reads_as_wrong"] += 1
		var tether := UnitView.plate_tether(u, state.units, chip)
		_room["tether_px"].append(tether[0].distance_to(tether[1]))
		var crossed := 0
		for other in state.units:
			if other.id == u.id or not other.alive:
				continue
			if _segment_hits(tether[0], tether[1], body_box_of(other, state.units)):
				crossed += 1
		_room["tether_crossings"] += crossed
		if crossed > 0:
			_room["tether_crosses_a_body"] += 1
		var b = reader_owner_b(chip, state)
		if b == null:
			_room["b_nobody"] += 1
		elif b.id != u.id:
			_room["b_wrong"] += 1
		var b_home = reader_owner_b(home, state)
		if b_home == null:
			_room["b_home_nobody"] += 1
		elif b_home.id != u.id:
			_room["b_home_wrong"] += 1
		if dist > _room["worst_dist"]:
			_room["worst_dist"] = dist
			_room["worst_dist_line"] = "\"%s\" %.0f px from its own unit, tick %d, reads as %s" % [
				u.display_name, dist, state.tick,
				"nobody" if reads_as == null else "\"%s\"" % reads_as.display_name]

## Godot has no segment-rect test, and a leader line that runs through three
## other pawns is the cost this device has to be judged on.
static func _segment_hits(a: Vector2, b: Vector2, box: Rect2) -> bool:
	if box.has_point(a) or box.has_point(b):
		return true
	var c := [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(a, b, c[i], c[(i + 1) % 4]) != null:
			return true
	return false

static func body_box_of(u, units: Array) -> Rect2:
	var at := UnitView.drawn_position(u, units)
	var box := UnitView.drawn_box(UnitView.shape_id(u), u.team, UnitView.display_radius(u))
	return Rect2(at + box.position, box.size)

## Which pawn a reader would say the plate names: the nearest body BELOW it
## whose columns overlap the chip's, because a plate is drawn above its unit
## and that is the only cue tying the two together. `null` is the playtester's
## "floats in empty space with no unit under or near it".
const READER_REACH := 120.0

## A second reader model, because the first is a judgement call and a finding
## that only holds under one model is not a finding: nearest body centre to the
## point the plate hangs from, rather than nearest body below its columns.
static func reader_owner_b(chip: Rect2, state):
	var stem := Vector2(chip.get_center().x, chip.end.y)
	var best = null
	var best_d := READER_REACH
	for u in state.units:
		if not u.alive:
			continue
		var d: float = stem.distance_to(body_box_of(u, state.units).get_center())
		if d < best_d:
			best_d = d
			best = u
	return best

static func reader_owner(chip: Rect2, state):
	var best = null
	var best_gap := INF
	for u in state.units:
		if not u.alive:
			continue
		var box := body_box_of(u, state.units)
		if box.end.x < chip.position.x or box.position.x > chip.end.x:
			continue
		var gap: float = box.position.y - chip.end.y
		if gap < -box.size.y or gap > READER_REACH:
			continue
		if absf(gap) < best_gap:
			best_gap = absf(gap)
			best = u
	return best

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
	print("  plate-ticks %d | reads as the WRONG pawn %d (%.1f%%) | reads as NOBODY %d (%.1f%%)"
		% [r["plates"], r["reads_as_wrong"], _pct(r["reads_as_wrong"], r["plates"]),
			r["reads_as_nobody"], _pct(r["reads_as_nobody"], r["plates"])])
	print("  at home row: wrong %d (%.1f%%), nobody %d (%.1f%%) | relocated %d (%.1f%%) | chip on another body %d (%.1f%%)"
		% [r["home_reads_as_wrong"], _pct(r["home_reads_as_wrong"], r["plates"]),
			r["home_reads_as_nobody"], _pct(r["home_reads_as_nobody"], r["plates"]),
			r["moved"], _pct(r["moved"], r["plates"]),
			r["on_other_body"], _pct(r["on_other_body"], r["plates"])])
	print("  model B: wrong %d (%.1f%%), nobody %d (%.1f%%) | at home row wrong %d (%.1f%%), nobody %d (%.1f%%)"
		% [r["b_wrong"], _pct(r["b_wrong"], r["plates"]), r["b_nobody"], _pct(r["b_nobody"], r["plates"]),
			r["b_home_wrong"], _pct(r["b_home_wrong"], r["plates"]),
			r["b_home_nobody"], _pct(r["b_home_nobody"], r["plates"])])
	print("  tether px: %s | crosses another body %d (%.1f%%), %d crossings"
		% [_percentiles(r["tether_px"]), r["tether_crosses_a_body"],
			_pct(r["tether_crosses_a_body"], r["plates"]), r["tether_crossings"]])
	print("  distance plate->own unit px: %s" % _percentiles(r["dist"]))
	print("  travel from home row px:     %s" % _percentiles(r["travel"]))
	if r["worst_dist_line"] != "":
		print("      worst: %s" % r["worst_dist_line"])
	print("  collisions summed over every tick: plate/plate %d, plate/floater %d, floater/floater %d"
		% [r["plate_pairs"], r["cross_pairs"], r["floater_pairs"]])
	print("  worst tick %d with %d overlapping pairs:" % [r["worst_tick"], r["worst"]])
	for line in r["worst_lines"]:
		print("      %s" % line)

static func _pct(n, of) -> float:
	return 0.0 if int(of) == 0 else 100.0 * float(n) / float(of)

## Percentiles rather than a mean: the complaint is about the tail, and a mean
## over every quiet tick hides it.
static func _percentiles(values: Array) -> String:
	if values.is_empty():
		return "no plates"
	var sorted := values.duplicate()
	sorted.sort()
	var out := PackedStringArray()
	for p in [50, 75, 90, 95, 99, 100]:
		var i := clampi(int(round(float(p) / 100.0 * (sorted.size() - 1))), 0, sorted.size() - 1)
		out.append("p%d %.0f" % [p, sorted[i]])
	return " | ".join(out)

func _report() -> void:
	var pp := 0
	var cp := 0
	var ff := 0
	var ticks := 0
	var ex := 0
	var plates := 0
	var mis := 0
	var onbody := 0
	var dist: Array = []
	var travel: Array = []
	var home_mis := 0
	var nobody := 0
	var home_nobody := 0
	var bw := 0
	var bn := 0
	var bhw := 0
	var bhn := 0
	var tether_px: Array = []
	var tcross := 0
	var tbody := 0
	var moved := 0
	var worst := {}
	for r in _rooms:
		plates += int(r["plates"])
		mis += int(r["reads_as_wrong"])
		nobody += int(r["reads_as_nobody"])
		onbody += int(r["on_other_body"])
		home_mis += int(r["home_reads_as_wrong"])
		home_nobody += int(r["home_reads_as_nobody"])
		bw += int(r["b_wrong"]); bn += int(r["b_nobody"])
		bhw += int(r["b_home_wrong"]); bhn += int(r["b_home_nobody"])
		tether_px.append_array(r["tether_px"])
		tcross += int(r["tether_crossings"]); tbody += int(r["tether_crosses_a_body"])
		moved += int(r["moved"])
		dist.append_array(r["dist"])
		travel.append_array(r["travel"])
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
	print("OWNERSHIP over %d drawn plate-ticks: reads as the WRONG pawn %d (%.1f%%), reads as NOBODY %d (%.1f%%)"
		% [plates, mis, _pct(mis, plates), nobody, _pct(nobody, plates)])
	print("AT HOME ROW: wrong %d (%.1f%%), nobody %d (%.1f%%). Relocated %d (%.1f%%). Chip on another body %d (%.1f%%)"
		% [home_mis, _pct(home_mis, plates), home_nobody, _pct(home_nobody, plates),
			moved, _pct(moved, plates), onbody, _pct(onbody, plates)])
	print("MODEL B over the same plate-ticks: wrong %d (%.1f%%), nobody %d (%.1f%%); at home row wrong %d (%.1f%%), nobody %d (%.1f%%)"
		% [bw, _pct(bw, plates), bn, _pct(bn, plates), bhw, _pct(bhw, plates), bhn, _pct(bhn, plates)])
	print("TETHER px: %s | crosses another body %d (%.1f%%), %d crossings in all"
		% [_percentiles(tether_px), tbody, _pct(tbody, plates), tcross])
	print("DISTANCE plate->own unit px: %s" % _percentiles(dist))
	print("TRAVEL from home row px:     %s" % _percentiles(travel))
	if not worst.is_empty():
		print("WORST TICK anywhere: %s tick %d, %d overlapping pairs"
			% [worst["id"], worst["worst_tick"], worst["worst"]])
