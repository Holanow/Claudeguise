extends Node

## Issue 931: all four of README's verbs from the roll to the screen. Every
## value is drawn by `ItemRoller` off the authored `.tres`, every draw comes
## from one seeded rng, and what the two display surfaces say about them is
## printed as well as photographed.

const OUT_DIR := "user://probe"
const PANEL_WIDTH := 700.0
const SEED := 931

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("VerbShot: use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

## One affix of one kind, rolled rather than assigned: the count draw can return
## none, so this asks again until the roller hands back the piece it is meant to.
func _rolled(base: EquipmentDef, affix_id: StringName) -> EquipmentDef:
	var pool: Array[AffixDef] = [AffixLibrary.get_affix(affix_id)]
	for i in 200:
		var item := ItemRoller.roll_from(base, ItemRoller.VERB_UNLOCK_FLOOR, _rng, pool)
		if item.affixes.size() == 1:
			return item
	return base

## README leaves the accessory slot empty pending its own design, so the ring
## the fourth verb rides is authored here rather than taken from the library.
func _ring() -> EquipmentDef:
	var e := EquipmentDef.new()
	e.id = &"probe_ring"
	e.display_name = "Ring"
	e.slot = EquipmentDef.Slot.ACCESSORY
	return e

## The Warrior rather than the Siege Master: the Siege Master's quiver already
## applies Bleed through a modifier, and the log would credit that piece for the
## proc rather than the rolled one this shot exists to show.
func _pawn() -> PawnData:
	var pawn := PawnFactory.make_starter_pawn(&"warrior", &"warrior", "Warrior")
	for plan in PresetPlans.for_class(&"warrior"):
		pawn.plans.append(plan)
	pawn.main_hand = _rolled(pawn.main_hand, &"thirsting")
	pawn.off_hand = _rolled(pawn.off_hand, &"serrated")
	pawn.body = _rolled(pawn.body, &"flowing")
	pawn.accessory = _rolled(_ring(), &"ravenous")
	return pawn

func _attack(pawn: PawnData) -> ActionDef:
	for id in pawn.main_hand.granted_actions:
		var action := ActionLibrary.get_action(id)
		if action != null and not CombatLogView._action_applies(action, CG.Status.BLEED):
			return action
	return null

func _deps() -> SimDeps:
	var d := SimDeps.new()
	d.attack_power = func(_u: CombatUnit, _a: ActionDef, _r: RandomNumberGenerator = null) -> float:
		return 12.0
	d.damage_reduction = func(_u: CombatUnit) -> float:
		return 0.0
	return d

func _state(pawn: PawnData) -> CombatState:
	var state := CombatState.new(SEED)
	var shooter := CombatUnit.new()
	shooter.id = 0
	shooter.team = CG.Team.PLAYER
	shooter.display_name = "Warrior"
	shooter.pawn = pawn
	shooter.hp_max = pawn.max_hp()
	shooter.hp = shooter.hp_max / 2
	shooter.resource_max = pawn.max_resource()
	shooter.resource = 0
	shooter.resource_kind = pawn.pawn_class.resource_kind
	state.units.append(shooter)
	var rat := CombatUnit.new()
	rat.id = 1
	rat.team = CG.Team.ENEMY
	rat.display_name = "Rat"
	rat.hp_max = 18
	rat.hp = 18
	state.units.append(rat)
	return state

## Two hits: the first bleeds and leeches, the second kills and pays. Driven
## through the simulation's own routines so the events are the ones a fight
## would emit rather than ones this tool wrote.
func _fight(state: CombatState, action: ActionDef) -> void:
	var shooter: CombatUnit = state.units[0]
	var rat: CombatUnit = state.units[1]
	var deps := _deps()
	for i in 3:
		if not rat.alive:
			break
		CombatSim._apply_action_effect(state, shooter, rat, action, deps)

func _run() -> void:
	_rng.seed = SEED
	var ground := ColorRect.new()
	ground.color = Palette.PAPER_FIELD
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.offset_right = 1280.0
	ground.offset_bottom = 720.0
	add_child(ground)

	var pawn := _pawn()
	var panel := InspectPanel.create()
	add_child(panel)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_right = PANEL_WIDTH
	panel.offset_bottom = 720.0
	await get_tree().process_frame
	panel.embed()
	panel.show_pawn(pawn)
	await _settle()

	var action := _attack(pawn)
	var state := _state(pawn)
	var log_view := CombatLogView.new()
	add_child(log_view)
	log_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	log_view.position = Vector2(PANEL_WIDTH, 0.0)
	log_view.size = Vector2(1280.0 - PANEL_WIDTH, 720.0)
	_fight(state, action)
	for e in state.events:
		log_view.append_event(state, e)
		var line := log_view.line_for_event(state, e)
		if line != "":
			print("VerbShot: log -- ", line)
	for t in InspectPanel.trait_lines(pawn):
		print("VerbShot: strip -- %s: %s (%s)" % [t["name"], t["text"], t["item"]])
	print("VerbShot: leech %.2f, cooldown %.2f, on kill %.2f" % [
		pawn.gear_life_leech(), pawn.gear_cooldown_reduction(), pawn.gear_resource_on_kill()])
	await _settle()

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_viewport().get_texture().get_image().save_png("%s/teal9_931_verbs_reach_a_fight.png" % OUT_DIR)
	print("VerbShot: teal9_931_verbs_reach_a_fight.png")
