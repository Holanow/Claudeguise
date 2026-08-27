extends Node

## Issue 378. Three measurements of a ten-enemy fight, on the real battle
## screen: spill outside the arena border, name plates that collide, and
## damage floaters that collide.
##
## Spill is rasterised with the Hud hidden, so every non-background pixel
## outside the border belongs to the arena's own subtree. The other two read
## `UnitView.plate_layout` and `DamageFloater.extent` rather than a copy.
## Exits 0 always; it is an instrument, not a gate.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const DamageFloaterScript := preload("res://Scripts/UI/DamageFloater.gd")

const OUT_DIR := "res://Screenshots"
const SEED := 0x2A

## The two ten-enemy rooms the third blind playtest could not read.
const ENCOUNTERS := [&"floor1_room1", &"floor1_hazard"]

## Fractions of each fight's own length. 0.15 is the first clash, 0.45 the
## scrum the report is about, 0.75 the tail.
const SAMPLE_AT := [0.15, 0.45, 0.75]

var _battle: Node = null
var _runs: Array = []
var _run_index := 0
var _targets: Array[int] = []
var _next := 0
var _busy := false
var _tag := ""

var _spill_total := 0
var _plate_pairs := 0
var _floater_pairs := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	DisplayOptions.set_enabled(&"name_plates", true)
	DisplayOptions.set_enabled(&"damage_numbers", true)
	var class_ids := Registry.all_class_ids()
	if class_ids.is_empty():
		printerr("ArenaSpill: no content registered")
		get_tree().quit(1)
		return
	for enc in ENCOUNTERS:
		for party_ids in ScreenSweepScript.sweep_parties(class_ids):
			_runs.append({"encounter": enc, "party": party_ids})
	print("ArenaSpill: name plates ON, damage numbers ON, %d runs" % _runs.size())
	print("arena is %.0f x %.0f world units, DISPLAY_SCALE %.2f"
		% [CG.ARENA_HALF_WIDTH * 2.0, CG.ARENA_HALF_HEIGHT * 2.0, UnitView.DISPLAY_SCALE])
	_start_run()

func _start_run() -> void:
	var run: Dictionary = _runs[_run_index]
	var party: Array[PawnData] = _party(run["party"])
	var encounter = Registry.get_encounter(run["encounter"])

	var probe := CombatSim.build(_party(run["party"]), encounter, SEED)
	CombatSim.run(probe)
	_targets = []
	_next = 0
	for f in SAMPLE_AT:
		_targets.append(maxi(1, int(round(float(probe.tick) * f))))
	_tag = "%s_%s" % [String(run["encounter"]), "-".join(PackedStringArray(run["party"]))]

	print("")
	print("=== %s : %d enemies, %d ticks ===" % [
		String(run["encounter"]), encounter.enemy_spawns.size(), probe.tick])

	var cfg := RunConfig.new()
	cfg.party = party
	cfg.encounter_id = run["encounter"]
	cfg.seed = SEED

	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), ClassLibrary.get_class_def(cid).display_name
		))
	return out

func _process(_delta: float) -> void:
	if _busy or _battle == null or _next >= _targets.size():
		return
	var state = _battle.state
	if state == null or state.tick < _targets[_next]:
		return
	_busy = true
	await _sample(state)
	_busy = false
	_next += 1
	if _next < _targets.size():
		return
	_run_index += 1
	if _run_index < _runs.size():
		_start_run()
		return
	_report()
	get_tree().quit(0)

func _sample(state) -> void:
	var tick: int = state.tick
	var arena: Node2D = _battle.get_node("Arena")
	var hud: CanvasLayer = _battle.get_node("Hud")

	var was_visible := hud.visible
	hud.visible = false
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	hud.visible = was_visible

	var spill := _spill_of(image, arena)
	_spill_total += int(spill["pixels"])
	var plates := _plate_collisions(state, arena)
	var floaters := _floater_collisions(arena)
	_plate_pairs += int(plates["pairs"])
	_floater_pairs += int(floaters["legible_pairs"])

	print("  tick %4d  spill %5d px  %-34s | plates %d/%d collide  worst %.0f px | floaters %d live %d legible, %d collide (%d legible)"
		% [tick, spill["pixels"], spill["where"],
			plates["pairs"], plates["count"], plates["worst"],
			floaters["count"], floaters["legible"], floaters["pairs"], floaters["legible_pairs"]])
	for line in plates["examples"]:
		print("      plate  %s" % line)
	for line in spill["examples"]:
		print("      out    %s" % line)

	if _next == 1:
		var path := "%s/spill_%s_t%d.png" % [OUT_DIR, _tag, tick]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path)
		print("      shot   %s" % path)

## Where the arena's border lands on screen, in pixels, grown by the border's
## own stroke. `ArenaFloor` centres a 2px stroke on the boundary, so its outer
## half sits outside the mathematical rectangle: without this the tool reported
## a constant 447px of "spill" down the left edge, which was the border.
static func arena_screen_rect(arena: Node2D) -> Rect2:
	var t := arena.get_global_transform_with_canvas()
	var tl := t * Vector2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT)
	var br := t * Vector2(CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_HEIGHT)
	var stroke := ceilf(ArenaFloor.BOUNDARY_WIDTH * arena.scale.x)
	return Rect2(tl, br - tl).grow(stroke)

## Every pixel outside the border that is not the page background. The
## reference colour is read off pixel (0,0), which is page background by
## construction once the Hud is hidden.
func _spill_of(image: Image, arena: Node2D) -> Dictionary:
	var rect := arena_screen_rect(arena)
	var bg := image.get_pixel(0, 0)
	var w := image.get_width()
	var h := image.get_height()
	var count := 0
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	var above := 0
	var below := 0
	var left := 0
	var right := 0
	for y in h:
		for x in w:
			if rect.has_point(Vector2(x, y)):
				continue
			var c := image.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) < 0.04:
				continue
			count += 1
			lo.x = mini(lo.x, x)
			lo.y = mini(lo.y, y)
			hi.x = maxi(hi.x, x)
			hi.y = maxi(hi.y, y)
			if y < rect.position.y:
				above += 1
			elif y > rect.end.y:
				below += 1
			elif x < rect.position.x:
				left += 1
			else:
				right += 1
	if count == 0:
		return {"pixels": 0, "where": "border y %.0f..%.0f" % [rect.position.y, rect.end.y], "examples": []}
	return {
		"pixels": count,
		"where": "above %d below %d left %d right %d" % [above, below, left, right],
		"examples": ["x %d..%d y %d..%d, border y %.0f..%.0f x %.0f..%.0f"
			% [lo.x, hi.x, lo.y, hi.y, rect.position.y, rect.end.y, rect.position.x, rect.end.x]],
	}

## The chip of every plate that is actually drawn, straight off `UnitView`'s own
## layout. Deliberately not a copy of the layout maths: an instrument that
## measures its own arithmetic agrees with itself by construction.
static func plate_rects(state) -> Array:
	var layout := UnitView.plate_layout(state)
	var out: Array = []
	for u in state.units:
		if not u.alive or not UnitView.label_visible(u, state):
			continue
		if not layout.has(u.id):
			continue
		out.append({"name": u.display_name, "rect": layout[u.id]})
	return out

func _plate_collisions(state, _arena: Node2D) -> Dictionary:
	var rects := plate_rects(state)
	var pairs := 0
	var worst := 0.0
	var examples: Array = []
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Rect2 = rects[i]["rect"]
			var b: Rect2 = rects[j]["rect"]
			var hit := a.intersection(b)
			if hit.size.x <= 0.0 or hit.size.y <= 0.0:
				continue
			pairs += 1
			var area := hit.size.x * hit.size.y
			if area > worst:
				worst = area
			if examples.size() < 3:
				examples.append("\"%s\" over \"%s\", %.0f x %.0f px"
					% [rects[i]["name"], rects[j]["name"], hit.size.x, hit.size.y])
	return {"pairs": pairs, "count": rects.size(), "worst": worst, "examples": examples}

## Live damage floaters, as the text extents that actually collide rather than
## as the points `_floater_stagger_offset` compares.
## Below this a floater is fading out and is no longer text anybody reads, so
## counting it as a "smear" would over-report the defect.
const LEGIBLE_ALPHA := 0.35

static func floater_rects(arena: Node2D) -> Array:
	var out: Array = []
	for child in arena.get_children():
		if child.get_script() != DamageFloaterScript:
			continue
		var box: Rect2 = child.extent()
		if box.size.x <= 0.0:
			continue
		out.append({"text": child._text, "rect": box, "alpha": child.modulate.a})
	return out

func _floater_collisions(arena: Node2D) -> Dictionary:
	var rects := floater_rects(arena)
	var pairs := 0
	var legible_pairs := 0
	var legible := 0
	for r in rects:
		if float(r["alpha"]) >= LEGIBLE_ALPHA:
			legible += 1
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var hit: Rect2 = (rects[i]["rect"] as Rect2).intersection(rects[j]["rect"])
			if hit.size.x <= 0.0 or hit.size.y <= 0.0:
				continue
			pairs += 1
			if float(rects[i]["alpha"]) >= LEGIBLE_ALPHA and float(rects[j]["alpha"]) >= LEGIBLE_ALPHA:
				legible_pairs += 1
	return {"pairs": pairs, "count": rects.size(), "legible": legible, "legible_pairs": legible_pairs}

func _report() -> void:
	print("")
	print("TOTALS over %d runs x %d samples: spill %d px, %d plate collisions, %d legible floater collisions"
		% [_runs.size(), SAMPLE_AT.size(), _spill_total, _plate_pairs, _floater_pairs])
