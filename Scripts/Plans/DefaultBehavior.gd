extends RefCounted

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const EnemyDef := preload("res://Scripts/Core/EnemyDef.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const Terrain := preload("res://Scripts/Core/Terrain.gd")
const PlanInterpreter := preload("res://Scripts/Plans/PlanInterpreter.gd")

## What a unit does when no plan fires. Every unit has this, including enemies,
## which have no plans at all in this slice.
##
## OWNER: teal.
##
## This is more load-bearing than it looks. A player is not expected to touch
## the plan system until late in the game per README.md, so the default
## behaviour is what most fights actually look like, and it is the thing being
## judged when the question is whether the combat is fun.
##
## Deliberately generic over pawns and enemies: it reads `unit.actions` and
## `unit.team` and nothing else class-specific, so the same logic drives a
## Warrior and a Grunt. "Ranged" is inferred from an action's own range rather
## than from ClassDef.style, because enemies have no ClassDef at all.

## An action with more range than this is treated as ranged: kept at, rather
## than closed to melee distance. Every melee action in this slice sits at
## 40-45 world units; every ranged one sits at 200+.
const MELEE_RANGE_THRESHOLD := 60.0

## A ranged unit closer than this fraction of its own range backs off instead
## of firing, so "ranged classes keep their distance" is an observable choice
## rather than an accident of where the fight started.
const KITE_RANGE_FRACTION := 0.6

## Range is checked when a hit lands, not when it commits (CombatSim's own
## rule), so firing right at the edge of range is a guaranteed whiff against
## anything that flees during the wind-up: it walks the small remaining
## distance to safety for free while the attacker stands there committed.
## Both branches below fire with a safety margin instead of at the literal
## boundary, which is what actually lets a faster melee unit run a kiter down
## instead of forever narrowly missing it.
const MELEE_COMMIT_FRACTION := 0.5
const RANGED_COMMIT_FRACTION := 0.85

## An ally at or below this fraction of max hp counts as needing a heal.
const HEAL_THRESHOLD_FRACTION := 0.5

const RETREAT_STEP := 200.0

static func decide(state: CombatState, unit: CombatUnit) -> Intent:
	var enemy_team := CG.Team.ENEMY if unit.team == CG.Team.PLAYER else CG.Team.PLAYER
	var enemies := state.living(enemy_team)
	if enemies.is_empty():
		return Intent.idle()

	var candidates := _actions_that_can_fire_now(state, unit)
	## Issue 214: nothing this unit carries can fire this tick, so fall back to
	## the whole list rather than idling. **The fallback is the half that keeps
	## this from being a regression**, and heron's own content comment on
	## `stalker_dart` is why it is here: a one-action enemy whose only action is
	## on cooldown must still kite, approach and retreat, and every one of those
	## branches below is reached through a chosen action. Filtering without this
	## would freeze it instead, which is a worse bug than the one being fixed.
	if candidates.is_empty():
		candidates = _all_actions(unit)
	if candidates.is_empty():
		return Intent.idle()

	# Issue 93: an action that may only be aimed at a MARKED enemy narrows the
	# candidate list before anything else looks at it, and a unit whose only
	# attacks are marked-only holds fire when nothing is marked.
	#
	# This, not the range change, is what the Siege Engine rebuild rests on. An
	# engine is a summon, so it has no plan at all and every decision it makes
	# arrives here. Filtering the candidates rather than vetoing after
	# `_choose_target` matters: the nearest enemy is usually not the marked one,
	# so a veto would make an engine idle beside a target it is allowed to shoot.
	#
	# Deliberately generic. It reads `ActionDef.requires_marked_target` and
	# nothing class-specific, the same way this file already infers "ranged" from
	# an action's own range rather than from a ClassDef -- a second unit with a
	# spotter is picked up for free. Every unit whose actions all leave the flag
	# false sees no change at all, which is every unit but one.
	if _all_attacks_require_a_mark(candidates):
		enemies = _only_marked(enemies)
		if enemies.is_empty():
			# Hold fire. Not `move_to`: the engine cannot move (move_speed 0.0)
			# and, more to the point, an artillery piece with no designated
			# target should sit silent rather than wander toward one.
			return Intent.idle()

	var heal_action := _first_heal(candidates)
	if heal_action != null:
		var neediest := _lowest_hp_fraction(_heal_candidates(state, unit, heal_action))
		if neediest != null and neediest.hp_fraction() <= HEAL_THRESHOLD_FRACTION:
			var dist_to_ally := unit.position.distance_to(neediest.position)
			if dist_to_ally <= heal_action.range_units:
				return Intent.use_action(heal_action.id, neediest.id)
			return Intent.move_to(neediest.position)

	var target := _choose_target(state, unit, enemies)
	if target == null:
		return Intent.idle()

	# Issue 62: picks a melee-vs-ranged action by the current target's actual
	# distance, rather than always the first non-heal entry in unit.actions.
	# Found while re-tuning after free basic attacks moved the floor-clear
	# table: The Warden carries both warden_axe (melee) and warden_chain_toss
	# (ranged, "chain for whoever does not [close]" per its own content
	# comment) specifically so a party that kites its slow move_speed still
	# has to answer something -- but axe being first in EnemyDef.actions
	# meant chain_toss never fired even once in a real fight, because the
	# old _first_non_heal always returned axe regardless of range. A unit
	# with only one non-heal action (every player, every other enemy in the
	# bestiary today) sees no behaviour change: _choose_attack_action
	# returns that single action exactly like _first_non_heal did.
	var attack_action := _choose_attack_action(candidates, unit, target)
	if attack_action == null:
		return Intent.idle()

	var dist := unit.position.distance_to(target.position)

	# Issue 93: a unit that cannot move does not kite and does not approach. It
	# fires if the target is in range and waits if it is not.
	#
	# **This is not a tidy-up, it is the bug that would have made the whole
	# artillery rebuild do nothing, and it was found by reasoning about the two
	# numbers together rather than by running it.** Both movement branches below
	# are fractions of the action's own range: a ranged unit retreats inside
	# `KITE_RANGE_FRACTION` (0.6) and approaches beyond `RANGED_COMMIT_FRACTION`
	# (0.85). Giving the Siege Engine ARENA_SPAN range makes those 720 and 1020
	# units, and the arena's own diagonal is 1101 -- so essentially every target
	# in the game sits inside the kite band, and an engine would have answered
	# every one of them with `move_to(_retreat_point(...))`. It has move_speed
	# 0.0, so that resolves to standing still, forever, without ever firing.
	# Unlimited range would have turned "never fires because it is out of range"
	# into "never fires because it thinks it is too close".
	#
	# Written against `move_speed` rather than against the Siege Engine, because
	# the defect is general: kiting and approaching are both statements about
	# where a unit intends to stand, and neither means anything to a unit that
	# cannot stand anywhere else. Nothing else in the game has move_speed 0.0,
	# so no existing behaviour changes.
	if unit.move_speed <= 0.0:
		if dist > attack_action.range_units:
			return Intent.idle()
		if attack_action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, target.position):
			return Intent.idle()
		return Intent.use_action(attack_action.id, target.id)

	var is_ranged := attack_action.range_units > MELEE_RANGE_THRESHOLD

	if is_ranged:
		# Issue 34: a flagged action whose line to the target is blocked has
		# nothing to gain from firing -- the resolve-time check would just
		# report the MISS this avoids committing to. Approaching is the same
		# fallback an out-of-range shot already gets; only actions that opted
		# into requires_line_of_sight are affected, so nothing unflagged
		# changes.
		if attack_action.requires_line_of_sight and Terrain.line_is_blocked(state.terrain, unit.position, target.position):
			return Intent.move_to(target.position)
		# PLAYTEST-NOTES-2.md note 11: "the Abomination runs away a lot...
		# tanks should move toward enemies." Root cause traced directly: with
		# no plan firing, `_choose_attack_action` picks `abomination_hook`
		# (range 140, so `is_ranged` here) the moment a target sits beyond
		# `abomination_grapple`'s own melee commit range -- and this branch
		# then treated a 140-range gap-closer exactly like a 200+-range
		# standoff weapon, backing off if the target ever closed inside 84
		# units (0.6 * 140) instead of letting it hold ground or finish
		# closing. Every real ranged action in the bestiary is a stay-at-
		# range weapon (bolts, arrows, blasts); a pull is the opposite by
		# construction -- it exists to drag a target closer, so a unit
		# firing one has nothing to protect by keeping its own distance.
		# `pull_distance > 0.0` is the same generic, action-level signal
		# `heals`/`requires_line_of_sight` already are: it needs no
		# ClassDef or role awareness, and no other action in the game sets
		# it today, so nothing else changes behaviour.
		var wants_to_close := attack_action.pull_distance > 0.0
		var kite_min := attack_action.range_units * KITE_RANGE_FRACTION
		var commit_max := attack_action.range_units * RANGED_COMMIT_FRACTION
		if dist < kite_min and not wants_to_close:
			return Intent.move_to(_retreat_point(unit, target))
		if dist > commit_max:
			return Intent.move_to(target.position)
		return Intent.use_action(attack_action.id, target.id)

	var commit_max_melee := attack_action.range_units * MELEE_COMMIT_FRACTION
	if dist > commit_max_melee:
		return Intent.move_to(target.position)
	return Intent.use_action(attack_action.id, target.id)

# ---------------------------------------------------------------------------

## Issue 93: true only when the unit has at least one attack and *every* one of
## them requires a marked target. "Every", not "any", on purpose -- a unit that
## also carries an ordinary weapon should use that weapon on unmarked enemies
## rather than standing idle, and only a unit whose whole arsenal is
## marked-only has a reason to hold fire. The Siege Engine is the one unit in
## the game with a single action, and that action is marked-only.
##
## Heals are excluded because `_first_heal` handles them on its own path above
## and an ally is never a marked-target candidate.
static func _all_attacks_require_a_mark(actions: Array[ActionDef]) -> bool:
	var found := false
	for a in _attack_candidates(actions):
		if not a.requires_marked_target:
			return false
		found = true
	return found

static func _only_marked(enemies: Array[CombatUnit]) -> Array[CombatUnit]:
	var out: Array[CombatUnit] = []
	for e in enemies:
		if e.has_status(CG.Status.MARKED):
			out.append(e)
	return out

## Every action the unit carries. **This used to be called `_usable_actions` and
## the name was a claim it did not make**, which is heron's finding in #214 and
## it cost content real work: they wrote `stalker_dart` as the Stalker's
## off-cooldown filler, relied on the word *usable*, and the dart fired zero
## times in 480 fights.
static func _all_actions(unit: CombatUnit) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for id in unit.actions:
		var a: ActionDef = Registry.get_action(id)
		if a != null:
			out.append(a)
	return out

## The actions `CombatSim._resolve_use_action` would actually let this unit
## start on this tick: affordable, and off cooldown.
##
## **Issue 214, and it is issue 22's fall-through bug on the enemy side.**
## `PlanInterpreter` has refused an unaffordable or cooling action since issue 22,
## so a *pawn's* plan falls through to the next one. Nothing did that here, so a
## unit with no plans -- every enemy in the game -- chose its first attack whether
## or not it could be started, `CombatSim` refused it at the cost/cooldown gate,
## and **the tick was spent**. `stalker_mark` carries a 60-tick cooldown and sits
## first in the Stalker's list, so `stalker_dart` underneath it was never
## consulted once.
##
## The predicate is `PlanInterpreter.can_afford` rather than a copy of its four
## lines: two copies of one gate is how the plan path and the fallback path drift
## into disagreeing about what a unit may do, which is the same argument
## `default_attack_action` below is public for.
##
## **#214's premise is right about the cause and wrong about who pays, and the
## correction is the larger half.** It reads *"issue 22's bug on the enemy side"*,
## and the Stalker is where it was found -- but counted over 480 fights, every
## encounter, all five buildable parties, this filter changes what gets chosen on
## **1,376 of 498,449 non-pawn decisions (0.3%)** and on **63,335 of 138,450 pawn
## decisions.** The player's own pawns were the main victim by a factor of forty.
##
##     what changed              pawns    non-pawns
##     the heal chosen          35,933            0
##     the attack chosen        27,402        1,376   <- the Stalker
##     decisions in total      138,450      498,449
##
## **The heal column is the one to read, and it is a worse bug than the dart.**
## `_first_heal` picks by list order and asked nothing about cost, so a Priest
## with too little Mana answered a hurt ally by committing to a heal `CombatSim`
## then refused -- or, when the ally was out of reach, by **walking toward it to
## cast a spell it could not pay for**, every tick, instead of fighting. Both
## columns exclude any decision the plan layer handled: pawns reach this file only
## when no plan fires.
##
## Non-pawn covers summons as well as enemies; `unit.pawn == null` is the split.
static func _actions_that_can_fire_now(state: CombatState, unit: CombatUnit) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for a in _all_actions(unit):
		if PlanInterpreter.can_afford(state, unit, a.id):
			out.append(a)
	return out

## Issue 87: `power_scale > 0.0` as well as `heals`, because this function
## answers "do I have a way to put health back into a hurt ally" and an action
## that restores nothing is not one. `geyser_cleanse` is the first action in the
## game with `heals = true` and no healing in it -- the flag is what routes it
## through `_apply_action_effect`'s heal branch, so it emits no DAMAGE event at
## an ally, not a claim that it heals.
##
## Without this the Geysermancer answers every ally below
## HEAL_THRESHOLD_FRACTION by casting a 0-power heal, or by walking toward that
## ally to get in range to cast one, instead of attacking -- a real behaviour
## change for a class that had no heal at all, arriving from a support action
## that has nothing to do with hp. Nothing else in the game changes: priest_heal
## is the only other action with `heals` set and its power_scale is well above 0.
static func _first_heal(actions: Array[ActionDef]) -> ActionDef:
	for a in actions:
		if a.heals and a.power_scale > 0.0:
			return a
	return null

## Issue 99: a heal with no reach is a heal a unit casts on itself, so the
## neediest-ally search is restricted to the caster.
##
## `warrior_second_wind` is the first zero-range heal in the game and without
## this the Warrior is actively broken by carrying it: `_lowest_hp_fraction`
## searches the whole team, so the moment any ally drops below the threshold the
## Warrior returns `move_to(that ally)` every tick, trying to close a distance
## that can never be small enough, and stops fighting entirely. It would not
## have failed loudly -- a tank that walks toward its hurt healer looks almost
## deliberate on screen.
##
## Reads `range_units` rather than a new flag, because zero range already means
## exactly this and every other heal in the game states a real reach
## (`priest_heal` 220, `geyser_cleanse` 200). Nothing else changes behaviour.
static func _heal_candidates(state: CombatState, unit: CombatUnit, heal_action: ActionDef) -> Array[CombatUnit]:
	if heal_action.range_units > 0.0:
		return state.living(unit.team)
	var out: Array[CombatUnit] = []
	if unit.alive:
		out.append(unit)
	return out

## Issue 129: an action a unit attacks *with*. Not a heal, and able to do damage
## at all.
##
## `power_scale > 0.0` is the same rule `_first_heal` above already applies in
## the other direction, and it is what makes the choice below independent of
## list order. Guard, Taunt, Directional Block, Haste, Ward and Build Siege
## Engine all deal no damage: each is a real action, none of them is a way to
## attack somebody, and a unit that "attacked" with one would stand in place
## casting a self-buff at an enemy forever.
##
## Inert on the content that existed before issue 129, checked action by action:
## every unit's first non-heal entry already had power_scale > 0.0, so the same
## action is chosen. It stops being inert the moment a class's free attack comes
## off its list and onto its weapon, which is exactly when a zero-power action
## would otherwise have inherited the fallback.
## Issue 219: a sustained action is excluded too, and it is the same rule as the
## two above rather than a new one -- "a way to attack somebody" is a thing that
## resolves, and a channel is a thing that is *held*.
##
## It is CLAUDE.md's pawn-behaviour principle, at the one place that can violate
## it. `_cheapest` picks by cost, `abomination_immolate` costs 1 Rage to light
## and Hook and Grapple cost 15 and 20, so an Abomination whose Sickle came off
## would fall back to lighting a channel -- for a reason written in no plan, on a
## screen with nowhere to change it, burning the Rage its own kit runs on. The
## fallback layer also has no way to *stop* one deliberately: it re-picks the
## cheapest attack every tick, so it would re-affirm the channel forever.
##
## Inert on every action that existed before this one: `sustain_cost_per_tick` is
## 0 on all of them, which is what issue 61 built it as.
static func _attack_candidates(actions: Array[ActionDef]) -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for a in actions:
		if a.heals or a.power_scale <= 0.0 or a.sustain_cost_per_tick > 0:
			continue
		out.append(a)
	return out

## The cheapest of `actions`, ties broken by list order. Null on an empty array.
##
## **This is the rule that replaces "whatever is first in the list", and that
## rule is why three sessions lost time.** `geyser_spout` had to be *placed
## first* to work; `warden_chain_toss` never fired for the same reason; every
## class comment in `starting_classes.gd` used to carry a paragraph explaining
## the ordering. None of it survives a basic attack that arrives from an item,
## because `Registry.actions_for_pawn` appends equipment grants last and
## `CombatSim` builds the same union the same way.
##
## Cost, not position, because in this game a basic attack *is* the free one:
## `resource_cost == 0` is what every one of Strike, Bolt, Spout, Shot and Claw
## has in common, and what Execute, Smite, Blast, Hook and Spotter's Mark do
## not. A pawn falls back to the thing it can always pay for and reaches the
## expensive ability through a plan, which is where the player can see it.
##
## Behaviour-identical on today's content: in every bucket where a unit has more
## than one attack, the free one already sat first. The Warden's two actions are
## both free and in different buckets, so it is untouched.
static func _cheapest(actions: Array[ActionDef]) -> ActionDef:
	var best: ActionDef = null
	for a in actions:
		if best == null or a.resource_cost < best.resource_cost:
			best = a
	return best

## The attack this fallback would reach for on one side of
## `MELEE_RANGE_THRESHOLD`, or null when it owns none on that side.
##
## **Public on purpose, and it is the fix for a drift that has already happened
## twice on this project.** `Scripts/UI/InspectPanel.gd` draws the immutable
## "default row" that tells a player what a pawn does when no plan fires -- issue
## 98's principle in its most direct form -- and it did that by keeping its own
## copy of this rule, written as "the first non-heal action on the requested
## side, in list order". A copy of a rule is a copy that goes stale: the same
## shape put `starting_actions` in the plan editor and `starting_actions plus
## equipment` in the fight (issue 100), and this is the one shared function that
## made those two agree again. One definition, two callers.
static func default_attack_action(actions: Array[ActionDef], want_ranged: bool) -> ActionDef:
	var side: Array[ActionDef] = []
	for a in _attack_candidates(actions):
		if (a.range_units > MELEE_RANGE_THRESHOLD) == want_ranged:
			side.append(a)
	return _cheapest(side)

## Issue 62: among a unit's attacks, prefers whichever one's own melee-vs-ranged
## shape matches the target's current distance -- melee if already (or almost)
## in a melee action's own commit range, ranged otherwise. With only one side
## present it uses that side. The Warden is still the only unit in the game
## carrying both a melee and a ranged attack.
static func _choose_attack_action(actions: Array[ActionDef], unit: CombatUnit, target: CombatUnit) -> ActionDef:
	var melee := default_attack_action(actions, false)
	var ranged := default_attack_action(actions, true)
	if melee == null:
		return ranged
	if ranged == null:
		return melee
	var dist := unit.position.distance_to(target.position)
	if dist <= melee.range_units * MELEE_COMMIT_FRACTION:
		return melee
	return ranged

## TAUNTING forces target *selection*, not what a unit does after choosing --
## a taunted unit still uses its own approach/kite/commit logic against the
## taunter, it just picks the taunter as its candidate up front, the same way
## it would pick anyone else. Checked before the focus_bias logic below, and
## unconditionally (both pawns and enemies can be taunted).
##
## This lives here rather than in CombatSim on purpose: CombatSim's
## _decide_phase only calls DefaultBehavior.decide() once PlanInterpreter has
## already had its turn and produced nothing, so a real Plan's explicit
## targeting is never touched by this -- not because of a check, but because
## this function simply never runs when a plan fired. Per rook's ruling: taunt
## overrides the *default* fallback, never a stated plan.
##
## Issue 7's concentration finding: numbers and a stat spread raise total
## damage but not concentrated damage, because every enemy independently
## picked its own nearest pawn. `EnemyDef.focus_bias` (0.0-1.0, pawns do not
## have one) is this unit's chance of joining whichever living enemy its own
## allies are already committed to, rather than defaulting to nearest. Rolled
## from state.rng, never a fresh generator, so a seed still reproduces a
## fight exactly.
static func _choose_target(state: CombatState, unit: CombatUnit, enemies: Array[CombatUnit]) -> CombatUnit:
	var taunter := _nearest_taunter(unit, enemies)
	if taunter != null:
		return taunter
	var nearest := _nearest(unit, enemies)
	if unit.pawn != null:
		return nearest
	var enemy_def: EnemyDef = Registry.get_enemy(unit.enemy_id)
	if enemy_def == null or enemy_def.focus_bias <= 0.0:
		return nearest
	var focused := _most_focused(state, unit, enemies)
	if focused == null:
		return nearest
	return focused if state.rng.randf() < enemy_def.focus_bias else nearest

## **Issue 132 asked whether this should go, now that `CombatSim._decide_phase`
## compels a TAUNTED unit outright. It stays, and the reason is a real
## behavioural gap rather than caution.**
##
## The two are keyed on different things. The compulsion reads **TAUNTED**, which
## `_apply_taunt` stamps on everyone inside the radius **at the moment the taunt
## is cast**. This reads **TAUNTING**, which sits on the taunter for the whole
## duration. So a unit that walks *into* the radius after the cast is never
## TAUNTED and the compulsion does not see it at all; this is the only thing that
## makes it prefer the taunter.
##
## That is a seam, not a duplicate: the hard mechanism covers who was there when
## the shout went up, the soft one covers who arrives during it. **swift: if you
## want the compulsion to own both, it needs to re-stamp TAUNTED per tick on
## radius membership -- the shape `_tick_hazards` already uses -- and then this
## can go. That is your call and a behaviour change, so I have not made it.**
##
## Also checked rather than assumed, and it is the more interesting half:
## `EnemyDef.spawn_taunt_radius` -- the permanent aura this function was
## originally written for -- **is set by no enemy in the game.** `_enemy()` in
## `core_actions.gd` does not even take the parameter. So that field and the
## `CombatSim` branch that reads it are a matched unreachable pair, and heron's
## Brute comment explains why nobody wants it: at `CG.MAX_TICKS` it is exactly
## the permanent lock the player's #58 ruling forbids. rook, that is worth an
## issue -- a Core field, a sim branch and a doc comment describing a mechanism
## no content can reach.
##
## The nearest living, opposing candidate carrying TAUNTING whose own
## taunt_radius reaches `unit` -- null when nobody taunting is in range,
## the natural "taunt does not apply" case. Deterministic: iterates the same
## `enemies` array `_nearest` already does, first strictly-closer candidate
## wins, no tie-break needed beyond iteration order.
static func _nearest_taunter(unit: CombatUnit, enemies: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for e in enemies:
		if not e.has_status(CG.Status.TAUNTING):
			continue
		var d := unit.position.distance_to(e.position)
		if d > e.taunt_radius:
			continue
		if d < best_dist:
			best_dist = d
			best = e
	return best

## The living enemy candidate that the most of `unit`'s own living allies
## currently have as their focus_id -- "already being attacked", read from the
## same field CombatSim sets whenever an ally's action resolves. Null when
## nobody has focused on any candidate yet, which is the natural "no pile
## exists to join" case.
static func _most_focused(state: CombatState, unit: CombatUnit, candidates: Array[CombatUnit]) -> CombatUnit:
	var counts := {}
	for ally in state.living(unit.team):
		if ally.focus_id != -1:
			counts[ally.focus_id] = int(counts.get(ally.focus_id, 0)) + 1
	var best: CombatUnit = null
	var best_count := 0
	for c in candidates:
		var n := int(counts.get(c.id, 0))
		if n > best_count:
			best_count = n
			best = c
	return best

static func _nearest(unit: CombatUnit, others: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_dist := INF
	for o in others:
		var d := unit.position.distance_to(o.position)
		if d < best_dist:
			best_dist = d
			best = o
	return best

static func _lowest_hp_fraction(units: Array[CombatUnit]) -> CombatUnit:
	var best: CombatUnit = null
	var best_fraction := INF
	for u in units:
		var f := u.hp_fraction()
		if f < best_fraction:
			best_fraction = f
			best = u
	return best

static func _retreat_point(unit: CombatUnit, threat: CombatUnit) -> Vector2:
	var away := unit.position - threat.position
	if away.length() < 0.0001:
		away = Vector2(1.0, 0.0)
	return unit.position + away.normalized() * RETREAT_STEP
