extends Node2D
class_name DeployView

## Placement. The legal band drawn on the arena the fight itself uses, and the
## two static rules that decide where a pawn may stand.

## Was a screen of its own until the player asked for placement on the battle
## screen: "I should basically be moving them around in a paused battle screen
## and then unpausing it."

## Same rect and same colour the level editor's overlay draws, so the band means
## one thing everywhere it appears.
const ZONE_ALPHA := 0.14

func _draw() -> void:
	var top_left := Vector2(-CG.ARENA_HALF_WIDTH, -CG.ARENA_HALF_HEIGHT)
	var bottom_right := Vector2(CG.party_deploy_max_x(), CG.ARENA_HALF_HEIGHT)
	var color := Palette.TEAM_PLAYER
	color.a = ZONE_ALPHA
	draw_rect(Rect2(top_left, bottom_right - top_left), color)

## Where the fight would start the party with nobody having placed anything,
## taken from `CombatSim.party_spawn_position` rather than reimplemented, so
## placement opens on the status quo instead of on a second opinion about it.
static func authored_positions(encounter, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in count:
		out.append(CombatSim.party_spawn_position(encounter, i))
	return out

## A copy of the room with the player's placement written into it. A copy and
## not a mutation: `Registry`'s encounters are shared, and writing placement
## straight into one would silently change every later fight in the same room --
## including the re-run that exists to be a comparison control.
static func encounter_with_placement(base, positions: Array[Vector2]):
	var out := Encounter.new()
	out.id = base.id
	out.display_name = base.display_name
	out.enemy_spawns = base.enemy_spawns
	out.terrain = base.terrain
	var spawns: Array[Vector2] = []
	for p in positions:
		spawns.append(p)
	out.party_spawns = spawns
	return out
