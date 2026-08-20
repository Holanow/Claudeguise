extends Node

## Issue 308: the plan rows of a pawn that is being dragged by a taunt and has
## not arrived yet. Driven through the screens a player uses -- party select,
## the room picker, the battle screen's own tick, its "Inspect party" button.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("TauntPanelShot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	var s := DisplayServer.window_get_size()
	_tag = "%dx%d" % [int(s.x), int(s.y)]
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s_%s.png" % [OUT_DIR, name, _tag])
	print("TauntPanelShot: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("TauntPanelShot: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

## The state this shot exists to photograph: TAUNTED right now, and the last
## thing the event stream saw this unit start was its own plan, not a compulsion.
func _dragged_and_walking(state) -> CombatUnit:
	for u in state.units:
		if not u.alive or u.pawn == null or not u.has_status(CG.Status.TAUNTED):
			continue
		var last := &""
		for i in range(state.events.size() - 1, -1, -1):
			var e = state.events[i]
			if e.kind == CG.EventKind.ACTION_START and e.source_id == u.id:
				last = e.source_plan
				break
		if last != Intent.COMPELLED and last != &"":
			return u
	return null

func _select_room(picker: OptionButton, want: String) -> bool:
	for i in picker.item_count:
		if String(picker.get_item_metadata(i)).contains(want):
			picker.selected = i
			picker.item_selected.emit(i)
			return true
	print("TauntPanelShot: the picker offers no room matching '%s'" % want)
	return false

## Every verdict on the screen, printed so a wrong capture is recognisable
## rather than merely unconvincing.
func _report(panel: Node) -> void:
	for child in panel._detail_box.get_children():
		var text := ""
		for n in _walk(child):
			if n is Label:
				text += n.text + " "
		text = text.strip_edges()
		if text.begins_with("1.") or text.begins_with("2.") or text.begins_with("3.") \
				or text.begins_with("Fallback"):
			print("TauntPanelShot:   %s" % text)

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var select := _node_with("PartySelect.gd")
	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await _settle()
	if not _select_room(select._room_picker, "hazard"):
		return false
	select._seed_edit.text = "00000001"
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	## The deploy screen stands between the picker and the fight, and its own
	## button carries the same words.
	if _node_with("DeployView.gd") != null:
		if not _press("start fight"):
			return false
		await _settle()

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("TauntPanelShot: no battle screen")
		return false

	## One tick per call, through the screen's own frame handler, with the
	## engine's own _process off so nothing else advances the fight.
	battle.set_process(false)
	var dragged: CombatUnit = null
	for tick in 3000:
		battle._process(CG.TICK_SECONDS)
		if battle.state.outcome != CombatState.Outcome.UNRESOLVED:
			break
		dragged = _dragged_and_walking(battle.state)
		if dragged != null:
			break
	if dragged == null:
		print("TauntPanelShot: no pawn was taunted and still walking in this fight")
		return false
	print("TauntPanelShot: %s is taunted and walking at tick %d" % [dragged.display_name, battle.state.tick])
	await _settle()

	if not _press("plans"):
		return false
	await _settle()
	var panel := _node_with("InspectPanel.gd")
	## Found first and pressed after the walk: selecting a pawn frees and
	## rebuilds the detail column, and the walk is holding those nodes.
	var pick: Button = null
	for n in _walk(panel):
		if n is Button and n.text == dragged.pawn.display_name:
			pick = n
			break
	if pick == null:
		print("TauntPanelShot: no button for '%s' in the panel" % dragged.pawn.display_name)
		return false
	pick.emit_signal("pressed")
	await _settle()
	for n in _walk(panel):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	_report(panel)
	await _shot("wren_taunt_walking_plans")
	return true
