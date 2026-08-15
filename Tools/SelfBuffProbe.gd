extends SceneTree

## Issue 150. What does an enemy carrying a self-targeted buff ACTUALLY do?
##
##   godot --headless --path . --script res://Tools/SelfBuffProbe.gd
##
## Not part of the gate. It exists because #150's premise -- "a range-0.0
## self-targeted action makes its owner walk toward a foe forever and never
## fire" -- was written before `DefaultBehavior._attack_candidates` (#129)
## existed, and a premise is the least reliable part of an issue. This runs the
## real decision layer against a real Brute carrying a real taunt and prints
## what comes back, rather than reading the file and reasoning about it.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CombatUnit := preload("res://Scripts/Core/CombatUnit.gd")
const ActionDef := preload("res://Scripts/Core/ActionDef.gd")
const Intent := preload("res://Scripts/Core/Intent.gd")
const DefaultBehavior := preload("res://Scripts/Plans/DefaultBehavior.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")

func _init() -> void:
	var slam := Registry.get_action(&"brute_slam")
	var taunt := Registry.get_action(&"warrior_taunt")
	if slam == null or taunt == null:
		printerr("content missing: brute_slam=", slam, " warrior_taunt=", taunt)
		quit(1)
		return
	print("brute_slam   range=%.1f power=%.2f" % [slam.range_units, slam.power_scale])
	print("warrior_taunt range=%.1f power=%.2f status=%d" % [
		taunt.range_units, taunt.power_scale, taunt.applies_status])

	# The Brute as it ships, plus the roar it was denied. Distances chosen to
	# straddle brute_slam's own commit fraction, so both the approach branch and
	# the fire branch are exercised.
	for dist in [400.0, 100.0, 45.0, 20.0]:
		_report("brute WITH a taunt", [&"brute_slam", &"warrior_taunt"], dist)
	print("")
	for dist in [400.0, 100.0, 45.0, 20.0]:
		_report("brute as it ships", [&"brute_slam"], dist)
	print("")
	# The worse half of the premise: an enemy whose ONLY action is a self-buff.
	for dist in [400.0, 45.0]:
		_report("taunt-only enemy", [&"warrior_taunt"], dist)
	quit(0)

func _report(label: String, actions: Array, dist: float) -> void:
	var state := CombatState.new()
	var e := _unit(0, CG.Team.ENEMY, Vector2.ZERO, actions)
	e.move_speed = 1.8
	var p := _unit(1, CG.Team.PLAYER, Vector2(dist, 0.0), [&"warrior_strike"])
	state.units = [e, p]
	var intent := DefaultBehavior.decide(state, e)
	print("%-20s dist %6.1f -> %s" % [label, dist, _describe(intent)])

func _describe(intent: Intent) -> String:
	if intent == null:
		return "null"
	match intent.kind:
		CG.IntentKind.IDLE: return "IDLE"
		CG.IntentKind.MOVE_TO: return "MOVE_TO %s" % intent.destination
		CG.IntentKind.USE_ACTION: return "USE_ACTION %s -> unit %d" % [intent.action_id, intent.target_id]
	return "?"

func _unit(id: int, team: CG.Team, pos: Vector2, actions: Array) -> CombatUnit:
	var u := CombatUnit.new()
	u.id = id
	u.team = team
	u.position = pos
	u.hp_max = 320
	u.hp = 320
	u.radius = 18.0
	u.move_speed = 2.0
	var typed: Array[StringName] = []
	for a in actions:
		typed.append(a)
	u.actions = typed
	return u
