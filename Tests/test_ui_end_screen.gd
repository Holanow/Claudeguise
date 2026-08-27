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

# ---------------------------------------------------------------------------
# Issue 591: damage healed
#
# Read off `HEAL` the same way dealt is read off `DAMAGE`. Nothing was added to
# the simulation for it: `_apply_heal` already emits the health the bar moved.

func _heal(tick: int, source: int, target: int, amount: int) -> CombatEvent:
	var e := CombatEvent.make(CG.EventKind.HEAL, tick)
	e.source_id = source
	e.target_id = target
	e.amount = amount
	return e

func test_the_tally_credits_healing_to_whoever_cast_it() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	s.units.append(_pawn_unit(1, &"priest"))
	s.units.append(_enemy_unit(2))
	s.events.append(_damage(1, 2, 0, 20))
	s.events.append(_heal(2, 1, 0, 12))
	s.events.append(_heal(3, 1, 1, 5))

	var rows := EndScreenScript.tally(s)
	assert_eq(int(rows[1]["healed"]), 17, "the caster is credited, not the target")
	assert_eq(int(rows[0]["healed"]), 0, "the pawn that was healed did no healing")
	assert_eq(int(rows[0]["taken"]), 20, "healing must not net off what was taken")

## The rule #552 set for overkill, holding for overhealing without a second
## decision: `_apply_heal` emits the health the bar moved and emits nothing at
## all into a full target, so a 40-point heal into a pawn missing 3 can only
## ever reach this screen as 3. Measured on a real fight rather than asserted
## from reading the simulation.
func test_a_real_fight_never_emits_a_heal_the_bar_did_not_move() -> void:
	var party: Array[PawnData] = [
		PawnFactory.make_starter_pawn(&"priest", &"p0", "P0"),
		PawnFactory.make_starter_pawn(&"warrior", &"p1", "P1"),
	]
	var e := Encounter.new()
	e.party_spawns = [Vector2(-80.0, -20.0), Vector2(-80.0, 20.0)]
	e.enemy_spawns = [{"enemy_id": &"goblin", "position": Vector2(80.0, 0.0)}]
	var s := CombatSim.build(party, e, 7)
	## The warrior starts hurt, or the priest never has a reason to cast and the
	## measurement is of a fight with no healing in it.
	for u in s.units:
		if u.team == CG.Team.PLAYER:
			u.hp = maxi(1, int(float(u.hp_max) * 0.3))
	for guard in 900:
		if s.outcome != CombatState.Outcome.UNRESOLVED:
			break
		CombatSim.step(s)
	var heals := 0
	for event in s.events:
		if event.kind == CG.EventKind.HEAL:
			heals += 1
			assert_true(event.amount > 0,
				"a HEAL carrying %d reached the stream, so overheal is countable" % event.amount)
	assert_true(heals > 0, "no heal happened at all, so this measured nothing")

## And the tally credits nothing for one anyway. The simulation cannot emit a
## zero heal today; this is what stops the screen from counting one if it ever
## can.
func test_a_zero_heal_credits_nobody() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"priest"))
	s.events.append(_heal(1, 0, 0, 0))
	assert_eq(int(EndScreenScript.tally(s)[0]["healed"]), 0)

func test_healing_is_its_own_sort() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	s.units.append(_pawn_unit(1, &"priest"))
	s.units.append(_enemy_unit(2))
	s.events.append(_damage(1, 0, 2, 30))
	s.events.append(_heal(2, 1, 0, 12))

	var rows := EndScreenScript.tally(s)
	var by_dealt := EndScreenScript.sorted_rows(rows, EndScreenScript.SortBy.DEALT)
	assert_eq(int(by_dealt[0]["unit_id"]), 0, "the warrior dealt the most")
	var by_healed := EndScreenScript.sorted_rows(rows, EndScreenScript.SortBy.HEALED)
	assert_eq(int(by_healed[0]["unit_id"]), 1, "the priest healed the most, and it is a sort of its own")

## Every sort the screen offers must read a column the tally actually writes,
## so a fourth number cannot be added to the card and left unsortable.
func test_every_sort_reads_a_column_the_tally_writes() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"warrior"))
	var row := EndScreenScript.tally(s)[0]
	for key in EndScreenScript.SortBy.values():
		assert_true(EndScreenScript.SORT_KEYS.has(key), "sort %d reads no column" % key)
		assert_true(row.has(String(EndScreenScript.SORT_KEYS[key])),
			"sort %d reads '%s', which the tally does not write" % [key, EndScreenScript.SORT_KEYS[key]])

## The card, not the tally: the number has to be on the screen as well as in the
## dictionary. Eleven features on this project were built and unreachable.
func test_the_card_prints_what_the_pawn_healed() -> void:
	var s := _state()
	s.units.append(_pawn_unit(0, &"priest"))
	s.units.append(_enemy_unit(1))
	s.events.append(_damage(1, 1, 0, 20))
	s.events.append(_heal(2, 0, 0, 12))
	var view := _battle_view()
	var screen = view._end_screen
	screen.open(s, view._combat_log)
	var text := _text_of(screen)
	assert_true(text.contains("Healed"), "no card names healing: %s" % text)
	assert_true(text.contains("12"), "the card names healing and not the number: %s" % text)
	view.free()

## Issue 591's mouseover half. The class in words and the gear it wore, both
## derived -- `Glossary` owns one and `EquipPanel.item_effect_text` the other.
func test_a_portrait_explains_the_class_and_the_gear_on_hover() -> void:
	var naked := PawnData.new()
	naked.id = &"p0"
	naked.display_name = "P0"
	naked.pawn_class = Registry.get_class_def(&"warrior")
	var bare := EndScreenScript.portrait_hover_text(naked)
	assert_true(bare.length() > 0, "a portrait with nothing to say is the defect this fixes")
	assert_true(bare.contains("Wore nothing."), "a naked pawn must say so: %s" % bare)
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"p0", "P0")
	var item: EquipmentDef = null
	for id in ItemLibrary.all_ids():
		var candidate := Registry.get_equipment(id)
		if candidate.slot == EquipmentDef.Slot.WEAPON and candidate.allows_class(pawn.pawn_class):
			item = candidate
			break
	assert_true(item != null, "no weapon this class can wear, so this proves nothing")
	pawn.weapon = item
	var worn := EndScreenScript.portrait_hover_text(pawn)
	assert_true(worn.contains(item.display_name), "the gear is not named: %s" % worn)
	assert_true(worn.contains(EquipPanel.item_effect_text(item)),
		"the effect is described some other way than the item's own fields: %s" % worn)

func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + " "
	if node is Button:
		out += node.text + " "
	for child in node.get_children():
		out += _text_of(child)
	return out

# ---------------------------------------------------------------------------
# Issue 591: the card has to fit the window it is drawn in.
#
# The Healed row costs 27 px per card and a defeat whose casualty list wraps to
# three lines costs another 31, and together they pushed Restart (same seed)
# 21 px past the bottom of a 720 px window. The log gives way instead. The
# arrangement is asserted here; `Tools/EndRoomPickProbe.gd` is what proves it
# works, by forcing a card too tall to fit and re-checking every button's rect
# -- no synchronous test has a laid-out rect to read.

## The log is the only part of the card that may grow or shrink, because it is
## the only part that scrolls. A second expanding child would take the space
## from it silently.
func test_the_log_is_the_only_part_of_the_card_that_gives_way() -> void:
	var screen := EndScreenScript.create()
	var expanding: Array[String] = []
	for child in screen.get_children():
		if (child as Control).size_flags_vertical & Control.SIZE_EXPAND:
			expanding.append(child.name)
	assert_eq(expanding.size(), 1, "expanding children of the card: %s" % [expanding])
	assert_true(screen._log_side in screen.get_children(), "the log is not a child of the card")
	assert_true(screen._log_side.size_flags_vertical & Control.SIZE_EXPAND,
		"the log is fixed, so the roster or the buttons have to absorb a tall card")
	screen.free()

## And it has a floor, or a long enough casualty list leaves a caption over
## nothing and the card still would not fit.
func test_the_log_has_a_floor_of_a_caption_and_a_line() -> void:
	var screen := EndScreenScript.create()
	assert_almost_eq(screen._log_side.custom_minimum_size.y, EndScreenScript.LOG_MIN_HEIGHT, 0.5)
	assert_true(EndScreenScript.LOG_MIN_HEIGHT > 0.0)
	screen.free()

## The card itself expands, or the column around it hands the surplus to nothing
## and the log's expand flag never sees a pixel.
func test_the_card_takes_the_column_it_is_given() -> void:
	var view = _battle_view()
	assert_true(view._end_screen.size_flags_vertical & Control.SIZE_EXPAND,
		"the card does not expand, so the log inside it cannot")
	view.free()
