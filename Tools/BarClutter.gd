extends SceneTree

## How ambiguous is a unit's chrome? Issue 82.
##
##   godot --headless --path . --script res://Tools/BarClutter.gd
##
## OWNER: wren. Not part of the game and not part of the gate.
##
## THIS EXISTS BECAUSE ISSUE 82 HAS BEEN WRONG TWICE FROM READING STILLS. The
## first version claimed units were 10px across and that a fight used a fifth of
## the arena; both were wrong, and `Tools/ArenaUsage.gd` was written to settle
## the second. This is the same instrument for the first: it samples every
## drawn bar of every living unit on every tick of real fights and reports four
## numbers rather than an impression.
##
## It reconstructs the geometry from `UnitView`'s own statics -- `bar_width`,
## `drawn_top`, `drawn_box`, `visual_offset`, `DISPLAY_SCALE` -- so it moves when
## the drawing moves. It is NOT a second copy of the layout: if `_draw` changes
## where the stack sits, the three lines below have to change with it, and that
## is the one thing to check before trusting a number from here.
##
## The four numbers, and what each is for:
##
##   nearer other body   A bar physically closer to a DIFFERENT unit's body than
##                       to its owner's. This is "bars often nearer to a
##                       different figure than their own", from a cold reader,
##                       as a percentage.
##   on another body     A bar drawn over another unit's silhouette. "Nothing
##                       tying a bar to a body."
##   bodies             Two silhouettes overlapping. Near zero, which is
##                       `UnitView.visual_offset` doing its job -- and it is the
##                       control that stops the other three being blamed on
##                       units standing inside each other.
##   party block ticks   The fraction of TICKS on which two party bar stacks
##                       share a column with less than two bar-heights between
##                       them: "teal, blue and orange bands merging with no
##                       clear owner", in the player's words. A per-tick figure
##                       rather than a per-pair one, because that is what
##                       somebody watching experiences.

const CG := preload("res://Scripts/Core/CG.gd")
const CombatSim := preload("res://Scripts/Combat/CombatSim.gd")
const CombatState := preload("res://Scripts/Core/CombatState.gd")
const Registry := preload("res://Scripts/Content/Registry.gd")
const PawnFactory := preload("res://Scripts/Content/PawnFactory.gd")
const PawnData := preload("res://Scripts/Core/PawnData.gd")
const UnitView := preload("res://Scripts/UI/UnitView.gd")
const PartySelect := preload("res://Scripts/UI/PartySelect.gd")

const PARTY := ["geysermancer", "priest", "siege_master", "warrior"]
const SEEDS := 20

func _shape(u) -> StringName:
	return u.pawn.pawn_class.id if (u.pawn != null and u.pawn.pawn_class != null) else u.enemy_id

func _pos(u, units) -> Vector2:
	return u.position + UnitView.visual_offset(u, units)

## The bar stack, mirroring UnitView._draw: resource row then hp row, stacked
## upward from the drawn body's top edge with one gap under each.
func _bars(u, units) -> Rect2:
	var radius: float = UnitView.display_radius(u)
	var shape := _shape(u)
	var w: float = UnitView.bar_width(radius, shape, u.team)
	var bh: float = UnitView.BAR_HEIGHT * UnitView.DISPLAY_SCALE
	var bg: float = UnitView.BAR_GAP * UnitView.DISPLAY_SCALE
	var rows := 2 if u.resource_max > 0 else 1
	var height := float(rows) * bh + float(rows) * bg
	var pos := _pos(u, units)
	return Rect2(pos.x - w * 0.5, pos.y - UnitView.drawn_top(shape, u.team, radius) - bg - height, w, height)

func _body(u, units) -> Rect2:
	var box: Rect2 = UnitView.drawn_box(_shape(u), u.team, UnitView.display_radius(u))
	return Rect2(box.position + _pos(u, units), box.size)

## Two stacks read as one striped block when they share a column and are closer
## than two bar heights: they do not have to overlap to merge, which is the
## thing a rectangle-intersection test misses and the reason this is measured
## separately from `on another body`.
func _reads_as_one_block(a: Rect2, b: Rect2) -> bool:
	if a.position.x >= b.end.x or b.position.x >= a.end.x:
		return false
	var gap: float = maxf(a.position.y, b.position.y) - minf(a.end.y, b.end.y)
	return gap < UnitView.BAR_HEIGHT * UnitView.DISPLAY_SCALE * 2.0

func _init() -> void:
	print("bar clutter: %d seeds per room, every tick of every fight" % SEEDS)
	print("%-20s %8s %10s %10s %8s %12s" % ["room", "bars", "nearer", "on body", "bodies", "block ticks"])
	var all_bars := 0
	var all_near := 0
	var all_over := 0
	for room in PartySelect.offered_rooms():
		var bars := 0
		var near := 0
		var over := 0
		var body_pairs := 0
		var pairs := 0
		var ticks := 0
		var block_ticks := 0
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in PARTY:
				party.append(PawnFactory.make_starter_pawn(
					StringName(cid), StringName(cid), Registry.get_class_def(StringName(cid)).display_name))
			var state := CombatSim.build(party, Registry.get_encounter(room), 0x2A + s)
			while state.outcome == CombatState.Outcome.UNRESOLVED:
				CombatSim.step(state)
				var live := []
				for u in state.units:
					if u.alive:
						live.append(u)
				var body_of := {}
				var bar_of := {}
				for u in live:
					body_of[u.id] = _body(u, live)
					bar_of[u.id] = _bars(u, live)
				ticks += 1
				var blocked := false
				for i in live.size():
					for j in range(i + 1, live.size()):
						pairs += 1
						if body_of[live[i].id].intersects(body_of[live[j].id]):
							body_pairs += 1
						if not _reads_as_one_block(bar_of[live[i].id], bar_of[live[j].id]):
							continue
						if live[i].team == CG.Team.PLAYER and live[j].team == CG.Team.PLAYER:
							blocked = true
				if blocked:
					block_ticks += 1
				for u in live:
					bars += 1
					var bar: Rect2 = bar_of[u.id]
					var nearest: float = bar.get_center().distance_to(body_of[u.id].get_center())
					var owner: int = u.id
					for o in live:
						if o.id == u.id:
							continue
						if bar.intersects(body_of[o.id]):
							over += 1
						var d: float = bar.get_center().distance_to(body_of[o.id].get_center())
						if d < nearest:
							nearest = d
							owner = o.id
					if owner != u.id:
						near += 1
		print("%-20s %8d %9.1f%% %9.1f%% %7.1f%% %11.1f%%" % [
			room, bars,
			100.0 * float(near) / float(maxi(1, bars)),
			100.0 * float(over) / float(maxi(1, bars)),
			100.0 * float(body_pairs) / float(maxi(1, pairs)),
			100.0 * float(block_ticks) / float(maxi(1, ticks)),
		])
		all_bars += bars
		all_near += near
		all_over += over
	print("%-20s %8d %9.1f%% %9.1f%%" % [
		"ALL", all_bars,
		100.0 * float(all_near) / float(maxi(1, all_bars)),
		100.0 * float(all_over) / float(maxi(1, all_bars)),
	])
	quit(0)
