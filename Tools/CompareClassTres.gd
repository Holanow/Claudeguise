extends SceneTree

## Scratch, issue 628: every field of every generated `.tres` against the
## ClassDef `starting_classes.gd` builds, so the round trip is proved rather
## than assumed.

func _init() -> void:
	var mod := load("res://Scripts/Content/Modules/starting_classes.gd")
	var failures := 0
	var checks := 0
	for old in mod.classes():
		var path := "res://Scripts/Content/Classes/%s.tres" % old.id
		var new_def: ClassDef = load(path)
		if new_def == null:
			print("FAIL  %s did not load" % path)
			failures += 1
			continue
		for a in ClassDef.ATTRIBUTE_NAME:
			checks += 1
			if old.attribute(a) != new_def.attribute(a):
				print("FAIL  %s.%s  old=%d new=%d" % [old.id, ClassDef.ATTRIBUTE_NAME[a], old.attribute(a), new_def.attribute(a)])
				failures += 1
		checks += 1
		if old.base_attributes.size() != new_def.base_attributes.size():
			print("FAIL  %s base_attributes size %d vs %d" % [old.id, old.base_attributes.size(), new_def.base_attributes.size()])
			failures += 1
		for field in ["id", "display_name", "method", "style", "role_primary", "role_secondary", "damage_types", "resource_kind"]:
			checks += 1
			if str(old.get(field)) != str(new_def.get(field)):
				print("FAIL  %s.%s  old=%s new=%s" % [old.id, field, old.get(field), new_def.get(field)])
				failures += 1
		checks += 1
		if str(old.starting_action_ids()) != str(new_def.starting_action_ids()):
			print("FAIL  %s.starting_actions  old=%s new=%s" % [old.id, old.starting_action_ids(), new_def.starting_action_ids()])
			failures += 1
		for i in range(new_def.starting_actions.size()):
			checks += 1
			if new_def.starting_actions[i] != Registry.get_action(new_def.starting_actions[i].id):
				print("FAIL  %s action %d is not the registry's instance" % [old.id, i])
				failures += 1
		checks += 1
		if not new_def.invalid_attribute_keys().is_empty():
			print("FAIL  %s has bad attribute keys %s" % [old.id, new_def.invalid_attribute_keys()])
			failures += 1
	print("CompareClassTres: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
