extends SceneTree

## How much headroom `Tests/test_content_cleanse.gd`'s fixture actually has,
## per encounter and per seed count.
##
##   godot --headless --path . --script res://Tools/CleanseFixture.gd
##
## Not part of the game and not part of the gate. Throwaway diagnostic for the
## fixture-fragility fix; kept because the next person to move this fixture will
## want the same table rather than a number in a commit message.
##
## The counts mirror `test_content_cleanse.gd` exactly -- same party (every
## class but the Abomination, in `Registry.all_class_ids()` order), same
## `_cleanse_events` shape, same stepping loop. If those drift, this stops being
## an instrument for that test.
##
## **Issue 121, finch: it drifted, and this is the correction.** The shape used to
## be "STATUS_EXPIRED carrying a source, which only a cleanse produces". A cleanse
## is no longer the only thing that produces it -- `geyser_blast` consuming a BURN
## emits the same event on purpose, so a log can tell "Blast ate the burn" from
## "the burn ran out". Unfixed, this tool counted the combo as cleanses and
## reported floor1_room1 at 66 ally cleanses where the test sees 0. **I nearly
## picked a fixture off that number**, which is the "measurement answers a
## slightly different question" trap this project keeps paying for.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const SimDeps := preload("res://Scripts/Combat/SimDeps.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")

const MAX_SEEDS := 24

func _init() -> void:
	print("")
	print("%-22s %6s %8s %8s %9s %9s" % ["encounter", "seeds", "casts", "strips", "on_ally", "poisonings"])
	for encounter_id in Registry.all_encounter_ids():
		for seeds in [6, 12, 24, 48]:
			var casts := 0
			var strips := 0
			var on_ally := 0
			var poisonings := 0
			for s in seeds:
				var state := _run(encounter_id, s)
				for e in state.events:
					if e.kind == CG.EventKind.ACTION_FIRE and e.action_id == &"geyser_cleanse":
						casts += 1
					elif e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.POISON:
						var t := state.unit(e.target_id)
						if t != null and t.team == CG.Team.PLAYER:
							poisonings += 1
					elif e.kind == CG.EventKind.STATUS_EXPIRED and e.source_id != -1 and e.action_id == &"geyser_cleanse":
						strips += 1
						if e.target_id != e.source_id:
							on_ally += 1
			print("%-22s %6d %8d %8d %9d %9d%s" % [
				encounter_id, seeds, casts, strips, on_ally, poisonings,
				"   <- ON_ALLY AT RISK" if on_ally <= 2 else "",
			])
	quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in Registry.all_class_ids():
		if cid == &"abomination":
			continue
		out.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, out.size()]), String(cid)))
	return out

func _run(encounter_id: StringName, fight_seed: int) -> CombatState:
	var deps := SimDeps.new()
	var state := CombatSim.build(_party(), Registry.get_encounter(encounter_id), fight_seed, deps)
	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state, deps)
	return state
