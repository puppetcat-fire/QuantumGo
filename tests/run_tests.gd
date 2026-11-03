## Headless entry point for the rules-engine and wire-codec test suites.
##
## Usage:
##   godot --headless --path <project> --script res://tests/run_tests.gd
## Exits with 0 when every check passes, 1 otherwise.
extends SceneTree

const TestEngine := preload("res://tests/test_engine.gd")
const TestWire := preload("res://tests/test_wire.gd")


func _initialize() -> void:
	var failures := 0
	var engine_suite := TestEngine.new()
	failures += engine_suite.run_all()

	print("")
	var wire_suite := TestWire.new()
	failures += wire_suite.run_all()

	print("")
	if failures == 0:
		print("ALL TESTS PASS")
	else:
		print("TESTS FAILED: %d suite failure(s)" % failures)
	quit(0 if failures == 0 else 1)
