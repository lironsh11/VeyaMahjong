class_name TouchScroll
extends ScrollContainer
## A vertical list that touch-drags from anywhere, cards and buttons included.
##
## Buttons and panels stop mouse events by default, so a drag that starts on one never reaches
## the ScrollContainer (only the gaps between cards scrolled). Every button and panel inside is
## switched to MOUSE_FILTER_PASS as it enters the tree, and a press that turns into a scroll is
## cancelled, so lifting the finger over a button never buys or opens anything.

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_started.connect(_cancel_presses)


func _ready() -> void:
	_pass_all(self)


func _enter_tree() -> void:
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is Control and is_ancestor_of(n):
		_pass(n)


func _pass_all(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			_pass(c)
		_pass_all(c)


static func _pass(c: Control) -> void:
	# Sliders, text fields and the scrollbars keep their own drags.
	if c.mouse_filter == Control.MOUSE_FILTER_STOP and (c is BaseButton or c is Panel or c is PanelContainer):
		c.mouse_filter = Control.MOUSE_FILTER_PASS


func _cancel_presses() -> void:
	# Disabling a button drops its press attempt, so the release that ends the drag is ignored.
	for b in find_children("*", "BaseButton", true, false):
		var btn := b as BaseButton
		if not btn.disabled:
			btn.disabled = true
			btn.disabled = false
