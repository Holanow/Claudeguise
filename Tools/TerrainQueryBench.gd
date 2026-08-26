extends SceneTree

## Issue 625: what the three terrain queries cost as the feature count grows.
## Run before and after the tilemap port and compare. Same geometry both times.

const COUNTS := [8, 64, 329]
const REPS := 20000

func _initialize() -> void:
	print("terrain query cost, %d reps per row" % REPS)
	print("%8s %14s %16s %12s" % ["features", "line_is_blocked", "point_is_blocked", "hazards_at"])
	for n in COUNTS:
		var features := _build(n)
		var pts := _probe_points()
		print("%8d %12.1f us %14.1f us %10.1f us" % [
			n,
			_time_line(features, pts),
			_time_point(features, pts),
			_time_hazards(features, pts),
		])
	quit(0)

## A spread of features over the arena, deterministic and independent of `n`'s
## other rows: kind cycles so every row has the same mix.
func _build(n: int) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 625
	for i in n:
		var pos := Vector2(
			rng.randf_range(-CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH - 60.0),
			rng.randf_range(-CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT - 60.0))
		var rect := Rect2(pos, Vector2(rng.randf_range(20.0, 60.0), rng.randf_range(20.0, 60.0)))
		match i % 4:
			0: out.append(Terrain.make(Terrain.Kind.WALL, rect))
			1: out.append(Terrain.make(Terrain.Kind.PILLAR, rect))
			2: out.append(Terrain.hazard(rect, 2, CG.DamageType.FIRE))
			3: out.append(Terrain.pool(rect))
	return out

func _probe_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 626
	for i in 64:
		out.append(Vector2(
			rng.randf_range(-CG.ARENA_HALF_WIDTH, CG.ARENA_HALF_WIDTH),
			rng.randf_range(-CG.ARENA_HALF_HEIGHT, CG.ARENA_HALF_HEIGHT)))
	return out

func _time_line(features: Array, pts: Array[Vector2]) -> float:
	var t := Time.get_ticks_usec()
	for i in REPS:
		Terrain.line_is_blocked(features, pts[i % 64], pts[(i * 7 + 3) % 64])
	return float(Time.get_ticks_usec() - t) / float(REPS)

func _time_point(features: Array, pts: Array[Vector2]) -> float:
	var t := Time.get_ticks_usec()
	for i in REPS:
		Terrain.point_is_blocked(features, pts[i % 64], 22.0)
	return float(Time.get_ticks_usec() - t) / float(REPS)

func _time_hazards(features: Array, pts: Array[Vector2]) -> float:
	var t := Time.get_ticks_usec()
	for i in REPS:
		Terrain.hazards_at(features, pts[i % 64])
	return float(Time.get_ticks_usec() - t) / float(REPS)
