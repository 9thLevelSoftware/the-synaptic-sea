extends Node2D
class_name TopDownLighting
## LightOccluder2D / PointLight2D system for dim-lit horror tone.
## Placeholder — full lighting pass happens in Gate 2 with real art.

var lights: Array[PointLight2D] = []


func add_point_light(pos: Vector2, color: Color, energy: float, radius: float) -> PointLight2D:
	var light := PointLight2D.new()
	light.position = pos
	light.color = color
	light.energy = energy
	light.texture = _make_circle_texture(radius)
	add_child(light)
	lights.append(light)
	return light


func clear_lights() -> void:
	for light in lights:
		if is_instance_valid(light):
			light.queue_free()
	lights.clear()


func _make_circle_texture(radius: float) -> ImageTexture:
	var size := int(radius * 2.0)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(radius, radius)
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				var alpha := 1.0 - (dist / radius)
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	return ImageTexture.create_from_image(img)
