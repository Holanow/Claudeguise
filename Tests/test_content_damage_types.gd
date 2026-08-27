extends "res://Tests/TestCase.gd"


## Issue 631, and this file is the transcription check rather than a design
## test. Eight names and eight colours moved out of two `match` statements into
## resources, and a colour is the one kind of value a fight can never show you
## is wrong.
##
## **Every expected value below is typed from the pre-631 source, not read back
## from the def.** A test that asks the def what the def says proves nothing.

## `Palette.damage_color`'s eight hex literals, exactly as they read before the
## move. Written as hex here on purpose: that is the form a person authored, and
## the `.tres` had to be written as floats, so this is a genuine second spelling
## rather than a copy.
const OLD_COLOR: Dictionary = {
	CG.DamageType.PHYSICAL: "d8d3c4",
	CG.DamageType.FIRE: "e8703a",
	CG.DamageType.WATER: "4aa3d8",
	CG.DamageType.AIR: "bfe0e8",
	CG.DamageType.EARTH: "a8834b",
	CG.DamageType.DIVINE: "f2e08a",
	CG.DamageType.PROFANE: "9c5fbd",
	CG.DamageType.RAW: "ff5fa8",
}

## `CG.damage_type_name`'s eight returns, as they read before the move.
const OLD_NAME: Dictionary = {
	CG.DamageType.PHYSICAL: "Physical",
	CG.DamageType.FIRE: "Fire",
	CG.DamageType.WATER: "Water",
	CG.DamageType.AIR: "Air",
	CG.DamageType.EARTH: "Earth",
	CG.DamageType.DIVINE: "Divine",
	CG.DamageType.PROFANE: "Profane",
	CG.DamageType.RAW: "Raw",
}

func _def(d: CG.DamageType) -> DamageTypeDef:
	var def := DamageTypeLibrary.of(d)
	assert_not_null(def, "no DamageType for %s" % CG.DamageType.keys()[d])
	return def

## Every enum member has exactly one file, and no file claims a member twice.
## Without this the checks below could all pass on a set with a hole in it.
func test_every_damage_type_has_exactly_one_def() -> void:
	assert_eq(DamageTypeLibrary.PATHS.size(), CG.DamageType.size(),
		"one .tres per CG.DamageType member, no more and no fewer")
	var seen: Dictionary = {}
	for path in DamageTypeLibrary.PATHS:
		var d: DamageTypeDef = load(path)
		assert_not_null(d, path + " did not load")
		assert_false(seen.has(d.damage_type),
			"%s and %s both claim %s" % [seen.get(d.damage_type, ""), path, CG.DamageType.keys()[d.damage_type]])
		seen[d.damage_type] = path
	for t in CG.DamageType.values():
		assert_true(seen.has(t), "no .tres for %s" % CG.DamageType.keys()[t])

## The `.tres` stores the enum as a bare integer, so a fat-fingered digit
## silently repoints a whole file and every colour after it shifts by one.
## The filename is the only human-readable half, so it is what gets checked.
func test_each_file_describes_the_type_its_name_claims() -> void:
	for path in DamageTypeLibrary.PATHS:
		var d: DamageTypeDef = load(path)
		var want := String(path.get_file().get_basename()).to_upper()
		assert_eq(String(CG.DamageType.keys()[d.damage_type]), want,
			"%s carries damage_type = %d, which is %s" % [path, d.damage_type, CG.DamageType.keys()[d.damage_type]])
		assert_eq(String(d.id), want.to_lower(), path + " carries the wrong id")

## The transcription that mattered. Float-by-float against `Color(hex)`, because
## the `.tres` could only hold the components as decimals and a rounded one is a
## colour nobody would ever notice had shifted.
func test_every_colour_is_the_one_palette_used_to_return() -> void:
	for t in CG.DamageType.values():
		var want := Color(OLD_COLOR[t])
		var name := String(CG.DamageType.keys()[t])
		assert_eq(_def(t).color, want, name + "'s colour moved in the transcription")
		assert_eq(Palette.damage_color(t), want, "Palette disagrees with the def for " + name)

func test_every_name_is_the_one_cg_used_to_return() -> void:
	for t in CG.DamageType.values():
		var name := String(CG.DamageType.keys()[t])
		assert_eq(_def(t).display_name, OLD_NAME[t], name + "'s display name moved")
		assert_eq(CG.damage_type_name(t), OLD_NAME[t], "CG disagrees with the def for " + name)

## Two colours that collide read as one type on the log, the floater and the
## hazard tile at once. `test_skeleton` asserted this while the colours were
## literals; it has to keep holding now they are authored in eight files.
func test_no_two_types_share_a_colour() -> void:
	var seen: Dictionary = {}
	for d in DamageTypeLibrary.all():
		var key := d.color.to_html()
		assert_false(seen.has(key), "%s and %s are both %s"
			% [seen.get(key, ""), CG.DamageType.keys()[d.damage_type], key])
		seen[key] = CG.DamageType.keys()[d.damage_type]

## `applied_status` is the one field with no reader yet, so nothing in a fight
## can tell you it is wrong. It is not invented either: it is the exact inverse
## of `StatusDef.dot_damage_type`, which the game already states, and this holds
## the two together in both directions so neither can drift alone.
func test_applied_status_is_the_inverse_of_the_statuses_own_damage_type() -> void:
	for d in DamageTypeLibrary.all():
		var name := String(CG.DamageType.keys()[d.damage_type])
		if d.applied_status != null:
			assert_eq(d.applied_status.dot_damage_type, d.damage_type,
				"%s applies %s, whose own damage type is %s"
				% [name, CG.Status.keys()[d.applied_status.status],
					CG.DamageType.keys()[d.applied_status.dot_damage_type]])
	for s in StatusLibrary.all():
		if not s.deals_damage_over_time:
			continue
		var owner := DamageTypeLibrary.of(s.dot_damage_type)
		assert_eq(owner.applied_status, s,
			"%s deals %s damage over time and %s applies something else"
			% [CG.Status.keys()[s.status], CG.DamageType.keys()[s.dot_damage_type],
				CG.DamageType.keys()[s.dot_damage_type]])

## The other side of the same check: a status named on a type that has none is
## as wrong as a missing one, and no fight would show it either.
func test_only_the_three_types_with_a_status_name_one() -> void:
	var with_status: Array = []
	for d in DamageTypeLibrary.all():
		if d.applied_status != null:
			with_status.append(d.damage_type)
	assert_eq(with_status, [CG.DamageType.PHYSICAL, CG.DamageType.FIRE, CG.DamageType.PROFANE],
		"a type gained or lost its default status without the statuses changing")

## The trap #627 named and #631 repeats: a write to a getter-only property in
## GDScript silently does nothing, so a suite gets defaults and passes. Every
## DamageType field is a plain `@export var`, and this proves one takes a write.
func test_a_damagetype_field_can_actually_be_written() -> void:
	var d := DamageTypeDef.new()
	d.color = Color(0.1, 0.2, 0.3, 1.0)
	assert_eq(d.color, Color(0.1, 0.2, 0.3, 1.0), "a DamageTypeDef field silently refused a write")
