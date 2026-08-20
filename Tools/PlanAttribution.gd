extends SceneTree

## Issue 155. What the plan tag costs the log, and what it says.
##
##   godot --headless --path . --script res://Tools/PlanAttribution.gd
##
## Not part of the game and not part of the gate.
##
## Two questions, and the second is the one that decides whether the tag belongs
## in the line at all:
##
##   1. How many log lines does a fight produce, and how many of them get a tag?
##      "Adding a clause to every line makes it longer" is the issue's own
##      objection and it is answerable with a number rather than an opinion.
##   2. What do the tags SAY? A tag that reads "plan 1" on every single action is
##      a tag nobody needs, and a tag that reads "fallback" on every single
##      action is a report that the plans are not running.
##
## Runs the real `CombatLogView.line_for_event` over real fights in every room a
## player can pick, so the counts are of lines that actually reach the screen --
## `line_for_event` returns "" for a great many events and counting `state.events`
## would overstate the log by several times.


const SEEDS := 20

func _init() -> void:
	var log_view := CombatLogView.new()
	var class_ids := Registry.all_class_ids()
	var party_ids := class_ids.slice(0, mini(4, class_ids.size()))

	var total_lines := 0
	var tagged := 0
	var untagged_starts := 0
	var by_tag := {}
	var chars_plain := 0
	var chars_tagged := 0

	for room_id in PartySelect.offered_rooms():
		var encounter := Registry.get_encounter(room_id)
		if encounter == null:
			continue
		for s in SEEDS:
			var party: Array[PawnData] = []
			for cid in party_ids:
				party.append(PawnFactory.make_starter_pawn(
					cid, StringName("%s" % cid), Registry.get_class_def(cid).display_name))
			var state := CombatSim.build(party, encounter, s)
			CombatSim.run(state)
			for e in state.events:
				var line := log_view.line_for_event(state, e)
				if line == "":
					continue
				total_lines += 1
				if e.kind != CG.EventKind.ACTION_START:
					continue
				var source := state.unit(e.source_id)
				var tag := _tag_of(log_view, source, e)
				if tag == "":
					untagged_starts += 1
					continue
				tagged += 1
				by_tag[tag] = int(by_tag.get(tag, 0)) + 1
				chars_tagged += _plain_length(line)
				chars_plain += _plain_length(line) - (tag.length() + 3)

	print("=== issue 155: what the plan tag costs and what it says ===")
	print("rooms %d x seeds %d" % [PartySelect.offered_rooms().size(), SEEDS])
	print("")
	print("log lines that reach the screen : %d" % total_lines)
	print("  of those, tagged              : %d (%.1f%%)" % [
		tagged, 100.0 * float(tagged) / maxf(1.0, float(total_lines))])
	print("  ACTION_STARTs left untagged   : %d  (enemies: no plans to name)" % untagged_starts)
	print("")
	print("mean tagged line, characters    : %.1f -> %.1f (+%.1f)" % [
		float(chars_plain) / maxf(1.0, float(tagged)),
		float(chars_tagged) / maxf(1.0, float(tagged)),
		float(chars_tagged - chars_plain) / maxf(1.0, float(tagged))])
	print("")
	print("what the tags say:")
	var keys := by_tag.keys()
	keys.sort()
	for k in keys:
		print("  %-12s %6d  (%.1f%% of tags)" % [
			k, by_tag[k], 100.0 * float(by_tag[k]) / maxf(1.0, float(tagged))])
	quit(0)

## The tag text, taken from the same function the log uses rather than from a
## second copy of the rule -- rule 3 on the board: a check that rebuilds its own
## expectation cannot fail.
func _tag_of(log_view, source, e) -> String:
	var tag: String = log_view._plan_tag(source, e)
	if tag == "":
		return ""
	var open: int = tag.find("[", tag.find("]") + 1)
	return tag.substr(open + 1, tag.find("]", open) - open - 1)

func _plain_length(line: String) -> int:
	var out := ""
	var depth := 0
	for i in line.length():
		var c := line[i]
		if c == "[":
			depth += 1
		elif c == "]":
			depth = maxi(0, depth - 1)
		elif depth == 0:
			out += c
	return out.length()
