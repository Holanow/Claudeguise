extends SceneTree

## Issue 344 measured how a raw roll becomes the number on screen. Issue 364
## adds the two questions that measurement raised: what the enemy short-circuit
## was costing, and why ARMOR never gets named.

const SEEDS := 12

var _reductions: Array[float] = []
var _causes := {}
var _armor_share := {}
var _short_circuit := {}

func _init() -> void:
	var class_ids := ClassLibrary.all_ids()
	var rows := []
	for encounter_id in RoomLibrary.all_ids():
		var encounter := RoomLibrary.get_room(encounter_id)
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
	for r in rows:
		var has_mit: bool = r[1] < r[0]
		var has_over: bool = r[2] < r[1]
		if has_mit and has_over:
			both += 1
		elif has_over:
			overkill += 1
		elif has_mit:
			mitigated += 1
		else:
			clean += 1

	print("action-damage events: ", rows.size())
	print("  untouched %d | reduced only %d | overkill only %d | both %d" % [
		clean, mitigated, overkill, both])
	print("")
	print("dominant cause, as the event carries it:")
	for k in _causes:
		print("  %-10s %d" % [k, _causes[k]])
	print("")
	print("ISSUE 364 A: hits where the OLD enemy short-circuit disagreed with Balance")
	if _short_circuit.is_empty():
		print("  none")
	for k in _short_circuit:
		print("  %-34s %d" % [k, _short_circuit[k]])
	print("")
	print("ISSUE 364 B: ARMOR. Every hit on a pawn wearing armour with reduction.")
	for k in _armor_share:
		print("  %-34s %d" % [k, _armor_share[k]])
	quit(0)

## Wraps `damage_reduction` so each hit's reduction can be paired with its
## event: `_apply_damage` calls it exactly once per DAMAGE it emits, in the same
## order, and nothing else calls it.
func _fight(party_ids: Array, encounter: RoomData, s: int) -> Array:
	var deps := SimDeps.new()
	_reductions = []
	deps.damage_reduction = func(u: CombatUnit) -> float:
		var v: float = SimDeps._default_damage_reduction(u)
		_reductions.append(clampf(v, 0.0, 1.0))
		_inspect(u, v)
		return v
	var party: Array[PawnData] = []
	for cid in party_ids:
		party.append(PawnFactory.make_starter_pawn(cid, StringName("%s_%d" % [cid, party.size()]), String(cid)))
	var state := CombatSim.build(party, encounter, s, deps)
	CombatSim.run(state, deps)

	var out := []
	var i := 0
	for e in state.events:
		if e.kind != CG.EventKind.DAMAGE or e.action_id == &"":
			continue
		var red: float = _reductions[i] if i < _reductions.size() else 0.0
		i += 1
		out.append([
			e.amount_before_mitigation,
			maxi(0, int(round(float(e.amount_before_mitigation) * (1.0 - red)))),
			e.amount,
		])
		_bump(_causes, str(e.mitigation_cause))
	return out

func _bump(d: Dictionary, k: String) -> void:
	d[k] = int(d.get(k, 0)) + 1

func _inspect(u: CombatUnit, used: float) -> void:
	if u.pawn == null:
		# What the shipped code did before this branch: hide only, statuses
		# never reached.
		var d: EnemyDef = EnemyLibrary.get_enemy(u.enemy_id)
		var old_value := 0.0 if d == null else d.damage_reduction
		if not is_equal_approx(old_value, used):
			_bump(_short_circuit, "old %.2f -> now %.2f" % [old_value, used])
		return
	if u.pawn.armor == null or u.pawn.armor.damage_reduction <= 0.0:
		return
	var armor: float = u.pawn.armor.damage_reduction
	var toughness := clampf(
		Balance.attribute(u.pawn, CG.Attribute.CON) * Balance.DAMAGE_REDUCTION_PER_CON,
		0.0, Balance.NATURAL_DAMAGE_REDUCTION_CAP)
	_bump(_armor_share, "armour %.2f vs own toughness %.2f" % [armor, toughness])
	if armor > toughness:
		_bump(_armor_share, "armour IS the largest contributor")
