extends RefCounted


## Every enemy in the slice that is not a monster, plus the loader for the
## action library. Issue 621 moved the actions themselves out of GDScript and
## into `.tres` under `Scripts/Content/Actions/`.

## "Reaches anywhere in the room", expressed as a real number.
const ARENA_SPAN := 1200.0

static func classes() -> Array[ClassDef]:
	return []

static func actions() -> Array[ActionDef]:
	var out: Array[ActionDef] = []
	for path in ActionLibrary.PATHS:
		out.append(load(path))
	return out

static func enemies() -> Array[EnemyDef]:
	return [
		## An allied minion, and it shares the monster profile because it shares
		## `EnemyDef` -- the player confirmed that. It must NOT ride the per-floor
		## monster curve when one exists: minions scale with their summoner, and
		## pawn progression is undesigned, so nothing here builds either.
		##
		## 1.4x hp is 140 against the Siege Master's 114. The minion is tankier
		## than the pawn that builds it. Reported by issue 542, not changed by it.
		_enemy(&"siege_engine", "Siege Engine", 1.4, 1.6, 0.0, 0.0, 1.0, 30.0, CG.DamageType.PHYSICAL, [&"siege_engine_bolt"], ["Ranged", "Construct"], 0.0),
	]

static func encounters() -> Array[Encounter]:
	return []

static func items() -> Array[EquipmentDef]:
	return []

static func _enemy(id: StringName, display_name: String, hp_mult: float, damage_mult: float, move_mult: float, resist_mult: float, action_speed: float, radius: float, damage_type: CG.DamageType, actions: Array[StringName], display_tags: Array[String], focus_bias: float = 0.0, resource_max: int = 0, resource_kind: CG.ResourceKind = CG.ResourceKind.ENERGY) -> EnemyDef:
	var e := EnemyDef.new()
	e.id = id
	e.display_name = display_name
	e.hp_max = MonsterProfile.hp(hp_mult)
	e.resource_max = resource_max
	e.resource_kind = resource_kind
	e.move_speed = MonsterProfile.move_speed(move_mult)
	e.radius = radius
	e.attack_power = {damage_type: MonsterProfile.damage(damage_mult)}
	e.damage_reduction = MonsterProfile.resistance(resist_mult)
	e.action_speed = action_speed
	e.actions = actions
	e.display_tags = display_tags
	e.focus_bias = focus_bias
	return e
