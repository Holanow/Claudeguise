extends SceneTree

## Issue 746: measures the quiver's `adds_status_chance` against many landed
## hits, on the Siege Master, rather than asserting it. One fight caps at
## `CG.MAX_TICKS`, so this pools SEED_COUNT independent seeds' hits.
##
##   godot --headless --path . --script res://Tools/QuiverBleedRate.gd

const SEED_COUNT := 60

## Always fires `siege_master_shot` at `target_id` whenever the caster is free.
## `_resolve_use_action` re-checks cooldown and resource itself, so returning
## the same intent every free tick is enough -- no bookkeeping needed here.
class ForceRepeat:
	var caster_id: int
	var action_id: StringName
	var target_id: int

	func decide(_state: CombatState, unit: CombatUnit) -> Intent:
		if unit.id == caster_id:
			return Intent.use_action(action_id, target_id)
		return null

func _one_fight(seed_value: int, quiver: EquipmentDef) -> Dictionary:
	var caster := CombatUnit.new()
	caster.id = 0
	caster.team = CG.Team.PLAYER
	caster.hp_max = 999999
	caster.hp = caster.hp_max
	caster.resource_max = 999999
	caster.resource = 999999
	caster.radius = 0.0
	caster.actions = [&"siege_master_shot"]
	caster.position = Vector2(-CG.ARENA_HALF_WIDTH + 40.0, 0.0)
	var pawn := PawnData.new()
	pawn.pawn_class = ClassLibrary.get_class_def(&"siege_master")
	pawn.off_hand = quiver
	caster.pawn = pawn

	var target := CombatUnit.new()
	target.id = 1
	target.team = CG.Team.ENEMY
	target.radius = 0.0
	target.hp_max = 999999999
	target.hp = target.hp_max
	target.resource_max = 999999
	target.resource = 999999
	target.position = caster.position + Vector2(300.0, 0.0)
	caster.facing = (target.position - caster.position).normalized()

	var state := CombatState.new(seed_value)
	state.units = [caster, target]

	var rig := ForceRepeat.new()
	rig.caster_id = caster.id
	rig.action_id = &"siege_master_shot"
	rig.target_id = target.id

	var deps := SimDeps.new()
	deps.default_decide = Callable(rig, "decide")
	## Fixed and positive so every hit deals damage regardless of Balance's
	## attribute math -- this rig measures the quiver's chance draw, not the
	## Siege Master's attack power.
	deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r: RandomNumberGenerator) -> float: return 50.0

	while state.outcome == CombatState.Outcome.UNRESOLVED and state.tick < CG.MAX_TICKS:
		CombatSim.step(state, deps)

	var hits := 0
	var bleeds := 0
	for e in state.events:
		## `action_id` excludes BLEED's own damage-over-time ticks, which emit a
		## DAMAGE event with an empty action id and would otherwise inflate the
		## denominator with damage this rig did not just land.
		if e.action_id != &"siege_master_shot":
			continue
		if e.kind == CG.EventKind.DAMAGE and e.target_id == target.id:
			hits += 1
		elif e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.BLEED and e.target_id == target.id:
			bleeds += 1
	return {"hits": hits, "bleeds": bleeds}

func _init() -> void:
	var quiver: EquipmentDef = ItemLibrary.get_equipment(&"quiver")
	var chance := quiver.modifiers[0].adds_status_chance

	var total_hits := 0
	var total_bleeds := 0
	for i in SEED_COUNT:
		var r := _one_fight(4600 + i, quiver)
		total_hits += int(r["hits"])
		total_bleeds += int(r["bleeds"])

	var observed := float(total_bleeds) / float(total_hits) if total_hits > 0 else 0.0
	print("seeds: %d" % SEED_COUNT)
	print("hits: %d" % total_hits)
	print("bleed applications: %d" % total_bleeds)
	print("observed rate: %.4f (stated chance: %.4f)" % [observed, chance])
	var within := absf(observed - chance) < 0.02
	print("within 2 points of stated chance: %s" % within)
	quit(0 if within else 1)
