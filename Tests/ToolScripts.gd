extends RefCounted
class_name ToolScripts

## Every `.gd` under a root, subdirectories included. Issue 864.
static func under(root: String) -> Array[String]:
	var out: Array[String] = []
	_walk(root, out)
	out.sort()
	return out


static func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, name])
	for sub in dir.get_directories():
		_walk("%s/%s" % [dir_path, sub], out)
