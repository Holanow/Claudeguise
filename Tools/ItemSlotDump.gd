extends SceneTree

## Issue 745 verification: load all eleven items and print each one's slot,
## so a renumbered enum that silently re-slots an item shows up here rather
## than nowhere.

func _init() -> void:
	for id in ItemLibrary.all_ids():
		var item := ItemLibrary.get_equipment(id)
		print("%s: slot=%d (%s)" % [id, item.slot, EquipmentDef.Slot.keys()[item.slot]])
	quit()
