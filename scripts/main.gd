extends Node3D
## Root of the app. Runs in one of two modes:
##
##   INTERACTIVE (normal launch): load a model, move the camera, and click
##       Record to start/stop capturing the camera's MOVEMENT (a MotionPath).
##   REPLAY (a relaunched copy of ourselves, with Godot's Movie Maker on):
##       loads the same model, replays the recorded camera path deterministically
##       into an AVI, then quits.
##
## Recording the real movement works because Movie Maker can only be switched on
## at launch (never mid-run). So we capture the path live in the interactive
## app, then relaunch a second copy with --write-movie/--fixed-fps that replays
## that exact path. When it finishes we convert the AVI to MP4 with ffmpeg.

const RECORD_FPS := 60
const MIN_CLIP_SECONDS := 0.3    ## ignore accidental too-short recordings

## This build's version. Bump it every time you publish a new build.
const APP_VERSION := "0.1.0"
## A small JSON file you host online describing the latest version. Leave empty
## to disable update checks. Format:
##   {"version": "0.2.0", "url": "https://.../download", "notes": "What's new"}
const UPDATE_CHECK_URL := "https://raw.githubusercontent.com/dannysusername/TomasAuraMachine/main/version.json"

@onready var camera: CameraController = $Camera3D
@onready var model_root: Node3D = $ModelRoot
@onready var ui: CanvasLayer = $UI
@onready var status_label: Label = $UI/Controls/StatusLabel
@onready var hint_label: Label = $UI/Controls/HintLabel
@onready var rec_label: Label = $UI/Controls/RecLabel
@onready var load_button: Button = $UI/Controls/LoadButton
@onready var sample_button: Button = $UI/Controls/SampleButton
@onready var record_button: Button = $UI/Controls/RecordButton
@onready var mode_button: Button = $UI/Controls/ModeButton
@onready var file_dialog: FileDialog = $UI/FileDialog
@onready var result_dialog: AcceptDialog = $UI/ResultDialog
@onready var update_dialog: AcceptDialog = $UI/UpdateDialog

const HINT_ORBIT := "Drag to rotate • Scroll to zoom • Right-drag to pan"
const HINT_FLY := "WASD move • Q/E down/up • Hold right-mouse to look • Shift = faster"

var _is_recording_instance := false
var _current_model_path := ""

# Interactive: live capture of the camera's movement.
var _path := MotionPath.new()
var _recording_path := false
var _record_start_usec := 0

# Replay instance: play back a recorded path.
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
	file_dialog.file_selected.connect(_load_and_frame)
	# Drag-and-drop a model file straight onto the window.
	get_window().files_dropped.connect(_on_files_dropped)
	# "Done!" popup with quick actions.
	result_dialog.add_button("📁 Open Folder", false, "folder")
	result_dialog.add_button("▶ Watch", true, "watch")
	result_dialog.custom_action.connect(_on_result_action)
	# "Update available" popup.
	update_dialog.add_button("⬇ Download", true, "download")
	update_dialog.custom_action.connect(_on_update_action)
	get_window().title = "TomasAuraMachine v%s" % APP_VERSION
	record_button.disabled = true
	_update_mode_ui()
	status_label.text = "Load a model, drag a .glb onto the window, or click \"Try a Sample\"."
	_check_for_updates()


# ----------------------------------------------------------------------------
# UPDATE CHECK
# ----------------------------------------------------------------------------

func _check_for_updates() -> void:
	if UPDATE_CHECK_URL.is_empty():
		return   # update checks not configured
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_update_check_completed)
	http.request(UPDATE_CHECK_URL)   # async; failures are ignored silently


func _on_update_check_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	# Never nag the user about network problems — only act on a clear newer version.
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return
	var dict := data as Dictionary
	var latest := str(dict.get("version", ""))
	if latest.is_empty() or not _is_newer(latest, APP_VERSION):
		return
	_update_url = str(dict.get("url", ""))
	var notes := str(dict.get("notes", ""))
	update_dialog.dialog_text = "A new version (%s) is available.\nYou have v%s.\n\n%s" % [latest, APP_VERSION, notes]
	update_dialog.popup_centered()


func _on_update_action(action: String) -> void:
	if action == "download" and not _update_url.is_empty():
		OS.shell_open(_update_url)
	update_dialog.hide()


## True if dotted version `remote` (e.g. "0.2.0") is greater than `local`.
func _is_newer(remote: String, local: String) -> bool:
	var r := remote.split(".")
	var l := local.split(".")
	for i in range(maxi(r.size(), l.size())):
		var rv := int(r[i]) if i < r.size() else 0
		var lv := int(l[i]) if i < l.size() else 0
		if rv != lv:
			return rv > lv
	return false


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
		base = OS.get_user_data_dir()   # fallback if there's no Desktop
	var folder := base.path_join("TomasMovies")
	DirAccess.make_dir_recursive_absolute(folder)
	return folder


func _unhandled_input(event: InputEvent) -> void:
	# Tab toggles orbit / free-fly (only in the interactive app).
	if not _is_recording_instance and event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
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


## Single place that loads a model file and frames it — used by the file
## dialog, drag-and-drop, and the sample generator.
func _load_and_frame(path: String) -> void:
	if _load_model(path):
		_current_model_path = path
		record_button.disabled = false
		_frame_model()
		status_label.text = "Loaded: %s" % path.get_file()


func _on_files_dropped(files: PackedStringArray) -> void:
	for f in files:
		var lower := f.to_lower()
		if lower.ends_with(".glb") or lower.ends_with(".gltf"):
			_load_and_frame(f)
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


## Build a simple 3D model on the fly, save it as a real .glb, and load it —
## so there's always something to play with, no download needed. Because it's
## saved to a real file, it records exactly like any other model.
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
	_load_and_frame(sample_path)


func _add_primitive(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh.material = mat   # set on the mesh so it survives the .glb export
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	mi.owner = parent


## Center and frame the loaded model. The camera controller works out the
## distance, angle, speed and clip planes from the model's size.
func _frame_model() -> void:
	var box := _model_aabb()
	var center := box.get_center()
	var radius: float = max(box.size.length() * 0.5, 0.001)
	camera.frame_object(center, radius)


func _on_record_pressed() -> void:
	if _recording_path:
		_stop_recording()
	else:
		_start_recording()


func _start_recording() -> void:
	_path.clear()
	_recording_path = true
	_record_start_usec = Time.get_ticks_usec()
	record_button.text = "■ Stop"
	rec_label.visible = true
	rec_label.text = "● REC  0.0s"
	load_button.disabled = true
	status_label.text = "Recording your shot — move the camera, then click Stop."


func _stop_recording() -> void:
	_recording_path = false
	rec_label.visible = false
	record_button.text = "● Record"
	record_button.disabled = true
	load_button.disabled = true

	if not _path.is_valid() or _path.duration() < MIN_CLIP_SECONDS:
		status_label.text = "That was too quick — press Record, move around a bit, then Stop."
		_reset_buttons()
		return

	status_label.text = "Rendering your %.1fs clip… (a window will flash, then your video opens)" % _path.duration()
	# Let the UI repaint before we block on the external render + convert.
	await get_tree().process_frame
	await get_tree().process_frame
	_run_recording_pipeline()


func _run_recording_pipeline() -> void:
	var temp_dir := OS.get_user_data_dir()              # scratch for AVI + path file
	var folder := _output_folder()                      # Desktop/TomasMovies for the MP4
	var avi_path := temp_dir.path_join("clip.avi")
	var path_file := temp_dir.path_join("flight.json")
	var stamp := Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var mp4_path := folder.path_join("shot_%s.mp4" % stamp)

	# Save the recorded camera movement for the replay copy to read.
	if not _path.save_json(path_file):
		status_label.text = "Couldn't save the recorded movement."
		_reset_buttons()
		return

	# Build the command line for the replay copy of ourselves.
	var exe := OS.get_executable_path()
	var args := PackedStringArray()
	if OS.has_feature("editor"):
		# In the editor, the executable IS the editor — point it at our project.
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--write-movie")
	args.append(avi_path)
	args.append("--fixed-fps")
	args.append(str(RECORD_FPS))
	# Everything after "--" is delivered to us via OS.get_cmdline_user_args().
	args.append("--")
	args.append("--record")
	args.append("--model")
	args.append(_current_model_path)
	args.append("--path-file")
	args.append(path_file)

	# Blocking: returns when the replay copy has fully quit (and finalized the AVI).
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

	# Convert AVI -> MP4 with the bundled ffmpeg.
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


func _reset_buttons() -> void:
	record_button.disabled = false
	load_button.disabled = false


## Locate the ffmpeg binary: next to the .exe first (for the exported app),
## then the project's bin/ folder (for running in the editor).
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


# ----------------------------------------------------------------------------
# RECORDING MODE
# ----------------------------------------------------------------------------

func _enter_recording_mode(args: PackedStringArray) -> void:
	_is_recording_instance = true
	ui.visible = false
	# Silence the interactive camera controller in this copy.
	camera.set_process(false)
	camera.set_process_unhandled_input(false)

	var model_path := _arg_value(args, "--model")
	if model_path != "":
		_load_model(model_path)

	if not _replay_path.load_json(_arg_value(args, "--path-file")):
		# Nothing valid to replay — don't leave the render hanging.
		get_tree().quit()


func _process(delta: float) -> void:
	if _is_recording_instance:
		_process_replay(delta)
	elif _recording_path:
		_sample_camera()


## REPLAY copy: drive the camera along the recorded path, then quit at the end.
func _process_replay(delta: float) -> void:
	_replay_time += delta
	camera.global_transform = _replay_path.sample_at(_replay_time)
	if _replay_time >= _replay_path.duration():
		get_tree().quit()


## INTERACTIVE: capture the camera's transform stamped with elapsed seconds.
func _sample_camera() -> void:
	var t := (Time.get_ticks_usec() - _record_start_usec) / 1000000.0
	_path.add_sample(t, camera.global_transform)
	rec_label.text = "● REC  %.1fs" % t


# ----------------------------------------------------------------------------
# SHARED HELPERS
# ----------------------------------------------------------------------------

## Load a .glb at runtime via GLTFDocument. Works in exported builds too.
func _load_model(path: String) -> bool:
	for child in model_root.get_children():
		child.queue_free()

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		status_label.text = "Couldn't read that file (error %d)." % err
		return false
	var scene := doc.generate_scene(state)
	if scene == null:
		status_label.text = "Couldn't build a scene from that model."
		return false
	model_root.add_child(scene)
	return true


## Combined world-space bounding box of every visible mesh under the model.
func _model_aabb() -> AABB:
	var result := AABB()
	var have_one := false
	var stack: Array = [model_root]
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


func _arg_value(args: PackedStringArray, key: String) -> String:
	var i := args.find(key)
	if i != -1 and i + 1 < args.size():
		return args[i + 1]
	return ""
