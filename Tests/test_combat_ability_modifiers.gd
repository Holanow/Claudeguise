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
