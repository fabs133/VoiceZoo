extends "res://tests/helpers/base_test.gd"
## Tests for CameraNudgePolicy - time-window rules for automatic camera nudges.

const PolicyScript = preload("res://presentation/camera_nudge_policy.gd")

var _policy


func before_each() -> void:
	_policy = PolicyScript.new()
	# defaults under test: pan_suppress 3.0s, nudge_cooldown 8.0s


func test_fresh_policy_allows_nudge() -> void:
	assert_true(_policy.try_nudge(0.0), "first nudge allowed immediately")


func test_cooldown_blocks_immediate_retry() -> void:
	assert_true(_policy.try_nudge(0.0), "first nudge")
	assert_false(_policy.try_nudge(1.0), "second nudge blocked inside 8s cooldown")
	assert_false(_policy.try_nudge(7.9), "still blocked just before cooldown ends")


func test_cooldown_expires() -> void:
	assert_true(_policy.try_nudge(0.0), "first nudge")
	assert_true(_policy.try_nudge(8.5), "allowed again after cooldown")


func test_pan_suppresses_nudge() -> void:
	_policy.record_pan(10.0)
	assert_false(_policy.try_nudge(11.0), "blocked inside 3s pan window")
	assert_false(_policy.try_nudge(12.9), "still blocked just before window ends")


func test_pan_suppression_expires() -> void:
	_policy.record_pan(10.0)
	assert_true(_policy.try_nudge(13.5), "allowed after pan window")


func test_blocked_attempt_does_not_start_cooldown() -> void:
	_policy.record_pan(0.0)
	assert_false(_policy.try_nudge(1.0), "blocked by pan")
	# If the blocked attempt had started the cooldown, this would fail:
	assert_true(_policy.try_nudge(3.5), "pan window expired; no phantom cooldown")


func test_pan_and_cooldown_combined() -> void:
	assert_true(_policy.try_nudge(0.0), "nudge at t=0")
	_policy.record_pan(9.0)
	assert_false(_policy.try_nudge(10.0), "cooldown over but pan window active")
	assert_true(_policy.try_nudge(12.5), "both windows expired")


func test_repeated_pans_extend_suppression() -> void:
	_policy.record_pan(0.0)
	_policy.record_pan(2.0)
	_policy.record_pan(4.0)
	assert_false(_policy.try_nudge(5.0), "window measured from latest pan")
	assert_true(_policy.try_nudge(7.5), "expires 3s after latest pan")


func test_tunables_are_adjustable() -> void:
	_policy.nudge_cooldown_seconds = 1.0
	assert_true(_policy.try_nudge(0.0), "first nudge")
	assert_true(_policy.try_nudge(1.5), "shortened cooldown respected")