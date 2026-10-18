extends Node
## DEBUG-ONLY performance logger. Enabled in debug builds by `--perf-log` on the command line
## or by the presence of user://perf_log.flag (create it on Android with
## `adb shell run-as <package> touch files/perf_log.flag`). Prints one line every 2 s:
##   PERF fps=.. frame_ms=.. draws=.. nodes=.. static_mb=.. screen=..
## Note: low-processor mode deliberately drops to near-zero redraws when nothing changes, so
## idle FPS is low by design; read FPS during animations/interaction.

var _t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_t += delta
	if _t < 2.0:
		return
	_t = 0.0
	print("PERF fps=%d frame_ms=%.2f draws=%d nodes=%d static_mb=%.1f objects=%d screen=%s low_profile=%s" % [
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		OS.get_static_memory_usage() / 1048576.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Router.current_name,
		AccessibilityService.low_profile,
	])
