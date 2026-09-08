extends "res://scripts/presentation/combat_vfx.gd"

## Separate lifetime from combat VFX, but reuse the bounded analytical particles.
func _ready() -> void:
	particle_budget = 32
	set_process(false)

func plant(point: Vector3, strength: float) -> void:
	for i in range(3):
		_particle(point, Vector3(_rng.randf_range(-0.16, 0.16), 0.13, _rng.randf_range(-0.16, 0.16)),
			Vector3(0.10, 0.035, 0.10) * strength, Color(0.50, 0.46, 0.39, 0.26), 0.32, &"smoke", point.y)
	set_process(true)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		clear()
	advance(delta)
	if particles.is_empty():
		set_process(false)
