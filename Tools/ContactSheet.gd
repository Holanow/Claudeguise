extends Node

## Renders one real fight through the real battle screen and saves a strip of
## frames from it, so the state of the game can be looked at rather than read
## about.


const BATTLE_SCENE := preload("res://Scenes/Battle.tscn")
const ScreenSweepScript := preload("res://Tools/ScreenSweep.gd")

const OUT_DIR := "res://Tools/preview"
const SHEET_PATH := "res://Tools/preview/fight_sheet.png"

const FRAMES := 6
const SEED := 0x2A

var _battle: Node = null
var _shots: Array[Image] = []
var _targets: Array[int] = []
var _next := 0
var _parties: Array = []
var _party_index := 0
## `_capture` awaits the end of the frame, so the next fight must not start
## until it has resumed and appended its image.
var _capturing := false

func _ready() -> void:
	Offscreen.hide_window(self)
	var class_ids := Registry.all_class_ids()
	var encounter_ids := Registry.all_encounter_ids()
	if class_ids.is_empty() or encounter_ids.is_empty():
		printerr("ContactSheet: no content registered")
		get_tree().quit(1)
		return

	## Parties that between them contain every class, rather than the first four
	## of an alphabetical roster, which never held a Warrior (#350).
	_parties = ScreenSweepScript.sweep_parties(class_ids)
	_start_fight()

func _start_fight() -> void:
	var party_ids: Array = _parties[_party_index]

	# Run the fight once headlessly first, only to learn how long it lasts, so
	# the frames can be spread across its actual arc. The screen then plays the
	# same seed and reaches the same ticks, because that is the whole point of
	# the determinism rule.
	var probe := CombatSim.build(_party(party_ids), Registry.get_encounter(CG.DEFAULT_ENCOUNTER), SEED)
	CombatSim.run(probe)
	var total: int = maxi(probe.tick, FRAMES)
	print("ContactSheet: party %s lasts %d ticks (%.1fs), outcome %d" % [
		", ".join(PackedStringArray(party_ids)), probe.tick,
		float(probe.tick) / float(CG.TICKS_PER_SECOND), probe.outcome
	])

	_targets = []
	_next = 0
	for i in FRAMES:
		# Skip tick 0: the interesting part is never the moment nothing has
		# happened yet. Last frame lands just before the end, not after it,
		# because a finished fight is a static screen.
		_targets.append(int(round(float(total) * float(i + 1) / float(FRAMES + 1))))

	var cfg := RunConfig.new()
	cfg.party = _party(party_ids)
	cfg.encounter_id = CG.DEFAULT_ENCOUNTER
	cfg.seed = SEED

	if _battle != null:
		_battle.queue_free()
	_battle = BATTLE_SCENE.instantiate()
	add_child(_battle)
	_battle.begin(cfg)

func _party(ids: Array) -> Array[PawnData]:
	var out: Array[PawnData] = []
	for cid in ids:
		# `cls.display_name`, the same source PartySelect uses, not `String(cid)`.
		out.append(PawnFactory.make_starter_pawn(
			cid, StringName("%s_%d" % [cid, out.size()]), ClassLibrary.get_class_def(cid).display_name
		))
	return out

func _process(_delta: float) -> void:
	if _capturing or _battle == null or _next >= _targets.size():
		return
	var state = _battle.state
	if state == null:
		return
	if state.tick < _targets[_next]:
		return
	_capturing = true
	await _capture(_next)
	_capturing = false
	_next += 1
	if _next < _targets.size():
		return
	_party_index += 1
	if _party_index < _parties.size():
		_start_fight()
		return
	_write_sheet()
	get_tree().quit(0)

func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_shots.append(image)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/fight_%02d.png" % [OUT_DIR, _shots.size()]
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
