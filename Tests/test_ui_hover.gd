extends "res://Tests/TestCase.gd"


## Issue 449, the player: *"I need a mouse-over glossary on basically
## everything ... it needs to work during pause and unit placement."*
##
## What is asserted here is the geometry and the copy. That a real
## `InputEventMouseMotion` reaches the layer through Godot's picking is
## `Tools/HoverProbe.gd`, which no assertion in a headless suite can stand in
## for -- a hover box is a thing the engine finds, not a thing this file calls.

func _state() -> CombatState:
	var s := CombatState.new()
	s.tick = 0
	return s

func _unit(id: int, name: String, team: CG.Team = CG.Team.PLAYER) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.display_name = name
	u.hp_max = 100
	u.hp = 100
	u.alive = true
	u.radius = 22.0
	if team == CG.Team.PLAYER:
		u.pawn = PawnData.new()
	else:
		u.enemy_id = &"goblin"
	return u

func _with_statuses(u: CombatUnit, statuses: Array, until: int = 75) -> CombatUnit:
	for s in statuses:
		u.statuses[s] = until
	return u

func _marks(u: CombatUnit, units: Array, kind: StringName) -> Array:
	var out: Array = []
	for entry in UnitView.below_block_rects(u, units):
		if entry["kind"] == kind:
			out.append(entry)
	return out

# ---------------------------------------------------------------------------
# The marks under a body, which is where four blind playtesters looked
# ---------------------------------------------------------------------------

## A unit with no statuses and a full resource bar has nothing under it, so
## nothing under it may answer a hover.
func test_a_clean_unit_has_no_marks_at_all() -> void:
	var u := _unit(0, "Warrior")
	assert_eq(UnitView.below_block_rects(u, [u]).size(), 0,
		"a unit carrying nothing offered a hover target anyway")

## One badge, one rect, and it sits under the body rather than over it.
func test_a_status_badge_is_a_rect_under_the_body() -> void:
	var u := _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON])
	var marks := _marks(u, [u], &"status")
	assert_eq(marks.size(), 1, "one status, one badge")
	assert_eq(marks[0]["status"], CG.Status.POISON, "the badge names the wrong status")
	var rect: Rect2 = marks[0]["rect"]
	assert_true(rect.position.y > u.position.y,
		"the badge row is drawn under the body and must be hit-tested there: %s" % rect)
	assert_true(rect.size.x > 0.0 and rect.size.y > 0.0, "an empty rect can never be hovered")

## The overflow chip exists exactly when the row dropped something, and it is
## the last slot in the row rather than a rect of its own invention.
func test_the_overflow_chip_appears_only_when_a_status_was_dropped() -> void:
	var few := _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON])
	assert_eq(_marks(few, [few], &"overflow").size(), 0, "nothing was hidden, so nothing may claim it was")
	var many := _with_statuses(_unit(0, "Warrior"),
		[CG.Status.POISON, CG.Status.BLEED, CG.Status.SLOWED, CG.Status.MARKED])
	var overflow := _marks(many, [many], &"overflow")
	assert_eq(overflow.size(), 1, "four statuses and two slots, and no chip said so")
	assert_eq(int(overflow[0]["count"]), UnitView.hidden_status_count(many),
		"the chip's number disagrees with the row that produced it")


# ---------------------------------------------------------------------------
# Resolving a point
# ---------------------------------------------------------------------------

func test_hover_at_finds_the_badge_it_is_pointing_at() -> void:
	var u := _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON, CG.Status.BURN])
	var state := _state()
	state.units = [u]
	var marks := _marks(u, [u], &"status")
	for mark in marks:
		var found := UnitView.hover_at(state, (mark["rect"] as Rect2).get_center())
		assert_false(found.is_empty(), "a point in the middle of a drawn badge found nothing")
		assert_eq(found["mark"]["status"], mark["status"],
			"the point landed on the badge beside the one it was over")

## The negative, and it is the one a whole-screen hover layer gets wrong: empty
## ground must answer nothing rather than the nearest unit's badge.
func test_empty_ground_finds_no_mark() -> void:
	var u := _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON])
	var state := _state()
	state.units = [u]
	var far := Vector2(CG.ARENA_HALF_WIDTH * 0.9, -CG.ARENA_HALF_HEIGHT * 0.9)
	assert_true(UnitView.hover_at(state, far).is_empty(),
		"a point in the far corner of the arena claimed to be a status badge")

## A dead unit's marks are not drawn, so they may not be hovered either.
func test_a_dead_unit_answers_nothing() -> void:
	var u := _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON])
	var state := _state()
	state.units = [u]
	var at: Vector2 = (_marks(u, [u], &"status")[0]["rect"] as Rect2).get_center()
	u.alive = false
	assert_true(UnitView.hover_at(state, at).is_empty(), "a corpse answered a hover")

# ---------------------------------------------------------------------------
# What the boxes say
# ---------------------------------------------------------------------------


## Complaint five: the "+2" names what it is hiding, and names exactly the
## statuses the badge row dropped rather than a second opinion about them.
func test_the_overflow_box_names_the_statuses_the_row_dropped() -> void:
	var u := _with_statuses(_unit(0, "Warrior"),
		[CG.Status.POISON, CG.Status.BLEED, CG.Status.SLOWED, CG.Status.MARKED])
	var state := _state()
	state.units = [u]
	var text := Glossary.hidden_statuses_text(state, u)
	var shown := UnitView.status_badges(u)
	for s in UnitView.ordered_statuses(u):
		if shown.has(s):
			continue
		assert_true(text.contains(Glossary.status_name(s)),
			"%s is hidden and the chip does not name it: %s" % [Glossary.status_name(s), text])
	assert_eq(Glossary.hidden_statuses_text(state, _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON])), "",
		"nothing was hidden, so the box must be empty rather than say so at length")

## Complaint two. An enemy answers with its target and how many things are on
## it, the same two lines a pawn gets.
func test_an_enemy_answers_with_its_target_and_its_attackers() -> void:
	# Ids are array positions: `CombatState.unit` indexes `units` directly.
	var goblin := _unit(0, "Goblin", CG.Team.ENEMY)
	var warrior := _unit(1, "Warrior")
	var priest := _unit(2, "Priest")
	goblin.focus_id = warrior.id
	warrior.focus_id = goblin.id
	priest.focus_id = goblin.id
	var state := _state()
	state.units = [goblin, warrior, priest]
	var text := Glossary.unit_hover_text(state, goblin)
	assert_true(text.contains("Enemy"), "the box does not say which side it is on: %s" % text)
	assert_true(text.contains("Aiming at Warrior"), "the box does not say what it is aiming at: %s" % text)
	assert_true(text.contains("2 units are aiming at it"),
		"the box does not say how much fire it is under: %s" % text)

## Hover is the cheap version of the click card, so it must point at the card
## rather than try to be it.
func test_the_unit_box_points_at_the_card_and_is_shorter_than_it() -> void:
	var u := _with_statuses(_unit(0, "Warrior"), [CG.Status.POISON, CG.Status.BLEED])
	var state := _state()
	state.units = [u]
	var hover := Glossary.unit_hover_text(state, u)
	assert_true(hover.contains(Glossary.HOVER_CLICK_HINT), "the box never mentions the card: %s" % hover)
	assert_true(hover.split("\n").size() < UnitCard.lines(state, u).size() + 2,
		"the hover box is as long as the card it is supposed to be the cheap version of")

## A team row says the numbers rather than naming its bars, which is what it
## used to do.
func test_a_team_row_box_carries_the_numbers() -> void:
	var u := _unit(0, "Warrior")
	u.hp = 185
	u.hp_max = 292
	u.resource_kind = CG.ResourceKind.RAGE
	u.resource = 40
	u.resource_max = 40
	var state := _state()
	state.units = [u]
	var text := Glossary.team_row_text(state, u)
	assert_true(text.contains("185 of 292 hp"), "the row's box does not say how much health is left: %s" % text)
	assert_true(text.contains("Rage 40 of 40"), "the row's box does not name the resource or its numbers: %s" % text)

## A summon has no plans, no resource and no cooldowns, and its row must still
## say the one thing that is true of it.
func test_a_summon_row_says_it_is_a_summon() -> void:
	var summon := _unit(0, "Siege Engine")
	summon.pawn = null
	var state := _state()
	state.units = [summon]
	assert_true(Glossary.team_row_text(state, summon).contains("Summoned"),
		"the summon row lost the one sentence that distinguished it from a pawn")
