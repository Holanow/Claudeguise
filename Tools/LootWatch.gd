extends Node

## Issue 811: the loot loop on a live floor, through the path the player takes.
## A real `Battle.tscn` through `begin_floor` at 24x, and a frame captured on
## the tick the log first says somebody picked something up. Filmed rather than
## staged on purpose: the award happens in `BattleView._handle_fight_end` and
## the announcement in the next room's `carry_into`, so the whole feature is a
## floor transition, which `.claude/ENGINEER.md` names as the one exception.

const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const OUT_DIR := "res://Screenshots"
const FLOOR_SEED := 3
const TIME_SCALE := 24.0

var _battle: Node = null
var _seen := 0
var _shots := 0
var _busy := false

## Every room builds a fresh CombatState, so the event array starts over while
## a plain index into it does not. Without this the pickup lands at index 0 of
## the new room and sits behind a cursor left at the last room's count.
var _last_state = null

func _ready() -> void:
	Offscreen.hide_window(self)
	Engine.time_scale = TIME_SCALE
	var cfg := RunConfig.new()
	cfg.seed = FLOOR_SEED
	var party: Array[PawnData] = []
	for cid in ClassLibrary.all_ids():
		party.append(PawnFactory.make_preset_pawn(cid, cid, String(cid)))
	cfg.party = party
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.floor_ended.connect(_on_floor_ended)
	_battle.begin_floor(cfg, FloorGenerator.generate(FLOOR_SEED))

func _process(_delta: float) -> void:
	if _battle == null or _battle.state == null or _busy:
		return
	if _battle.state != _last_state:
		_last_state = _battle.state
		_seen = 0
	var events: Array = _battle.state.events
	while _seen < events.size():
		var e = events[_seen]
		_seen += 1
		if e.kind == CG.EventKind.LOOT_AWARDED:
			_busy = true
			_capture(_battle.state, e)
			return

func _capture(state, e) -> void:
	await RenderingServer.frame_post_draw
	var unit = state.unit(e.target_id)
	var who: String = unit.display_name if unit != null else "?"
	print("LootWatch: %s picked up %s" % [who, e.item_id])
	_shots += 1
	get_viewport().get_texture().get_image().save_png(
		"%s/finch_811_loot_%d.png" % [OUT_DIR, _shots])
	_busy = false

func _on_floor_ended(victory: bool) -> void:
	print("LootWatch: floor ended, victory=%s, %d pickups seen" % [victory, _shots])
	for item in _battle._floor_run.loot:
		print("LootWatch:   found %s (%s)" % [item.id, item.display_name])
	## The room the drops came from, so the report can say the rule fired on the
	## rooms it was meant to and on no others.
	for room in _battle._floor_walk.plan.rooms:
		print("LootWatch:   %-22s %s" % [room.content_id, FloorRoom.type_name(room.type)])
	get_tree().quit(0 if _shots > 0 else 1)
