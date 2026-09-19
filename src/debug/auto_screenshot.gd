class_name AutoScreenshot
extends Node

## Development tool: capture the running game to a PNG and quit
## (spec sections 21, 22).
##
##   godot --path . --resolution 1024x768 -- --shot build/shot.png
##   godot --path . -- --shot build/shot.png --shot-after 90
##
## Art iteration needs to be looked at, not reasoned about. This makes a
## render of the actual game available as a file, so a change to the
## renderer can be checked the same way a change to the simulation is
## checked by the test suite.
##
## Added by game.gd only when the flag is present, and only in a debug build.

var path: String = "build/shot.png"
var after_frames: int = 60
var quit_when_done: bool = true

var _frames: int = 0
var _done: bool = false


## Reads the command line. Returns null when no capture was requested.
static func from_cmdline() -> AutoScreenshot:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--shot")
	if i < 0:
		return null
	var s: AutoScreenshot = AutoScreenshot.new()
	if i + 1 < args.size():
		s.path = args[i + 1]
	var j: int = args.find("--shot-after")
	if j >= 0 and j + 1 < args.size():
		s.after_frames = int(args[j + 1])
	s.quit_when_done = not args.has("--shot-stay")
	return s


func _ready() -> void:
	## Draw on top of nothing: this node never renders, it only captures.
	process_priority = 1000


func _process(_delta: float) -> void:
	if _done:
		return
	_frames += 1
	if _frames < after_frames:
		return
	_done = true
	_capture()
	if quit_when_done:
		get_tree().quit(0)


func _capture() -> void:
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("screenshot: viewport produced no image")
		return
	var dir: String = path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var err: int = img.save_png(path)
	if err != OK:
		push_error("screenshot: could not write %s (error %d)" % [path, err])
	else:
		print("screenshot: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
