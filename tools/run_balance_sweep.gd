extends Node

const BatchRunnerScript := preload("res://tests/batch_runner.gd")


func _ready() -> void:
	_run()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var count: int = maxi(1, int(args[0])) if args.size() > 0 else 1000
	var policy: String = args[1] if args.size() > 1 else "builder"
	var location: String = args[2] if args.size() > 2 else MetaProgress.DEFAULT_LOCATION
	var started_at: int = Time.get_ticks_msec()
	var runner: RefCounted = BatchRunnerScript.new()
	var summary: Dictionary = runner.call("run", count, policy, location)
	summary["elapsed_seconds"] = (
		float(Time.get_ticks_msec() - started_at) / 1000.0
	)
	print(JSON.stringify(summary, "\t"))
	var failed: bool = (
		int(summary.get("invalid_number_count", 0)) > 0
		or int(summary.get("guard_limit_count", 0)) > 0
		or int(summary.get("stuck_count", 0)) > 0
	)
	get_tree().quit(1 if failed else 0)
