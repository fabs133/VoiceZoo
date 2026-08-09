extends SceneTree
## Headless test runner — auto-discovers and runs all test_*.gd files.
## Usage: godot --headless --script tests/test_runner.gd

func _init() -> void:
	print("=".repeat(60))
	print("VOICEZOO TEST RUNNER")
	print("=".repeat(60))
	print("")

	var test_files = _discover_tests("res://tests/")
	if test_files.is_empty():
		print("No test files found!")
		quit(1)
		return

	var total_passed := 0
	var total_failed := 0
	var all_messages: Array[String] = []

	for file_path in test_files:
		var name = file_path.get_file().replace(".gd", "")
		print("Running %s..." % name)
		print("-".repeat(40))

		var script = load(file_path)
		if script == null or not script.can_instantiate():
			printerr("  Could not load: %s" % file_path)
			total_failed += 1
			continue

		var test = script.new()
		var results: Dictionary = test.run_all_tests()
		# A file that loads but exposes no test_* methods is a silent zombie.
		if int(results.get("methods", 0)) == 0:
			printerr("  No test methods found in %s" % file_path)
			total_failed += 1

		var passed: int = results["passed"]
		var failed: int = results["failed"]
		total_passed += passed
		total_failed += failed

		if failed > 0:
			for msg in results["messages"]:
				all_messages.append(str(msg))

		var status = "PASS" if failed == 0 else "FAIL"
		print("  %s: %d passed, %d failed [%s]" % [name, passed, failed, status])
		print("")

	print("=".repeat(60))
	print("TOTAL: %d passed, %d failed" % [total_passed, total_failed])

	if all_messages.size() > 0:
		print("")
		print("Failed tests:")
		for msg in all_messages:
			print("  " + msg)

	print("")
	if total_failed == 0:
		print("ALL TESTS PASSED!")
	else:
		print("SOME TESTS FAILED!")
	print("=".repeat(60))

	quit(0 if total_failed == 0 else 1)


func _discover_tests(dir_path: String) -> Array[String]:
	var files: Array[String] = []
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = dir_path.path_join(file_name)
		if dir.current_is_dir():
			# Skip helpers/ directory
			if file_name != "helpers":
				files.append_array(_discover_tests(full_path))
		elif file_name.begins_with("test_") and file_name.ends_with(".gd") and file_name != "test_runner.gd":
			files.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()
	return files
