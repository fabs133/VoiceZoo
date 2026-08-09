class_name FormatUtils
extends RefCounted
## Pure number formatting utilities — no dependencies.


static func format_number(value: float) -> String:
	if value >= 1_000_000_000:
		return "%.1fB" % (value / 1_000_000_000)
	elif value >= 1_000_000:
		return "%.1fM" % (value / 1_000_000)
	elif value >= 10_000:
		return "%.1fK" % (value / 1_000)
	elif value >= 1:
		return str(int(value))
	else:
		return "0"
