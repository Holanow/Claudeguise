extends Resource

## One room's worth of fight: which enemies, where they and the party start.
##
## MANAGER-OWNED SHAPE. The slice's single encounter lives in
## Scripts/Content/Encounters/ and belongs to teal.
##
## Spawn positions are explicit rather than generated. The slice is one hand
## authored room, and a procedural layout would put a second variable in front
## of the question being asked.

@export var id: StringName = &""
@export var display_name: String = ""

## Issue 180. Whether the room picker offers this encounter to the player.
##
## **The set of pickable rooms was written in three places and only one was
## machine-readable**: prose in `floor1_encounters.gd`, `PICKABLE` in a test, and
## `ROOM_ORDER` in `Scripts/UI` -- the last being both the only one a tool could
## see and the one furthest from the content. Adding a fifth room meant
## remembering all three, and forgetting the UI one is exactly how three rooms sat
## unreachable for days.
##
## Declared here rather than derived by a `Registry.pickable_encounter_ids()`,
## because a derived function still needs a list to derive from and so relocates
## the third source of truth instead of removing it. The content declares it; both
## readers query it.
##
## **Defaults to false, so an encounter that says nothing is not offered.** The
## safer direction: a new room silently missing from the picker is a bug somebody
## notices, while a new room silently *appearing* in it is one they may not.
@export var pickable: bool = false

## One entry per enemy. Each is { "enemy_id": StringName, "position": Vector2 }.
@export var enemy_spawns: Array[Dictionary] = []

## Where party members stand, in party order. Shorter than the party means the
## remaining pawns are placed by the simulation behind the last given point.
@export var party_spawns: Array[Vector2] = []

## Walls, pillars, hazards and pits, as `Terrain.Feature`. Untyped `Array` to
## match `Terrain.gd`'s own API, which takes and returns plain arrays everywhere
## — the same choice as `CombatState.terrain`, and for the same reason.
##
## Empty by default, so every encounter that does not set it behaves exactly as
## it did before terrain existed, and no measurement anybody has taken becomes
## invalid on the day this lands.
##
## NOT YET WIRED, as of the commit that added this field. `CombatSim.build` does
## not copy it onto the `CombatState`, so setting it here currently does nothing.
## That copy is one line in `Scripts/Combat`, which is wren's — asked for on the
## board rather than done here.
##
## I nearly shipped this comment claiming the copy already existed. It cannot:
## the field did not exist until this commit, so nothing could have read it. That
## is the operational-claim trap I have written about three times tonight and
## walked into anyway, and it would have sent teal to author terrain that
## silently did nothing.
##
## Everything downstream of the copy is ready: `Scripts/Combat` has respected
## walls, pits and hazards since issue 13a.
##
## Why this matters more than it looks, from a fight read on 2026-08-13: ranged
## units currently take **zero** damage in a winning fight while the melee half
## of the party dies. Nothing in the room can threaten a unit standing at 200+
## units, so the whole cost of every fight falls on whoever closes. Line of sight
## is the only lever that threatens a back line as such rather than punishing one
## composition — which makes this field the most load-bearing thing on the board.
@export var terrain: Array = []
