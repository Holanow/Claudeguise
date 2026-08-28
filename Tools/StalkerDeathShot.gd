extends Node

## Issue 639 verification, not shipped as a permanent instrument: measures
## drawn pixels on the frame a Stalker's death chunks appear, the same
## measurement the issue itself reports (6,190 px before the fix). Run once
## before the DeathExplosion/BattleView change and once after, same seed.
##
##   powershell -ExecutionPolicy Bypass -File Tools\run.ps1 StalkerDeathShot

const OUT := "res://Screenshots/kestrel_639_stalker_death_%s.png"
const SEED := 3
var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	var args := OS.get_cmdline_user_args()
	var tag := args[0] if not args.is_empty() else "frame0"
	await _run(tag)
	get_tree().quit(0)

func _party() -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in 4:
		out.append(PawnFactory.make_preset_pawn(&"warrior", StringName("w%d" % i), "W%d" % i))
	return out

func _build() -> void:
	var cfg := RunConfig.new()
	cfg.party = _party()
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED
	var room := RoomData.new()
	room.id = &"staged"
	room.display_name = "Staged"
	room.enemy_spawns = [{"enemy_id": &"stalker", "position": Vector2(160.0, 0.0)}]
	room.party_spawns = [Vector2(-350.0, -100.0), Vector2(-350.0, -33.0),
		Vector2(-350.0, 33.0), Vector2(-350.0, 100.0)]
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, room)
	_view.set_process(false)

func _frame() -> void:
	_view._process(CG.TICK_SECONDS / 4.0)

func _run(tag: String) -> void:
	await _build()
	var stalker_id := -1
	for u in _view.state.units:
		if u.enemy_id == &"stalker":
			stalker_id = u.id
	print("StalkerDeathShot: stalker id %d, idle phase %.3f" % [
		stalker_id, PartAnimation.phase_for(stalker_id)])
	var died := false
	for _i in 3000:
		_frame()
		await get_tree().process_frame
		var u: CombatUnit = _view.state.unit(stalker_id)
		if u == null or not u.alive:
			died = true
			break
		if _view.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
	if not died:
		printerr("StalkerDeathShot: the stalker never died")
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Screenshots"))
	img.save_png(OUT % tag)
	print("StalkerDeathShot: %s" % (OUT % tag))
