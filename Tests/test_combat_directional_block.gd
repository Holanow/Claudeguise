extends "res://Tests/TestCase.gd"


## Issue 593: the Warrior's block names an ally, faces that ally's threat, and
## is spent by damage rather than by a clock. The arc mechanic itself is not
## tested here -- `test_combat_taunt_and_shield.gd` already owns it, and #593
## deliberately did not build a second one.

func _unit(id: int, team: CG.Team, hp: int, pos: Vector2) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.hp_max = hp
	u.hp = hp
	u.position = pos
	u.move_speed = 8.0
	return u

func _block() -> ActionDef:
	return Registry.get_action(&"warrior_block")

func _shot() -> ActionDef:
	var a := ActionDef.new()
	a.id = &"probe_shot"
	a.wind_up_ticks = 1
	a.recover_ticks = 1
	a.targeting = ActionTargeting.new()
	a.targeting.range_units = 9999.0
	a.delivery = ActionDelivery.new()
	a.delivery.speed = 20.0
	var hit := HitEffect.new()
	hit.damage_type = CG.DamageType.PHYSICAL
	a.effects = [hit] as Array[AbilityEffect]
	return a

## Every action this file uses, and a flat attack power so a hit is a known
## number rather than a roll.
func _deps(actions: Array[ActionDef], power: float) -> SimDeps:
	var by_id := {}
	for a in actions:
		by_id[a.id] = a
	var deps := SimDeps.new()
	deps.action_lookup = func(id: StringName): return by_id.get(id)
	deps.attack_power = func(_u, _a, _rng): return power
	deps.damage_reduction = func(_u): return 0.0
	deps.default_decide = func(_s: CombatState, _u: CombatUnit) -> Intent: return Intent.idle()
	return deps

# ---------------------------------------------------------------------------
# directional: it names an ally and shields the caster
# ---------------------------------------------------------------------------

## The whole point of `covers_target`. The row names somebody else; the shield
## goes up on the Warrior.
func test_the_block_shields_the_caster_not_the_ally_it_names() -> void:
	var block := _block()
	var deps := _deps([block], 0.0)
	var state := CombatState.new(1)
	var warrior := _unit(0, CG.Team.PLAYER, 100, Vector2.ZERO)
	warrior.actions = [block.id]
	var ally := _unit(1, CG.Team.PLAYER, 100, Vector2(60, 0))
	var foe := _unit(2, CG.Team.ENEMY, 100, Vector2(0, -300))
	state.units.append(warrior)
	state.units.append(ally)
	state.units.append(foe)

	warrior.intent = Intent.use_action(block.id, ally.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_true(warrior.has_status(CG.Status.SHIELDING), "the caster should be the one carrying the shield")
	assert_false(ally.has_status(CG.Status.SHIELDING), "the named ally must not be given the shield itself")

## And it turns to face that ally's nearest enemy, because `_find_shielder`
## only stops a shot the shielder is facing into. Without this the block is a
## status with no direction and the word "directional" means nothing.
func test_the_caster_turns_to_face_the_threat_to_the_ally() -> void:
	var block := _block()
	var deps := _deps([block], 0.0)
	var state := CombatState.new(2)
	var warrior := _unit(0, CG.Team.PLAYER, 100, Vector2.ZERO)
	warrior.actions = [block.id]
	warrior.facing = Vector2(1, 0)
	var ally := _unit(1, CG.Team.PLAYER, 100, Vector2(0, 400))
	## THE FIXTURE HAD TO BE BUILT TWICE. The first version put the ally and its
	## threat in the same direction from the Warrior, so "face the ally" and
	## "face the ally's threat" gave the same vector and the test passed with the
	## facing code deleted. The threat is now off-axis from the ally, so the two
	## answers are (0, 1) and (0.6, 0.8) and only one of them passes. The near
	## enemy is also nearer the ALLY than the Warrior, so "my own nearest enemy"
	## is a third distinct answer.
	var far_from_ally := _unit(2, CG.Team.ENEMY, 100, Vector2(100, 0))
	var near_the_ally := _unit(3, CG.Team.ENEMY, 100, Vector2(300, 400))
	state.units.append(warrior)
	state.units.append(ally)
	state.units.append(far_from_ally)
	state.units.append(near_the_ally)

	warrior.intent = Intent.use_action(block.id, ally.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_almost_eq(warrior.facing.x, 0.6, 0.001,
		"the Warrior should face the enemy next to the ally, not the ally itself, got %s" % warrior.facing)
	assert_almost_eq(warrior.facing.y, 0.8, 0.001,
		"the Warrior should face the enemy next to the ally, not the ally itself, got %s" % warrior.facing)

## The ally is a reference point, not a victim. Before this the block emitted a
## 0-damage DAMAGE event on the ally, which reads as the Warrior hitting it.
func test_covering_an_ally_does_not_damage_it() -> void:
	var block := _block()
	var deps := _deps([block], 12.0)
	var state := CombatState.new(3)
	var warrior := _unit(0, CG.Team.PLAYER, 100, Vector2.ZERO)
	warrior.actions = [block.id]
	var ally := _unit(1, CG.Team.PLAYER, 100, Vector2(60, 0))
	var foe := _unit(2, CG.Team.ENEMY, 100, Vector2(0, -300))
	state.units.append(warrior)
	state.units.append(ally)
	state.units.append(foe)

	warrior.intent = Intent.use_action(block.id, ally.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(ally.hp, ally.hp_max, "covering an ally must not hurt it")
	for e in state.events:
		assert_ne(e.kind, CG.EventKind.DAMAGE,
			"the block emitted a DAMAGE event, which the log renders as an attack on the covered ally")

# ---------------------------------------------------------------------------
# health instead of duration
# ---------------------------------------------------------------------------

## The pool is authored on the action, not derived from a hit.
func test_the_block_starts_with_the_health_its_action_declares() -> void:
	var block := _block()
	assert_true(block.status_magnitude > 0.0,
		"warrior_block carries no status_magnitude, so its shield has no health and #593 is not built")
	assert_true(block.covers_target, "warrior_block should name an ally rather than itself")

## A shield with no pool would be a shield with a timer wearing a new name.
func test_a_shielding_action_in_the_content_always_carries_health() -> void:
	var checked := 0
	for id in Registry.all_action_ids():
		var a := Registry.get_action(id)
		if a == null or not a.applies_status_enabled or a.applies_status != CG.Status.SHIELDING:
			continue
		checked += 1
		assert_true(a.status_magnitude > 0.0,
			"%s grants SHIELDING with no health pool, so nothing can ever break that shield" % id)
	assert_true(checked > 0, "no action grants SHIELDING at all, so this guard measures nothing")

## THE BACKSTOP, and it is a real requirement rather than a joke: an unbounded
## status is a stall risk and this repo has had tick-cap stalls. Long enough to
## outlast any fight, finite enough that nothing can run forever.
func test_the_duration_is_a_backstop_and_is_still_finite() -> void:
	var block := _block()
	assert_eq(block.status_duration_ticks, CG.MAX_TICKS,
		"the block's timer should be the fight's own budget: the whole fight, and not one tick more")
	assert_true(block.status_duration_ticks > 0, "an unbounded status is a stall waiting to happen")

## The pool is spent by the shot the shield STOPPED. This is the assertion the
## whole issue turns on.
func test_an_intercepted_shot_spends_the_shields_health() -> void:
	var block := _block()
	var shot := _shot()
	var deps := _deps([block, shot], 7.0)
	var state := CombatState.new(4)
	var shooter := _unit(0, CG.Team.ENEMY, 100, Vector2.ZERO)
	shooter.actions = [shot.id]
	var squishy := _unit(1, CG.Team.PLAYER, 100, Vector2(200, 0))
	var shielder := _unit(2, CG.Team.PLAYER, 100, Vector2(100, 0))
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.status_magnitude[CG.Status.SHIELDING] = 40.0
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(squishy.hp, squishy.hp_max, "the shot never reaches the unit it was aimed at")
	assert_eq(shielder.hp, shielder.hp_max,
		"the shield's health should have taken the whole hit, not the shielder's")
	assert_almost_eq(float(shielder.status_magnitude.get(CG.Status.SHIELDING, 0.0)), 33.0, 0.001,
		"40 health minus a 7-damage shot")

## Overflow reaches the health bar. A pool bigger than the hit absorbs it all; a
## pool smaller than the hit absorbs what it can and the rest still lands.
func test_a_hit_bigger_than_the_pool_lands_for_the_difference() -> void:
	var block := _block()
	var shot := _shot()
	var deps := _deps([block, shot], 30.0)
	var state := CombatState.new(5)
	var shooter := _unit(0, CG.Team.ENEMY, 100, Vector2.ZERO)
	shooter.actions = [shot.id]
	var squishy := _unit(1, CG.Team.PLAYER, 100, Vector2(200, 0))
	var shielder := _unit(2, CG.Team.PLAYER, 100, Vector2(100, 0))
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.status_magnitude[CG.Status.SHIELDING] = 10.0
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(shielder.hp, shielder.hp_max - 20, "10 soaked, 20 through")
	assert_false(shielder.has_status(CG.Status.SHIELDING), "a shield spent to nothing is gone")

## And it says so, once, when it breaks.
func test_a_spent_shield_announces_itself() -> void:
	var block := _block()
	var shot := _shot()
	var deps := _deps([block, shot], 30.0)
	var state := CombatState.new(6)
	var shooter := _unit(0, CG.Team.ENEMY, 100, Vector2.ZERO)
	shooter.actions = [shot.id]
	var squishy := _unit(1, CG.Team.PLAYER, 100, Vector2(200, 0))
	var shielder := _unit(2, CG.Team.PLAYER, 100, Vector2(100, 0))
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.status_magnitude[CG.Status.SHIELDING] = 10.0
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	var soaked := 0
	var expired := 0
	for e in state.events:
		if e.kind == CG.EventKind.SHIELD_ABSORBED:
			soaked += e.amount
		elif e.kind == CG.EventKind.STATUS_EXPIRED and e.status == CG.Status.SHIELDING:
			expired += 1
	assert_eq(soaked, 10, "the log must be able to say how much the shield ate")
	assert_eq(expired, 1, "exactly one break, so the player is told once rather than never or twice")

# ---------------------------------------------------------------------------
# the negative half
# ---------------------------------------------------------------------------

## THE NARROWING, and without this test the pool would quietly soak everything.
## Damage the shield did not intercept -- a melee blow to a shielder who is not
## in that shot's way -- must not spend it. Soaking everything measured out as
## two parties leaving The Warden with over 80% of their health.
func test_damage_the_shield_did_not_stop_does_not_spend_it() -> void:
	var block := _block()
	var melee := ActionDef.new()
	melee.id = &"probe_melee"
	melee.wind_up_ticks = 1
	melee.recover_ticks = 1
	melee.targeting = ActionTargeting.new()
	melee.targeting.range_units = 9999.0
	var melee_hit := HitEffect.new()
	melee_hit.damage_type = CG.DamageType.PHYSICAL
	melee.effects = [melee_hit] as Array[AbilityEffect]
	var deps := _deps([block, melee], 7.0)
	var state := CombatState.new(7)
	var attacker := _unit(0, CG.Team.ENEMY, 100, Vector2.ZERO)
	attacker.actions = [melee.id]
	var shielder := _unit(1, CG.Team.PLAYER, 100, Vector2(40, 0))
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.status_magnitude[CG.Status.SHIELDING] = 40.0
	shielder.facing = Vector2(-1, 0)
	state.units.append(attacker)
	state.units.append(shielder)

	attacker.intent = Intent.use_action(melee.id, shielder.id)
	for i in 10:
		CombatSim.step(state, deps)

	assert_eq(shielder.hp, shielder.hp_max - 7, "an unintercepted hit lands on the health bar as normal")
	assert_almost_eq(float(shielder.status_magnitude.get(CG.Status.SHIELDING, 0.0)), 40.0, 0.001,
		"the shield's health should be untouched by a blow it never stopped")

## And a shield with no pool at all is not silently immortal: it simply soaks
## nothing, which is what every fixture predating #593 models.
func test_a_shield_with_no_pool_soaks_nothing() -> void:
	var block := _block()
	var shot := _shot()
	var deps := _deps([block, shot], 7.0)
	var state := CombatState.new(8)
	var shooter := _unit(0, CG.Team.ENEMY, 100, Vector2.ZERO)
	shooter.actions = [shot.id]
	var squishy := _unit(1, CG.Team.PLAYER, 100, Vector2(200, 0))
	var shielder := _unit(2, CG.Team.PLAYER, 100, Vector2(100, 0))
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)

	assert_eq(shielder.hp, shielder.hp_max - 7,
		"with no pool the shielder takes the intercepted hit itself, exactly as it did before #593")
	assert_true(shielder.has_status(CG.Status.SHIELDING), "and nothing broke, because there was nothing to break")

# ---------------------------------------------------------------------------
# the log has to say which half was which
# ---------------------------------------------------------------------------

const LogScript := preload("res://Scripts/UI/CombatLogView.gd")

## As `_deps`, with damage reduction and a cause for it, so a hit is stopped by
## two different things at once.
func _deps_reduced(actions: Array[ActionDef], power: float, reduction: float) -> SimDeps:
	var deps := _deps(actions, power)
	deps.damage_reduction = func(_u): return reduction
	deps.damage_reduction_cause = func(_u): return CG.MitigationCause.ARMOR
	return deps

func _intercepted_hit(power: float, reduction: float, pool: float) -> CombatEvent:
	var block := _block()
	var shot := _shot()
	var deps := _deps_reduced([block, shot], power, reduction)
	var state := CombatState.new(9)
	var shooter := _unit(0, CG.Team.ENEMY, 100, Vector2.ZERO)
	shooter.actions = [shot.id]
	var squishy := _unit(1, CG.Team.PLAYER, 100, Vector2(200, 0))
	var shielder := _unit(2, CG.Team.PLAYER, 400, Vector2(100, 0))
	shielder.display_name = "Warrior"
	shielder.statuses[CG.Status.SHIELDING] = 999
	shielder.status_magnitude[CG.Status.SHIELDING] = pool
	shielder.facing = Vector2(-1, 0)
	state.units.append(shooter)
	state.units.append(squishy)
	state.units.append(shielder)

	shooter.intent = Intent.use_action(shot.id, squishy.id)
	for i in 20:
		CombatSim.step(state, deps)
	for e in state.events:
		if e.kind == CG.EventKind.DAMAGE:
			return e
	return null

func _gap(e: CombatEvent) -> String:
	return LogScript.gap_text(e)

## THE DEFECT THIS FILE EXISTS TO PIN. The pool sits inside the same
## raw-to-landed gap issue 344 built `mitigation_cause` to explain, so the two
## shares have to be carried separately or one cause is credited with both.
func test_the_event_separates_what_armor_stopped_from_what_the_shield_soaked() -> void:
	var e := _intercepted_hit(40.0, 0.5, 12.0)
	assert_not_null(e, "the intercepted shot must produce a damage event at all")
	assert_eq(e.amount_before_mitigation, 40, "raw roll")
	assert_eq(e.amount_absorbed, 12, "the pool was 12 and the shield ate all of it")
	assert_eq(e.amount_after_mitigation, 8, "20 survived the armor, 12 of that went on the shield")
	assert_eq(e.mitigation_cause, CG.MitigationCause.ARMOR,
		"the cause names the reduction share only, never the pool's")

func test_the_log_names_both_shares_with_their_own_numbers() -> void:
	var line := _gap(_intercepted_hit(40.0, 0.5, 12.0))
	assert_true(line.find("20 stopped by") >= 0, "half of 40 was reduction: %s" % line)
	assert_true(line.findn(LogScript.mitigation_cause_text(CG.MitigationCause.ARMOR)) >= 0,
		"and it is still named: %s" % line)
	assert_true(line.find("12 soaked by") >= 0, "the pool's share, separately: %s" % line)
	assert_true(line.findn(LogScript.mitigation_cause_text(CG.MitigationCause.RAISED_SHIELD)) >= 0,
		"named as the shield rather than as toughness: %s" % line)

## A shot the shield swallowed whole. `amount_after_mitigation` is genuinely 0
## here, which is also the sentinel `gap_text` reads as "never filled in".
func test_a_shot_the_shield_ate_entirely_is_still_credited_to_the_shield() -> void:
	var e := _intercepted_hit(10.0, 0.0, 40.0)
	assert_eq(e.amount, 0, "nothing reached the health bar")
	assert_eq(e.amount_absorbed, 10, "the shield took the lot")
	assert_eq(e.mitigation_cause, CG.MitigationCause.NONE,
		"no reduction happened, so naming one would be the lie")
	var line := _gap(e)
	assert_true(line.find("10 soaked by") >= 0, "the whole hit, on the shield: %s" % line)
	assert_true(line.findn(LogScript.mitigation_cause_text(CG.MitigationCause.ARMOR)) < 0,
		"armor did nothing here and must not be named: %s" % line)

## THE NEGATIVE. Every hit in the game that no shield touched must render
## exactly as it did before #593, or the fix is a regression wearing a fix's
## clothes.
func test_a_hit_no_shield_touched_reads_exactly_as_it_did_before() -> void:
	var e := CombatEvent.new()
	e.kind = CG.EventKind.DAMAGE
	e.amount_before_mitigation = 36
	e.amount_after_mitigation = 20
	e.amount = 3
	e.mitigation_cause = CG.MitigationCause.BLOCK
	var line := _gap(e)
	assert_eq(line, " (36 raw, 16 stopped by %s, 17 more than it had left)"
		% LogScript.mitigation_cause_text(CG.MitigationCause.BLOCK), line)
	assert_true(line.findn("soak") < 0, "nothing soaked anything: %s" % line)

## And the pool's word is its own, so a reader can tell the two shields apart.
func test_the_raised_shield_has_a_word_no_other_cause_uses() -> void:
	var word: String = LogScript.mitigation_cause_text(CG.MitigationCause.RAISED_SHIELD)
	assert_ne(word, "", "the cause must have a word at all")
	for cause in CG.MitigationCause.values():
		if cause == CG.MitigationCause.RAISED_SHIELD or cause == CG.MitigationCause.NONE:
			continue
		assert_ne(LogScript.mitigation_cause_text(cause), word,
			"%s shares its word with the raised shield" % CG.MitigationCause.keys()[cause])
