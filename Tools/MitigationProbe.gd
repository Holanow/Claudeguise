extends SceneTree

## Issue 344. Measures how a raw damage roll turns into the number on screen,
## across real parties and real encounters, so "1 out of 29" can be attributed.

const SEEDS := 12

var _reductions: Array[float] = []

func _init() -> void:
	var class_ids := Registry.all_class_ids()
	var rows := []
	for encounter_id in Registry.all_encounter_ids():
		var encounter := Registry.get_encounter(encounter_id)
		for skip in class_ids.size():
			var party_ids := []
			for i in class_ids.size():
				if i != skip:
					party_ids.append(class_ids[i])
			for s in SEEDS:
				rows.append_array(_fight(party_ids, encounter, s))

	var overkill := 0
	var mitigated := 0
	var both := 0
	var clean := 0
	var worst_ratio := 1.0
	var worst := ""
	var above_cap := 0
	for r in rows:
		var raw: int = r[0]
		var mit: int = r[1]
		var applied: int = r[2]
		var red: float = r[3]
		var has_mit := mit < raw
		var has_over := applied < mit
		if has_mit and has_over:
			both += 1
		elif has_over:
			overkill += 1
		elif has_mit:
			mitigated += 1
		else:
			clean += 1
		if raw > 0:
			var ratio := float(applied) / float(raw)
			if ratio < worst_ratio:
				worst_ratio = ratio
				worst = "%d raw -> %d after %.0f%% reduction -> %d applied" % [raw, mit, red * 100.0, applied]
			# 0.85 is Balance.MAX_DAMAGE_REDUCTION: no reduction can take more.
			if float(mit) < float(raw) * 0.15 - 0.51:
				above_cap += 1

	print("action-damage events: ", rows.size())
	print("  untouched (applied == raw):        ", clean)
	print("  reduced only:                      ", mitigated)
	print("  overkill only (applied < mitigated):", overkill)
	print("  both:                              ", both)
	print("  reduction beyond the 85%% cap:      ", above_cap)
	print("  worst applied/raw ratio: %.3f  (%s)" % [worst_ratio, worst])
	print("")
	print("what the log calls mitigation but is overkill: ", overkill + both)
	print("")
	print("dominant contributor, over every hit that was reduced at all:")
	for k in _causes:
		print("  %-12s %d" % [k, _causes[k]])
	quit(0)

var _causes := {}

func _attribute(u: CombatUnit) -> void:
	var parts := {}
	if u.pawn != null:
		parts["toughness"] = clampf(Balance.attribute(u.pawn, CG.Attribute.CON) * Balance.DAMAGE_REDUCTION_PER_CON, 0.0, Balance.NATURAL_DAMAGE_REDUCTION_CAP)
		if u.pawn.armor != null:
			parts["armor"] = u.pawn.armor.damage_reduction
	else:
		var d: EnemyDef = Registry.get_enemy(u.enemy_id)
		if d != null:
			parts["hide"] = d.damage_reduction
	if u.has_status(CG.Status.SHIELD):
		parts["shield"] = Balance.STATUS_SHIELD_REDUCTION
	if u.has_status(CG.Status.BLOCK):
		parts["block"] = Balance.STATUS_BLOCK_REDUCTION
	var best := ""
	var best_v := 0.0
	for k in parts:
		if parts[k] > best_v:
			best_v = parts[k]
			best = k
	# Does SimDeps' enemy short-circuit disagree with Balance?
	if u.pawn == null:
		var used: float = SimDeps._default_damage_reduction(u)
		var full: float = Balance.damage_reduction(u)
		if not is_equal_approx(used, full):
			_causes["ENEMY DISAGREES %.2f used vs %.2f Balance" % [used, full]] = int(_causes.get("ENEMY DISAGREES %.2f used vs %.2f Balance" % [used, full], 0)) + 1
	if best == "":
		return
	if u.has_status(CG.Status.MARKED):
		best += "+marked"
	_causes[best] = int(_causes.get(best, 0)) + 1

## Wraps `damage_reduction` so the reduction of each hit can be recorded and
## paired with its event: `_apply_damage` calls it exactly once per DAMAGE it
## emits, in the same order, and nothing else calls it.
func _fight(party_ids: Array, encounter: Encounter, s: int) -> Array:
	var deps := SimDeps.new()
	_reductions = []
	deps.damage_reduction = func(u: CombatUnit) -> float:
		var v: float = SimDeps._default_damage_reduction(u)
		_reductions.append(clampf(v, 0.0, 1.0))
		_attribute(u)
		return v
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, s, deps)
	CombatSim.run(state, deps)

	var out := []
	var i := 0
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE:
			continue
		# A DOT or hazard tick carries no action and consults no reduction.
		if e.action_id == &"":
			continue
		var red: float = _reductions[i] if i < _reductions.size() else 0.0
		i += 1
		var mit := maxi(0, int(round(float(e.amount_before_mitigation) * (1.0 - red))))
		out.append([e.amount_before_mitigation, mit, e.amount, red])
	return out
