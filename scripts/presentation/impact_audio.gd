class_name ImpactAudio
extends RefCounted

## Original, cached PCM cues; private deterministic noise never consumes combat RNG.
static var _cache: Dictionary = {}

static func stream(kind: StringName) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var sample_rate := 22050
	var duration := 0.48 if kind == &"fatal" else 0.20
	var data := PackedByteArray()
	data.resize(int(sample_rate * duration) * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 812
	for i in range(data.size() / 2):
		var t := float(i) / sample_rate
		var value := random.randf_range(-1, 1) * exp(-t * 45.0) * 0.24
		if kind == &"armor":
			value += (sin(TAU * 1450 * t) + sin(TAU * 2317 * t) * 0.4) * exp(-t * 24) * 0.22
		elif kind == &"fatal":
			value += sin(TAU * (160 * t - 90 * t * t)) * exp(-t * 9) * 0.4
			value += random.randf_range(-1, 1) * exp(-t * 10) * 0.13
		else:
			value += sin(TAU * 330 * t) * exp(-t * 28) * 0.3
		data.encode_s16(i * 2, int(clampf(value, -1, 1) * 32767))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = sample_rate
	result.data = data
	_cache[kind] = result
	return result
