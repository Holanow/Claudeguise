extends SceneTree

## Issue 621. What the action layer costs to build once and to read 380,000
## times, so the `.tres` migration is reported against the shape it replaced
## rather than against a guess.
##
## Two read arms, because they cost different things: the flat bridge
## (`a.power_scale`) walks `effects` on every read, and the sim walks the list
## once and dispatches. Issue 622 deletes the first.

const LOOKUP_REPEATS := 10000

func _init() -> void:
	var t0 := Time.get_ticks_usec()
	Registry._load()
	var build_us := Time.get_ticks_usec() - t0

	var ids := ActionLibrary.all_ids()
	var lookups := 0
	var sink := 0.0
	var t1 := Time.get_ticks_usec()
	for _i in LOOKUP_REPEATS:
		for id in ids:
			var a := Registry.get_action(id)
			sink += a.power_scale
			lookups += 1
	var lookup_us := Time.get_ticks_usec() - t1

	var sink2 := 0.0
	var t2 := Time.get_ticks_usec()
	for _i in LOOKUP_REPEATS:
		for id in ids:
			var a := Registry.get_action(id)
			for fx in a.effects:
				if fx is HitEffect:
					sink2 += fx.power_scale
	var direct_us := Time.get_ticks_usec() - t2

	print("actions in registry:  ", ids.size())
	print("registry build:       ", build_us, " us")
	print("lookups:              ", lookups)
	print("lookup total:         ", lookup_us, " us")
	print("direct effect walk:   ", direct_us, " us")
	print("sink (ignore):        ", sink, " ", sink2)
	quit(0)
