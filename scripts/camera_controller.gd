class_name CameraController
extends Camera3D
## Two camera modes for framing a model:
##
##   ORBIT (default) — the easy, intuitive one (like Sketchfab / Google Maps):
##     • Left-drag ........ spin around the model
##     • Scroll wheel ..... zoom in / out
##     • Right-drag ....... pan (slide the view sideways/up)
##
##   FREE-FLY (advanced) — video-game style:
##     • WASD ............. move (relative to where you look)
##     • Q / E ........... down / up
##     • Hold right-mouse . look around
##     • Shift ........... move faster
##
## Switch with the in-app button or the Tab key. Auto-framing a model calls
## frame_object() to set a good starting distance/angle.

enum Mode { ORBIT, FLY }

@export var orbit_sensitivity := 0.01
@export var pan_sensitivity := 1.0
@export var zoom_step := 0.12
@export var fly_sprint := 3.0
@export var fly_look_sensitivity := 0.0025

var mode: Mode = Mode.ORBIT
var fly_speed := 4.0

# Orbit state
var _pivot := Vector3.ZERO
var _distance := 5.0
var _yaw := 0.6
var _pitch := 0.5
var _min_distance := 0.05
var _max_distance := 1000.0
var _reference := 1.0          # model radius — scales speed/zoom/pan

# Drag state
var _dragging_orbit := false
var _dragging_pan := false
var _looking := false
var _fly_yaw := 0.0
var _fly_pitch := 0.0


func _ready() -> void:
	_apply_orbit()


# ---------------------------------------------------------------------------
# Public API (called by main.gd)
# ---------------------------------------------------------------------------

## Center on a model and back off so it fully fits the view.
func frame_object(center: Vector3, radius: float) -> void:
	_reference = maxf(radius, 0.001)
	_pivot = center
	var half_fov := deg_to_rad(fov) * 0.5
	_distance = (_reference / sin(half_fov)) * 1.15   # 15% breathing room
	_min_distance = _reference * 0.1
	_max_distance = _distance * 8.0
	_yaw = 0.6
	_pitch = 0.5
	near = maxf(_distance * 0.005, 0.01)
	far = (_distance + _reference) * 8.0
	fly_speed = clampf(_reference * 0.9, 0.25, 200.0)
	if mode == Mode.ORBIT:
		_apply_orbit()


func toggle_mode() -> void:
	set_mode(Mode.ORBIT if mode == Mode.FLY else Mode.FLY)


func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	if new_mode == Mode.FLY:
		# Seed look angles from the current orientation so it doesn't jump.
		_fly_yaw = rotation.y
		_fly_pitch = rotation.x
	else:
		# Re-derive orbit angles from where the camera currently is.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_looking = false
		var off := global_position - _pivot
		_distance = clampf(off.length(), _min_distance, _max_distance)
		if _distance > 0.001:
			_yaw = atan2(off.x, off.z)
			_pitch = asin(clampf(off.y / _distance, -1.0, 1.0))
		_apply_orbit()
	mode = new_mode


func current_mode_name() -> String:
	return "Orbit" if mode == Mode.ORBIT else "Free-fly"


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.ORBIT:
		_orbit_input(event)
	else:
		_fly_input(event)


func _orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging_orbit = event.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging_pan = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0)
	elif event is InputEventMouseMotion:
		if _dragging_orbit:
			_yaw -= event.relative.x * orbit_sensitivity
			_pitch = clampf(_pitch - event.relative.y * orbit_sensitivity, -1.5, 1.5)
			_apply_orbit()
		elif _dragging_pan:
			_pan(event.relative)


func _zoom(dir: float) -> void:
	_distance = clampf(_distance * (1.0 + dir * zoom_step), _min_distance, _max_distance)
	_apply_orbit()


func _pan(rel: Vector2) -> void:
	# Pan speed scales with distance so it feels consistent at any zoom.
	var amount := _distance * 0.0015 * pan_sensitivity
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	_pivot += (-right * rel.x + up * rel.y) * amount
	_apply_orbit()


func _apply_orbit() -> void:
	var offset := Vector3(
		sin(_yaw) * cos(_pitch),
		sin(_pitch),
		cos(_yaw) * cos(_pitch)
	) * _distance
	global_position = _pivot + offset
	look_at(_pivot, Vector3.UP)


func _fly_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _looking:
		_fly_yaw -= event.relative.x * fly_look_sensitivity
		_fly_pitch = clampf(_fly_pitch - event.relative.y * fly_look_sensitivity, -1.4, 1.4)
		rotation = Vector3(_fly_pitch, _fly_yaw, 0.0)


func _process(delta: float) -> void:
	if mode != Mode.FLY:
		return
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	var vertical := 0.0
	if Input.is_key_pressed(KEY_E): vertical += 1.0
	if Input.is_key_pressed(KEY_Q): vertical -= 1.0
	if input == Vector3.ZERO and vertical == 0.0:
		return

	var speed := fly_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= fly_sprint
	var move := transform.basis * input
	move.y += vertical
	if move.length() > 0.0:
		global_position += move.normalized() * speed * delta
