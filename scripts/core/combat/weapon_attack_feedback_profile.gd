@tool
class_name WeaponAttackFeedbackProfile
extends Resource

## Static, data-driven presentation settings for a weapon attack.
## This resource never participates in damage, range, AP, or hit validation.
@export var profile_id: StringName = &""
@export var attack_sound: AudioStream
@export_range(0.0, 0.5, 0.005, "suffix:m") var recoil_distance: float = 0.05
@export_range(0.0, 45.0, 0.5, "suffix:deg") var weapon_kick_degrees: float = 4.0
@export_range(0.0, 0.5, 0.01) var body_squash: float = 0.03
@export_range(0.0, 1.0, 0.01, "suffix:s") var recoil_duration: float = 0.08
@export_range(0.0, 1.0, 0.01, "suffix:s") var hold_duration: float = 0.04
@export_range(0.0, 1.0, 0.01, "suffix:s") var recover_duration: float = 0.12
@export_range(0.0, 3.0, 0.05) var muzzle_flash_scale: float = 0.9
@export_range(0.0, 1.0, 0.01, "suffix:s") var muzzle_flash_duration: float = 0.06


func total_duration() -> float:
	return maxf(recoil_duration, 0.0) + maxf(hold_duration, 0.0) + maxf(recover_duration, 0.0)
