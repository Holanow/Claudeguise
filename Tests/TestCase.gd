extends RefCounted
class_name TestCase

## Base class for every test. Copy Tests/test_skeleton.gd as the pattern.

var failures: Array[String] = []
var assertions: int = 0

## Godot defers a node's `_ready` until the tree processes, so a scene built
## with `instantiate()` and never added is asserted against half-built. Enter it
## here instead; teardown frees it, so do not call `free()` yourself. Issue 370.
func in_tree(node: Node) -> Node:
	assert(tree != null, "TestCase.tree unset -- run_tests sets it before running")
	tree.root.add_child(node)
	_entered.append(node)
	return node

## Set by the runner rather than read from `Engine.get_main_loop()`, which is
## null while the runner is still inside its own `_initialize`.
static var tree: SceneTree = null

var _entered: Array[Node] = []

func setup() -> void:
	pass

func teardown() -> void:
	for n in _entered:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.queue_free()
	_entered.clear()

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
