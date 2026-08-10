class_name TestUtil
extends RefCounted
## Minimal assertion helpers for the plain-script test runner (no GUT
## dependency). State is static so individual test_*.gd files can call the
## assert_* functions without holding a reference to anything.

static var pass_count: int = 0
static var fail_count: int = 0
static var failures: Array[String] = []
static var _current_context: String = ""

static func reset() -> void:
	pass_count = 0
	fail_count = 0
	failures = []
	_current_context = ""

static func set_context(context: String) -> void:
	_current_context = context

static func _record(cond: bool, msg: String) -> void:
	if cond:
		pass_count += 1
	else:
		fail_count += 1
		var full := msg if _current_context == "" else "[%s] %s" % [_current_context, msg]
		failures.append(full)

static func assert_true(cond: bool, msg: String) -> void:
	_record(cond, msg)

static func assert_false(cond: bool, msg: String) -> void:
	_record(not cond, msg)

static func assert_eq(actual, expected, msg: String) -> void:
	_record(actual == expected, "%s (expected %s, got %s)" % [msg, str(expected), str(actual)])

static func assert_ne(actual, expected, msg: String) -> void:
	_record(actual != expected, "%s (expected value different from %s)" % [msg, str(expected)])

static func assert_null(actual, msg: String) -> void:
	_record(actual == null, "%s (expected null, got %s)" % [msg, str(actual)])

static func assert_not_null(actual, msg: String) -> void:
	_record(actual != null, "%s (expected non-null)" % msg)
