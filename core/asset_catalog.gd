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
	_data = AssetCatalogLoader.load_catalog(CATALOG_PATH)


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


## The empty desk bay reserved for the run's staged workstation. The room art
## deliberately carries no computer of its own; one shared foreground machine
## is fitted into this rectangle on both the idle desk and the Burn Board.
static func board_workstation_bay(dwelling: String) -> Rect2:
	var scene: Dictionary = _board_scene(dwelling)
	if scene.has("workstation_bay"):
		return _rect_from(Array(scene["workstation_bay"]))
	if scene.has("laptop_screen"):
		return _rect_from(Array(scene["laptop_screen"]))
	return Rect2()


## Temporary compatibility alias for callers and older content authored before
## the foreground workstation replaced the laptop baked into every room.
static func board_laptop_screen(dwelling: String) -> Rect2:
	return board_workstation_bay(dwelling)


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


## The photographed face of a venue panel, as top-left, top-right,
## bottom-right, bottom-left viewport fractions. A rect still supplies focus and
## fallback layout; the plane is what lets the live panel follow the furniture.
static func venue_plane(venue: String, key: String) -> PackedVector2Array:
	var planes: Variant = _venue_scene(venue).get("planes")
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


## Largest axis-aligned rectangle inside a convex quadrilateral, in the same
## fraction space the corners were authored in. Empty when the points do not
## enclose a rectangle.
##
## Native venues warp a live panel onto the photographed plane. The Web
## Compatibility renderer cannot, so the axis-aligned fallback has to sit inside
## the writing surface rather than on the bounding box — otherwise the top rail
## and the brick below the board receive controls.
static func inscribed_rect(corners: PackedVector2Array) -> Rect2:
	if corners.size() != 4:
		return Rect2()
	var left: float = maxf(corners[0].x, corners[3].x)
	var right: float = minf(corners[1].x, corners[2].x)
	var top: float = maxf(corners[0].y, corners[1].y)
	var bottom: float = minf(corners[2].y, corners[3].y)
	if right - left < 0.0001 or bottom - top < 0.0001:
		return Rect2()
	return Rect2(left, top, right - left, bottom - top)


## Where an unwarped live panel may sit. Prefers the inscribed writing surface
## of a measured plane and falls back to the authored bounding region.
static func venue_axis_aligned_region(venue: String, key: String) -> Rect2:
	var inner: Rect2 = inscribed_rect(venue_plane(venue, key))
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		return inner
	return venue_region(venue, key)


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


## The Burn Cabinet: one painted chassis with every well, socket and button left
## blank, and the live game drawn into rects authored beside it. Same idea as a
## room, measured the same way — fractions of the plate, which is drawn at the
## design aspect so a region lands on the well it was measured off.
static func cabinet_art() -> Texture2D:
	var path: String = str(_cabinet().get("art", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var loaded: Variant = load(path)
	return loaded if loaded is Texture2D else null


## Cutout art the cabinet mounts onto its glass: the paper job tag, the module
## cartridge frame.
static func cabinet_texture(key: String) -> Texture2D:
	var textures: Variant = _cabinet().get("textures")
	if not textures is Dictionary or not Dictionary(textures).has(key):
		return null
	var path: String = str(Dictionary(textures)[key])
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("AssetCatalog: missing cabinet texture %s" % path)
		return null
	var loaded: Variant = load(path)
	return loaded if loaded is Texture2D else null


## The cabinet's own bold glyphs: one per module category, one per contract
## sector stamp. Solid white on alpha, made to be tinted and read at 16px, which
## the hairline SVG icons of the rooms were not. Falls back to those when the
## cabinet has no glyph under that key.
static func cabinet_glyph(key: String) -> Texture2D:
	var glyphs: Variant = _cabinet().get("glyphs")
	if glyphs is Dictionary and Dictionary(glyphs).has(key.to_lower()):
		var path: String = str(Dictionary(glyphs)[key.to_lower()])
		if ResourceLoader.exists(path):
			var loaded: Variant = load(path)
			if loaded is Texture2D:
				return loaded
	return null


## A module's glyph on the cabinet, by category.
static func cabinet_module_glyph(category: String) -> Texture2D:
	var glyph: Texture2D = cabinet_glyph(category)
	return glyph if glyph != null else module_icon(category)


## A contract's stamp on the cabinet, by the sector's stat icon name.
static func cabinet_stamp(icon_key: String) -> Texture2D:
	var glyph: Texture2D = cabinet_glyph(icon_key)
	if glyph == null:
		glyph = cabinet_glyph("target")
	return glyph if glyph != null else stat_icon(icon_key)


## Where a named well of the cabinet sits, as a fraction of the plate. Empty when
## the plate does not carry that well.
static func cabinet_region(key: String) -> Rect2:
	var regions: Variant = _cabinet().get("regions")
	if not regions is Dictionary or not Dictionary(regions).has(key):
		return Rect2()
	return _rect_from(Array(Dictionary(regions)[key]))


## A well painted off square: its top-left, top-right and bottom-left glass
## corners as fractions of the plate, so the readout can be sheared to fit.
## Empty for wells that are plain rectangles.
static func cabinet_quad(key: String) -> PackedVector2Array:
	var quads: Variant = _cabinet().get("quads")
	if not quads is Dictionary or not Dictionary(quads).has(key):
		return PackedVector2Array()
	var corners := PackedVector2Array()
	for raw in Array(Dictionary(quads)[key]):
		var pair: Array = Array(raw)
		if pair.size() >= 2:
			corners.append(Vector2(float(pair[0]), float(pair[1])))
	return corners if corners.size() == 3 else PackedVector2Array()


## The module dock's sockets, in bay order, as fractions of the plate.
static func cabinet_sockets() -> Array[Rect2]:
	var sockets: Array[Rect2] = []
	for raw in Array(_cabinet().get("sockets", [])):
		var rect: Rect2 = _rect_from(Array(raw))
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			sockets.append(rect)
	return sockets


static func _cabinet() -> Dictionary:
	_ensure_loaded()
	var section: Variant = _data.get("cabinet")
	return section if section is Dictionary else {}


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
	var upgrades: Array = Array(build.get("upgrades", []))
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
		for upgrade_id in Array(rule.get("upgrades", [])):
			if upgrades.has(str(upgrade_id)):
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
		"hardware", "component":
			return get_texture("category_icons", "hardware")
		"local":
			return get_texture("category_icons", "local")
		"hybrid":
			return get_texture("category_icons", "hybrid")
		"perks":
			return get_texture("category_icons", "perks")
		_:
			return null


## Burn Board modules reuse the existing kit: a module's category maps onto the
## nearest stat or category glyph rather than needing bespoke art per module.
static func module_icon(category: String) -> Texture2D:
	match category.to_lower():
		"model", "prompt", "context":
			return get_texture("category_icons", "local")
		"agent":
			return stat_icon("agents")
		"test":
			return stat_icon("quality")
		"cache":
			return get_texture("category_icons", "local")
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
	return tag == "local" or tag == "hybrid" or tag == "hardware" or tag == "perks"


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
		"speed":
			return "deadline"
		_:
			return ""
