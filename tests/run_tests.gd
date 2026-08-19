extends SceneTree
## Plain-script headless test runner (no GUT dependency).
##
## Run with:
##   godot --headless --script res://tests/run_tests.gd
##
## Discovers every res://tests/**/test_*.gd file, instantiates it, and calls
## every method on it named test_*. A test records failures via TestUtil's
## assert_* helpers; it does not need to return anything.

func _init() -> void:
	TestUtil.reset()
	var test_files := _find_test_files("res://tests")
	test_files.sort()

	for path in test_files:
		var script: GDScript = load(path)
		var instance = script.new()
		TestUtil.set_context(path.get_file())
		for m in instance.get_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_"):
				instance.callv(mname, [])

	if TestUtil.fail_count > 0:
		printerr("")
		printerr("%d test(s) FAILED, %d passed" % [TestUtil.fail_count, TestUtil.pass_count])
		for f in TestUtil.failures:
			printerr(" - " + f)
		quit(1)
	else:
		print("All %d test assertions passed (%d test files)." % [TestUtil.pass_count, test_files.size()])
		quit(0)

func _find_test_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full_path := dir_path + "/" + name
		if dir.current_is_dir():
			out.append_array(_find_test_files(full_path))
		elif name.begins_with("test_") and name.ends_with(".gd"):
			out.append(full_path)
		name = dir.get_next()
	return out
