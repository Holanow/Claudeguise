extends Node

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## Issue 150: the Brute's roar landing on a real pawn, on the real battle screen.
##
##   godot --path . --resolution 1280x720 res://Tools/RoarShot.tscn
##
## Not part of the game and not part of the gate.
##
## **Nothing is written onto the state.** It starts an ordinary fight in the burn
## pit -- the one room in the game that fields a Brute -- watches for the first
## pawn carrying TAUNTED, and captures. Same shape as `Tools/ImmolateShot.gd`,
## and the same reason: a frame produced by poking the simulation is evidence
## about the poke.
##
## No --headless: `get_viewport().get_texture()` never populates under
## --headless on this machine.
##
## **The icon is real now.** sable's `brute_roar` glyph merged into this branch,
## so the mark beside the Abomination's bar in `finch_150_roar_lands.png` is the
## TAUNTED arc-and-barb, not the placeholder this comment used to warn about.

const OUT_DIR := "res://Screenshots"
const SETTLE_FRAMES := 4

var _battle: Node = null
var _settle := -1
var _done := false
var _holder_id := -1
var _held_shot := false

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ["abomination", "geysermancer", "priest", "warrior"]:
		var c := StringName(cid)
		out.append(PawnFactory.make_starter_pawn(
			c, StringName("%s_%d" % [cid, out.size()]), Registry.get_class_def(c).display_name
		))
	return out

func _ready() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = &"floor1_hazard"
	cfg.seed = 7
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _process(_delta: float) -> void:
	if _battle == null or _done:
		return
	var state = _battle.state
	if state == null:
		return
	if _settle < 0:
		for u in state.units:
			if u.alive and u.pawn != null and u.has_status(CG.Status.TAUNTED):
				_holder_id = u.id
				_settle = 0
				break
		return
	## Settling matters here for the reason swift's own header gives: a frame
	## captured the instant the state changes photographs the state before it.
	## The channel lasts about fifteen ticks, so four frames is well inside it --
	## re-checked below rather than assumed, and the capture is abandoned if the
	## channel ended while we waited.
	if _settle < SETTLE_FRAMES:
		_settle += 1
		return
	var holder = state.unit(_holder_id)
	if holder == null:
		_settle = -1
		_holder_id = -1
		return
	if not holder.has_status(CG.Status.TAUNTED) and not _held_shot:
		_settle = -1
		_holder_id = -1
		return
	if not _held_shot:
		_held_shot = true
		_capture(state, holder, "finch_150_roar_lands.png")
		return
	## The second half of the story, and the one a reader of the log needs: the
	## line that says it stopped. Waits for the channel this frame photographed
	## to actually end rather than for a fixed tick.
	if holder.has_status(CG.Status.TAUNTED):
		return
	_done = true
	_capture(state, holder, "finch_150_roar_ends.png")

func _capture(state, holder, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s" % [OUT_DIR, filename]
	image.save_png(path)
	print("RoarShot: %s at tick %d" % [path, state.tick])
	print("  taunted pawn: %s badges=%s" % [holder.display_name, UnitViewScript.status_badges(holder)])
	var roars := 0
	for e in state.events:
		if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"brute_roar":
			roars += 1
	print("  brute_roar fires so far: %d" % roars)
	if _done:
		get_tree().quit(0)
