extends Node2D

## Proves `Offscreen.hide_window` leaves the render intact. Run it by hand; the
## gate is headless and cannot draw.
func _ready() -> void:
	Offscreen.hide_window(self)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var lit := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			var c := img.get_pixel(x, y)
			if c.a > 0.0 and c != Color(0, 0, 0, 1):
				lit += 1
	print("offscreen at %s, rendered %s, lit samples %d" % [get_window().position, img.get_size(), lit])
	get_tree().quit()
