extends Node


const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## Issue 219: a real channel, on the real battle screen, earned by a plan.
##
##   godot --path . --resolution 1280x720 res://Tools/ImmolateShot.tscn
##
## Not part of the game and not part of the gate.
##
## **This replaces what `Tools/SustainShot.gd` could not do, and the difference
## is not a better harness -- it is that the content now exists.** swift's tool
## had to *write* `CG.Status.SUSTAINING` onto living pawns by hand, because in
## #61 every action's `sustain_cost_per_tick` was 0 and no fight could ever
## produce one. Its own header records that those writes never reached the drawn
## frame, with the controls that prove it was the harness. **Nothing here writes
## anything.** It starts an ordinary fight, watches `state`, and captures the
## first frame on which some unit is really holding a channel -- so the bug that
## defeated swift cannot be in the path at all, and the frame is evidence about
## the game rather than about the probe. swift: yours is now safe to delete.
##
## No --headless: `get_viewport().get_texture()` never populates under
## --headless on this machine (see `Tools/AttackFXPreview.gd`'s own note).
##
## **What it proves and what it does not.** It proves a channel happens in a
## real fight from the shipped plan, that the badge is on the drawn unit, and
## that the log says so. It does not prove the icon is right:
## `abomination_immolate` has no `ActionIcons` glyph yet -- that is sable's half
## and the gate names it -- so whatever the log draws beside the line is a
## placeholder and should not be read as art.

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
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
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
			if u.alive and u.sustaining != &"":
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
	if holder.sustaining == &"" and not _held_shot:
		_settle = -1
		_holder_id = -1
		return
	if not _held_shot:
		_held_shot = true
		_capture(state, holder, "finch_219_immolate_channel.png")
		return
	## The second half of the story, and the one a reader of the log needs: the
	## line that says it stopped. Waits for the channel this frame photographed
	## to actually end rather than for a fixed tick.
	if holder.sustaining != &"":
		return
	_done = true
	_capture(state, holder, "finch_219_immolate_ends.png")

func _capture(state, holder, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s" % [OUT_DIR, filename]
	image.save_png(path)
	print("ImmolateShot: %s at tick %d" % [path, state.tick])
	print("  holder: %s sustaining=%s badges=%s" % [
		holder.display_name, holder.sustaining, UnitViewScript.status_badges(holder)])
	var starts := 0
	for e in state.events:
		if e.kind == CG.EventKind.SUSTAIN_START:
			starts += 1
	print("  SUSTAIN_START events so far: %d" % starts)
	if _done:
		get_tree().quit(0)
