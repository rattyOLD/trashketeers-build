extends Node
## Загружает каждый .gd проекта и считает, сколько не скомпилировалось.
func _ready() -> void:
	var files: Array[String] = []
	_collect("res://scripts", files)
	_collect("res://scenes", files)
	var failed := 0
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate() and not (s as GDScript).is_abstract() if s is GDScript else false:
			failed += 1
			print("CHECK failed ", f)
	print("CHECK checked %d scripts, failed %d" % [files.size(), failed])
	get_tree().quit()


func _collect(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)
