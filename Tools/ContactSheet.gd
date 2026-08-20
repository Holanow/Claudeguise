extends Node

## Renders one real fight through the real battle screen and saves a strip of
## frames from it, so the state of the game can be looked at rather than read
## about.


const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")

const OUT_DIR := "res://Tools/preview"
const SHEET_PATH := "res://Tools/preview/fight_sheet.png"

const FRAMES := 6
const SEED := 0x2A

var _battle: Node = null
var _shots: Array[Image] = []
var _targets: Array[int] = []
var _next := 0

func _ready() -> void:
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("ContactSheet: no content registered")
		get_tree().quit(1)
		return

	# A mixed party, because four of one class is not what anybody plays.
	var party_ids := class_ids.slice(0, mini(4, class_ids.size()))

	# Run the fight once headlessly first, only to learn how long it lasts, so
	# the frames can be spread across its actual arc. The screen then plays the
	# same seed and reaches the same ticks, because that is the whole point of
	# the determinism rule.
	var probe := CombatSim.build(_party(party_ids), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), SEED)
	CombatSim.run(probe)
	var total: int = maxi(probe.tick, FRAMES)
	print("ContactSheet: fight lasts %d ticks (%.1fs), outcome %d" % [
		probe.tick, float(probe.tick) / float(CG.TICKS_PER_SECOND), probe.outcome
	])

	for i in FRAMES:
		# Skip tick 0: the interesting part is never the moment nothing has
		# happened yet. Last frame lands just before the end, not after it,
		# because a finished fight is a static screen.
		_targets.append(int(round(float(total) * float(i + 1) / float(FRAMES + 1))))

	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED

	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		# `cls.display_name`, the same source PartySelect uses, not `String(cid)`.
		out.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), Registry.get_class_def(cid).display_name
		))
	return out

func _process(_delta: float) -> void:
	if _battle == null or _next >= _targets.size():
		return
	var state = _battle.state
	if state == null:
		return
	if state.tick < _targets[_next]:
		return
	_capture(_next)
	_next += 1
	if _next >= _targets.size():
		_write_sheet()
		get_tree().quit(0)

func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shots.append(image)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/fight_%02d.png" % [OUT_DIR, index + 1]
	image.save_png(path)
	print("ContactSheet: %s at tick %d" % [path, _targets[index]])

## Stacks the frames into one tall image. One file to open beats six, and the
## whole point is that somebody actually looks at it.
func _write_sheet() -> void:
	if _shots.is_empty():
		return
	var w := _shots[0].get_width()
	var h := _shots[0].get_height()
	var gap := 8
	var sheet := Image.create(w, h * _shots.size() + gap * (_shots.size() - 1), false, _shots[0].get_format())
	sheet.fill(Color("14131a"))
	for i in _shots.size():
		sheet.blit_rect(_shots[i], Rect2i(0, 0, w, h), Vector2i(0, i * (h + gap)))
	sheet.save_png(SHEET_PATH)
	print("ContactSheet: wrote ", SHEET_PATH)
