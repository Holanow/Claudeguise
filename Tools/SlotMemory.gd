extends Node

## Resident texture memory after every party has been watched fighting in every
## pickable room, to the end.
##
## Asking what one body costs answers the wrong question: what matters is what a
## whole session of fights leaves resident, because a wind-up and a death each
## reach for art a still body never touches. Uses no art API at all, only the
## battle screen, so the number cannot drift from what a player loads.

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const SEED := 7
const FRAMES_PER_TICK := 4

var _view: Node2D = null

func _ready() -> void:
	Offscreen.hide_window(self)
	var before := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var parties: Array = ScreenSweepScript.sweep_parties(ClassLibrary.all_ids())
	var deaths := 0
	for party_ids in parties:
		for encounter_id in RoomLibrary.pickable_ids():
			deaths += await _watch(party_ids, encounter_id)
	await RenderingServer.frame_post_draw
	var after := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	print("SlotMemory: %d fights watched, %d deaths drawn" % [
		parties.size() * RoomLibrary.pickable_ids().size(), deaths])
	print("SlotMemory: texture memory before %d, after %d, unit art %d bytes" % [
		before, after, after - before])
	get_tree().quit(0)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for i in ids.size():
		out.append(PawnFactory.make_starter_pawn(
			ids[i], StringName("p%d" % i), String(ids[i])))
	return out

## One fight, played through the real screen at the real frame rate, so every
## body that dies is drawn coming apart and every wind-up is drawn moving.
func _watch(party_ids: Array, encounter_id: StringName) -> int:
	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = encounter_id
	cfg.seed = SEED
	_view = (load("res://Scenes/Battle.tscn") as PackedScene).instantiate()
	add_child(_view)
	await get_tree().process_frame
	_view.begin_with_encounter(cfg, RoomLibrary.get_room(encounter_id))
	_view.set_process(false)
	var deaths := 0
	while _view.state.outcome == CombatState.Outcome.UNRESOLVED \
			and _view.state.tick < CG.MAX_TICKS:
		for f in FRAMES_PER_TICK:
			_view._process(CG.TICK_SECONDS / float(FRAMES_PER_TICK))
		await RenderingServer.frame_post_draw
	for u in _view.state.units:
		if not u.alive:
			deaths += 1
	_view.queue_free()
	_view = null
	await get_tree().process_frame
	return deaths
