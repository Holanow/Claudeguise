extends RefCounted
class_name EncounterCodec


## Converts an `Encounter` to and from the plain `Dictionary` shape kite's
## level editor (`Scripts/UI/LevelEditorView.gd::_encounter_dict`) already
## writes to `res://Assets/Rooms/<id>.json` -- posted to TEAM_LOG.md and
## agreed there before either side of issue 19 was built, so this is the
## decode half of a contract already fixed by the encoder, not a shape
## invented here.
##
## OWNER: dace. Pure and side-effect free, same reasoning as
## `_encounter_dict` itself: a test can check the exact round trip without
## touching a file, and `Modules/authored_rooms.gd` is the only thing that
## reads a real file and calls this.
##
## `kind`/`damage_type` round-trip as the enum's own string name
## (`Terrain.Kind.keys()[k]` / `CG.DamageType.keys()[d]`), not a raw int --
## survives either enum being reordered, matching `describe_op`'s existing
## reasoning for reading an enum back as text elsewhere in this codebase.

static func encounter_to_dict(e: Encounter) -> Dictionary:
	var enemies := []
	for spawn in e.enemy_spawns:
		var pos: Vector2 = spawn.get("position", Vector2.ZERO)
		enemies.append({"enemy_id": String(spawn.get("enemy_id", &"")), "x": pos.x, "y": pos.y})
	var spawns := []
	for p in e.party_spawns:
		spawns.append({"x": p.x, "y": p.y})
	var terrain_out := []
	for f in e.terrain:
		terrain_out.append({
			"kind": Terrain.Kind.keys()[f.kind],
			"x": f.rect.position.x,
			"y": f.rect.position.y,
			"w": f.rect.size.x,
			"h": f.rect.size.y,
			"damage_per_tick": f.damage_per_tick,
			"damage_type": CG.DamageType.keys()[f.damage_type],
		})
	return {
		"id": String(e.id),
		"display_name": e.display_name,
		"enemy_spawns": enemies,
		"party_spawns": spawns,
		"terrain": terrain_out,
	}

## Returns null on anything malformed rather than a half-built Encounter --
## `Modules/authored_rooms.gd` treats null as "skip this file, log why", the
## same "unknown id reads as does-nothing, not as a crash" posture the rest
## of the content layer already takes for a bad reference (`Registry`'s own
## `get_*` functions return null on a miss rather than erroring).
static func dict_to_encounter(d: Dictionary) -> Encounter:
	if not (d.has("id") and d.has("display_name")):
		return null
	var id := String(d.get("id", ""))
	if id.is_empty():
		return null
	var e := Encounter.new()
	e.id = StringName(id)
	e.display_name = String(d.get("display_name", ""))

	var enemy_spawns: Array[Dictionary] = []
	for raw in d.get("enemy_spawns", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		enemy_spawns.append({
			"enemy_id": StringName(String(raw.get("enemy_id", ""))),
			"position": Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0))),
		})
	e.enemy_spawns = enemy_spawns

	var party_spawns: Array[Vector2] = []
	for raw in d.get("party_spawns", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		party_spawns.append(Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0))))
	e.party_spawns = party_spawns

	var terrain: Array = []
	for raw in d.get("terrain", []):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var kind_name := String(raw.get("kind", ""))
		var kind_index := Terrain.Kind.keys().find(kind_name)
		if kind_index < 0:
			continue
		var damage_type_name := String(raw.get("damage_type", ""))
		var damage_type_index := CG.DamageType.keys().find(damage_type_name)
		var rect := Rect2(
			float(raw.get("x", 0.0)), float(raw.get("y", 0.0)),
			float(raw.get("w", 0.0)), float(raw.get("h", 0.0))
		)
		var f := Terrain.make(kind_index as Terrain.Kind, rect)
		f.damage_per_tick = int(raw.get("damage_per_tick", 0))
		if damage_type_index >= 0:
			f.damage_type = damage_type_index as CG.DamageType
		terrain.append(f)
	e.terrain = terrain

	return e
