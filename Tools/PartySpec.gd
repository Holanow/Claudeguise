extends RefCounted
class_name PartySpec

## Issue 808: the party is four, and which four is a choice. Every sweep tool
## used to build from `ClassLibrary.all_ids()`, so the party silently grew
## with the library and every number this project has taken is a party-of-five
## number.

const PARTY_SIZE := 4

## Every composition a sweep runs. `--party warrior,priest,...` names one;
## absent, all size-4 compositions of the class library. Empty means a
## `--party` was given and refused, which every caller reports and quits on --
## a refused spec must never fall through to the whole sweep.
static func compositions() -> Array:
	if not OS.get_cmdline_user_args().has("--party"):
		return _combinations(ClassLibrary.all_ids(), PARTY_SIZE)
	var named := _from_cmdline()
	return [] if named.is_empty() else [named]

## Refuses an unknown id, a duplicate, and any count but PARTY_SIZE. A pawn's
## id is its class id, so two of one class collide in `FloorRun.carry`.
static func _from_cmdline() -> Array:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--party")
	if at + 1 >= args.size():
		printerr("--party needs a comma-separated list of %d class ids" % PARTY_SIZE)
		return []
	var ids: Array = []
	for name in String(args[at + 1]).split(",", false):
		var c := StringName(name.strip_edges())
		if ClassLibrary.get_class_def(c) == null:
			printerr("--party: no such class '%s'; known: %s" % [c, ClassLibrary.all_ids()])
			return []
		if ids.has(c):
			printerr("--party: '%s' twice; one pawn per class, ids collide otherwise" % c)
			return []
		ids.append(c)
	if ids.size() != PARTY_SIZE:
		printerr("--party: %d classes, and the party is %d" % [ids.size(), PARTY_SIZE])
		return []
	return ids

## Lexicographic by index, so the order a report lists compositions in does
## not depend on anything but the class library's own order.
static func _combinations(ids: Array, size: int) -> Array:
	if size == 0:
		return [[]]
	var out: Array = []
	for i in ids.size():
		if ids.size() - i < size:
			break
		for tail in _combinations(ids.slice(i + 1), size - 1):
			out.append([ids[i]] + tail)
	return out

static func label(ids: Array) -> String:
	var parts := PackedStringArray()
	for id in ids:
		parts.append(String(id))
	return ", ".join(parts)

## One pawn per id, preset plans for arm B and a bare starter for arm A.
## Order is kept: it decides placement, so the same four in another order is a
## different fight. A sweep uses `ClassLibrary.all_ids()`' sorted order.
static func make(ids: Array, planned: bool) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for id in ids:
		var c := StringName(id)
		var display := ClassLibrary.get_class_def(c).display_name
		party.append(PawnFactory.make_preset_pawn(c, c, display) if planned \
			else PawnFactory.make_starter_pawn(c, c, display))
	return party
