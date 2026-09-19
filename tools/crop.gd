extends SceneTree

## Development tool: crop a region out of a PNG and magnify it with
## nearest-neighbour, for inspecting pixel art at working size.
##
##   godot --headless --path . --script res://tools/crop.gd -- \
##       in.png out.png X Y W H SCALE
##
## Pixel art has to be judged at the size it is drawn, not at the size it is
## displayed. This exists so a change to a 16x16 tile or a 20-pixel character
## can actually be looked at.


func _initialize() -> void:
	var a: PackedStringArray = OS.get_cmdline_user_args()
	if a.size() < 7:
		print("usage: crop.gd -- <in.png> <out.png> <x> <y> <w> <h> [scale]")
		quit(2)
		return

	var img: Image = Image.load_from_file(a[0])
	if img == null:
		push_error("crop: cannot read %s" % a[0])
		quit(1)
		return

	var region: Rect2i = Rect2i(int(a[2]), int(a[3]), int(a[4]), int(a[5]))
	region = region.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if region.size.x <= 0 or region.size.y <= 0:
		push_error("crop: region is outside the image")
		quit(1)
		return

	var out: Image = img.get_region(region)
	var scale: int = int(a[6]) if a.size() > 6 else 1
	if scale > 1:
		out.resize(region.size.x * scale, region.size.y * scale,
				Image.INTERPOLATE_NEAREST)

	var err: int = out.save_png(a[1])
	if err != OK:
		push_error("crop: cannot write %s (error %d)" % [a[1], err])
		quit(1)
		return
	print("crop: wrote %s (%dx%d)" % [a[1], out.get_width(), out.get_height()])
	quit(0)
