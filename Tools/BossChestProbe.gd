extends Node

## Issue 935: the chest a cleared boss room leaves, staged. Every room but the
## boss is marked cleared and each fight is won by decree, because what is under
## test is what a cleared boss room draws and not whether this party beats the
## Warden -- seeds 1 to 4 all lose to it, measured with Tools/FloorWatch.gd.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const AUTOPILOT := preload("res://Tools/FloorAutoPilot.gd")
const OUT_DIR := "user://probe"
const FLOOR_SEED := 3

var _battle: Node = null
var _ended := 0

func _ready() -> void:
	Offscreen.hide_window(self)
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	cfg.party = party
	var plan := FloorGenerator.generate(FLOOR_SEED)
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(func(_victory: bool): _ended += 1)
	_battle.begin_floor(cfg, plan)
	await get_tree().process_frame
	var walk: FloorWalk = _battle._floor_walk
	for room in plan.rooms:
		if room.id != plan.boss_id:
			walk.mark_cleared(room.id)
	await _walk_to_the_boss(plan)
	await _the_chest(plan)
	get_tree().quit(0 if _ended == 1 and _battle._floor_run.loot.size() > 0 else 1)

func _walk_to_the_boss(plan: FloorPlan) -> void:
	var walk: FloorWalk = _battle._floor_walk
	while walk.current_id != plan.boss_id:
		_win()
		var next := AUTOPILOT.next_door(_battle)
		if next < 0:
			print("BossChestProbe: no route to the boss from room %d" % walk.current_id)
			get_tree().quit(1)
			return
		_battle.take_door(next)
		while _battle._slide_left >= 0.0:
			await get_tree().process_frame
	print("BossChestProbe: arrived in %s" % plan.room(plan.boss_id).content_id)

## The fight is won by decree, through the same entry point `_process` uses when
## the simulation resolves one. The enemy is put down first so the picture shows
## a cleared room rather than a boss standing beside its own chest.
func _win() -> void:
	for unit in _battle.state.units:
		if unit.team == CG.Team.ENEMY and unit.alive:
			unit.hp = 0
			unit.alive = false
	_battle._curr_drawn = _battle._drawn_snapshot()
	for id in _battle._unit_views:
		_battle._unit_views[id].sync(_battle.state, _battle._curr_drawn.get(id, UnitView.RECOMPUTE_AT))
	if _battle._team_status != null:
		_battle._team_status.sync(_battle.state)
	_battle.state.outcome = CombatState.Outcome.PLAYER_WIN
	_battle._handle_fight_end()

func _the_chest(plan: FloorPlan) -> void:
	_win()
	print("BossChestProbe: boss room cleared -- chest_open=%s doors_open=%s floor_ended=%d" % [
		_battle.chest_open(), _battle.doors_open(), _ended])
	await RenderingServer.frame_post_draw
	var path := "%s/wren7_935_boss_chest.png" % OUT_DIR
	get_viewport().get_texture().get_image().save_png(path)
	print("BossChestProbe: %s (%s)" % [path, plan.room(plan.boss_id).content_id])
	var at: Vector2 = AUTOPILOT.chest_point(_battle)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e, true)
		await get_tree().process_frame
	var run: FloorRun = _battle._floor_run
	print("BossChestProbe: clicked at %s -- %d item(s), floor_ended=%d" % [
		at, run.loot.size(), _ended])
	for item in run.loot:
		print("BossChestProbe:   %s (%s)" % [item.id, item.display_name])
