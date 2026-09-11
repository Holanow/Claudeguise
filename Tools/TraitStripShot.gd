extends Node

## Issue 920: both halves of the trait strip in one frame -- the plan editor
## naming the Siege Master's quiver on the left, and the combat log naming the
## same piece as the Bleed lands on the right.

const OUT_DIR := "user://probe"
const PANEL_WIDTH := 700.0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TraitStripShot: use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _pawn() -> PawnData:
	var pawn := PawnFactory.make_starter_pawn(&"siege_master", &"siege_master", "Siege Master")
	for plan in PresetPlans.for_class(&"siege_master"):
		pawn.plans.append(plan)
	return pawn

## The attack the quiver rides: one this pawn's own weapon grants, whose own
## effects never apply Bleed, so the Bleed came from the gear and nothing else.
func _attack(pawn: PawnData) -> ActionDef:
	for id in pawn.main_hand.granted_actions:
		var action := ActionLibrary.get_action(id)
		if action != null and not CombatLogView._action_applies(action, CG.Status.BLEED):
			return action
	return null

func _state(pawn: PawnData) -> CombatState:
	var state := CombatState.new(1)
	var shooter := CombatUnit.new()
	shooter.id = 0
	shooter.team = CG.Team.PLAYER
	shooter.display_name = "Siege Master"
	shooter.pawn = pawn
	state.units.append(shooter)
	var rat := CombatUnit.new()
	rat.id = 1
	rat.team = CG.Team.ENEMY
	rat.display_name = "Rat"
	state.units.append(rat)
	return state

func _event(kind: CG.EventKind, action_id: StringName) -> CombatEvent:
	var e := CombatEvent.make(kind, 1)
	e.source_id = 0
	e.target_id = 1
	e.action_id = action_id
	return e

func _run() -> void:
	## The screens this rides on paint their own parchment; a bare Node does
	## not, and every colour the strip and the log choose is ink against it.
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
	var log_view := CombatLogView.new()
	add_child(log_view)
	log_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	log_view.size = Vector2(1280.0, 720.0)
	var state := _state(pawn)
	var damage := _event(CG.EventKind.DAMAGE, action.id)
	damage.amount = 9
	var bleed := _event(CG.EventKind.STATUS_APPLIED, action.id)
	bleed.status = CG.Status.BLEED
	bleed.amount = 1
	for e in [_event(CG.EventKind.ACTION_START, action.id), damage, bleed]:
		log_view.append_event(state, e)
	print("TraitStripShot: log says -- ", log_view.line_for_event(state, bleed))
	for t in InspectPanel.trait_lines(pawn):
		print("TraitStripShot: strip says -- %s: %s" % [t["name"], t["text"]])
	await _settle()

	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_viewport().get_texture().get_image().save_png("%s/sable5_920_trait_strip_and_proc.png" % OUT_DIR)
	print("TraitStripShot: sable5_920_trait_strip_and_proc.png")
