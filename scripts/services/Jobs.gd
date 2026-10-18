extends Node
## Runs pure-data work (solver, generator) on WorkerThreadPool and delivers the result on the
## main thread. Work callables must only touch their own cloned data - never nodes.
## Results for cancelled or superseded jobs are dropped.

var _next_id: int = 1
var _pending: Dictionary = {}   # job id -> {task, callback}
var _results: Dictionary = {}
var _mutex := Mutex.new()


func run(work: Callable, on_done: Callable) -> int:
	var id := _next_id
	_next_id += 1
	var task := WorkerThreadPool.add_task(func() -> void:
		var r: Variant = work.call()
		_mutex.lock()
		_results[id] = r
		_mutex.unlock())
	_pending[id] = {"task": task, "cb": on_done}
	set_process(true)
	return id


func cancel(id: int) -> void:
	if _pending.has(id):
		_pending[id].cb = Callable()


func _ready() -> void:
	set_process(false)


func _process(_dt: float) -> void:
	for id in _pending.keys():
		var p: Dictionary = _pending[id]
		if not WorkerThreadPool.is_task_completed(p.task):
			continue
		WorkerThreadPool.wait_for_task_completion(p.task)
		_mutex.lock()
		var r: Variant = _results.get(id)
		_results.erase(id)
		_mutex.unlock()
		_pending.erase(id)
		var cb: Callable = p.cb
		if cb.is_valid():
			cb.call(r)
	if _pending.is_empty():
		set_process(false)


func run_sync_for_tests(work: Callable) -> Variant:
	return work.call()
