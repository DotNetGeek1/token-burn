class_name AssetCatalog
extends RefCounted

## Loads presentation asset paths from presentation/asset_catalog.json.

const CATALOG_PATH := "res://presentation/asset_catalog.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(CATALOG_PATH):
		push_warning("AssetCatalog: missing %s" % CATALOG_PATH)
		_data = {}
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_warning("AssetCatalog: could not open %s" % CATALOG_PATH)
		_data = {}
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_data = parsed if parsed is Dictionary else {}


static func get_path(category: String, key: String, fallback: String = "") -> String:
	_ensure_loaded()
	var section: Variant = _data.get(category)
	if section is Dictionary and section.has(key):
		return str(section[key])
	return fallback


static func get_texture(category: String, key: String) -> Texture2D:
	var path: String = get_path(category, key)
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		push_warning("AssetCatalog: missing resource %s" % path)
		return null
	var loaded: Variant = load(path)
	if loaded is Texture2D:
		return loaded
	return null


static func perk_icon(perk_id: String) -> Texture2D:
	var slug: String = perk_id.get_file() if perk_id.contains(".") else perk_id
	if slug.begins_with("perk."):
		slug = slug.substr(5)
	return get_texture("perk_icons", slug)


static func nav_icon(tab: String) -> Texture2D:
	return get_texture("nav_icons", tab.to_lower())


static func stat_icon(stat: String) -> Texture2D:
	return get_texture("stat_icons", stat.to_lower())


## The room the campaign is currently played in. Every location is painted as
## one picture with its furniture in known places, and the shell mounts itself
## onto that picture: the HUD, the machine, the readouts and the side panel are
## all positioned against rects authored beside the art, so moving the run to
## the garage moves the furniture with it instead of leaving the UI pinned to
## coordinates that were measured off the bedroom.
const DEFAULT_DWELLING := "bedroom"


static func board_scene_art(dwelling: String) -> Texture2D:
	var path: String = str(_board_scene(dwelling).get("art", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var loaded: Variant = load(path)
	return loaded if loaded is Texture2D else null


## Where a named part of the shell sits in the room, as a fraction of the
## viewport. Returns an empty rect when the key is unknown, which callers read
## as "this room does not place that part" and fall back to their own layout.
static func board_region(dwelling: String, key: String) -> Rect2:
	return _board_rect(dwelling, "regions", key)


## Where a diegetic readout is painted into the room: the plan board on the
## wall, the thermometer, the power meter, the phone.
static func board_prop(dwelling: String, key: String) -> Rect2:
	return _board_rect(dwelling, "props", key)


static func board_prop_keys(dwelling: String) -> Array:
	var props: Variant = _board_scene(dwelling).get("props")
	return Dictionary(props).keys() if props is Dictionary else []


## The surface a prop's readout is actually painted on, as four corners in
## viewport fractions: top-left, top-right, bottom-right, bottom-left.
##
## Most props face the camera, so their rect is the whole story. A phone lying
## flat on the desk does not: its screen is a foreshortened parallelogram, and
## writing on it in an upright box makes the text look stuck to the picture
## rather than displayed on the thing. Rooms that measure the quad get their
## readout laid into the phone's own plane. Empty when the room does not.
static func board_prop_plane(dwelling: String, key: String) -> PackedVector2Array:
	var planes: Variant = _board_scene(dwelling).get("prop_planes")
	if not planes is Dictionary or not Dictionary(planes).has(key):
		return PackedVector2Array()
	var corners: Array = Array(Dictionary(planes)[key])
	if corners.size() != 4:
		return PackedVector2Array()
	var quad := PackedVector2Array()
	for corner in corners:
		var point: Array = Array(corner)
		if point.size() != 2:
			return PackedVector2Array()
		quad.append(Vector2(float(point[0]), float(point[1])))
	return quad


## The blank screen of the laptop standing on the desk. The office console is
## drawn into this rather than floated over the room.
static func board_laptop_screen(dwelling: String) -> Rect2:
	var scene: Dictionary = _board_scene(dwelling)
	if not scene.has("laptop_screen"):
		return Rect2()
	return _rect_from(Array(scene["laptop_screen"]))


## A room rect expressed relative to one of that room's own regions, for
## controls that are mounted inside a region rather than on the window.
static func board_rect_in_region(outer: Rect2, inner: Rect2) -> Rect2:
	if outer.size.x <= 0.0 or outer.size.y <= 0.0 or inner.size.x <= 0.0:
		return Rect2()
	return Rect2(
		(inner.position.x - outer.position.x) / outer.size.x,
		(inner.position.y - outer.position.y) / outer.size.y,
		inner.size.x / outer.size.x,
		inner.size.y / outer.size.y
	)


## Which rooms the art kit carries, in catalog order.
static func board_scene_keys() -> Array:
	_ensure_loaded()
	var scenes: Variant = _data.get("board_scenes")
	return Dictionary(scenes).keys() if scenes is Dictionary else []


## A location with no art of its own still has to have somewhere to stand, so
## every lookup falls back to the room the campaign starts in.
static func _board_scene(dwelling: String) -> Dictionary:
	_ensure_loaded()
	var scenes: Variant = _data.get("board_scenes")
	if not scenes is Dictionary:
		return {}
	var table: Dictionary = scenes
	if table.has(dwelling):
		return Dictionary(table[dwelling])
	if table.has(DEFAULT_DWELLING):
		return Dictionary(table[DEFAULT_DWELLING])
	return {}


static func _board_rect(dwelling: String, group: String, key: String) -> Rect2:
	var group_data: Variant = _board_scene(dwelling).get(group)
	if not group_data is Dictionary or not Dictionary(group_data).has(key):
		return Rect2()
	return _rect_from(Array(Dictionary(group_data)[key]))


## A venue: one of the places the player goes to that is not the desk.
##
## Same idea as a room, and authored the same way. The picture is the place, and
## the panels hanging in it are blank in the art so the live screen is printed
## into them: the market's stock board is a board on a wall, not a table
## floating over a photograph. Rects are fractions of the picture, which is
## drawn at the design aspect, so a region lands on the panel it was measured
## off whatever the window is doing.
static func venue_art(venue: String) -> Texture2D:
	var path: String = str(_venue_scene(venue).get("art", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var loaded: Variant = load(path)
	return loaded if loaded is Texture2D else null


## Where a named panel is painted in the venue. Empty when the picture does not
## carry one, which the venue reads as "this place has nothing to say there".
##
## The venue pictures are shot against one panel template, so the rects live once
## under venue_defaults and a venue only names the ones its own picture moved.
static func venue_region(venue: String, key: String) -> Rect2:
	var own: Variant = _venue_scene(venue).get("regions")
	if own is Dictionary and Dictionary(own).has(key):
		return _rect_from(Array(Dictionary(own)[key]))
	var shared: Variant = _venue_defaults().get("regions")
	if shared is Dictionary and Dictionary(shared).has(key):
		return _rect_from(Array(Dictionary(shared)[key]))
	return Rect2()


static func _venue_defaults() -> Dictionary:
	_ensure_loaded()
	var defaults: Variant = _data.get("venue_defaults")
	return defaults if defaults is Dictionary else {}


static func venue_keys() -> Array:
	_ensure_loaded()
	var scenes: Variant = _data.get("venue_scenes")
	return Dictionary(scenes).keys() if scenes is Dictionary else []


static func _venue_scene(venue: String) -> Dictionary:
	_ensure_loaded()
	var scenes: Variant = _data.get("venue_scenes")
	if not scenes is Dictionary:
		return {}
	var table: Dictionary = scenes
	return Dictionary(table[venue]) if table.has(venue) else {}


static func investor_texture(key: String) -> Texture2D:
	return get_texture("investor", key)


## Burn Board rig art: the workstation the player watches while a batch runs and
## the warning beacon that spins up when the rig is about to cook itself.
static func rig_texture(key: String) -> Texture2D:
	return get_texture("rig", key)


## The workstation the run has earned, with everything the board needs to mount
## its own furniture on it: where the artwork's screens are, and where the hottest
## component vents. Those are properties of the picture, so they are authored
## beside it rather than as constants in the rig's script.
##
## Screen rects and the vent point are fractions of the *source* image. The board
## shows the band between `crop_top` and `crop_height` — trimming a photograph's
## empty sky and its empty floor is what stops the alcove from being mostly black —
## so the crop is applied here and the fractions rebased onto what is drawn.
static func rig_stage(stage_index: int) -> Dictionary:
	_ensure_loaded()
	var key: String = "stage_%02d" % clampi(stage_index, 1, 5)
	var section: Variant = _data.get("rig_stages")
	if not section is Dictionary or not section.has(key):
		return {}
	var entry: Dictionary = Dictionary(section[key])
	var path: String = str(entry.get("art", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("AssetCatalog: missing rig art %s" % path)
		return {}
	var texture: Variant = load(path)
	if not texture is Texture2D:
		return {}
	var crop_top: float = clampf(float(entry.get("crop_top", 0.0)), 0.0, 0.8)
	var crop_bottom: float = clampf(
		float(entry.get("crop_height", 1.0)), crop_top + 0.1, 1.0
	)
	var span: float = crop_bottom - crop_top
	var screens: Array[Rect2] = []
	for raw in Array(entry.get("screens", [])):
		var numbers: Array = Array(raw)
		if numbers.size() < 4:
			continue
		screens.append(Rect2(
			float(numbers[0]),
			(float(numbers[1]) - crop_top) / span,
			float(numbers[2]),
			float(numbers[3]) / span
		))
	var vent_numbers: Array = Array(entry.get("vent", [0.5, 0.1]))
	var vent := Vector2(0.5, 0.1)
	if vent_numbers.size() >= 2:
		vent = Vector2(
			float(vent_numbers[0]), (float(vent_numbers[1]) - crop_top) / span
		)
	return {
		"stage": clampi(stage_index, 1, 5),
		"texture": texture,
		"crop_top": crop_top,
		"crop_height": crop_bottom,
		# How narrow a slice of the artwork may be shown before it stops reading as
		# a machine in an alcove. A laptop sits in the middle of its frame and can
		# lose most of its black margin; two towers stand at the outer edges of
		# theirs and can lose almost nothing.
		"safe_width": clampf(float(entry.get("safe_width", 1.0)), 0.2, 1.0),
		"screens": screens,
		"vent": vent,
	}


## Which workstation the run has earned. Read off a ladder in the catalog rather
## than hardcoded, because "what counts as a datacentre" is content.
##
## `machine_count` is how many machines stand on the floor, which the caller has
## from the compute system: the hardware list also holds cooling and components,
## and neither of those is a second machine.
static func rig_stage_for_build(build: Dictionary, machine_count: int) -> int:
	_ensure_loaded()
	var owned: Array = Array(build.get("hardware", []))
	for raw_rule in Array(_data.get("rig_stage_ladder", [])):
		if not raw_rule is Dictionary:
			continue
		var rule: Dictionary = raw_rule
		var stage: int = int(rule.get("stage", 1))
		var wanted: int = int(rule.get("machines", 0))
		if wanted > 0 and machine_count >= wanted:
			return stage
		for key in Array(rule.get("hardware", [])):
			if owned.has(str(key)):
				return stage
	return 1


## Housing art for a rig instrument, plus the sub-rects the instrument draws into.
## The dial and the segment column are photographs of empty hardware; the reading
## is painted into the recessed windows so the widget looks bolted to the machine
## rather than floated over it.
static func rig_instrument(key: String) -> Dictionary:
	_ensure_loaded()
	var section: Variant = _data.get("rig_instruments")
	if not section is Dictionary or not section.has(key):
		return {}
	var entry: Dictionary = Dictionary(section[key])
	var path: String = str(entry.get("art", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("AssetCatalog: missing instrument art %s" % path)
		return {}
	var texture: Variant = load(path)
	if not texture is Texture2D:
		return {}
	var housing: Dictionary = {"texture": texture}
	for field in ["label", "channel", "readout"]:
		if entry.has(field):
			housing[field] = _rect_from(Array(entry[field]))
	if entry.has("face_centre"):
		var centre: Array = Array(entry["face_centre"])
		if centre.size() >= 2:
			housing["face_centre"] = Vector2(float(centre[0]), float(centre[1]))
	if entry.has("face_radius"):
		housing["face_radius"] = float(entry["face_radius"])
	return housing


static func _rect_from(numbers: Array) -> Rect2:
	if numbers.size() < 4:
		return Rect2()
	return Rect2(
		float(numbers[0]), float(numbers[1]), float(numbers[2]), float(numbers[3])
	)


static func title_art() -> Texture2D:
	return get_texture("title", "key_art")


static func logo_texture(key: String = "full") -> Texture2D:
	return get_texture("logo", key)


static func event_art(event_id: String) -> Texture2D:
	var tex: Texture2D = get_texture("event_art", event_id)
	if tex != null:
		return tex
	return get_texture("event_art", "default")


static func rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common":
			return palette_color("green")
		"rare":
			return palette_color("blue")
		"epic":
			return palette_color("purple")
		"legendary":
			return palette_color("yellow")
		_:
			return palette_color("grey")


static func category_icon(category: String) -> Texture2D:
	match category.to_lower():
		"dwelling":
			return nav_icon("office")
		"advertising":
			# No dedicated advertising icon in the kit yet; cash reads closest.
			return stat_icon("cash")
		"hardware", "component":
			return get_texture("category_icons", "hardware")
		"cloud":
			return get_texture("category_icons", "cloud")
		"local":
			return get_texture("category_icons", "local")
		"hybrid":
			return get_texture("category_icons", "hybrid")
		"perks":
			return get_texture("category_icons", "perks")
		_:
			return null


## Burn Board modules reuse the existing kit: a module's category maps onto the
## nearest stat or category glyph rather than needing bespoke art per operation.
static func operation_icon(category: String) -> Texture2D:
	match category.to_lower():
		"model", "prompt", "context":
			return get_texture("category_icons", "local")
		"agent":
			return stat_icon("agents")
		"test":
			return stat_icon("quality")
		"cache":
			return get_texture("category_icons", "cloud")
		"hardware":
			return get_texture("category_icons", "hardware")
		"deploy":
			return stat_icon("deadline")
		_:
			return category_icon(category)


## Permanent unlocks borrow the glyph that matches what they change, so a
## debrief card reads at a glance rather than needing bespoke art.
static func unlock_icon(kind: String) -> Texture2D:
	match kind.to_lower():
		"extra_slot":
			return nav_icon("board")
		"starting_module":
			return get_texture("category_icons", "local")
		"starting_hardware":
			return get_texture("category_icons", "local")
		"cooling":
			return stat_icon("power")
		"starting_cash":
			return stat_icon("cash")
		"efficiency_base":
			return stat_icon("quality")
		_:
			return get_texture("category_icons", "perks")


## Award art. Falls back to the padlock rather than to nothing, so a row in the
## trophy cabinet always has something in its icon slot.
static func achievement_icon(key: String) -> Texture2D:
	var texture: Texture2D = get_texture("achievement_icons", key.to_lower())
	if texture != null:
		return texture
	return get_texture("achievement_icons", "locked")


static func status_icon(status: String) -> Texture2D:
	return get_texture("status_icons", status.to_lower())


static func tag_icon(tag: String) -> Texture2D:
	var normalized_tag: String = tag.to_lower()
	if _is_category_tag(normalized_tag):
		return get_texture("category_icons", normalized_tag)
	var status_key: String = _status_key_for_tag(normalized_tag)
	if not status_key.is_empty():
		return status_icon(status_key)
	var stat_key: String = _stat_key_for_tag(normalized_tag)
	if stat_key.is_empty():
		return null
	return stat_icon(stat_key)


## Which room a run is being played in. The rig growing on the desk is the burn
## board's job; the room only changes when the operation moves premises.
static func dwelling_for_build(build: Dictionary) -> String:
	var dwelling: String = str(build.get("dwelling", DEFAULT_DWELLING))
	return dwelling if not dwelling.is_empty() else DEFAULT_DWELLING


static func palette_color(color_name: String, fallback: Color = Color.WHITE) -> Color:
	_ensure_loaded()
	var colors: Variant = _data.get("palette")
	if colors is Dictionary and colors.has(color_name):
		return Color(str(colors[color_name]))
	return fallback


static func _is_category_tag(tag: String) -> bool:
	return tag == "cloud" or tag == "local" or tag == "hybrid" or tag == "hardware" or tag == "perks"


static func _status_key_for_tag(tag: String) -> String:
	match tag:
		"bugs":
			return "bug"
		"risk":
			return "warning"
		_:
			return ""


static func _stat_key_for_tag(tag: String) -> String:
	match tag:
		"agents":
			return "agents"
		"quality":
			return "quality"
		"deadline":
			return "deadline"
		"reward":
			return "cash"
		"cash":
			return "cash"
		"advertising":
			return "cash"
		"tokens":
			return "tokens"
		"passive":
			return "tokens"
		"throughput":
			return "power"
		"efficiency":
			return "power"
		"reputation":
			return "reputation"
		"demand":
			return "reputation"
		"speed":
			return "deadline"
		_:
			return ""
