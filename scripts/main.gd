extends Node3D
## Root of the app. Runs in one of two modes:
##
##   INTERACTIVE (normal launch): load one or more models into the scene, move
##       the camera, and click Record to capture the camera's MOVEMENT.
##   REPLAY (a relaunched copy of ourselves, with Godot's Movie Maker on):
##       rebuilds the whole scene from a scene file (every model at its place)
##       and replays the recorded camera path into an AVI, then quits.
##
## Movie Maker can only be switched on at launch, so we capture the movement
## live here, then relaunch a second copy with --write-movie/--fixed-fps that
## replays it. When it finishes we convert the AVI to MP4 with ffmpeg.

const RECORD_FPS := 60
const MIN_CLIP_SECONDS := 0.3    ## ignore accidental too-short recordings

## This build's version. Bump it every time you publish a new build.
const APP_VERSION := "0.5.0"
## A small JSON file you host online describing the latest version. Leave empty
## to disable update checks. Format:
##   {"version": "0.2.0", "url": "https://.../download", "notes": "What's new"}
const UPDATE_CHECK_URL := "https://raw.githubusercontent.com/dannysusername/TomasAuraMachine/main/version.json"

const HINT_ORBIT := "Drag to rotate • Scroll to zoom • Right-drag to pan"
const HINT_FLY := "WASD move • Q/E down/up • Hold right-mouse to look • Shift = faster"

@onready var camera: CameraController = $Camera3D
@onready var model_root: Node3D = $ModelRoot
@onready var ui: CanvasLayer = $UI
@onready var status_label: Label = $UI/Controls/StatusLabel
@onready var hint_label: Label = $UI/Controls/HintLabel
@onready var rec_label: Label = $UI/Controls/RecLabel
@onready var version_label: Label = $UI/Controls/VersionLabel
@onready var load_button: Button = $UI/Controls/LoadButton
@onready var sample_button: Button = $UI/Controls/SampleButton
@onready var record_button: Button = $UI/Controls/RecordButton
@onready var mode_button: Button = $UI/Controls/ModeButton
@onready var place_button: Button = $UI/Controls/PlaceButton
@onready var pilot_button: Button = $UI/Controls/PilotButton
@onready var play_button: Button = $UI/ScenePanel/SceneBox/PlayButton
@onready var objects_list: VBoxContainer = $UI/ScenePanel/SceneBox/ObjectsList
@onready var place_panel: PanelContainer = $UI/PlacePanel
@onready var pilot_panel: PanelContainer = $UI/PilotPanel
@onready var record_motion_btn: Button = $UI/PilotPanel/PilotBox/RecordMotionBtn
@onready var file_dialog: FileDialog = $UI/FileDialog
@onready var result_dialog: AcceptDialog = $UI/ResultDialog
@onready var update_dialog: AcceptDialog = $UI/UpdateDialog

var _is_recording_instance := false

# The scene's models. Each: {"name": String, "path": String, "node": Node3D}.
var _objects: Array = []
var _selected := -1

# Arrange (placement) mode for the selected model.
var _arrange_mode := false
var _dragging_place := false

# Pilot mode: fly the selected model and record its motion.
var _pilot_mode := false
var _pilot_node: Node3D = null
var _pilot_motion: MotionPath = null
var _pilot_recording := false
var _pilot_start_usec := 0
var _pilot_steering := false
var _pilot_speed := 5.0

# Scene playback (preview + while filming) of recorded object motions.
var _playing := false
var _play_time := 0.0

# Replay instance: objects that animate during render. Each: {node, motion}.
var _replay_objects: Array = []
var _replay_duration := 0.0

# Interactive: live capture of the camera's movement.
var _path := MotionPath.new()
var _recording_path := false
var _record_start_usec := 0

# Replay instance: play back a recorded camera path.
var _replay_path := MotionPath.new()
var _replay_time := 0.0

# Last produced video, for the "Watch / Open folder" buttons.
var _last_mp4 := ""
var _last_folder := ""

# Where to send the user when they click "Download" on an update.
var _update_url := ""


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--record"):
		_enter_recording_mode(user_args)
	else:
		_setup_interactive_mode()


# ----------------------------------------------------------------------------
# INTERACTIVE MODE
# ----------------------------------------------------------------------------

func _setup_interactive_mode() -> void:
	load_button.pressed.connect(_on_load_pressed)
	sample_button.pressed.connect(_load_sample)
	record_button.pressed.connect(_on_record_pressed)
	mode_button.pressed.connect(_toggle_camera_mode)
	place_button.pressed.connect(_toggle_place)
	pilot_button.pressed.connect(_toggle_pilot)
	play_button.pressed.connect(_toggle_play)
	$UI/PlacePanel/PlaceBox/RotLBtn.pressed.connect(_arrange_rotate.bind(20.0))
	$UI/PlacePanel/PlaceBox/RotRBtn.pressed.connect(_arrange_rotate.bind(-20.0))
	$UI/PlacePanel/PlaceBox/SmallerBtn.pressed.connect(_arrange_scale.bind(0.85))
	$UI/PlacePanel/PlaceBox/BiggerBtn.pressed.connect(_arrange_scale.bind(1.18))
	$UI/PlacePanel/PlaceBox/DropBtn.pressed.connect(_arrange_drop)
	$UI/PlacePanel/PlaceBox/DonePlaceBtn.pressed.connect(_exit_arrange)
	record_motion_btn.pressed.connect(_toggle_pilot_recording)
	$UI/PilotPanel/PilotBox/DonePilotBtn.pressed.connect(_exit_pilot)
	file_dialog.file_selected.connect(_add_model)
	get_window().files_dropped.connect(_on_files_dropped)
	# "Done!" popup with quick actions.
	result_dialog.add_button("📁 Open Folder", false, "folder")
	result_dialog.add_button("▶ Watch", true, "watch")
	result_dialog.custom_action.connect(_on_result_action)
	# "Update available" popup.
	update_dialog.add_button("⬇ Download", true, "download")
	update_dialog.custom_action.connect(_on_update_action)
	get_window().title = "TomasAuraMachine v%s" % APP_VERSION
	version_label.text = "v%s" % APP_VERSION
	record_button.disabled = true
	_update_mode_ui()
	_refresh_object_list()
	status_label.text = "Load a model, drag a .glb onto the window, or click \"Try a Sample\"."
	_check_for_updates()


func _unhandled_input(event: InputEvent) -> void:
	if _is_recording_instance:
		return
	if _arrange_mode:
		_arrange_input(event)
		return
	if _pilot_mode:
		_pilot_input(event)
		return
	# Tab toggles orbit / free-fly.
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_camera_mode()


func _toggle_camera_mode() -> void:
	camera.toggle_mode()
	_update_mode_ui()


func _update_mode_ui() -> void:
	if camera.current_mode_name() == "Orbit":
		mode_button.text = "Switch to Free-fly"
		hint_label.text = HINT_ORBIT
	else:
		mode_button.text = "Switch to Orbit"
		hint_label.text = HINT_FLY


func _on_load_pressed() -> void:
	file_dialog.popup_centered()


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var lower := f.to_lower()
		if lower.ends_with(".glb") or lower.ends_with(".gltf"):
			_add_model(f)
			return
	# Nothing usable was dropped — explain in plain language.
	var dropped := files[0] if files.size() > 0 else ""
	var ext := dropped.get_extension().to_lower()
	match ext:
		"blend":
			status_label.text = "That's a Blender file. In Blender, export it as .glb, then drop that here."
		"fbx", "obj", "dae":
			status_label.text = "That's a .%s file — not supported yet. Look for a .glb version." % ext
		"zip":
			status_label.text = "That's a zip. Unzip it first, then drop the .glb inside onto the window."
		_:
			status_label.text = "That file won't work. Drop a .glb (or .gltf) 3D model onto the window."


# ----------------------------------------------------------------------------
# SCENE: adding / selecting / removing models
# ----------------------------------------------------------------------------

## Add a model file to the scene (keeping any already loaded), select it, and
## reframe so everything is visible. Used by the dialog, drag-drop and sample.
func _add_model(path: String) -> void:
	var node := _instantiate_glb(path)
	if node == null:
		status_label.text = "Couldn't load that model."
		return
	var display := _unique_name(path.get_file().get_basename())
	node.name = display
	node.set_meta("source_path", path)
	model_root.add_child(node)
	_objects.append({"name": display, "path": path, "node": node, "motion": MotionPath.new()})
	_selected = _objects.size() - 1
	_refresh_object_list()
	record_button.disabled = false
	_frame_model()
	status_label.text = "Added: %s  (%d in scene)" % [display, _objects.size()]


func _select_object(index: int) -> void:
	_selected = index
	_refresh_object_list()


func _delete_object(index: int) -> void:
	if index < 0 or index >= _objects.size():
		return
	(_objects[index]["node"] as Node).queue_free()
	_objects.remove_at(index)
	_selected = mini(_selected, _objects.size() - 1)
	_refresh_object_list()
	record_button.disabled = _objects.is_empty()
	if _objects.is_empty():
		status_label.text = "Scene is empty. Load a model to begin."
	_frame_model()


## Rebuild the right-hand scene list (a select button + delete button per model).
func _refresh_object_list() -> void:
	for c in objects_list.get_children():
		objects_list.remove_child(c)
		c.queue_free()
	if _objects.is_empty():
		var empty := Label.new()
		empty.text = "No models yet."
		objects_list.add_child(empty)
		_update_scene_buttons()
		return
	for i in _objects.size():
		var row := HBoxContainer.new()
		var sel := Button.new()
		sel.text = ("● " if i == _selected else "○ ") + str(_objects[i]["name"])
		sel.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sel.pressed.connect(_select_object.bind(i))
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Remove from scene"
		del.pressed.connect(_delete_object.bind(i))
		row.add_child(sel)
		row.add_child(del)
		objects_list.add_child(row)
	_update_scene_buttons()


func _unique_name(base: String) -> String:
	var wanted := base if not base.is_empty() else "model"
	var candidate := wanted
	var n := 2
	while _name_taken(candidate):
		candidate = "%s %d" % [wanted, n]
		n += 1
	return candidate


func _name_taken(name: String) -> bool:
	for o in _objects:
		if o["name"] == name:
			return true
	return false


## Frame the whole scene (all models) so everything is centered and visible.
func _frame_model() -> void:
	var box := _model_aabb()
	var center := box.get_center()
	var radius: float = max(box.size.length() * 0.5, 0.001)
	camera.frame_object(center, radius)


# ----------------------------------------------------------------------------
# ARRANGE MODE: place / pose the selected model
# ----------------------------------------------------------------------------

func _toggle_place() -> void:
	if _arrange_mode:
		_exit_arrange()
	else:
		_enter_arrange()


func _enter_arrange() -> void:
	if _selected_node() == null:
		return
	_arrange_mode = true
	# Hand the mouse/keys to placement instead of the camera.
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	place_panel.visible = true
	place_button.text = "Done Placing"
	record_button.disabled = true
	load_button.disabled = true
	sample_button.disabled = true
	mode_button.disabled = true
	hint_label.text = "Drag = move • Scroll = up/down • A/D = turn • W/S = tilt • [ ] = size"
	status_label.text = "Placing: %s" % str(_objects[_selected]["name"])


func _exit_arrange() -> void:
	_arrange_mode = false
	_dragging_place = false
	camera.set_process(true)
	camera.set_process_unhandled_input(true)
	place_panel.visible = false
	place_button.text = "Place Selected"
	record_button.disabled = _objects.is_empty()
	load_button.disabled = false
	sample_button.disabled = false
	mode_button.disabled = false
	_update_mode_ui()
	_frame_model()


func _arrange_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging_place = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_arrange_height(1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_arrange_height(-1.0)
	elif event is InputEventMouseMotion and _dragging_place:
		_arrange_move(event.position)


## Continuous key controls while placing: A/D turn, W/S tilt, [ ] resize.
func _process_arrange(delta: float) -> void:
	var node := _selected_node()
	if node == null:
		return
	if Input.is_key_pressed(KEY_A):
		node.rotate_y(1.5 * delta)
	if Input.is_key_pressed(KEY_D):
		node.rotate_y(-1.5 * delta)
	if Input.is_key_pressed(KEY_W):
		node.rotate_object_local(Vector3.RIGHT, 1.5 * delta)
	if Input.is_key_pressed(KEY_S):
		node.rotate_object_local(Vector3.RIGHT, -1.5 * delta)
	if Input.is_key_pressed(KEY_BRACKETLEFT):
		node.scale *= (1.0 - 0.6 * delta)
	if Input.is_key_pressed(KEY_BRACKETRIGHT):
		node.scale *= (1.0 + 0.6 * delta)


## Slide the model across the horizontal plane at its current height, following
## the cursor — the intuitive "drag it where you want" gesture.
func _arrange_move(mouse_pos: Vector2) -> void:
	var node := _selected_node()
	if node == null:
		return
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.0001:
		return
	var y := node.global_position.y
	var t := (y - from.y) / dir.y
	if t <= 0.0:
		return
	var hit := from + dir * t
	node.global_position = Vector3(hit.x, y, hit.z)


func _arrange_height(dir: float) -> void:
	var node := _selected_node()
	if node == null:
		return
	var step: float = maxf(_node_aabb(node).size.length() * 0.08, 0.05)
	node.global_position.y += dir * step


func _arrange_rotate(degrees: float) -> void:
	var node := _selected_node()
	if node != null:
		node.rotate_y(deg_to_rad(degrees))


func _arrange_scale(factor: float) -> void:
	var node := _selected_node()
	if node != null:
		node.scale *= factor


## Drop the model so its lowest point rests on the floor (y = 0).
func _arrange_drop() -> void:
	var node := _selected_node()
	if node == null:
		return
	node.global_position.y -= _node_aabb(node).position.y


func _selected_node() -> Node3D:
	if _selected < 0 or _selected >= _objects.size():
		return null
	return _objects[_selected]["node"]


func _update_scene_buttons() -> void:
	var has_selection := _selected_node() != null
	place_button.disabled = not has_selection and not _arrange_mode
	pilot_button.disabled = not has_selection and not _pilot_mode
	play_button.disabled = not _any_motion() and not _playing


func _any_motion() -> bool:
	for o in _objects:
		if (o["motion"] as MotionPath).is_valid():
			return true
	return false


# ----------------------------------------------------------------------------
# PILOT MODE: fly the selected model and record its motion
# ----------------------------------------------------------------------------

func _toggle_pilot() -> void:
	if _pilot_mode:
		_exit_pilot()
	else:
		_enter_pilot()


func _enter_pilot() -> void:
	var node := _selected_node()
	if node == null:
		return
	_pilot_mode = true
	_pilot_node = node
	_pilot_motion = _objects[_selected]["motion"]
	_pilot_speed = maxf(_node_aabb(node).size.length() * 0.9, 1.0)
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	pilot_panel.visible = true
	pilot_button.text = "Stop Piloting"
	record_button.disabled = true
	load_button.disabled = true
	sample_button.disabled = true
	mode_button.disabled = true
	place_button.disabled = true
	# Show the other recorded objects at their starting poses to fly against.
	_apply_scene_pose(0.0, _pilot_node)
	hint_label.text = "WASD = fly • hold right-mouse = steer • Q/E = down/up • Shift = faster"
	status_label.text = "Piloting: %s — click ● Record flight, fly, then Stop." % str(_objects[_selected]["name"])


func _exit_pilot() -> void:
	if _pilot_recording:
		_toggle_pilot_recording()   # stop & save first
	_pilot_mode = false
	_pilot_steering = false
	_pilot_node = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.set_process(true)
	camera.set_process_unhandled_input(true)
	pilot_panel.visible = false
	pilot_button.text = "Pilot Selected"
	load_button.disabled = false
	sample_button.disabled = false
	mode_button.disabled = false
	_apply_scene_pose(0.0)   # rest every animated object at its start
	_update_mode_ui()
	_update_scene_buttons()
	record_button.disabled = _objects.is_empty()
	_frame_model()


func _toggle_pilot_recording() -> void:
	if _pilot_node == null:
		return
	if _pilot_recording:
		_pilot_recording = false
		record_motion_btn.text = "● Record flight"
		rec_label.visible = false
		status_label.text = "Flight saved (%.1fs). Fly again to redo, or ✓ Done." % _pilot_motion.duration()
		_apply_scene_pose(0.0, _pilot_node)
	else:
		_pilot_motion.clear()
		_pilot_recording = true
		_pilot_start_usec = Time.get_ticks_usec()
		_play_time = 0.0
		record_motion_btn.text = "■ Stop"
		rec_label.visible = true
		rec_label.text = "● REC  0.0s"
		status_label.text = "Recording flight — fly with WASD + right-mouse steer."


func _pilot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_pilot_steering = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _pilot_steering else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and _pilot_steering and _pilot_node != null:
		_pilot_node.rotate_y(-event.relative.x * 0.004)                       # yaw
		_pilot_node.rotate_object_local(Vector3.RIGHT, -event.relative.y * 0.004)  # pitch


func _process_pilot(delta: float) -> void:
	if _pilot_node == null:
		return
	# Move the model relative to where it points.
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_key_pressed(KEY_S): input.z += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	var vertical := 0.0
	if Input.is_key_pressed(KEY_E): vertical += 1.0
	if Input.is_key_pressed(KEY_Q): vertical -= 1.0
	var speed := _pilot_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 3.0
	if input != Vector3.ZERO:
		_pilot_node.global_position += (_pilot_node.global_transform.basis * input).normalized() * speed * delta
	_pilot_node.global_position.y += vertical * speed * delta

	_chase_camera(delta)

	if _pilot_recording:
		var t := (Time.get_ticks_usec() - _pilot_start_usec) / 1000000.0
		_pilot_motion.add_sample(t, _pilot_node.global_transform)
		rec_label.text = "● REC  %.1fs" % t
		# Other recorded objects fly their paths so you can react to them.
		_apply_scene_pose(t, _pilot_node)


## Keep the camera following behind and above the piloted model.
func _chase_camera(delta: float) -> void:
	var b := _pilot_node.global_transform.basis
	var size := maxf(_node_aabb(_pilot_node).size.length(), 1.0)
	var target := _pilot_node.global_position + b.z * size * 1.3 + Vector3.UP * size * 0.5
	camera.global_position = camera.global_position.lerp(target, clampf(delta * 5.0, 0.0, 1.0))
	camera.look_at(_pilot_node.global_position, Vector3.UP)


# ----------------------------------------------------------------------------
# PLAYBACK: preview recorded motions (and reuse the same poser while filming)
# ----------------------------------------------------------------------------

func _toggle_play() -> void:
	if _playing:
		_stop_play()
	else:
		if not _any_motion():
			return
		_playing = true
		_play_time = 0.0
		play_button.text = "■ Stop"
		status_label.text = "Playing the scene…"


func _stop_play() -> void:
	_playing = false
	play_button.text = "▶ Play scene"
	_apply_scene_pose(0.0)
	status_label.text = "Stopped."


func _process_play(delta: float) -> void:
	_play_time += delta
	_apply_scene_pose(_play_time)
	if _play_time >= _scene_motion_duration():
		_stop_play()


## Pose every animated object at time `t`. Objects without a recorded motion
## stay where they were placed. `exclude` is skipped (the one being piloted).
func _apply_scene_pose(t: float, exclude: Node3D = null) -> void:
	for o in _objects:
		var node: Node3D = o["node"]
		if node == exclude:
			continue
		var motion: MotionPath = o["motion"]
		if motion.is_valid():
			node.global_transform = motion.sample_at(t)


func _scene_motion_duration() -> float:
	var longest := 0.0
	for o in _objects:
		longest = maxf(longest, (o["motion"] as MotionPath).duration())
	return longest


# ----------------------------------------------------------------------------
# SAMPLE MODEL (built on the fly so there's always something to try)
# ----------------------------------------------------------------------------

func _load_sample() -> void:
	var root := Node3D.new()
	_add_primitive(root, SphereMesh.new(), Vector3(0, 1.1, 0), Color(0.85, 0.3, 0.35))
	_add_primitive(root, BoxMesh.new(), Vector3(0, 0.3, 0), Color(0.3, 0.55, 0.85))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.9
	_add_primitive(root, torus, Vector3(0, 1.9, 0), Color(0.9, 0.75, 0.25))

	var sample_path := OS.get_user_data_dir().path_join("sample.glb")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var err := doc.write_to_filesystem(state, sample_path)
	root.queue_free()
	if err != OK:
		status_label.text = "Couldn't create the sample model (error %d)." % err
		return
	_add_model(sample_path)


func _add_primitive(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat   # set on the mesh so it survives the .glb export
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	mi.owner = parent


# ----------------------------------------------------------------------------
# RECORDING (interactive side): capture the camera's movement
# ----------------------------------------------------------------------------

func _on_record_pressed() -> void:
	if _recording_path:
		_stop_recording()
	else:
		_start_recording()


func _start_recording() -> void:
	_path.clear()
	_recording_path = true
	_record_start_usec = Time.get_ticks_usec()
	_apply_scene_pose(0.0)   # moving objects start from the top of their flights
	record_button.text = "■ Stop"
	rec_label.visible = true
	rec_label.text = "● REC  0.0s"
	load_button.disabled = true
	status_label.text = "Recording your shot — move the camera, then click Stop."


func _stop_recording() -> void:
	_recording_path = false
	_apply_scene_pose(0.0)   # rest moving objects back at their start
	rec_label.visible = false
	record_button.text = "● Record"
	record_button.disabled = true
	load_button.disabled = true

	if not _path.is_valid() or _path.duration() < MIN_CLIP_SECONDS:
		status_label.text = "That was too quick — press Record, move around a bit, then Stop."
		_reset_buttons()
		return

	status_label.text = "Rendering your %.1fs clip… (a window will flash, then your video opens)" % _path.duration()
	await get_tree().process_frame
	await get_tree().process_frame
	_run_recording_pipeline()


func _run_recording_pipeline() -> void:
	var temp_dir := OS.get_user_data_dir()              # scratch for AVI + scene file
	var folder := _output_folder()                      # Desktop/TomasMovies for the MP4
	var avi_path := temp_dir.path_join("clip.avi")
	var scene_file := temp_dir.path_join("scene.json")
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var mp4_path := folder.path_join("shot_%s.mp4" % stamp)

	if not _save_scene_file(scene_file):
		status_label.text = "Couldn't save the scene to render."
		_reset_buttons()
		return

	# Build the command line for the replay copy of ourselves.
	var exe := OS.get_executable_path()
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--write-movie")
	args.append(avi_path)
	args.append("--fixed-fps")
	args.append(str(RECORD_FPS))
	args.append("--")
	args.append("--record")
	args.append("--scene-file")
	args.append(scene_file)

	var godot_output := []
	var code := OS.execute(exe, args, godot_output, true)
	if code != 0:
		status_label.text = "Recording process failed (exit %d). See console." % code
		_reset_buttons()
		return
	if not FileAccess.file_exists(avi_path):
		status_label.text = "No video file was produced. See console."
		_reset_buttons()
		return

	var ffmpeg := _find_ffmpeg()
	if ffmpeg == "":
		status_label.text = "Recorded the AVI, but couldn't find ffmpeg. Put it in the bin/ folder."
		_reset_buttons()
		return
	var ff_args := [
		"-y", "-i", avi_path,
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
		mp4_path,
	]
	var ff_output := []
	var ff_code := OS.execute(ffmpeg, ff_args, ff_output, true)
	if ff_code != 0 or not FileAccess.file_exists(mp4_path):
		status_label.text = "ffmpeg failed (exit %d). See console." % ff_code
		_reset_buttons()
		return

	_last_mp4 = mp4_path
	_last_folder = folder
	status_label.text = "Saved to Desktop ▸ TomasMovies ▸ %s" % mp4_path.get_file()
	result_dialog.dialog_text = "Your clip is ready! 🎬\n\nSaved to your Desktop in the “TomasMovies” folder as:\n%s" % mp4_path.get_file()
	result_dialog.popup_centered()
	_reset_buttons()


## Save the whole scene (every model at its place + the camera path) so the
## replay copy can rebuild and re-render it.
func _save_scene_file(path: String) -> bool:
	var objs: Array = []
	for o in _objects:
		var n: Node3D = o["node"]
		var motion: MotionPath = o["motion"]
		var entry := {"path": o["path"], "xform": _xform_to_array(n.global_transform)}
		if motion.is_valid():
			entry["motion"] = motion.to_dict()
		objs.append(entry)
	var data := {"objects": objs, "camera": _path.to_dict()}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func _reset_buttons() -> void:
	record_button.disabled = _objects.is_empty()
	load_button.disabled = false


## Locate the ffmpeg binary: next to the .exe first (exported app), then bin/.
func _find_ffmpeg() -> String:
	var names := PackedStringArray(["ffmpeg"])
	if OS.has_feature("windows"):
		names = PackedStringArray(["ffmpeg.exe"])
	var exe_dir := OS.get_executable_path().get_base_dir()
	var bin_dir := ProjectSettings.globalize_path("res://bin")
	for n in names:
		for dir in [exe_dir, bin_dir]:
			var candidate: String = dir.path_join(n)
			if FileAccess.file_exists(candidate):
				return candidate
	return ""


func _on_result_action(action: String) -> void:
	if action == "watch" and _last_mp4 != "":
		OS.shell_open(_last_mp4)
	elif action == "folder" and _last_folder != "":
		OS.shell_open(_last_folder)
	result_dialog.hide()


## Where finished videos are saved — an obvious, easy-to-find spot.
func _output_folder() -> String:
	var base := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if base == "":
		base = OS.get_user_data_dir()
	var folder := base.path_join("TomasMovies")
	DirAccess.make_dir_recursive_absolute(folder)
	return folder


# ----------------------------------------------------------------------------
# UPDATE CHECK
# ----------------------------------------------------------------------------

func _check_for_updates() -> void:
	if UPDATE_CHECK_URL.is_empty():
		return
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(_on_update_check_completed)
	status_label.text = "Checking for updates…"
	var err := http.request(UPDATE_CHECK_URL)
	if err != OK:
		status_label.text = "Update check couldn't start (error %d)." % err


func _on_update_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# NOTE: verbose on-screen reporting is temporary, to debug the update flow.
	if result != HTTPRequest.RESULT_SUCCESS:
		status_label.text = "Update check failed: network result %d (couldn't reach the server)." % result
		return
	if code != 200:
		status_label.text = "Update check: server returned HTTP %d." % code
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		status_label.text = "Update check: couldn't read the version file."
		return
	var dict := data as Dictionary
	var latest := str(dict.get("version", ""))
	if latest.is_empty():
		status_label.text = "Update check: no version listed."
		return
	if not _is_newer(latest, APP_VERSION):
		status_label.text = "You're up to date (v%s)." % APP_VERSION
		return
	_update_url = str(dict.get("url", ""))
	var notes := str(dict.get("notes", ""))
	status_label.text = "Update available: v%s!" % latest
	update_dialog.dialog_text = "A new version (%s) is available.\nYou have v%s.\n\n%s" % [latest, APP_VERSION, notes]
	update_dialog.popup_centered()


func _on_update_action(action: String) -> void:
	if action == "download" and not _update_url.is_empty():
		OS.shell_open(_update_url)
	update_dialog.hide()


func _is_newer(remote: String, local: String) -> bool:
	var r := remote.split(".")
	var l := local.split(".")
	for i in range(maxi(r.size(), l.size())):
		var rv := int(r[i]) if i < r.size() else 0
		var lv := int(l[i]) if i < l.size() else 0
		if rv != lv:
			return rv > lv
	return false


# ----------------------------------------------------------------------------
# REPLAY MODE (the relaunched copy that renders the movie)
# ----------------------------------------------------------------------------

func _enter_recording_mode(args: PackedStringArray) -> void:
	_is_recording_instance = true
	ui.visible = false
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	if not _load_scene(_arg_value(args, "--scene-file")):
		get_tree().quit()


## Rebuild the scene from a scene file: every model at its place (and its motion,
## if any), plus the camera path to replay.
func _load_scene(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var dict := data as Dictionary
	for o in dict.get("objects", []):
		var node := _instantiate_glb(str(o["path"]))
		if node == null:
			continue
		model_root.add_child(node)
		node.global_transform = _array_to_xform(o["xform"])
		if o.has("motion"):
			var motion := MotionPath.new()
			if motion.from_dict(o["motion"]):
				_replay_objects.append({"node": node, "motion": motion})
	if not _replay_path.from_dict(dict.get("camera", {})):
		return false
	# The clip lasts as long as the longest of: the camera move or any flight.
	_replay_duration = _replay_path.duration()
	for ro in _replay_objects:
		_replay_duration = maxf(_replay_duration, (ro["motion"] as MotionPath).duration())
	return true


func _process(delta: float) -> void:
	if _is_recording_instance:
		_process_replay(delta)
	elif _pilot_mode:
		_process_pilot(delta)
	elif _recording_path:
		_sample_camera()
	elif _arrange_mode:
		_process_arrange(delta)
	elif _playing:
		_process_play(delta)


func _process_replay(delta: float) -> void:
	_replay_time += delta
	camera.global_transform = _replay_path.sample_at(_replay_time)
	for ro in _replay_objects:
		(ro["node"] as Node3D).global_transform = (ro["motion"] as MotionPath).sample_at(_replay_time)
	if _replay_time >= _replay_duration:
		get_tree().quit()


func _sample_camera() -> void:
	var t := (Time.get_ticks_usec() - _record_start_usec) / 1000000.0
	_path.add_sample(t, camera.global_transform)
	_apply_scene_pose(t)   # any piloted objects fly while you film them
	rec_label.text = "● REC  %.1fs" % t


# ----------------------------------------------------------------------------
# SHARED HELPERS
# ----------------------------------------------------------------------------

## Instantiate a .glb/.gltf into a scene node (no adding, no clearing).
func _instantiate_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	return scene as Node3D


## Combined world-space bounding box of every visible mesh in the scene.
func _model_aabb() -> AABB:
	return _node_aabb(model_root)


## World-space bounding box of every visible mesh under (and including) `root`.
func _node_aabb(root: Node) -> AABB:
	var result := AABB()
	var have_one := false
	var stack: Array = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is VisualInstance3D:
			var world_box: AABB = (node as Node3D).global_transform * (node as VisualInstance3D).get_aabb()
			if have_one:
				result = result.merge(world_box)
			else:
				result = world_box
				have_one = true
	if not have_one:
		result = AABB(Vector3.ZERO, Vector3.ONE)
	return result


func _xform_to_array(t: Transform3D) -> Array:
	var b := t.basis
	return [
		b.x.x, b.x.y, b.x.z,
		b.y.x, b.y.y, b.y.z,
		b.z.x, b.z.y, b.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]


func _array_to_xform(a: Array) -> Transform3D:
	return Transform3D(
		Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])),
		Vector3(a[9], a[10], a[11])
	)


func _arg_value(args: PackedStringArray, key: String) -> String:
	var i := args.find(key)
	if i != -1 and i + 1 < args.size():
		return args[i + 1]
	return ""
