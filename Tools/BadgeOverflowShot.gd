extends Node

## Issue 161: a fifth status was dropped with nothing saying so.
##   godot --path . --resolution 1280x720 res://Tools/BadgeOverflowShot.tscn
##
## Piles six statuses onto ONE unit -- IconsInFight spreads them across every
## living unit, so it never produces the overflow case at all. Captures at 1x
## and at 3x, because sable's finding is that these badges are unreadable at
## true size and a legibility claim made from a zoom is not a claim about the
## game.

const CG := preload("res://Scripts/Core/CG.gd")
const UnitView := preload("res://Scripts/UI/UnitView.gd")

const OUT_DIR := "res://Screenshots"
var _main: Node
var _fail := 0

func _ready() -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://.git")):
		printerr("BadgeOverflowShot: use a worktree."); get_tree().quit(2); return
	await _run()
	print("BadgeOverflowShot: %d failure(s)" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)

func _settle(n := 6) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _press(prefix: String) -> bool:
	for n in _walk(_main):
		if n is Button and n.is_visible_in_tree() and n.text.to_lower().begins_with(prefix.to_lower()):
			n.emit_signal("pressed"); return true
	print("BadgeOverflowShot: no button '%s'" % prefix); return false

func _node_with(f: String) -> Node:
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with(f):
			return n
	return null

func _check(ok: bool, msg: String) -> void:
	print("BadgeOverflowShot: %s %s" % ["OK  " if ok else "FAIL", msg])
	if not ok: _fail += 1

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("BadgeOverflowShot: %s.png" % name)

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var cards: Array[Node] = []
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartyCard.gd"):
			cards.append(n)
	for i in mini(4, cards.size()):
		cards[i].toggled.emit(true)
	await _settle()
	if not _press("start fight"): return
	await _settle()
	if not _press("start fight"): return
	await _settle()
	var battle := _node_with("BattleView.gd")
	_check(battle != null, "reached the battle")
	if battle == null: return

	battle.set_paused(true)
	var subject = null
	for u in battle.state.units:
		if u.alive and u.team == CG.Team.PLAYER:
			subject = u
			break
	if subject == null: return

	# Six harmful-and-beneficial statuses on one unit: more than the cap.
	var applied := 0
	for s in CG.Status.values():
		if applied >= 6: break
		subject.statuses[s] = CG.MAX_TICKS
		applied += 1
	var shown: int = UnitView.status_badges(subject).size()
	var hidden: int = UnitView.hidden_status_count(subject)
	print("BadgeOverflowShot: %d statuses -> %d badges + '+%d'" % [applied, shown, hidden])
	_check(hidden > 0, "the overflow is reported rather than dropped")
	_check(shown + hidden == applied, "every status is drawn or counted")
	_check(shown + 1 <= UnitView.MAX_STATUS_BADGES, "the row is no wider than the cap")

	for view in _walk(battle):
		if view.get_script() == UnitView:
			view.queue_redraw()
	await _settle()
	await _shot("wren_badge_overflow_1x")

	# Same frame at 3x, cropped to the subject, so the chip can be read.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var arena = battle.get_node("Arena")
	var at: Vector2 = arena.position + subject.position * arena.scale.x
	var box := Rect2i(Vector2i(at) - Vector2i(90, 110), Vector2i(180, 200))
	box = box.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if box.size.x > 0 and box.size.y > 0:
		var crop := img.get_region(box)
		crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		crop.save_png("%s/wren_badge_overflow_3x.png" % OUT_DIR)
		print("BadgeOverflowShot: wren_badge_overflow_3x.png")
