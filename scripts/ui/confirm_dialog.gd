class_name ConfirmDialog
extends Modal

## Yes/no question. Calls `on_confirm` and closes.

var _on_confirm: Callable


func _init(title: String, message: String, confirm_text: String, on_confirm: Callable, danger: bool = false) -> void:
	super(title, 440)
	_on_confirm = on_confirm
	body.add_child(UIKit.label(message, "Muted", true))
	add_footer_button(UIKit.button("Cancel", close, "GhostButton"))
	add_footer_button(UIKit.button(confirm_text, _confirm, "DangerButton" if danger else "PrimaryButton"))
	closed.connect(queue_free)


func _confirm() -> void:
	var cb := _on_confirm
	_on_confirm = Callable()
	close()
	if cb.is_valid():
		cb.call()
