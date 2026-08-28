extends Node

## Issues 651/652/654: the default row read off `DefaultPlan.rows_for(unit)`,
## and the action picker offering the three derived-action blocks. Driven
## through the screens a player uses -- party select, "Plans".

const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")
const OUT_DIR := "res://Screenshots"

var _main: Node

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("Finch650Shot: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
	var ok := await _run()
	get_tree().quit(0 if ok else 1)

func _settle(n: int = 6) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("Finch650Shot: no visible button '%s'" % prefix)
	return false

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	img.save_png("%s/%s.png" % [OUT_DIR, name])
	print("Finch650Shot: %s.png" % name)

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	if not ScreenSweepScript.add_presets(_main):
		print("Finch650Shot: no PartySelect to add preset plans to")
		return false
	var select := _node_with("PartySelect.gd")
	select._seed_edit.text = "00000001"
	select._seed_edit.text_submitted.emit("00000001")
	await _settle()

	var by_id := {}
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			if n.class_def != null:
				by_id[n.class_def.id] = n
	## The Priest has a real heal, so the default rows show both branches.
	for id in [&"priest", &"warrior", &"geysermancer", &"abomination"]:
		if by_id.has(id):
			by_id[id].toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return false
		await _settle()

	var battle := _node_with("BattleView.gd")
	if battle == null:
		print("Finch650Shot: no battle screen")
		return false
	if not _press("plans"):
		return false
	await _settle()

	var panel := _node_with("InspectPanel.gd")
	var pick: Button = null
	for n in _walk(panel):
		if n is Button and n.text.begins_with("Priest"):
			pick = n
			break
	if pick == null:
		print("Finch650Shot: no Priest button in the panel")
		return false
	pick.emit_signal("pressed")
	await _settle()
	for n in _walk(panel):
		if n is ScrollContainer:
			n.scroll_vertical = 100000
	await _settle()
	await _shot("finch_651_654_default_rows")

	var rows := 0
	for n in _walk(panel):
		if n.name == "FallbackRow":
			rows += 1
	print("Finch650Shot: %d default row(s) shown" % rows)

	## Now show the action picker offering the derived ops on the Priest's own
	## first plan (issue 652). Add one if the preset carried none.
	if not _press("+ add a plan"):
		print("Finch650Shot: no '+ Add a plan' button; hoping a preset row exists")
	await _settle()
	var pickers: Array[OptionButton] = []
	for n in _walk(panel):
		if n is OptionButton:
			pickers.append(n)
	var derived_picker: OptionButton = null
	for p in pickers:
		for i in p.item_count:
			if p.get_item_text(i).begins_with("Use my"):
				derived_picker = p
				break
		if derived_picker != null:
			break
	if derived_picker == null:
		print("Finch650Shot: FAIL no action picker offers a derived op")
		return false
	derived_picker.get_popup().visible = true
	await _settle()
	await _shot("finch_652_derived_action_picker")
	derived_picker.get_popup().visible = false
	print("Finch650Shot: derived ops found in the action picker")
	return rows > 0
