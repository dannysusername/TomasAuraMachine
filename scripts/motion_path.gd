class_name MotionPath
extends RefCounted
## A recorded sequence of (time, position, rotation) samples for ONE moving
## thing — the camera today, a car or prop later. Record it live, save it to
## disk, then replay it deterministically by time. This is the reusable core
## of the whole "puppeteer + record" idea.

var samples: Array = []   # each: {"t": float, "p": Vector3, "q": Quaternion}


func clear() -> void:
	samples.clear()


## Append the current transform stamped with elapsed seconds since record start.
func add_sample(t: float, xform: Transform3D) -> void:
	samples.append({
		"t": t,
		"p": xform.origin,
		"q": xform.basis.get_rotation_quaternion(),
	})


func duration() -> float:
	if samples.is_empty():
		return 0.0
	return samples[samples.size() - 1]["t"]


func is_valid() -> bool:
	return samples.size() >= 2


## The interpolated transform at playback time `t` (seconds). Positions are
## lerped and rotations slerped between the two surrounding samples, so the
## motion is smooth and its length matches how long it was recorded for —
## independent of the frame rate it was recorded or replayed at.
func sample_at(t: float) -> Transform3D:
	if samples.is_empty():
		return Transform3D.IDENTITY
	var last := samples.size() - 1
	if t <= samples[0]["t"]:
		return _to_transform(samples[0])
	if t >= samples[last]["t"]:
		return _to_transform(samples[last])
	for i in range(last):
		var a: Dictionary = samples[i]
		var b: Dictionary = samples[i + 1]
		if t >= a["t"] and t <= b["t"]:
			var span: float = b["t"] - a["t"]
			var f: float = 0.0 if span <= 0.0 else (t - a["t"]) / span
			var pos: Vector3 = (a["p"] as Vector3).lerp(b["p"], f)
			var rot: Quaternion = (a["q"] as Quaternion).slerp(b["q"], f)
			return Transform3D(Basis(rot), pos)
	return _to_transform(samples[last])


func _to_transform(s: Dictionary) -> Transform3D:
	return Transform3D(Basis(s["q"] as Quaternion), s["p"] as Vector3)


## Plain-data form (for embedding in a scene file / JSON).
func to_dict() -> Dictionary:
	var arr: Array = []
	for s in samples:
		var p: Vector3 = s["p"]
		var q: Quaternion = s["q"]
		arr.append({"t": s["t"], "p": [p.x, p.y, p.z], "q": [q.x, q.y, q.z, q.w]})
	return {"samples": arr}


func from_dict(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("samples"):
		return false
	clear()
	for s in (data as Dictionary)["samples"]:
		var p: Array = s["p"]
		var q: Array = s["q"]
		samples.append({
			"t": float(s["t"]),
			"p": Vector3(p[0], p[1], p[2]),
			"q": Quaternion(q[0], q[1], q[2], q[3]),
		})
	return is_valid()
