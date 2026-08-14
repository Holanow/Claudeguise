extends Node

const CG := preload("res://Scripts/Core/CG.gd")
const RunConfig := preload("res://Scripts/Core/RunConfig.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const UnitViewScript := preload("res://Scripts/UI/UnitView.gd")

## Issue 61: the SUSTAINING badge on real units, on the real battle screen.
##
##   godot --path . --resolution 1280x720 res://Tools/SustainShot.tscn
##
## Not part of the game and not part of the gate.
##
## **THIS DOES NOT WORK YET AND ITS OUTPUT PROVES NOTHING. Do not screenshot
## with it and do not cite a frame it produced.** It is committed unfinished
## rather than deleted because the harness is most of a useful tool and the
## failure is worth somebody knowing about.
##
## What happens: it writes a status onto live units, waits, captures, and the
## captured frame does not contain the change. Measured rather than assumed --
## and the control is what makes it a harness problem rather than a badge
## problem:
##
##   - SUSTAINING on all four pawns vs none: images byte-identical.
##   - SHIELDING (an existing, shipped status with a shipped glyph) on all
##     four vs none: byte-identical. So it is not about the new status.
##   - `u.hp = 1` on all four vs none: **also byte-identical**, and that one
##     cannot be right. Setting every pawn to 1 hp must move four hp bars.
##   - Capturing at tick 40 vs tick 200: images differ. So the capture is live
##     with respect to the simulation and stale only with respect to writes
##     made from this node.
##
## So a write from this node reaches `_battle.state` -- the diagnostic below
## reads the status straight back out of it, and `UnitView.status_badges`
## returns it -- and does not reach the drawn frame. I could not find the reason
## inside a reasonable time, and `Scripts/UI/BattleView.gd` is not my file to go
## rummaging in. Left here rather than "fixed" by picking a frame that looks
## right: a screenshot that agrees with what you already believe is exactly the
## measurement that answers a slightly different question than the one asked.
##
## What DOES cover the badge in the meantime: `test_art.gd` and
## `test_ui_unit_view.gd` both refuse a `CG.Status` with no glyph, and
## `test_art.gd` bounds-checks the glyph's geometry. What covers the mechanism
## is `Tests/test_combat_sustain.gd` and `Tools/SustainProbe.gd`.
##
## **What this proves and what it does not, stated up front because the gap
## matters.** It proves the new status renders: the glyph exists, `UnitView`
## picks it up through its ordinary badge row, and it is legible at the size and
## against the background a player actually sees. It does NOT show a channel
## running, because **no content uses the mechanism yet** -- every action still
## has `sustain_cost_per_tick == 0`, deliberately, so the balance movement stays
## a separate and attributable step when finch's Immolate lands.
##
## So the status is written onto two live pawns by hand here rather than earned
## by an action. `Scripts/UI/BattleView.gd` builds its own `CombatState` from a
## `RunConfig` and takes no `SimDeps`, so there is no seam for a probe to inject
## a synthetic action through, and inventing one would mean editing wren's file.
## `Tools/SustainProbe.gd` is where the mechanism itself is exercised, 150
## fights at a time.
##
## No --headless: `get_viewport().get_texture()` never populates under
## --headless on this machine (see Tools/AttackFXPreview.gd's own note).

const OUT_DIR := "res://Screenshots"
const CAPTURE_TICK := 40

var _battle: Node = null
var _applied := false
var _done := false
## Frames to let the arena redraw after the status lands. Capturing on the very
## next frame photographed the state BEFORE the mutation -- the Warrior showed
## its one pre-existing badge and not the new one, while the diagnostic print
## in the same call already listed two. A screenshot one frame stale is exactly
## the "evidence for something you are no longer shipping" ENGINEER.md warns
## about, and it is invisible unless something else in the frame disagrees.
const SETTLE_FRAMES := 4
var _settle := 0

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
	if state == null or state.tick < CAPTURE_TICK:
		return
	if not _applied:
		var n := 0
		for u in state.units:
			if u.team != CG.Team.PLAYER or not u.alive:
				continue
			## CG.MAX_TICKS is "outlives the fight", the same expiry
			## `CombatSim._begin_sustain` uses -- a channel is ended by a rule,
			## not by a clock.
			## The status ONLY, and not `u.sustaining`. The first version of this
			## set both, and the badge never appeared: `_tick_sustain` looked the
			## named action up, got null because no such action is registered,
			## and correctly ended the channel -- badge included -- on the very
			## next tick. That is the mechanism defending itself against exactly
			## this kind of poking, and it is worth knowing it does.
			##
			## So the two pieces of state are deliberately inconsistent here, in
			## a preview harness, for one frame. Nothing in a real fight can
			## reach that: `CombatSim` writes both together and is the only
			## writer.
			u.statuses[CG.Status.SUSTAINING] = CG.MAX_TICKS
			n += 1
		if n == 0:
			printerr("SustainShot: no living player pawn to badge")
			get_tree().quit(1)
			return
		_applied = true
		return
	if _settle < SETTLE_FRAMES:
		_settle += 1
		return
	_done = true
	_capture(state)

func _capture(state) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/swift_61_sustaining_badge.png" % OUT_DIR
	image.save_png(path)
	print("SustainShot: %s at tick %d" % [path, state.tick])
	for u in state.units:
		if u.team == CG.Team.PLAYER:
			print("  %s statuses=%s badges=%s" % [u.display_name, u.statuses, UnitViewScript.status_badges(u)])
	get_tree().quit(0)
