extends SceneTree

## Issue 594: prints the top edge `test_art.gd` scores, for any shape.
##
## sable needed five attempts at the Rat King's crown -- 2, 5, 1, 4, 4 crests --
## before printing this and finding the cause was the tail. Their own lesson:
## "four guesses cost more than the one measurement that settled it, and I had
## the instrument the whole time." There was no instrument. This is it.
##
##   ... Tools/run.ps1 TopProfile -ToolArgs rat_king,rat

const RADIUS := 200.0
const COLUMNS := 40

## The same margin `test_art.gd` scores with, read here rather than retyped so
## the two cannot drift.
static func _margin() -> float:
	return RADIUS * 0.08

func _init() -> void:
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		for id in String(arg).split(",", false):
			ids.append(StringName(id))
	if ids.is_empty():
		ids = [&"rat_king", &"rat"]
	for id in ids:
		_report(id)
	quit(0)

func _report(id: StringName) -> void:
	if not Silhouettes.has_shape(id):
		print("TopProfile: no shape '%s'" % id)
		return
	var top := Silhouettes.top_profile(id, RADIUS, CG.Team.ENEMY, COLUMNS)
	var ext := _extremes(top, _margin())
	print("TopProfile: %s at radius %.0f, %d columns, margin %.1f" % [
		String(id), RADIUS, COLUMNS, _margin()])
	var crests := 0
	for i in ext.size():
		if i % 2 == 0:
			crests += 1
	print("  crests %d   shallowest valley %.1f" % [crests, _shallowest(ext)])
	print("  extremes (crest, valley, crest, ...): %s" % _fmt(ext))
	print("  profile: %s" % _fmt(top))

func _fmt(values) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append("inf" if is_inf(v) else "%.0f" % v)
	return ", ".join(parts)

## Lifted from `test_art.gd::_extremes` so the numbers printed are the numbers
## scored. Even indices are crests, odd ones valleys.
func _extremes(top: PackedFloat32Array, margin: float) -> Array:
	var vals: Array[float] = []
	for v in top:
		if v < INF:
			vals.append(v)
	if vals.is_empty():
		return []
	var out: Array = []
	var rising := true
	var extreme := vals[0]
	for v in vals:
		if rising:
			if v > extreme + margin:
				out.append(extreme)
				rising = false
				extreme = v
			elif v < extreme:
				extreme = v
		else:
			if v < extreme - margin:
				out.append(extreme)
				rising = true
				extreme = v
			elif v > extreme:
				extreme = v
	if rising:
		out.append(extreme)
	return out

func _shallowest(ext: Array) -> float:
	var shallowest := INF
	var i := 1
	while i < ext.size() - 1:
		shallowest = minf(shallowest, ext[i] - maxf(ext[i - 1], ext[i + 1]))
		i += 2
	return 0.0 if is_inf(shallowest) else shallowest
