extends SceneTree

## Issue 621, one-off. Builds every action through the 23 decorator helpers it
## is replacing, converts each to the composed shape, saves it as a `.tres`,
## loads that file back and compares all 34 flat fields with EXACT equality.
##
## Exact, not approximate, on purpose: `IMMOLATE_TICK_POWER_SCALE` is 2.8/18 and
## a text serialiser that truncates it by one ulp moves the sim fingerprint.
## This file and `GenActionTres_legacy.gd` are deleted once the output is in.

const OUT_DIR := "res://Scripts/Content/Actions/"
const Legacy := preload("res://Tools/GenActionTres_legacy.gd")

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var rows: Array = Legacy.actions()
	var ids: Array[String] = []
	var bad := 0
	for row in rows:
		var path: String = OUT_DIR + String(row["id"]) + ".tres"
		var err := ResourceSaver.save(_compose(row), path)
		if err != OK:
			print("SAVE FAILED ", path, " err ", err)
			bad += 1
			continue
		ids.append(String(row["id"]))
		bad += _verify(row, path)
	print("")
	print("actions written: ", ids.size())
	print("mismatched fields: ", bad)
	_write_manifest(ids)
	quit(1 if bad > 0 else 0)

func _compose(row: Dictionary) -> ActionDef:
	var a := ActionDef.new()
	a.id = row["id"]
	a.display_name = row["display_name"]
	a.description = row["description"]
	a.wind_up_ticks = row["wind_up_ticks"]
	a.recover_ticks = row["recover_ticks"]
	a.cooldown_ticks = row["cooldown_ticks"]
	a.resource_cost = row["resource_cost"]

	var t := ActionTargeting.new()
	t.range_units = row["range_units"]
	t.splash_radius = row["splash_radius"]
	t.requires_line_of_sight = row["requires_line_of_sight"]
	t.targets_self = row["targets_self"]
	t.covers_target = row["covers_target"]
	t.requires_marked_target = row["requires_marked_target"]
	a.targeting = t

	if row["projectile_speed"] > 0.0:
		var d := ActionDelivery.new()
		d.speed = row["projectile_speed"]
		a.delivery = d

	if row["sustain_cost_per_tick"] > 0 or row["sustain_radius"] > 0.0:
		var s := ActionSustain.new()
		s.cost_per_tick = row["sustain_cost_per_tick"]
		s.radius = row["sustain_radius"]
		a.sustain = s

	## Resolution order, and it is the order `_apply_action_effect` already runs
	## them in: hit, status, pull, cleanse. The caster-side three come after.
	var fx: Array[AbilityEffect] = []
	var h := HitEffect.new()
	h.damage_type = row["damage_type"]
	h.power_scale = row["power_scale"]
	h.heals = row["heals"]
	h.consumes_status_enabled = row["consumes_status_enabled"]
	h.consumes_status = row["consumes_status"]
	h.consumed_power_scale = row["consumed_power_scale"]
	fx.append(h)

	if row["applies_status_enabled"]:
		var st := StatusEffect.new()
		st.status = row["applies_status"]
		st.duration_ticks = row["status_duration_ticks"]
		st.magnitude = row["status_magnitude"]
		st.taunt_radius = row["taunt_radius"]
		fx.append(st)

	if row["pull_distance"] > 0.0:
		var p := PullEffect.new()
		p.distance = row["pull_distance"]
		fx.append(p)

	if row["cleanses_harmful"]:
		fx.append(CleanseEffect.new())

	if row["summons_unit_id"] != &"":
		var su := SummonEffect.new()
		su.unit_id = row["summons_unit_id"]
		su.max_active = row["max_active_summons"]
		fx.append(su)

	if row["leaves_pool_radius"] > 0.0:
		var po := PoolEffect.new()
		po.radius = row["leaves_pool_radius"]
		fx.append(po)

	if row["restores_resource"] > 0:
		var r := RestoreEffect.new()
		r.amount = row["restores_resource"]
		fx.append(r)

	a.effects = fx
	return a

func _verify(row: Dictionary, path: String) -> int:
	var loaded: ActionDef = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var bad := 0
	for key in row.keys():
		var want: Variant = row[key]
		var got: Variant = loaded.get(key)
		if typeof(want) == TYPE_FLOAT and typeof(got) == TYPE_FLOAT:
			if not is_same(want, got):
				print("MISMATCH ", row["id"], ".", key, "  want ", String.num(want, 17), " got ", String.num(got, 17))
				bad += 1
			continue
		if want != got:
			print("MISMATCH ", row["id"], ".", key, "  want ", want, " got ", got)
			bad += 1
	return bad

func _write_manifest(ids: Array[String]) -> void:
	ids.sort()
	var lines := PackedStringArray()
	lines.append("extends RefCounted")
	lines.append("class_name ActionLibrary")
	lines.append("")
	lines.append("## Issue 621: every action `.tres` the game ships, listed rather than")
	lines.append("## scanned. A `DirAccess` walk is ordered by the filesystem, and the")
	lines.append("## registry may not be.")
	lines.append("")
	lines.append("const PATHS: Array[String] = [")
	for id in ids:
		lines.append("\t\"%s%s.tres\"," % [OUT_DIR, id])
	lines.append("]")
	lines.append("")
	var f := FileAccess.open("res://Scripts/Content/ActionLibrary.gd", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("manifest: ", ids.size(), " paths")
