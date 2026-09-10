extends Node

## Issue 851: the click card on the frame the Warrior's block is held, where the
## card used to print the booked placeholder as a countdown.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const PARTY := ["warrior", "priest", "geysermancer", "siege_master"]
const ENCOUNTER := &"floor1_chokepoint"
const SEED := 1
const HELD := &"warrior_block"

var _battle: Node = null
var _busy := false

func _ready() -> void:
	Offscreen.hide_window(self)
	DisplayOptions.reset()
	DisplayOptions.set_enabled(&"name_plates", true)
	var cfg := RunConfig.new()
	cfg.party = _party(PARTY)
	cfg.encounter_id = ENCOUNTER
	cfg.seed = SEED
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		out.append(PawnFactory.make_preset_pawn(
			StringName(cid), StringName("%s_%d" % [cid, out.size()]),
			ClassLibrary.get_class_def(StringName(cid)).display_name))
	return out

## Whoever is holding the block, read from the state rather than from a tick.
func _holder() -> CombatUnit:
	var a := ActionLibrary.get_action(HELD)
	for u in _battle.state.units:
		if not u.cooldowns.has(HELD):
			continue
		if TeamStatusView.is_held(a, int(u.cooldowns[HELD]) - _battle.state.tick):
			return u
	return null

func _process(_delta: float) -> void:
	if _busy or _battle == null or _battle.state == null:
		return
	if _battle.state.outcome != CombatState.Outcome.UNRESOLVED:
		printerr("Card851Shot: the fight ended and nobody raised the block")
		get_tree().quit(1)
		return
	var u := _holder()
	if u == null:
		return
	_busy = true
	## The player's own gesture: clicking the pawn pauses the fight and opens the
	## card on it.
	_battle.select_unit_at(u.position)
	await RenderingServer.frame_post_draw
	var rect: Rect2 = _battle._unit_card.get_global_rect().grow(4.0)
	var image := get_viewport().get_texture().get_image()
	image.get_region(Rect2i(rect)).save_png(_out_path())
	print("Card851Shot: wrote %s at tick %d, %s booked to %d" % [
		_out_path(), _battle.state.tick, u.display_name, int(u.cooldowns[HELD])])
	get_tree().quit(0)

func _out_path() -> String:
	var args := OS.get_cmdline_user_args()
	return args[0] if args.size() > 0 else "user://card851.png"
