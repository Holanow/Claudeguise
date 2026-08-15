extends Node

## Photograph an interrupt at the moment it happens. Issue 151.
##
##   godot --path . --resolution 1280x720 res://Tools/InterruptShot.tscn
##
## An INTERRUPTED fires about 1.15 times in a Burn Pit fight, on one tick out of
## five hundred, and the flash it triggers lives 0.35 seconds. Shooting fixed
## ticks the way RoomWatch does will miss it essentially always, which is how a
## feature ships built-and-unseen: the tool that would have caught it was
## pointed at the wrong moment rather than at the wrong thing.
##
## So this watches the real event stream and shoots the frame the event lands
## on, plus one a few frames later while the ring is still expanding. Real
## content, real controls, no hand-built state: party select, then the room
## picker, then Start fight, the same three things a player presses.
##
## OWNER: wren. Not part of the game and not part of the gate.

const Registry := preload("res://Scripts/Content/Registry.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const CG := preload("res://Scripts/Core/CG.gd")

const OUT_DIR := "res://Screenshots"
const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
## The Brute's stun is the only thing in the game that cancels a cast, and it
## stands in the Burn Pit. Both are overridable, because the aiming problem is
## not specific to interrupts: any event rare enough to matter is too rare to
## catch on a fixed tick.
##
##   godot --path . --resolution 1280x720 res://Tools/InterruptShot.tscn -- ##       --kind STATUS_EXPIRED --room floor1_room1 --name burn_consume
##
## `--kind` takes a CG.EventKind name.
const DEFAULT_ROOM := &"floor1_hazard"
const DEFAULT_KIND := CG.EventKind.INTERRUPTED

var _main: Node
var _room: StringName = DEFAULT_ROOM
var _wanted: int = DEFAULT_KIND
var _name := "interrupt"
## Optional: also require the event to carry this action id. STATUS_EXPIRED
## fires for a natural expiry, a cleanse and a consume alike, and the consume is
## the one worth a picture -- without this the tool photographs whichever comes
## first, which is almost always the dull one.
var _action := &""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("InterruptShot: use a worktree."); get_tree().quit(2); return
	await _run()
	get_tree().quit(0)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	print("InterruptShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _fresh() -> void:
	if _main != null:
		_main.queue_free()
		await _settle()
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null and PARTY.has(String(n.class_def.id)):
				n.toggled.emit(true)
	await _settle()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if i + 1 >= args.size():
			continue
		if args[i] == "--room":
			_room = StringName(args[i + 1])
		elif args[i] == "--name":
			_name = args[i + 1]
		elif args[i] == "--action":
			_action = StringName(args[i + 1])
		elif args[i] == "--kind":
			var found := CG.EventKind.keys().find(args[i + 1])
			if found < 0:
				printerr("InterruptShot: no such CG.EventKind '%s'" % args[i + 1])
				return
			_wanted = found

	# The event is not guaranteed in any one fight, so try seeds until one
	# lands rather than reporting a miss as a result.
	for attempt in 8:
		if await _try_once(attempt):
			return
	print("InterruptShot: no %s in 8 fights" % CG.EventKind.keys()[_wanted])

func _try_once(attempt: int) -> bool:
	await _fresh()
	var select := _node_with("PartySelect.gd")
	var picker: OptionButton = select._room_picker
	var found := -1
	for i in picker.item_count:
		if picker.get_item_metadata(i) == _room:
			found = i
	if found < 0:
		print("InterruptShot: %s not offered" % _room); return false
	picker.selected = found
	picker.item_selected.emit(found)
	await _settle()
	if not _press("start fight"): return false
	await _settle()
	if not _press("start fight"): return false
	await _settle(2)

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("InterruptShot: never reached the battle"); return false

	var seen := 0
	var frames := 0
	while battle.state.outcome == CombatState.Outcome.UNRESOLVED and frames < 200000:
		await get_tree().process_frame
		frames += 1
		while seen < battle.state.events.size():
			var e = battle.state.events[seen]
			seen += 1
			if e.kind != _wanted:
				continue
			if _action != &"" and e.action_id != _action:
				continue
			# The log line is already appended and the flash node already
			# spawned by the time this frame ends: BattleView.consume_events
			# runs on the same frame the tick is stepped.
			await _shot("%s_now" % _name)
			await _settle(4)
			await _shot("%s_after" % _name)
			var who = battle.state.unit(e.source_id)
			print("InterruptShot: %s at tick %d, source %s, action %s, amount %d, attempt %d" % [
				CG.EventKind.keys()[e.kind], e.tick,
				who.display_name if who != null else "?", e.action_id, e.amount, attempt])
			return true
	print("InterruptShot: attempt %d finished with no such event (tick %d)" % [attempt, battle.state.tick])
	return false
