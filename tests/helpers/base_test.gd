extends RefCounted
class_name BaseTest
## Simple test base class with assertions. No external dependencies.
## Reused pattern from godot-idle-game.

var _test_name: String = ""
var _passed_count: int = 0
var _failed_count: int = 0
var _failed_messages: Array[String] = []


func run_all_tests() -> Dictionary:
	_passed_count = 0
	_failed_count = 0
	_failed_messages.clear()

	var test_methods: Array[String] = []
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_"):
			test_methods.append(method_name)

	for method_name in test_methods:
		_test_name = method_name
		var before := _passed_count + _failed_count
		before_each()
		call(method_name)
		after_each()
		# A method that records NOTHING did not really run: GDScript aborts the
		# method on a runtime error and the runner would otherwise report the
		# whole file as [PASS] with a quietly lower count.
		if _passed_count + _failed_count == before:
			_failed_count += 1
			_failed_messages.append("FAIL: [%s] recorded no assertions - runtime error or empty test?" % method_name)

	return {
		"passed": _passed_count,
		"failed": _failed_count,
		"total": _passed_count + _failed_count,
		"methods": test_methods.size(),
		"messages": _failed_messages,
	}


func before_each() -> void:
	pass


func after_each() -> void:
	pass


# --- Assertions ---

func assert_true(condition: bool, message: String = "") -> void:
	if condition:
		_passed_count += 1
	else:
		_fail("assert_true failed: " + message)


func assert_false(condition: bool, message: String = "") -> void:
	if not condition:
		_passed_count += 1
	else:
		_fail("assert_false failed: " + message)


func assert_eq(actual, expected, message: String = "") -> void:
	if actual == expected:
		_passed_count += 1
	else:
		_fail("assert_eq: expected '%s' got '%s'. %s" % [str(expected), str(actual), message])


func assert_ne(actual, expected, message: String = "") -> void:
	if actual != expected:
		_passed_count += 1
	else:
		_fail("assert_ne: values should differ but both are '%s'. %s" % [str(actual), message])


func assert_gt(actual: float, expected: float, message: String = "") -> void:
	if actual > expected:
		_passed_count += 1
	else:
		_fail("assert_gt: %.4f is not > %.4f. %s" % [actual, expected, message])


func assert_lt(actual: float, expected: float, message: String = "") -> void:
	if actual < expected:
		_passed_count += 1
	else:
		_fail("assert_lt: %.4f is not < %.4f. %s" % [actual, expected, message])


func assert_almost_eq(actual: float, expected: float, epsilon: float, message: String = "") -> void:
	if absf(actual - expected) <= epsilon:
		_passed_count += 1
	else:
		_fail("assert_almost_eq: %.6f not within %.6f of %.6f. %s" % [actual, epsilon, expected, message])


func assert_not_null(value, message: String = "") -> void:
	if value != null:
		_passed_count += 1
	else:
		_fail("assert_not_null: value is null. " + message)


func _fail(message: String) -> void:
	_failed_count += 1
	var full_message = "[%s] %s" % [_test_name, message]
	_failed_messages.append(full_message)
	printerr("  FAIL: " + full_message)
