extends Node

## Issue 593: where the player SEES whom the Warrior covers. The pawn-behaviour
## principle asks that the choice be findable, so this shoots the library row
## itself -- "Cover the weakest ally", a TARGETING block naming the ally and the
## block beneath it -- on the real party screen a player clicks.

const OUT := "res://Screenshots/finch_593_plan_row.png"

## The library renders a row as its blocks, so this is the sentence that proves
## the ally is CHOSEN rather than picked for the player behind the screen.
const ROW := "Directional Block"

var _main: Node = null

func _ready() -> void:
	Offscreen.hide_window(self)
	await _run()
	get_tree().quit(0)

func _settle(n: int = 8) -> void:
	for i in n:
		await get_tree().process_frame

func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _run() -> void:
	_main = load(ProjectSettings.get_setting("application/run/main_scene", "res://Scenes/Main.tscn")).instantiate()
	add_child(_main)
	await _settle()
	var select: Node = null
	for n in _walk(_main):
		if n.get_script() != null and n.get_script().resource_path.ends_with("PartySelect.gd"):
			select = n
	if select == null:
		printerr("Block593Plan: no party screen")
		return
	var pawn: PawnData = null
	for p in select.available_pawns():
		if p.pawn_class.id == &"warrior":
			pawn = p
	var card: Control = select._cards[pawn.id]
	var at := card.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		get_viewport().push_input(e)
		await _settle(2)
	await _settle()
	## The library is open and below the fold, so the shot has to scroll to it
	## the way a player would rather than assert it is already visible.
	var found := false
	for n in _walk(select._inspect_panel):
		if n is ScrollContainer:
			var y := _row_offset(n)
			if y >= 0:
				n.scroll_vertical = y
				found = true
	if not found:
		printerr("Block593Plan: no row reading '%s' on this screen" % ROW)
		return
	await _settle()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT)
	print("Block593Plan: wrote ", OUT)

## Where the block's own library row sits inside the scroller, or -1 if this is
## not the scroller holding it. Found by its text, so the capture cannot
## quietly drift onto a different row.
func _row_offset(scroller: ScrollContainer) -> int:
	for n in _walk(scroller):
		if n is Label and String(n.text).findn(ROW) >= 0:
			return maxi(0, int(n.get_global_rect().position.y - scroller.get_global_rect().position.y)
				+ scroller.scroll_vertical - 40)
	return -1
