extends "res://Tests/TestCase.gd"


## Hover-info-box system, phase 1 (see TEAM_LOG.md, wren's block). The rule
## that matters most: the glossary owns the sentence, Balance owns the
## number, and the sentence reads the number -- rook's correction after the
## condition-editor bug found a UI file captioning a control from a copy of
## a fact PlanInterpreter already owned. These tests check the numbers in
## the glossary text actually come from Balance's real constants rather
## than a retyped literal that can drift the moment a balance pass changes
## the source.

func test_every_role_has_non_empty_text() -> void:
	for r in CG.Role.values():
		assert_false(Glossary.role_text(r).is_empty(), "role %d has no glossary text" % r)

func test_every_style_has_non_empty_text() -> void:
	for s in CG.Style.values():
		assert_false(Glossary.style_text(s).is_empty(), "style %d has no glossary text" % s)

func test_every_method_has_non_empty_text() -> void:
	for m in CG.Method.values():
		assert_false(Glossary.method_text(m).is_empty(), "method %d has no glossary text" % m)

func test_every_attribute_has_non_empty_text() -> void:
	for a in CG.Attribute.values():
		assert_false(Glossary.attribute_text(a).is_empty(), "attribute %d has no glossary text" % a)

func test_every_status_has_non_empty_text() -> void:
	for s in CG.Status.values():
		assert_false(Glossary.status_text(s).is_empty(), "status %d has no glossary text" % s)

func test_class_tags_text_combines_all_three() -> void:
	var text := Glossary.class_tags_text(CG.Role.TANK, CG.Style.MELEE, CG.Method.MARTIAL)
	assert_true(text.contains(Glossary.role_text(CG.Role.TANK)))
	assert_true(text.contains(Glossary.style_text(CG.Style.MELEE)))
	assert_true(text.contains(Glossary.method_text(CG.Method.MARTIAL)))

# ---------------------------------------------------------------------------
# The glossary owns the sentence, Balance owns the number.
# ---------------------------------------------------------------------------

func test_str_text_reads_the_real_hp_bonus_and_attack_power() -> void:
	var text := Glossary.attribute_text(CG.Attribute.STR)
	assert_true(text.contains(str(Balance.HP_PER_STR_BONUS)), text)
	assert_true(text.contains("%.1f" % Balance.ATTACK_POWER_PER_POINT), text)

func test_con_text_reads_the_real_hp_and_reduction_constants() -> void:
	var text := Glossary.attribute_text(CG.Attribute.CON)
	assert_true(text.contains(str(Balance.HP_PER_CON)), text)
	assert_true(text.contains("%d%%" % int(round(Balance.DAMAGE_REDUCTION_PER_CON * 100.0))), text)
	assert_true(text.contains("%d%%" % int(round(Balance.NATURAL_DAMAGE_REDUCTION_CAP * 100.0))), text)

func test_poison_text_reads_the_real_damage_percent() -> void:
	var text := Glossary.status_text(CG.Status.POISON)
	assert_true(text.contains("%.2f" % Balance.POISON_DAMAGE_PERCENT_PER_TICK), text)

## Issue 121, finch: **burn no longer has a percentage to read.** Its rate is a
## fraction of the hit that lit it, so there is no single number to print -- a
## big hit burns harder. The line follows BLEED's precedent and states the rule
## in words, which was wren's own preference.
##
## The two assertions left are the ones that still mean something: burn does not
## read like poison, and **it names the combo**. A player who cannot see that
## Blast eats a burn cannot find the only combo in the game (#186).
func test_burn_text_states_its_rule_and_names_the_combo() -> void:
	var text := Glossary.status_text(CG.Status.BURN)
	assert_true(text.to_lower().contains("blast"),
		"burn's text must say what snuffs it, or the combo is invisible: %s" % text)
	assert_false(text.contains("%"),
		"burn has no fixed percentage now; a number here would be a lie: %s" % text)
	assert_ne(text, Glossary.status_text(CG.Status.POISON), "BURN and POISON work differently and must not read identically")

func test_marked_text_reads_the_real_vulnerability_bonus() -> void:
	var text := Glossary.status_text(CG.Status.MARKED)
	assert_true(text.contains("%d%%" % int(round(Balance.MARKED_VULNERABILITY_BONUS * 100.0))), text)

func test_shield_and_block_text_read_their_own_real_reduction() -> void:
	assert_true(Glossary.status_text(CG.Status.SHIELD).contains("%d%%" % int(round(Balance.STATUS_SHIELD_REDUCTION * 100.0))))
	assert_true(Glossary.status_text(CG.Status.BLOCK).contains("%d%%" % int(round(Balance.STATUS_BLOCK_REDUCTION * 100.0))))

func test_haste_text_reads_the_real_tick_scale() -> void:
	var text := Glossary.status_text(CG.Status.HASTE)
	assert_true(text.contains("%d%%" % int(round(Balance.HASTE_TICK_SCALE * 100.0))), text)

func test_slowed_text_reads_the_real_speed_scale() -> void:
	var text := Glossary.status_text(CG.Status.SLOWED)
	assert_true(text.contains("%d%%" % int(round(Balance.SLOWED_SPEED_SCALE * 100.0))), text)

# ---------------------------------------------------------------------------
# GlossaryTooltip: the themed popup every hoverable node returns.
# ---------------------------------------------------------------------------

## Issue 112 made this `contains` rather than `==`: the box now ends with the
## sentence naming the gesture that pins it, so its label is the glossary
## sentence plus that hint. The assertion still fails if the sentence itself
## goes missing, which is what it was written to catch. Disclosed in the PR.
func test_tooltip_builds_a_control_carrying_the_text() -> void:
	var popup := GlossaryTooltip.build("Deals 4 damage.")
	var found := false
	for child in popup.get_children():
		if child is Label and child.text.contains("Deals 4 damage."):
			found = true
	assert_true(found, "the built popup must contain the given text")
	popup.free()
