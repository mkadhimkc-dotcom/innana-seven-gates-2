extends Node

## Player-facing settings, persisted to user:// (spec sections 11, 35).
##
## Controls must be configurable and the game must be playable on a phone
## without a physical controller, so the virtual pad layout lives here too.

const PATH: String = "user://settings.cfg"

signal changed

## Audio, 0-100 so the values survive a round trip through the config file
## without float formatting noise.
var music_volume: int = 80
var sfx_volume: int = 100

## Virtual pad (spec section 11).
##
## On by default only where there is no keyboard. On a desktop it sat on top
## of the play area and hid the corners of the room, which is exactly the
## "excessive permanent UI" section 34 warns against. Players can still turn
## it on anywhere from the controls menu.
##
## The touchscreen check matters as much as the platform one: `has_feature`
## is FALSE for a phone running the web export, so testing the platform alone
## would ship a browser build with no controls at all on mobile.
var touch_enabled: bool = (OS.has_feature("mobile")
		or DisplayServer.is_touchscreen_available())
var pad_scale: int = 100          ## percent
var pad_opacity: int = 55         ## percent
var pad_left_handed: bool = false
var pad_margin: int = 12          ## world units from the screen edge

## Accessibility and presentation.
var screen_shake: bool = true
var high_contrast: bool = false
var show_timer: bool = false
var language: String = "en"

## Development only. Never true in a release build.
var qa_tools: bool = false


func _ready() -> void:
	load_settings()
	qa_tools = OS.is_debug_build()


func load_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	music_volume = int(cfg.get_value("audio", "music", music_volume))
	sfx_volume = int(cfg.get_value("audio", "sfx", sfx_volume))
	touch_enabled = bool(cfg.get_value("controls", "touch", touch_enabled))
	pad_scale = int(cfg.get_value("controls", "pad_scale", pad_scale))
	pad_opacity = int(cfg.get_value("controls", "pad_opacity", pad_opacity))
	pad_left_handed = bool(cfg.get_value("controls", "left_handed", pad_left_handed))
	pad_margin = int(cfg.get_value("controls", "pad_margin", pad_margin))
	screen_shake = bool(cfg.get_value("video", "screen_shake", screen_shake))
	high_contrast = bool(cfg.get_value("video", "high_contrast", high_contrast))
	show_timer = bool(cfg.get_value("video", "show_timer", show_timer))
	language = str(cfg.get_value("misc", "language", language))
	changed.emit()


func save_settings() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "touch", touch_enabled)
	cfg.set_value("controls", "pad_scale", pad_scale)
	cfg.set_value("controls", "pad_opacity", pad_opacity)
	cfg.set_value("controls", "left_handed", pad_left_handed)
	cfg.set_value("controls", "pad_margin", pad_margin)
	cfg.set_value("video", "screen_shake", screen_shake)
	cfg.set_value("video", "high_contrast", high_contrast)
	cfg.set_value("video", "show_timer", show_timer)
	cfg.set_value("misc", "language", language)
	cfg.save(PATH)
	changed.emit()
