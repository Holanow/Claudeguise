extends Resource
class_name AbilityVFX

## What an action looks like, hanging off the action itself so nothing in the
## view holds a switch statement keyed on an action id.
@export var display_name: String = ""
@export var layers: Array[VFXLayer] = []

func for_cue(cue: VFXLayer.Cue) -> Array[VFXLayer]:
	var out: Array[VFXLayer] = []
	for l in layers:
		if l != null and l.cue == cue:
			out.append(l)
	return out

func describe() -> String:
	var parts: PackedStringArray = []
	for l in layers:
		if l != null:
			parts.append(l.describe())
	return ", ".join(parts)
