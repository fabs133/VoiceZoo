extends RefCounted
## Decides whether an automatic camera nudge is allowed right now.
## Pure time-window logic - "now" is injected so it stays headless-testable.
## Tunables are vars (not consts) so the camera or tests can adjust them.

var pan_suppress_seconds: float = 3.0   # no nudges this long after user camera input
var nudge_cooldown_seconds: float = 8.0  # minimum spacing between automatic nudges

var _last_pan_time: float = -INF
var _last_nudge_time: float = -INF


func record_pan(now: float) -> void:
	_last_pan_time = now


## Returns true and records the nudge if allowed; false otherwise.
## A blocked attempt does NOT start the cooldown.
func try_nudge(now: float) -> bool:
	if now - _last_pan_time < pan_suppress_seconds:
		return false
	if now - _last_nudge_time < nudge_cooldown_seconds:
		return false
	_last_nudge_time = now
	return true