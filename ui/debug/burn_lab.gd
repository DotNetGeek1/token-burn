extends Control

const BATCH_RUNS := 1000

@onready var economy_slider: HSlider = $Margin/Layout/Scroll/VBox/EconomySlider
@onready var token_slider: HSlider = $Margin/Layout/Scroll/VBox/TokenSlider
@onready var cloud_slider: HSlider = $Margin/Layout/Scroll/VBox/CloudSlider
@onready var event_slider: HSlider = $Margin/Layout/Scroll/VBox/EventSlider
@onready var trace_list: VBoxContainer = $Margin/Layout/Scroll/VBox/TracePanel/TraceList
@onready var reload_button: Button = $Margin/Layout/Scroll/VBox/ReloadButton
@onready var batch_button: Button = $Margin/Layout/Scroll/VBox/BatchButton
@onready var close_button: Button = $Margin/Layout/Top/CloseButton


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	economy_slider.value_changed.connect(func(v): Simulation.set_tuning("economy_multiplier", v))
	token_slider.value_changed.connect(func(v): Simulation.set_tuning("token_multiplier", v))
	cloud_slider.value_changed.connect(func(v): Simulation.set_tuning("cloud_cost_multiplier", v))
	event_slider.value_changed.connect(func(v): Simulation.set_tuning("event_probability_multiplier", v))
	reload_button.pressed.connect(_reload_content)
	batch_button.pressed.connect(_run_batch)
	close_button.pressed.connect(_on_close)


func _on_close() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func open() -> void:
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().call_group("main_ui", "sync_overlay_input")
	economy_slider.value = float(Simulation.tuning.get("economy_multiplier", 1.0))
	token_slider.value = float(Simulation.tuning.get("token_multiplier", 1.0))
	cloud_slider.value = float(Simulation.tuning.get("cloud_cost_multiplier", 1.0))
	event_slider.value = float(Simulation.tuning.get("event_probability_multiplier", 1.0))
	_refresh_trace()


func _reload_content() -> void:
	ContentDatabase.reload()
	_refresh_trace()


func _refresh_trace() -> void:
	for child in trace_list.get_children():
		child.queue_free()
	for entry in Simulation.effect_resolver.get_trace().slice(-30):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s %s %s" % [entry.get("operation", ""), entry.get("target", ""), entry.get("after", "")]
		trace_list.add_child(label)


func _run_batch() -> void:
	var runner := BatchRunner.new()
	var summary: Dictionary = runner.run(BATCH_RUNS, "random")
	var label := Label.new()
	label.text = "Batch: %d runs, win rate %.1f%%" % [summary.get("runs", 0), float(summary.get("win_rate", 0.0)) * 100.0]
	trace_list.add_child(label)
