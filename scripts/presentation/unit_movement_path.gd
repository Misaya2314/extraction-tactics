class_name UnitMovementPath
extends RefCounted

## Time-parametrized legal polyline: continuous speed across ordinary waypoints.
var segments: Array[Dictionary] = []
var duration := 0.0
var length := 0.0
var endpoint := Vector3.ZERO
var acceleration := 14.0

func build(start: Vector3, destinations: Array[Vector3], top_speed: float = 3.6) -> void:
	segments.clear()
	duration = 0.0
	length = 0.0
	var points: Array[Vector3] = [start]
	for point in destinations:
		if point.distance_to(points.back()) > 0.0001:
			points.append(point)
	endpoint = points.back()
	if points.size() < 2:
		return
	var maximum := maxf(top_speed, 0.1)
	var speeds: Array[float] = []
	for i in range(points.size()):
		var cap := maximum
		if i == 0 or i == points.size() - 1:
			cap = 0.0
		else:
			var incoming := (points[i] - points[i - 1]).normalized()
			var outgoing := (points[i + 1] - points[i]).normalized()
			var dot := incoming.dot(outgoing)
			if dot < 0.98:
				cap = maximum * lerpf(0.22, 0.70, clampf((dot + 1.0) / 2.0, 0, 1))
		speeds.append(cap)
	for i in range(1, points.size()):
		speeds[i] = minf(speeds[i], sqrt(speeds[i - 1] * speeds[i - 1] + 2 * acceleration * points[i].distance_to(points[i - 1])))
	for i in range(points.size() - 2, -1, -1):
		speeds[i] = minf(speeds[i], sqrt(speeds[i + 1] * speeds[i + 1] + 2 * acceleration * points[i].distance_to(points[i + 1])))
	for i in range(points.size() - 1):
		var distance := points[i].distance_to(points[i + 1])
		var first := speeds[i]
		var last := speeds[i + 1]
		var peak := minf(maximum, sqrt(acceleration * distance + (first * first + last * last) * 0.5))
		var up := (peak - first) / acceleration
		var down := (peak - last) / acceleration
		var accelerate_distance := (first + peak) * up * 0.5
		var decelerate_distance := (last + peak) * down * 0.5
		var cruise := maxf(0, (distance - accelerate_distance - decelerate_distance) / peak)
		segments.append({"start": points[i], "direction": (points[i + 1] - points[i]).normalized(), "length": distance,
			"time": duration, "distance": length, "first": first, "last": last, "peak": peak,
			"up": up, "cruise": cruise, "down": down, "accelerate_distance": accelerate_distance})
		duration += up + cruise + down
		length += distance

func sample(time: float) -> Dictionary:
	if segments.is_empty():
		return {"position": endpoint, "direction": Vector3.ZERO, "distance": 0.0, "speed": 0.0, "remaining": 0.0}
	if time >= duration:
		return {"position": endpoint, "direction": segments.back().direction, "distance": length, "speed": 0.0, "remaining": 0.0}
	var segment: Dictionary = segments[0]
	for candidate in segments:
		if time >= candidate.time:
			segment = candidate
		else:
			break
	var t := maxf(0, time - float(segment.time))
	var speed: float
	var traveled: float
	if t < segment.up:
		speed = segment.first + acceleration * t
		traveled = segment.first * t + 0.5 * acceleration * t * t
	elif t < segment.up + segment.cruise:
		speed = segment.peak
		traveled = segment.accelerate_distance + segment.peak * (t - segment.up)
	else:
		var braking: float = t - segment.up - segment.cruise
		speed = maxf(segment.last, segment.peak - acceleration * braking)
		traveled = segment.accelerate_distance + segment.peak * segment.cruise + segment.peak * braking - 0.5 * acceleration * braking * braking
	var distance: float = segment.distance + traveled
	return {"position": segment.start + segment.direction * traveled, "direction": segment.direction,
		"distance": distance, "speed": speed, "remaining": maxf(0, length - distance)}
