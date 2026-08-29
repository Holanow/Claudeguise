extends "res://Tests/TestCase.gd"


## Issue 632: an item changes an ability's shape for abilities it did not
## author. The player's three examples: every projectile spell throws an extra
## bolt, everything hits harder, all fire damage also poisons.
##
## The trap this file exists to pin, and I walked into it once already in the
## other project: **match on the damage the action actually deals, never on a
## label beside it.** A modifier keyed to a tag while damage routes through a
## different field is two spellings of one idea with only one of them true, and
## nothing in the game can catch it.

## `ActionDef.damage_type` is a GETTER derived from the first HitEffect, so
## assigning it does nothing at all -- silently, which is wren's #621 finding
## and the reason the first version of this file failed. The damage type has
## to be set where the damage actually lives.
func _hit(dt: CG.DamageType) -> HitEffect:
	var h := HitEffect.new()
	h.damage_type = dt
	h.power_scale = 1.0
	return h

func _projectile_action(dt: CG.DamageType) -> ActionDef:
	var a := ActionDef.new()
	a.id = &"probe_bolt"
	a.effects = [_hit(dt)] as Array[AbilityEffect]
	a.delivery = ActionDelivery.new()
	a.delivery.speed = 16.0
	a.delivery.count = 1
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 999.0
	return a

func _melee_action(dt: CG.DamageType) -> ActionDef:
	var a := ActionDef.new()
	a.id = &"probe_swing"
	a.effects = [_hit(dt)] as Array[AbilityEffect]
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 40.0
	return a

func _item_with(mod: AbilityModifier) -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = &"probe_item"
	e.modifiers = [mod] as Array[AbilityModifier]
	return e

func _armed(mod: AbilityModifier) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = 0
	u.team = CG.Team.PLAYER
	u.hp = 40
	u.hp_max = 40
	u.pawn = PawnData.new()
	if mod != null:
		u.pawn.main_hand = _item_with(mod)
	return u


## Every projectile spell throws one more, and nothing else does.
func test_an_item_adds_a_projectile_to_projectile_actions_only() -> void:
	var mod := AbilityModifier.new()
	mod.only_projectiles = true
	mod.target_count_bonus = 1
	var unit := _armed(mod)
	assert_eq(AbilityModifiers.extra_targets(unit, _projectile_action(CG.DamageType.FIRE)), 1,
		"a projectile action gains the bolt")
	assert_eq(AbilityModifiers.extra_targets(unit, _melee_action(CG.DamageType.FIRE)), 0,
		"a melee action has no delivery and must not gain one")


## The negative half. Without it the test above proves the plumbing runs, not
## that the filter decides anything.
func test_an_unarmed_unit_is_unmodified() -> void:
	var bare := _armed(null)
	assert_eq(AbilityModifiers.extra_targets(bare, _projectile_action(CG.DamageType.FIRE)), 0)
	assert_eq(AbilityModifiers.power_multiplier(bare, _projectile_action(CG.DamageType.FIRE)), 1.0)
	assert_eq(AbilityModifiers.added_statuses(bare, _projectile_action(CG.DamageType.FIRE)).size(), 0)


## An enemy has no pawn and therefore no equipment. This is the path every
## enemy in the game takes, so it must be the unmodified one.
func test_an_enemy_carries_no_modifiers() -> void:
	var goblin := CombatUnit.new()
	goblin.id = 1
	goblin.team = CG.Team.ENEMY
	assert_eq(AbilityModifiers.of(goblin).size(), 0)
	assert_eq(AbilityModifiers.power_multiplier(goblin, _projectile_action(CG.DamageType.FIRE)), 1.0)


## THE TRAP. The filter must read the damage the action deals, so an item keyed
## to fire must not touch a physical action -- and must go quiet the moment the
## same action's damage type changes.
func test_a_damage_type_filter_matches_the_damage_actually_dealt() -> void:
	var mod := AbilityModifier.new()
	mod.any_damage_type = false
	mod.only_damage_type = CG.DamageType.FIRE
	mod.adds_status_enabled = true
	mod.adds_status = CG.Status.POISON
	mod.adds_status_ticks = 30
	var unit := _armed(mod)

	assert_eq(AbilityModifiers.added_statuses(unit, _melee_action(CG.DamageType.FIRE)).size(), 1,
		"fire damage picks up the item's poison")
	assert_eq(AbilityModifiers.added_statuses(unit, _melee_action(CG.DamageType.PHYSICAL)).size(), 0,
		"the SAME action dealing physical must not: the filter reads the damage, not a label")


## Issue 746: `adds_status_chance` defaults to 1.0, so every modifier authored
## before the field existed still reads as unconditional.
func test_adds_status_chance_defaults_to_certain() -> void:
	var mod := AbilityModifier.new()
	mod.adds_status_enabled = true
	mod.adds_status = CG.Status.BLEED
	mod.adds_status_ticks = 45
	var unit := _armed(mod)
	var out := AbilityModifiers.added_statuses(unit, _melee_action(CG.DamageType.PHYSICAL))
	assert_eq(out.size(), 1)
	assert_almost_eq(float(out[0]["chance"]), 1.0, 0.0001)


## And a quiver-shaped modifier reports its own chance rather than the default.
func test_added_statuses_reports_the_modifiers_own_chance() -> void:
	var mod := AbilityModifier.new()
	mod.adds_status_enabled = true
	mod.adds_status = CG.Status.BLEED
	mod.adds_status_ticks = 45
	mod.adds_status_chance = 0.25
	var unit := _armed(mod)
	var out := AbilityModifiers.added_statuses(unit, _melee_action(CG.DamageType.PHYSICAL))
	assert_almost_eq(float(out[0]["chance"]), 0.25, 0.0001)


## Issue 746: the chance draw comes from `state.rng`, so a seed must reproduce
## it. A modifier with a mid-range chance (0.5, not 1.0 or 0.0) makes the draw
## actually decide something rather than always landing the same way.
func test_two_runs_of_one_seed_draw_the_status_chance_identically() -> void:
	var mod := AbilityModifier.new()
	mod.adds_status_enabled = true
	mod.adds_status = CG.Status.BLEED
	mod.adds_status_ticks = 45
	mod.adds_status_chance = 0.5

	var action := _melee_action(CG.DamageType.PHYSICAL)
	action.id = &"probe_swing"

	var results: Array[int] = []
	for _run in 2:
		var caster := _armed(mod)
		caster.actions = [action.id]
		caster.hp_max = 999999
		caster.hp = caster.hp_max
		caster.resource_max = 999999
		caster.resource = 999999
		var target := CombatUnit.new()
		target.id = 1
		target.team = CG.Team.ENEMY
		target.hp_max = 999999
		target.hp = target.hp_max
		target.position = Vector2(20.0, 0.0)
		caster.facing = Vector2.RIGHT

		var state := CombatState.new(9001)
		state.units = [caster, target]

		var deps := SimDeps.new()
		deps.action_lookup = func(id: StringName) -> ActionDef: return action if id == action.id else null
		deps.default_decide = func(_s: CombatState, u: CombatUnit) -> Intent:
			return Intent.use_action(action.id, target.id) if u.id == caster.id else null
		deps.attack_power = func(_u: CombatUnit, _a: ActionDef, _r: RandomNumberGenerator) -> float: return 20.0

		for _t in 40:
			CombatSim.step(state, deps)

		var applications := 0
		for e in state.events:
			if e.kind == CG.EventKind.STATUS_APPLIED and e.status == CG.Status.BLEED:
				applications += 1
		results.append(applications)

	assert_eq(results[0], results[1], "same seed must draw the same chance the same way every time")


## Two modifiers on two items compose rather than one winning.
func test_two_items_stack() -> void:
	var a := AbilityModifier.new()
	a.target_count_bonus = 1
	a.power_multiplier = 2.0
	var b := AbilityModifier.new()
	b.target_count_bonus = 2
	b.power_multiplier = 1.5

	var unit := _armed(a)
	unit.pawn.body = _item_with(b)
	var action := _projectile_action(CG.DamageType.FIRE)
	assert_eq(AbilityModifiers.extra_targets(unit, action), 3, "bonuses add")
	assert_eq(AbilityModifiers.power_multiplier(unit, action), 3.0, "multipliers multiply")
