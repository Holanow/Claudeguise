extends SceneTree

## Issue 835: `floor1_warden` per COMPOSITION, not averaged. An aggregate win
## rate cannot tell a fight that separates good parties from bad ones apart
## from one that is a coin flip for everybody.

const ROOM := &"floor1_warden"

func _init() -> void:
	var seeds := int(_arg("--seeds", "20"))
	var warden := EnemyLibrary.get_enemy(&"the_warden")
	_override(warden)
	print("WardenSpread -- %s, %d seeds per composition, seed = hash([s, comp])" % [ROOM, seeds])
	print("  the_warden   hp %d  attack_power %s  damage_reduction %.2f  move_speed %.2f"
		% [warden.hp_max, warden.attack_power, warden.damage_reduction, warden.move_speed])
	for aid in [&"warden_axe", &"warden_throw", &"warden_chain_toss", &"warden_throw_impact"]:
		var a := ActionLibrary.get_action(aid)
		var scales := PackedStringArray()
		for fx in a.effects:
			if fx is HitEffect:
				scales.append("effects %.2f" % (fx as HitEffect).power_scale)
		for i in a.beats.size():
			for fx in a.beats[i].effects:
				if fx is HitEffect:
					scales.append("beat%d %.2f" % [i, (fx as HitEffect).power_scale])
		print("  %-22s %s" % [String(aid), ", ".join(scales)])
	print("")
	print("  %-46s  win    deaths  hp left  seconds" % "composition (arm B, planned)")
	var wins_all := 0
	var runs_all := 0
	for combo in PartySpec.compositions():
		var r := _measure(combo, true, seeds)
		wins_all += int(r.wins)
		runs_all += seeds
		_row(PartySpec.label(combo), r, seeds)
	print("  %-46s  %3d%%" % ["ALL COMPOSITIONS", int(round(100.0 * wins_all / maxi(1, runs_all)))])
	if _arg("--arm", "AB") == "AB":
		print("")
		print("  %-46s  win    deaths  hp left  seconds" % "composition (arm A, no plans)")
		for combo in PartySpec.compositions():
			_row(PartySpec.label(combo), _measure(combo, false, seeds), seeds)
	quit(0)

func _row(label: String, r: Dictionary, seeds: int) -> void:
	print("  %-46s  %3d%%  %5.2f    %3d%%   %6.1f" % [label,
		int(round(100.0 * float(r.wins) / seeds)), float(r.deaths) / seeds,
		int(round(100.0 * float(r.hp_left) / seeds)), float(r.ticks) / seeds * CG.TICK_SECONDS])

func _measure(combo: Array, planned: bool, seeds: int) -> Dictionary:
	var out := {"wins": 0, "deaths": 0.0, "hp_left": 0.0, "ticks": 0}
	for s in range(seeds):
		var party := PartySpec.make(combo, planned)
		var state := CombatSim.build(party, RoomLibrary.get_room(ROOM), hash([s, combo]))
		CombatSim.run(state)
		out.ticks += state.tick
		if state.outcome == CombatState.Outcome.PLAYER_WIN:
			out.wins += 1
		var frac := 0.0
		for j in party.size():
			var u := state.unit(j)
			if u.alive:
				frac += float(u.hp) / float(u.hp_max)
			else:
				out.deaths += 1.0
		out.hp_left += frac / float(party.size())
	return out

## Every knob this issue is allowed to move, applied to the cached def and
## action resources the room itself spawns from.
func _override(warden: EnemyDef) -> void:
	if _arg("--hp", "") != "":
		warden.hp_max = int(_arg("--hp", ""))
	if _arg("--power", "") != "":
		warden.attack_power = {0: int(_arg("--power", ""))}
	if _arg("--dr", "") != "":
		warden.damage_reduction = float(_arg("--dr", ""))
	for pair in _arg("--scale", "").split(",", false):
		var bits := String(pair).split(":", false)
		_scale(StringName(bits[0]), float(bits[1]))

## `id:factor` multiplies every HitEffect power_scale of that action, beats
## included, so one argument moves an action's whole damage.
func _scale(id: StringName, factor: float) -> void:
	var a := ActionLibrary.get_action(id)
	for fx in a.effects:
		if fx is HitEffect:
			(fx as HitEffect).power_scale *= factor
	for beat in a.beats:
		for fx in beat.effects:
			if fx is HitEffect:
				(fx as HitEffect).power_scale *= factor

func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(name)
	return fallback if at < 0 or at + 1 >= args.size() else String(args[at + 1])
