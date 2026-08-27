extends Resource
class_name DamageTypeDef

## What one `CG.DamageType` IS, in one place. Authored as a `.tres` under
## `Scripts/Core/DamageTypes/`, one file per enum member. Issue 631.

## NOTHING MAY WRITE TO ONE OF THESE AT RUN TIME: a `.tres` loaded twice is the
## same instance, so a write would change fire for every unit in the game.

## The enum member this file describes, held to the file's own name by the
## transcription test.
@export var damage_type: CG.DamageType = CG.DamageType.PHYSICAL

## The lower-case enum key, for anything that names a type in authored text.
@export var id: StringName = &""

## Read through `CG.damage_type_name`.
@export var display_name: String = ""

## The one colour for this type. Read through `Palette.damage_color`.
@export var color: Color = Color.WHITE

## The status this type applies by default. NOTHING READS THIS YET.
@export var applied_status: StatusDef = null

## `terrain_reactions` is deliberately absent rather than present and empty.
