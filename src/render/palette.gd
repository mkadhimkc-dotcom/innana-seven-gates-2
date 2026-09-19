class_name Palette
extends RefCounted

## Colour language (spec sections 25, 26).
##
## Each Gate has its own identity while staying inside one coherent world.
## The shared anchors are mud brick, bitumen shadow, bronze, gold and lapis:
## the materials a Sumerian builder actually had. Nothing here is a generic
## fantasy dungeon grey, and nothing is the sand-and-turquoise that would read
## as Egyptian.

## Shared material anchors.
const BITUMEN := Color("0b090e")
const LAPIS := Color("1d3f8f")
const LAPIS_LIGHT := Color("3a68c4")
const GOLD := Color("e0ab48")
const GOLD_DEEP := Color("a6761f")
const BRONZE := Color("8c6239")
const CARNELIAN := Color("a4392c")
const SHELL := Color("e8ddc4")

## UI.
const UI_TEXT := Color("e8ddc4")
const UI_DIM := Color("8a7f68")
const UI_PANEL := Color(0.05, 0.04, 0.06, 0.88)
const UI_PAD := Color(0.85, 0.78, 0.62, 0.30)
const UI_PAD_DOWN := Color(0.88, 0.67, 0.28, 0.55)
const UI_PAD_EDGE := Color(0.93, 0.87, 0.74, 0.85)

## Debug overlay (spec section 22). Deliberately outside the game palette so
## an overlay can never be mistaken for level art.
const DBG_GRID := Color(1, 1, 1, 0.10)
const DBG_COLLISION := Color(0.2, 1.0, 0.4, 0.55)
const DBG_HAZARD := Color(1.0, 0.25, 0.2, 0.6)
const DBG_PLAYER := Color(0.3, 0.9, 1.0, 0.9)
const DBG_ENEMY := Color(1.0, 0.4, 0.9, 0.9)
const DBG_TRIGGER := Color(1.0, 0.9, 0.2, 0.7)
const DBG_PATH := Color(0.4, 0.7, 1.0, 0.85)
const DBG_REACH := Color(0.2, 0.8, 1.0, 0.18)

## Per-gate palettes. Keys are the tile palette names from TileDB.
const GATES: Dictionary = {
	# Gate I - warm clay and sandstone, the outer temple in daylight.
	"gate1": {
		"bg": Color("241a17"),
		"bg_far": Color("2f2119"),
		"wall": Color("6b4a33"),
		"wall_hi": Color("8a6244"),
		"brick": Color("a9743f"),
		"brick_hi": Color("c48f52"),
		"brick_lo": Color("7d5029"),
		"ladder": Color("caa25f"),
		"stair": Color("9c6b3d"),
		"gate_locked": Color("4a3628"),
		"gate_open": Color("f0c96a"),
		"spikes": Color("cdbfa4"),
		"collapse": Color("8e6a45"),
		"water": Color("2f6d86"),
		"pillar": Color("7a5639"),
		"plate": Color("b08a4e"),
		"block": Color("96693c"),
		"hidden": Color("a9743f"),
		"dark": Color("120d10"),
		"empty": Color("241a17"),
	},
	# Gate II - gold, bronze and royal red.
	"gate2": {
		"bg": Color("241b14"),
		"bg_far": Color("33241a"),
		"wall": Color("6a4f2c"),
		"wall_hi": Color("8d6a38"),
		"brick": Color("b08840"),
		"brick_hi": Color("d8ac53"),
		"brick_lo": Color("805e28"),
		"ladder": Color("e0ab48"),
		"stair": Color("a1782f"),
		"gate_locked": Color("4d3a22"),
		"gate_open": Color("ffd97a"),
		"spikes": Color("d8cdb2"),
		"collapse": Color("9a7434"),
		"water": Color("2f6d86"),
		"pillar": Color("8a6535"),
		"plate": Color("c79a45"),
		"block": Color("a37b39"),
		"hidden": Color("b08840"),
		"dark": Color("140f0a"),
		"empty": Color("241b14"),
	},
	# Gate III - tomb stone, bitumen and dry bone.
	"gate3": {
		"bg": Color("161318"),
		"bg_far": Color("1f1b21"),
		"wall": Color("3d3742"),
		"wall_hi": Color("554d5c"),
		"brick": Color("5b5260"),
		"brick_hi": Color("776c7e"),
		"brick_lo": Color("423a48"),
		"ladder": Color("8a7f68"),
		"stair": Color("4f4757"),
		"gate_locked": Color("2a2530"),
		"gate_open": Color("c9b27a"),
		"spikes": Color("cfc6b0"),
		"collapse": Color("574e5c"),
		"water": Color("26536a"),
		"pillar": Color("4a4350"),
		"plate": Color("7d7186"),
		"block": Color("564d5b"),
		"hidden": Color("5b5260"),
		"dark": Color("0b090e"),
		"empty": Color("161318"),
	},
	# Gate IV - flooded sanctuaries, lapis and turquoise reflection.
	"gate4": {
		"bg": Color("0f1e2a"),
		"bg_far": Color("142a3a"),
		"wall": Color("264055"),
		"wall_hi": Color("36596f"),
		"brick": Color("3c6a80"),
		"brick_hi": Color("4f8ba0"),
		"brick_lo": Color("2b4d5e"),
		"ladder": Color("7fc2cc"),
		"stair": Color("35627a"),
		"gate_locked": Color("1c3345"),
		"gate_open": Color("a8e6e0"),
		"spikes": Color("cbd9dc"),
		"collapse": Color("3a6376"),
		"water": Color("2a7d9b"),
		"pillar": Color("2e4f64"),
		"plate": Color("5e9aab"),
		"block": Color("386478"),
		"hidden": Color("3c6a80"),
		"dark": Color("07131b"),
		"empty": Color("0f1e2a"),
	},
	# Gate V - cedar shadow, deep green and old bronze.
	"gate5": {
		"bg": Color("11190f"),
		"bg_far": Color("182414"),
		"wall": Color("2c3d23"),
		"wall_hi": Color("3e5531"),
		"brick": Color("4a6234"),
		"brick_hi": Color("628044"),
		"brick_lo": Color("354826"),
		"ladder": Color("9c8347"),
		"stair": Color("3f5530"),
		"gate_locked": Color("1e2a18"),
		"gate_open": Color("cfe08a"),
		"spikes": Color("c3c9ae"),
		"collapse": Color("475f31"),
		"water": Color("245f5a"),
		"pillar": Color("35492a"),
		"plate": Color("6f8a4c"),
		"block": Color("445c30"),
		"hidden": Color("4a6234"),
		"dark": Color("070c06"),
		"empty": Color("11190f"),
	},
	# Gate VI - Kur. Near-black, lit only by what the player carries.
	"gate6": {
		"bg": Color("07070d"),
		"bg_far": Color("0c0c16"),
		"wall": Color("191b2c"),
		"wall_hi": Color("262941"),
		"brick": Color("232640"),
		"brick_hi": Color("343a5c"),
		"brick_lo": Color("181a2c"),
		"ladder": Color("5a5f8c"),
		"stair": Color("20233a"),
		"gate_locked": Color("111324"),
		"gate_open": Color("8fa4e8"),
		"spikes": Color("9aa0c0"),
		"collapse": Color("212440"),
		"water": Color("152a49"),
		"pillar": Color("1c1f33"),
		"plate": Color("41476e"),
		"block": Color("262a47"),
		"hidden": Color("232640"),
		"dark": Color("030308"),
		"empty": Color("07070d"),
	},
	# Gate VII - the throne. Dark royal, gold and a cold underworld glow.
	"gate7": {
		"bg": Color("120a16"),
		"bg_far": Color("1c0f22"),
		"wall": Color("35203f"),
		"wall_hi": Color("4c2f59"),
		"brick": Color("4a2b52"),
		"brick_hi": Color("68406f"),
		"brick_lo": Color("341d3b"),
		"ladder": Color("e0ab48"),
		"stair": Color("42264c"),
		"gate_locked": Color("23142a"),
		"gate_open": Color("ffe08a"),
		"spikes": Color("d9c9d4"),
		"collapse": Color("452850"),
		"water": Color("1f2a5c"),
		"pillar": Color("3a2244"),
		"plate": Color("7c4f86"),
		"block": Color("48294f"),
		"hidden": Color("4a2b52"),
		"dark": Color("07030a"),
		"empty": Color("120a16"),
	},
}

## Treasure tiers (spec section 13).
const TREASURE_TIER: Dictionary = {
	"common": Color("b9a57e"),
	"valuable": Color("e0ab48"),
	"legendary": Color("6fc6e8"),
}


static func gate(name_or_gate: Variant) -> Dictionary:
	var key: String = ""
	if typeof(name_or_gate) == TYPE_INT:
		key = "gate%d" % int(name_or_gate)
	else:
		key = str(name_or_gate)
	if GATES.has(key):
		return GATES[key]
	return GATES["gate1"]


static func tile_color(palette: Dictionary, tile_id: int) -> Color:
	var key: String = TileDB.palette_of(tile_id)
	if palette.has(key):
		return palette[key]
	return palette.get("empty", BITUMEN)


static func treasure_color(tier: String) -> Color:
	return TREASURE_TIER.get(tier, TREASURE_TIER["common"])
