extends Resource
class_name DamageTypeDef

## What one `CG.DamageType` IS, in one place. Authored as a `.tres` under
## `Scripts/Core/DamageTypes/`, one file per enum member. Issue 631, and it
## follows #627's shape deliberately: the enum stays the key, only the
## properties move.

## Every field is a plain `@export var`. Nothing here is computed: a write to a
## getter-only property in GDScript silently does nothing.

## NOTHING MAY WRITE TO ONE OF THESE AT RUN TIME. `Resource` is by-reference
## and a `.tres` loaded twice is the same instance, so a write to
## `fire.applied_status` would change fire for every unit in the game until the
## editor restarts. An item that makes fire also poison is a modifier resolved
## at use, which is #632.

## The enum member this file describes. `CG.DamageType` stays the key; this is
## the back-reference, held to the file's own name by the transcription test.
@export var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## The lower-case enum key, for anything that has to name a type in text a
## person authored -- a saved room, a `terrain_reactions` entry when that is
## built. Held to the enum key and the filename by the transcription test.
@export var id: StringName = &""

## What a player is shown. Read through `CG.damage_type_name`.
@export var display_name: String = ""

## The one colour for this type: the log word, the floater, the projectile, the
## hazard tile. Read through `Palette.damage_color`.
@export var color: Color = Color.WHITE

## The status this type applies by default, so fire burns without every fire
## ability naming BURN. NOTHING READS THIS YET -- the ability-side channel that
## rolls a chance against it is not built, and it is null on the five types
## that have no status to name.
@export var applied_status: StatusDef = null

## `terrain_reactions` is deliberately absent rather than present and empty.
## Water clearing fire is the terrain follow-up #631 names and does not scope,
## and an unread Dictionary here would be indistinguishable from a broken one.
