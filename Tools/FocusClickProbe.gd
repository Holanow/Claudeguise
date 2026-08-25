extends Node

## Issue 588: clicking an enemy and pressing Focus fire, through the real
## controls -- a real InputEventMouseButton at a real screen position and a real
## button press -- then reading what the party actually aims at afterwards.

const OUT_DIR := "res://Screenshots"

var _main: Node
var _tag := ""

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("FocusClickProbe: refusing to run in the main checkout -- use a worktree.")
		get_tree().quit(2)
		return
	Offscreen.hide_window(self)
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
	print("FocusClickProbe: %s_%s.png" % [name, _tag])

func _walk(n: Node) -> Array[Node]:
	if not is_instance_valid(n) or n.is_queued_for_deletion():
		return []
	var out: Array[Node] = [n]
	for c in n.get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if is_instance_valid(n) and n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed")
			return true
	print("FocusClickProbe: no visible button '%s'" % prefix)
	return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)

## What the card is showing, or "" when nothing is. Read off the panel rather
## than off the view's own field, so a card that opened invisibly still reads
## as nothing.
func _card_text(battle) -> String:
	var card = battle.get("_unit_card")
	if card == null or not card.is_visible_in_tree():
		return ""
	return "%s | %s" % [card._title.text, card._body.text]


## The button on the card carrying one of the two focus words, or null.
func _focus_button(battle) -> Button:
	var card = battle.get("_unit_card")
	if card == null or not card.is_visible_in_tree():
		return null
	for n in _walk(card):
		if n is Button and n.is_visible_in_tree() 			and n.text in [UnitCard.FOCUS_SET, UnitCard.FOCUS_CLEAR]:
			return n
	return null

## How many living party pawns are aiming at `id` right now.
func _aiming_at(battle, id: int) -> int:
	var n := 0
	for u in battle.state.units:
		if u.alive and u.pawn != null and u.focus_id == id:
			n += 1
	return n

func _run() -> bool:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()

	var cards: Array[Node] = []
	for n in _walk(_main):
		if is_instance_valid(n) and n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for want in [&"geysermancer", &"warrior"]:
		for card in cards:
			if is_instance_valid(card) and card.class_def != null and card.class_def.id == want:
				card.toggled.emit(true)
	await _settle()
	if not _press("start fight"):
		return false
	await _settle()
	var held = _node_with("BattleView.gd")
	if held != null and held.setup:
		if not _press("start fight"):
			return false
		await _settle()
	var battle = _node_with("BattleView.gd")
	if battle == null:
		print("FocusClickProbe: no battle screen")
		return false

	battle.set_process(false)
	for tick in 60:
		battle._process(CG.TICK_SECONDS)
	await _settle()

	## The enemy the party is NOT already aiming at, so a change is visible.
	var living_foes: Array = battle.state.living(CG.Team.ENEMY)
	if living_foes.size() < 2:
		print("FocusClickProbe: this fight needs two living enemies")
		return false
	var already: int = -1
	for u in battle.state.units:
		if u.alive and u.pawn != null and u.focus_id >= 0:
			already = u.focus_id
			break
	var want_foe = null
	for f in living_foes:
		if f.id != already:
			want_foe = f
			break
	if want_foe == null:
		print("FocusClickProbe: every living enemy is already the focus of somebody")
		return false

	var failures := 0
	var before_aiming := _aiming_at(battle, want_foe.id)
	print("FocusClickProbe: targeting %s (id %d); %d pawn(s) aim there before the click" % [
		want_foe.display_name, want_foe.id, before_aiming])

	var at: Vector2 = battle._arena.get_global_transform() * BattleView.drawn_position(battle.state, want_foe)
	await _click(at)
	var text := _card_text(battle)
	if not text.begins_with(want_foe.display_name):
		print("FocusClickProbe: the enemy click opened '%s' rather than its own card" % text.replace("
", " / "))
		failures += 1
	else:
		print("FocusClickProbe: the enemy click opened its own card")

	var button := _focus_button(battle)
	if button == null:
		print("FocusClickProbe: the card carries no focus button")
		return false
	print("FocusClickProbe: the button reads '%s'" % button.text)
	await _shot("wren_588_enemy_card_before_focus")
	button.emit_signal("pressed")
	await _settle()
	if battle.state.player_focus_id != want_foe.id:
		print("FocusClickProbe: pressing it left player_focus_id at %d" % battle.state.player_focus_id)
		failures += 1
	button = _focus_button(battle)
	print("FocusClickProbe: after pressing, the button reads '%s'" % (button.text if button != null else "GONE"))
	await _shot("wren_588_enemy_card_focused")

	## Tick in short steps and read the decision while the focus is still ALIVE.
	## The first version of this probe ticked 120 and then measured: the Goblin
	## was dead by then, so "nobody is aiming at it" was correct and the probe
	## was wrong.
	var checked := 0
	var went_for_it := 0
	for step in 40:
		var foe_now = battle.state.unit(battle.state.player_focus_id)
		if foe_now == null or not foe_now.alive:
			print("FocusClickProbe: the focus died after %d checks" % checked)
			break
		for u in battle.state.units:
			if not u.alive or u.pawn == null:
				continue
			var foes: Array = battle.state.living(CG.Team.ENEMY)
			var would = DefaultBehavior._choose_target(battle.state, u, foes)
			checked += 1
			if would != null and would.id == battle.state.player_focus_id:
				went_for_it += 1
		for tick in 3:
			battle._process(CG.TICK_SECONDS)
	await _settle()
	print("FocusClickProbe: %d of %d live decisions went for the focused enemy" % [went_for_it, checked])
	if checked == 0:
		print("FocusClickProbe: the focus died before a single decision was read, so this proves nothing")
		failures += 1
	elif went_for_it != checked:
		print("FocusClickProbe: %d decision(s) ignored the focus" % (checked - went_for_it))
		failures += 1
	await _shot("wren_588_party_on_the_focus")

	## The toggle back off, through the same button on the same open card, with
	## no second arena click: clicking a dead enemy's old position picks up
	## whoever walked over it, which is how this probe fooled itself once.
	var off := _focus_button(battle)
	if off == null:
		print("FocusClickProbe: the card closed, so the focus button is gone; reopening")
		var alive_foe = battle.state.living(CG.Team.ENEMY)[0]
		battle._unit_card.show_unit(battle.state, alive_foe)
		battle.state.player_focus_id = alive_foe.id
		battle._unit_card.refresh(battle.state)
		off = _focus_button(battle)
	if off == null:
		print("FocusClickProbe: still no focus button")
		return false
	var was: int = battle.state.player_focus_id
	off.emit_signal("pressed")
	await _settle()
	if battle.state.player_focus_id != -1:
		print("FocusClickProbe: pressing it on the focused enemy (%d) left the focus at %d" % [
			was, battle.state.player_focus_id])
		failures += 1
	else:
		print("FocusClickProbe: pressing it again cleared the focus")

	print("FocusClickProbe: %d failure(s)" % failures)
	return failures == 0
