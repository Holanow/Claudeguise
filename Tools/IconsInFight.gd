extends Node

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const OVERLAY := preload("res://Tools/IconsOverlay.gd")

## The status badges and ability icons drawn on REAL UNITS in a REAL FIGHT, at
## the size and against the background they will actually have.
##
##   godot --path . --resolution 1280x720 res://Tools/IconsInFight.tscn
##
## Why this exists and why the design sheet is not enough: a siege engine
## silhouette shipped twice, was confirmed present in the registry twice, and
## was invisible in the game both times, because a summoned unit never got a
## view node at all. **A shape existing in a table is not a thing being drawn.**
## So this drives the real `Scenes/Battle.tscn` with the real simulation, the
## same way Tools/ContactSheet.gd does and for the same reason, and only adds a
## sibling node that draws on top.
##
## What this DOES prove: the badges and icons are legible at true size, over
## real art, over the real arena floor, among the real HP bars and name labels
## and floating numbers, on units that are actually afflicted with what the
## badge says.
##
## What this does NOT prove, stated plainly rather than left to look like
## coverage: **this is not the shipped placement.** Placement is
## `Scripts/UI/UnitView.gd`, wren's, and this tool does not touch it. The
## overlay here positions badges above the unit's own stack the way the real
## one is expected to, but the real one will be wren's code, and it can land
## somewhere else. This measures the art, not the wiring.
##
## No --headless: get_viewport().get_texture() never populates under --headless
## on this machine. See Tools/AttackFXPreview.gd.

const OUT_DIR := "res://Screenshots"
const SEED := 0x2A
const FRAMES := 4

var _battle: Node = null
var _overlay: Node2D = null
var _targets: Array[int] = []
var _next := 0

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), Registry.get_class_def(cid).display_name
		))
	return out

func _ready() -> void:
	var class_ids := Registry.all_class_ids()
	if class_ids.is_empty():
		printerr("IconsInFight: no content registered")
		get_tree().quit(1)
		return
	var party_ids := class_ids.slice(0, mini(4, class_ids.size()))

	# Same probe-then-replay trick ContactSheet uses: run the fight once to
	# learn its length, so the captures land across its actual arc rather than
	# at fixed times that might all fall before anything is afflicted.
	var probe := CombatSim.build(_party(party_ids), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), SEED)
	CombatSim.run(probe)
	var total: int = maxi(probe.tick, FRAMES)
	print("IconsInFight: fight lasts %d ticks (%.1fs)" % [probe.tick, float(probe.tick) / float(CG.TICKS_PER_SECOND)])
	for i in FRAMES:
		_targets.append(int(round(float(total) * float(i + 1) / float(FRAMES + 1))))

	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED

	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

	# A sibling of Arena, not a child of it: this way the badges are sized in
	# real screen pixels the way the shipped ones will be, instead of inheriting
	# the arena's own fit scale and silently being drawn bigger than they are.
	_overlay = OVERLAY.new()
	_overlay.z_index = 100
	_overlay.arena = _battle.get_node("Arena")
	_overlay.battle = _battle
	_battle.add_child(_overlay)

func _process(_delta: float) -> void:
	if _battle == null or _next >= _targets.size():
		return
	var state = _battle.state
	if state == null:
		return
	_overlay.state = state
	_overlay.queue_redraw()
	if state.tick < _targets[_next]:
		return
	_capture(_next)
	_next += 1
	if _next >= _targets.size():
		_capture_every_status()

## A real fight afflicts one or two units with one status each, which is a thin
## sample to judge twelve badges from. This writes every status onto the living
## units directly, so all twelve can be read at true size over real art on the
## real floor, several to a unit, which is the crowded case that actually
## decides whether they work.
##
## It mutates the state after the real captures are finished, so nothing above
## is affected. This frame is a legibility test and is labelled as one; it is
## not a picture of a fight that could happen.
func _capture_every_status() -> void:
	var living: Array = []
	for u in _battle.state.units:
		if u.alive:
			living.append(u)
	if living.is_empty():
		get_tree().quit(0)
		return
	var all := CG.Status.values()
	for i in all.size():
		var u = living[i % living.size()]
		u.statuses[all[i]] = CG.MAX_TICKS
	_overlay.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/icons_in_fight_every_status.png" % OUT_DIR
	image.save_png(path)
	print("IconsInFight: %s -- all %d statuses over %d living units" % [path, all.size(), living.size()])
	get_tree().quit(0)

func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/icons_in_fight_%02d.png" % [OUT_DIR, index + 1]
	image.save_png(path)
	print("IconsInFight: %s at tick %d, %d units afflicted" % [path, _targets[index], _overlay.afflicted_count()])
