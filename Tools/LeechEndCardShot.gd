extends Control

## Issue 938: the end card of a fight a leeching pawn won, so both halves of
## this issue are in one frame -- the card's own leech line, and a log line
## naming BOTH pieces that leeched rather than whichever slot came first.

const OUT_DIR := "user://probe"
const ROOM_ID := &"floor1_cover"
const SHOT := "curlew6_938_leech_on_the_end_card"
const SEED := 938

var _rng := RandomNumberGenerator.new()
var _screen: EndScreen = null
var _log: CombatLogView = null

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("LeechEndCardShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

## Rolled rather than assigned, the same way `Tools/VerbShot.gd` does it: the
## count draw can return none, so it asks again until the piece comes back.
func _rolled(base: EquipmentDef, affix_id: StringName) -> EquipmentDef:
	var pool: Array[AffixDef] = [AffixLibrary.get_affix(affix_id)]
	for i in 200:
		var item := ItemRoller.roll_from(base, ItemRoller.VERB_UNLOCK_FLOOR, _rng, pool)
		if item.affixes.size() == 1:
			return item
	return base

func _run() -> bool:
	_rng.seed = SEED
	size = get_viewport().get_visible_rect().size
	var backdrop := ColorRect.new()
	backdrop.color = Palette.BACKGROUND
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_log = CombatLogView.new()
	add_child(_log)
	_screen = EndScreen.create()
	_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_screen.offset_left = 24.0
	_screen.offset_top = 24.0
	_screen.offset_right = -24.0
	_screen.offset_bottom = -24.0
	add_child(_screen)
	await _settle()

	var state := _fight()
	var leeched := EndScreen.leeched_total(state)
	_screen.open(state, _log)
	await _settle()

	for line in EndScreen.ledger_lines(state):
		print("LeechEndCardShot: card -- %s" % line)
	var tagged := ""
	for e in state.events:
		if e.kind == CG.EventKind.LEECHED:
			tagged = _log.line_for_event(state, e)
			break
	print("LeechEndCardShot: log  -- %s" % tagged)
	await _shot(SHOT)

	if leeched <= 0:
		print("LeechEndCardShot: FAIL nothing leeched, so this measured nothing")
		return false
	if not _screen._log_label.text.contains("Leeched by your gear: %d." % leeched):
		print("LeechEndCardShot: FAIL the end card never names the leech")
		return false
	if not tagged.contains(",") :
		print("LeechEndCardShot: FAIL the log named fewer than both leeching pieces")
		return false
	print("LeechEndCardShot: PASS the card names %d leeched and the log names both pieces" % leeched)
	return true

## A real room, fought to a finish, with one pawn wearing two leeching pieces.
## `body` rather than the off hand: a two-handed main hand blocks that slot and
## nothing in it would reach the simulation.
func _fight() -> CombatState:
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		var c := StringName(cid)
		party.append(PawnFactory.make_preset_pawn(c, c, ClassLibrary.get_class_def(c).display_name))
	for p in party:
		if p.pawn_class != null and p.pawn_class.id == &"warrior":
			p.main_hand = _rolled(p.main_hand, &"thirsting")
			p.body = _rolled(p.body, &"thirsting")
	var state := CombatSim.build(party, RoomLibrary.get_room(ROOM_ID), SEED)
	for guard in 4000:
		if state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		CombatSim.step(state)
	return state

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("LeechEndCardShot: %s.png" % name)
