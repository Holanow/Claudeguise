extends "res://Tests/TestCase.gd"

## Issue 849: `test_content_items.gd` proves every item DOES something and
## nothing proved the equip screen SAYS so, which is how the Quiver shipped
## applying Bleed while the panel read "No effect." and the Focus shipped
## naming its action while dropping its pool bonus.
##
## The field set here is read off the resource with `get_property_list`, never
## typed out, so a new export on `EquipmentDef` or `AbilityModifier` is red in
## this file until somebody teaches the renderer about it.

## Fields that say which item this is rather than what it does; `part` is the
## sprite the weapon draws, which the icon carries and the sentence should not.
const IDENTITY_ITEM: Array[StringName] = [
	&"id", &"display_name", &"slot", &"part", &"description", &"required_tags",
]

const IDENTITY_MODIFIER: Array[StringName] = [&"display_name"]

## Everything a `.tres` can carry, which is also everything a content author can
## set without touching code.
func _stored_fields(res: Resource) -> Array[StringName]:
	var out: Array[StringName] = []
	for p in res.get_property_list():
		var usage := int(p["usage"])
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if not (usage & PROPERTY_USAGE_STORAGE):
			continue
		out.append(StringName(p["name"]))
	return out

# ---------------------------------------------------------------------------
# The walk
# ---------------------------------------------------------------------------

## The assertion the issue asks for: every field a registered item actually
## carries is named by `item_effect_text`, derived from the item's own data.
func test_every_registered_item_is_fully_described() -> void:
	var complaints: Array[String] = []
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		complaints.append_array(_complaints(id, item, EquipPanel.item_effect_text(item)))
	assert_eq(complaints, [], "the equip screen is silent about fields these items carry")

## Issue 916: the walk above only ever sees hand-authored items, none of which
## carry an affix, so rolled items are walked through the same complaints.
func test_every_rolled_item_is_fully_described() -> void:
	var complaints: Array[String] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 916
	for id in ItemLibrary.all_ids():
		var base := ItemLibrary.get_equipment(id)
		for i in 40:
			var rolled := ItemRoller.roll(base, 1, rng)
			complaints.append_array(_complaints(id, rolled, EquipPanel.item_effect_text(rolled)))
	assert_eq(complaints, [], "the equip screen is silent about affixes these rolls carry")

## A field nobody has taught the renderer about must fail rather than pass
## quietly, so this is asserted at the class level too: it goes red the moment
## the export is added, before any item sets it.
func test_every_equipment_field_has_somebody_to_name_it() -> void:
	var blank := EquipmentDef.new()
	for f in _stored_fields(blank):
		if IDENTITY_ITEM.has(f):
			continue
		if f == &"modifiers":
			continue
		assert_true(_tokens_for(blank, f) != null,
			"EquipmentDef.%s: nothing says what this does on the equip screen" % f)

func test_every_modifier_field_has_somebody_to_name_it() -> void:
	var blank := AbilityModifier.new()
	for f in _stored_fields(blank):
		if IDENTITY_MODIFIER.has(f):
			continue
		assert_true(_modifier_tokens(blank, f) != null,
			"AbilityModifier.%s: nothing says what this does on the equip screen" % f)

## Inert is allowed as long as it is recorded in the item's own data: a piece
## with every capability field at its default reads "No effect." and a piece
## carrying anything must not.
func test_only_an_item_carrying_nothing_reads_as_no_effect() -> void:
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		var text := EquipPanel.item_effect_text(item)
		if _carries_anything(item):
			assert_ne(text, "No effect.", "%s carries a capability and reads inert" % id)
		else:
			assert_eq(text, "No effect.", "%s carries nothing and should say so plainly" % id)

func _carries_anything(item: EquipmentDef) -> bool:
	var blank := EquipmentDef.new()
	for f in _stored_fields(item):
		if IDENTITY_ITEM.has(f):
			continue
		if item.get(f) != blank.get(f):
			return true
	return false

func _complaints(id: StringName, item: EquipmentDef, text: String) -> Array[String]:
	var out: Array[String] = []
	var blank := EquipmentDef.new()
	for f in _stored_fields(item):
		if IDENTITY_ITEM.has(f):
			continue
		if item.get(f) == blank.get(f):
			continue
		if f == &"modifiers":
			out.append_array(_modifier_complaints(id, item, text))
			continue
		var tokens: Variant = _tokens_for(item, f)
		if tokens == null:
			out.append("%s carries %s and nothing on the equip screen names it" % [id, f])
			continue
		out.append_array(_missing(id, f, tokens, text))
	return out

func _modifier_complaints(id: StringName, item: EquipmentDef, text: String) -> Array[String]:
	var out: Array[String] = []
	var blank := AbilityModifier.new()
	for m in item.modifiers:
		if m == null:
			continue
		for f in _stored_fields(m):
			if IDENTITY_MODIFIER.has(f):
				continue
			if m.get(f) == blank.get(f):
				continue
			var tokens: Variant = _modifier_tokens(m, f)
			if tokens == null:
				out.append("%s carries a modifier field %s and nothing names it" % [id, f])
				continue
			out.append_array(_missing(id, f, tokens, text))
	return out

func _missing(id: StringName, field: StringName, tokens: Array, text: String) -> Array[String]:
	var out: Array[String] = []
	for t in tokens:
		if not _says(text, String(t)):
			out.append("%s carries %s and the screen never says \"%s\" -- it says \"%s\"" % [
				id, field, t, text])
	return out

# ---------------------------------------------------------------------------
# What each field has to put on the screen
# ---------------------------------------------------------------------------

## Tokens rather than whole sentences, so rewording the panel does not break
## this while dropping a field still does; `null` means the field is one nobody
## has taught the screen to describe.
func _tokens_for(item: EquipmentDef, field: StringName) -> Variant:
	var out: Array[String] = []
	match field:
		&"attribute_flat":
			for a in item.attribute_flat:
				var flat := int(item.attribute_flat[a])
				if flat != 0:
					out.append("%s %+d" % [CG.attribute_name(a), flat])
		&"attribute_percent":
			for a in item.attribute_percent:
				var percent := float(item.attribute_percent[a])
				if percent != 0.0:
					out.append("%s %+d%%" % [CG.attribute_name(a), int(round(percent * 100.0))])
		&"damage_reduction":
			out.append("%d%%" % int(round(item.damage_reduction * 100.0)))
		&"resource_regen_percent_bonus":
			out.append("%d%%" % int(round(item.resource_regen_percent_bonus)))
			out.append("second")
		&"affixes":
			for r in item.affixes:
				if r == null or r.affix == null:
					continue
				out.append(r.affix.display_name)
				out.append_array(_affix_value_tokens(r))
		&"granted_actions":
			for action_id in item.granted_actions:
				var action: ActionDef = ActionLibrary.get_action(action_id)
				out.append(String(action_id).capitalize() if action == null else action.display_name)
		_:
			return null
	return out

## Derived from `AffixDef`'s own fields rather than from the panel's routine,
## so a renderer that stops saying the number still fails here.
func _affix_value_tokens(r: AffixRoll) -> Array[String]:
	match r.affix.effect:
		AffixDef.Effect.MAX_HP_FLAT:
			return ["%+d" % int(round(r.value))]
		AffixDef.Effect.DAMAGE_REDUCTION:
			return ["%d%%" % int(round(r.value * 100.0))]
		AffixDef.Effect.DAMAGE_PERCENT:
			return ["%+d%%" % int(round(r.value * 100.0))]
	return ["%s %+d" % [CG.attribute_name(r.affix.attribute), int(round(r.value))]]

## The gates here are the simulation's, read off `AbilityModifiers` and
## `AbilityModifier.matches`, not the renderer's: mirroring the renderer's own
## conditions would import whatever it is already blind to.
func _modifier_tokens(m: AbilityModifier, field: StringName) -> Variant:
	var out: Array[String] = []
	match field:
		&"only_projectiles":
			out.append("projectile")
		&"any_damage_type":
			out.append(CG.damage_type_name(m.only_damage_type).to_lower())
		&"only_damage_type":
			# `matches` reads this only when `any_damage_type` is off, so a
			# modifier that matches everything carries a dead setting here.
			if not m.any_damage_type:
				out.append(CG.damage_type_name(m.only_damage_type).to_lower())
		&"target_count_bonus":
			out.append("%+d" % m.target_count_bonus)
		&"power_multiplier":
			out.append("%+d%%" % int(round((m.power_multiplier - 1.0) * 100.0)))
		&"adds_status_enabled":
			out.append(Glossary.status_name(m.adds_status))
		&"adds_status", &"adds_status_ticks", &"adds_status_chance":
			# `added_statuses` ignores all three unless the status is enabled.
			if m.adds_status_enabled:
				out.append_array(_status_tokens(m, field))
		_:
			return null
	return out

func _status_tokens(m: AbilityModifier, field: StringName) -> Array[String]:
	match field:
		&"adds_status":
			return [Glossary.status_name(m.adds_status)]
		&"adds_status_ticks":
			return ["%.1fs" % (float(m.adds_status_ticks) / float(CG.TICKS_PER_SECOND))]
	return ["%d%%" % int(round(m.adds_status_chance * 100.0))]

## `contains` on its own is hollow for a number: "2%" is inside "25%", which is
## exactly the pair the Focus and the Quiver would have produced.
func _says(text: String, token: String) -> bool:
	var from := 0
	while true:
		var at := text.find(token, from)
		if at == -1:
			return false
		var before := "" if at == 0 else text[at - 1]
		var after_at := at + token.length()
		var after := "" if after_at >= text.length() else text[after_at]
		if not before.is_valid_int() and not _runs_on(token, after):
			return true
		from = at + 1
	return false

func _runs_on(token: String, after: String) -> bool:
	if after.is_valid_int():
		return true
	return after == "%" and not token.ends_with("%")
