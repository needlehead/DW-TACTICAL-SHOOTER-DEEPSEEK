extends SceneTree
## Headless check: loads every script/scene/resource, then runs logic asserts.
## Run: godot --headless --path . -s res://tests/smoke_test.gd

var failures := 0


func _init() -> void:
	for path in _files("res://", ["gd", "tscn", "tres"]):
		if path.begins_with("res://tests/") or path.begins_with("res://maps/tools/"):
			continue
		if load(path) == null:
			_fail("could not load " + path)
	_logic_checks()
	print("SMOKE TEST: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	quit(1 if failures else 0)


func _logic_checks() -> void:
	pass


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fail(what)


func _fail(msg: String) -> void:
	failures += 1
	push_error(msg)


func _files(dir: String, exts: Array) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in exts:
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			out.append_array(_files(dir.path_join(d), exts))
	return out
