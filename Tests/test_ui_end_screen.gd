extends "res://Tests/TestCase.gd"


## Issue 552: the post-fight roster. The tally is static and takes a
## `CombatState`, so most of this needs no viewport -- which is the point of
## keeping it out of the node.

const EndScreenScript := preload("res://Scripts/UI/EndScreen.gd")
const BattleScene := preload("res://Scenes/Battle.tscn")

func _battle_view() -> Node2D:
	var view = in_tree(BattleScene.instantiate())
	view._ready()
	return view

func _pawn_unit(id: int, class_id: StringName, hp: int = 100) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = CG.Team.PLAYER
	u.pawn = PawnFactory.make_starter_pawn(class_id, StringName("p%d" % id), "P%d" % id)
	u.display_name = "P%d" % id
	u.hp_max = hp
	u.hp = hp
	return u

func _enemy_unit(id: int, team: CG.Team = CG.Team.ENEMY) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.enemy_id = &"goblin"
	u.display_name = "E%d" % id
	u.hp_max = 40
	u.hp = 40
	return u

func _damage(tick: int, source: int, target: int, amount: int) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.DAMAGE, tick)
	e.source_id = source
	e.target_id = target
	e.amount = amount
	return e

func _state() -> CombatState:
	return CombatState.new(0)


## The plain case, and the one the player asked for: who dealt the most and who
## took the most, both read off DAMAGE events alone.
func test_the_tally_counts_damage_dealt_and_taken_per_pawn() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	s.units.append(_pawn_unit(1, &"priest"))
	s.units.append(_enemy_unit(2))
	s.events.append(_damage(1, 0, 2, 12))
	s.events.append(_damage(2, 0, 2, 8))
	s.events.append(_damage(3, 2, 1, 5))
	s.events.append(_damage(4, 2, 0, 3))

	var rows := EndScreenScript.tally(s)
	assert_eq(rows.size(), 2, "one row per party pawn, and none for the enemy")
	assert_eq(int(rows[0]["dealt"]), 20)
	assert_eq(int(rows[0]["taken"]), 3)
	assert_eq(int(rows[1]["dealt"]), 0)
	assert_eq(int(rows[1]["taken"]), 5)


## The negative half. A tally that only ever counts up passes on a stream that
## says nothing, so this asserts it reads zero rather than inventing a number.
func test_a_pawn_that_did_nothing_reads_zero_on_both_columns() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	var rows := EndScreenScript.tally(s)
	assert_eq(rows.size(), 1)
	assert_eq(int(rows[0]["dealt"]), 0)
	assert_eq(int(rows[0]["taken"]), 0)
	assert_eq(int(rows[0]["by_summons"]), 0)
	assert_true(bool(rows[0]["alive"]))
	assert_eq(int(rows[0]["died_tick"]), -1)


## Attribution question one. A DOT tick carries no `action_id` and the applier
## as `source_id`, because `CombatSim._tick_dot_statuses` reads `status_source`.
## So a poison tick credits whoever applied it, and no rule had to be invented.
func test_a_status_tick_credits_whoever_applied_the_status() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"geysermancer"))
	s.units.append(_enemy_unit(1))
	var tick := _damage(9, 0, 1, 4)
	tick.action_id = &""
	tick.status = CG.Status.POISON
	s.events.append(tick)
	var rows := EndScreenScript.tally(s)
	assert_eq(int(rows[0]["dealt"]), 4,
		"a poison tick names its author on the event; the roster must read it")


## The other side of the same rule: terrain emits `source_id` -1, so a Burn Pit
## belongs to nobody. It still counts as damage taken.
func test_terrain_damage_is_taken_by_somebody_and_dealt_by_nobody() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	s.units.append(_pawn_unit(1, &"priest"))
	s.events.append(_damage(4, -1, 0, 7))
	var rows := EndScreenScript.tally(s)
	assert_eq(int(rows[0]["taken"]), 7)
	assert_eq(int(rows[0]["dealt"]), 0, "nobody dealt the fire's damage")
	assert_eq(int(rows[1]["dealt"]), 0)


## Attribution question two. A Siege Engine is EnemyDef-backed and belongs to
## the player: its damage is the Siege Master's at one remove. Counted for the
## summoner AND reported separately, because zero would be wrong and silently
## absorbing it would be wrong differently.
func test_a_summons_damage_counts_for_its_summoner_and_is_named_separately() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"siege_master"))
	s.units.append(_enemy_unit(1, CG.Team.PLAYER))
	s.units.append(_enemy_unit(2))
	var summoned := CombatEvent.make(CG.EventKind.SUMMONED, 5)
	summoned.source_id = 0
	summoned.target_id = 1
	s.events.append(summoned)
	s.events.append(_damage(6, 0, 2, 10))
	s.events.append(_damage(7, 1, 2, 25))

	var rows := EndScreenScript.tally(s)
	assert_eq(rows.size(), 1, "the engine is not a pawn and gets no card of its own")
	assert_eq(int(rows[0]["dealt"]), 35, "its own 10 plus the engine's 25")
	assert_eq(int(rows[0]["by_summons"]), 25)
	assert_true(EndScreenScript._dealt_text(rows[0]).contains("25"),
		"the engine's share has to be visible, not absorbed: %s" % EndScreenScript._dealt_text(rows[0]))


## A summon of a summon still lands on the pawn. Nothing does this today, which
## is exactly why it is asserted rather than assumed.
func test_summon_ownership_resolves_through_a_chain() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"siege_master"))
	s.units.append(_enemy_unit(1, CG.Team.PLAYER))
	s.units.append(_enemy_unit(2, CG.Team.PLAYER))
	s.units.append(_enemy_unit(3))
	for pair in [[0, 1], [1, 2]]:
		var e := CombatEvent.make(CG.EventKind.SUMMONED, 5)
		e.source_id = pair[0]
		e.target_id = pair[1]
		s.events.append(e)
	s.events.append(_damage(8, 2, 3, 9))
	var rows := EndScreenScript.tally(s)
	assert_eq(int(rows[0]["dealt"]), 9)
	assert_eq(int(rows[0]["by_summons"]), 9)


## Attribution question three. `amount` is what landed after the clamp, so a
## blow for 40 into a pawn with 3 left is 3 on both columns and the party's
## dealt total reconciles against the enemies' taken total.
func test_overkill_is_not_credited_so_the_two_columns_reconcile() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	s.units.append(_pawn_unit(1, &"priest", 3))
	var killing := _damage(11, 0, 1, 3)
	killing.amount_after_mitigation = 40
	s.events.append(killing)
	var rows := EndScreenScript.tally(s)
	assert_eq(int(rows[0]["dealt"]), 3, "the roster shows what landed, not what was rolled")
	assert_eq(int(rows[1]["taken"]), 3)


func test_a_death_is_recorded_with_the_tick_it_happened_on() -> void:
	var s := _state()
	var dead := _pawn_unit(0, &"priest")
	dead.alive = false
	dead.hp = 0
	s.units.append(dead)
	var death := CombatEvent.make(CG.EventKind.DEATH, 88)
	death.target_id = 0
	s.events.append(death)
	var rows := EndScreenScript.tally(s)
	assert_false(bool(rows[0]["alive"]))
	assert_eq(int(rows[0]["died_tick"]), 88)
	assert_true(EndScreenScript._fate_text(rows[0]).contains("Died"),
		"got %s" % EndScreenScript._fate_text(rows[0]))


func test_sorting_orders_by_the_column_asked_for_highest_first() -> void:
	var rows: Array[Dictionary] = [
		{"unit_id": 0, "dealt": 10, "taken": 90},
		{"unit_id": 1, "dealt": 50, "taken": 10},
		{"unit_id": 2, "dealt": 30, "taken": 40},
	]
	var by_dealt := EndScreenScript.sorted_rows(rows, EndScreenScript.SortBy.DEALT)
	assert_eq([int(by_dealt[0]["unit_id"]), int(by_dealt[1]["unit_id"]), int(by_dealt[2]["unit_id"])], [1, 2, 0])
	var by_taken := EndScreenScript.sorted_rows(rows, EndScreenScript.SortBy.TAKEN)
	assert_eq([int(by_taken[0]["unit_id"]), int(by_taken[1]["unit_id"]), int(by_taken[2]["unit_id"])], [0, 2, 1])


## A tie must not shuffle under a player reading the screen.
func test_a_tie_keeps_the_partys_own_order() -> void:
	var rows: Array[Dictionary] = [
		{"unit_id": 2, "dealt": 7, "taken": 0},
		{"unit_id": 0, "dealt": 7, "taken": 0},
		{"unit_id": 1, "dealt": 7, "taken": 0},
	]
	var sorted := EndScreenScript.sorted_rows(rows, EndScreenScript.SortBy.DEALT)
	assert_eq([int(sorted[0]["unit_id"]), int(sorted[1]["unit_id"]), int(sorted[2]["unit_id"])], [0, 1, 2])


## Against a real fight rather than a hand-built stream, which is the check that
## would catch an event shape I assumed and got wrong.
func test_the_tally_reads_a_real_fight_and_its_totals_reconcile() -> void:
	var party: Array[PawnData] = []
	for cid in [&"warrior", &"priest"]:
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 3)
	CombatSim.run(state)

	var rows := EndScreenScript.tally(state)
	assert_eq(rows.size(), 2)
	var dealt := 0
	for row in rows:
		dealt += int(row["dealt"])
	assert_true(dealt > 0, "two pawns fought a whole encounter and the roster says they dealt nothing")

	## The reconciliation the overkill rule buys: what the party is credited
	## with equals what the other side is recorded as having taken.
	var owner := EndScreenScript.summoner_of(state)
	var taken_by_enemies := 0
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE or e.amount <= 0:
			continue
		var victim := state.unit(e.target_id)
		if victim == null or victim.team == CG.Team.PLAYER:
			continue
		var credit: int = owner.get(e.source_id, e.source_id)
		var source := state.unit(credit)
		if source != null and source.pawn != null:
			taken_by_enemies += e.amount
	assert_eq(dealt, taken_by_enemies,
		"dealt and taken must be the same number counted from two ends")


## The summon rule cannot be asserted against a real fight, and this test says
## why rather than pretending otherwise. Measured over 12 seeds: a preset Siege
## Master builds two engines every time and they deal **zero damage in all 24**
## -- each one starts an action, never fires it, and dies. Filed as its own
## issue; the tally is proved against a built stream above.
##
## So this asserts the REASON, not the rule: it goes red the day an engine lands
## a hit, which is the day the assertion above it can be a real one.
func test_a_real_siege_engine_still_deals_nothing_which_is_why_the_rule_is_unproven() -> void:
	var party: Array[PawnData] = []
	for cid in [&"siege_master", &"warrior"]:
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 5)
	CombatSim.run(state)

	var engines := {}
	for e in state.events:
		if e.kind == CG.EventKind.SUMMONED:
			engines[e.target_id] = true
	assert_true(engines.size() > 0, "no engine was built at all, which is a different defect")

	var rows := EndScreenScript.tally(state)
	assert_eq(int(rows[0]["by_summons"]), 0,
		"an engine landed a hit: turn this into an assertion that the master is credited")
	assert_false(EndScreenScript._dealt_text(rows[0]).contains("by summons"),
		"and name the share on the card: %s" % EndScreenScript._dealt_text(rows[0]))


## The log is every line the fight produced through the running log's own
## formatter, so the What-to-show toggles apply here too.
func test_the_full_log_is_every_line_the_running_log_would_have_printed() -> void:
	var party: Array[PawnData] = [PawnFactory.make_preset_pawn(&"warrior", &"w", "W")]
	var state := CombatSim.build(party, Registry.get_encounter(CG.DEFAULT_ENCOUNTER), 1)
	CombatSim.run(state)
	var view := CombatLogView.new()
	var lines := EndScreenScript.log_lines(state, view)
	var expected := 0
	for e in state.events:
		if view.line_for_event(state, e) != "":
			expected += 1
	assert_eq(lines.size(), expected)
	assert_true(lines.size() > 10, "a whole encounter produced %d log lines" % lines.size())
	view.free()


## Issue 343's defect, in the node that grew. The banner's centred column is a
## `VBoxContainer`, which defaults to `MOUSE_FILTER_STOP`; while it held one
## paragraph it was too small to cover anything, and the roster made it big
## enough to swallow Change party and Plans. The real-click probe found it.
## Nothing structural inside the banner may take a mouse event.
func test_nothing_structural_in_the_end_banner_takes_a_mouse_event() -> void:
	var view = _battle_view()
	var offenders: Array[String] = []
	for n in _walk(view._end_banner):
		if n is Button or n is ScrollContainer:
			continue
		if n is Control and n.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			offenders.append("%s (%s)" % [n.name, n.get_class()])
	assert_eq(offenders, [] as Array[String],
		"these cover the toolbar the moment the banner is bigger than its text: %s" % [offenders])
	view.free()

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
