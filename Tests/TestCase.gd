extends RefCounted

## Base class for every test. Copy Tests/test_skeleton.gd as the pattern.
##
## MANAGER-OWNED. Add a helper by proposing it in TEAM_LOG.md.
##
## A test is any method whose name begins with `test_` on a class extending
## this, in a file named `test_*.gd` under Tests/. The runner fails naming any
## `test_*.gd` file anywhere else in the repository, because a test file outside
## the runner's reach reports nothing and looks exactly like a passing one.

var failures: Array[String] = []
var assertions: int = 0

func setup() -> void:
	pass

func teardown() -> void:
	pass

func fail(message: String) -> void:
	assertions += 1
	failures.append(message)

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func assert_true(condition: bool, message: String = "") -> void:
	check(condition, "expected true: %s" % message)

func assert_false(condition: bool, message: String = "") -> void:
	check(not condition, "expected false: %s" % message)

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assertions += 1
	if actual != expected:
		failures.append("expected %s, got %s%s" % [
			_show(expected), _show(actual), "" if message == "" else " (%s)" % message
		])

func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> void:
	assertions += 1
	if actual == unexpected:
		failures.append("expected anything but %s%s" % [
			_show(unexpected), "" if message == "" else " (%s)" % message
		])

func assert_almost_eq(actual: float, expected: float, epsilon: float = 0.0001, message: String = "") -> void:
	assertions += 1
	if absf(actual - expected) > epsilon:
		failures.append("expected %f +/- %f, got %f%s" % [
			expected, epsilon, actual, "" if message == "" else " (%s)" % message
		])

func assert_not_null(value: Variant, message: String = "") -> void:
	check(value != null, "expected non-null: %s" % message)

func _show(v: Variant) -> String:
	if v is String or v is StringName:
		return "\"%s\"" % v
	return str(v)
