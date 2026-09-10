extends Node

## Issue 857: the team panel on the frame the Warrior's block is held AND two
## ordinary cooldowns are running, which is the frame the cap drops the held
## chip. Preset pawns, because a starter pawn carries no plan rows.

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

func _running(u: CombatUnit, action_id: StringName) -> bool:
	return u.cooldowns.has(action_id) and int(u.cooldowns[action_id]) - _battle.state.tick > 0

## The first frame the block is held and enough ordinary cooldowns are running
## to fill the cap without it, found from the state rather than from a tick.
func _holder() -> CombatUnit:
	for u in _battle.state.units:
		if not _running(u, HELD):
			continue
		var others := 0
		for action_id in u.actions:
			var a = ActionLibrary.get_action(action_id)
			if a != null and a.cooldown_ticks > 0 and not a.status_holds_cooldown and _running(u, action_id):
				others += 1
		if others >= TeamStatusView.MAX_COOLDOWN_CHIPS:
			return u
	return null

func _process(_delta: float) -> void:
	if _busy or _battle == null or _battle.state == null:
		return
	if _battle.state.outcome != CombatState.Outcome.UNRESOLVED:
		printerr("Block857Shot: the fight ended with no frame holding the block and two cooldowns")
		get_tree().quit(1)
		return
	var u := _holder()
	if u == null:
		return
	_busy = true
	await RenderingServer.frame_post_draw
	var rect: Rect2 = _battle._team_status.get_global_rect().grow(4.0)
	var image := get_viewport().get_texture().get_image()
	image.get_region(Rect2i(rect)).save_png(_out_path())
	print("Block857Shot: wrote %s at tick %d, %s chips: %s" % [
		_out_path(), _battle.state.tick, u.display_name,
		str(TeamStatusView.cooldowns_for(_battle.state, u).map(func(e): return "%s=%s" % [e["action_id"], e["chip_text"]]))])
	get_tree().quit(0)

func _out_path() -> String:
	var args := OS.get_cmdline_user_args()
	return args[0] if args.size() > 0 else "user://block857.png"
