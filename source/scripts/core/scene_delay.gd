class_name SceneDelay
extends RefCounted
## Отложенное действие живёт вместе с экраном, а не с глобальным SceneTree.
static func after(owner_node: Node, seconds: float, callback: Callable, always: bool = false, realtime: bool = false) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(seconds, 0.001)
	timer.ignore_time_scale = realtime
	timer.process_mode = Node.PROCESS_MODE_ALWAYS if always else Node.PROCESS_MODE_PAUSABLE
	owner_node.add_child(timer)
	timer.timeout.connect(callback, CONNECT_ONE_SHOT)
	timer.timeout.connect(timer.queue_free, CONNECT_ONE_SHOT)
	timer.start()
	return timer
