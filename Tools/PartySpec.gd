extends RefCounted
class_name PartySpec

## Issue 808: the party is four, and which four is a choice. Every sweep tool
## used to build from `ClassLibrary.all_ids()`, so the party silently grew
## with the library and every number this project has taken is a party-of-five
## number.

const PARTY_SIZE := 4

## Every composition a sweep runs. `--party warrior,priest,...` names one;
## absent, all size-4 compositions of the class library.
static func compositions() -> Array:
	var named := _from_cmdline()
	if not named.is_empty():
		return [named]
	return _combinations(ClassLibrary.all_ids(), PARTY_SIZE)

## Empty when no `--party` was given, and empty after an unknown id has been
## reported -- a typo must not quietly run a party of three.
static func _from_cmdline() -> Array:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] != "--party" or i + 1 >= args.size():
			continue
		var ids: Array = []
		for name in String(args[i + 1]).split(",", false):
			var c := StringName(name.strip_edges())
			if ClassLibrary.get_class_def(c) == null:
				printerr("--party: no such class '%s'; known: %s" % [c, ClassLibrary.all_ids()])
				return []
			ids.append(c)
		return ids
	return []

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
static func make(ids: Array, planned: bool) -> Array[PawnData]:
	var party: Array[PawnData] = []
	for id in ids:
		var c := StringName(id)
		var display := ClassLibrary.get_class_def(c).display_name
		party.append(PawnFactory.make_preset_pawn(c, c, display) if planned \
			else PawnFactory.make_starter_pawn(c, c, display))
	return party
