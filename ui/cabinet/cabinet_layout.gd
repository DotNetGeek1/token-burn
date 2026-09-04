class_name CabinetLayout
extends RefCounted

## Where everything on the cabinet goes. The shell asks this for geometry and
## never reads a picture for it, so the way instruments are placed can change
## under the shell without the shell noticing.
##
## The responsive shell: `presentation/cabinet_layout_profiles.json` carries
## three profiles (wide, compact, tablet) chosen by the window's aspect and
## width. Each profile gives the coarse regions — abort rail, CRT, telemetry,
## command deck, backplane — as fractions of the *safe area*: the viewport
## minus the display's own safe-area insets (notches) minus a fixed inset.
## Art decorates those regions; nothing here is measured off a painting.

const PROFILES_PATH := "res://presentation/cabinet_layout_profiles.json"

static var _profiles_data: Dictionary = {}
static var _profiles_loaded: bool = false

var _profile_key: String = ""
var _profile: Dictionary = {}
var _view: Vector2 = Vector2.ZERO
var _safe: Rect2 = Rect2()


static func _data() -> Dictionary:
	if _profiles_loaded:
		return _profiles_data
	_profiles_loaded = true
	_profiles_data = AssetCatalogLoader.load_catalog(PROFILES_PATH)
	if _profiles_data.is_empty():
		push_error("CabinetLayout: could not load %s" % PROFILES_PATH)
	return _profiles_data


static func _section(key: String) -> Dictionary:
	var section: Variant = _data().get(key)
	return section if section is Dictionary else {}


# --- Profile selection --------------------------------------------------------

## Fits the layout to a viewport: picks the profile and computes the safe area.
## Everything else answers against the last fit.
func fit(view: Vector2) -> void:
	_view = view
	_profile_key = select_profile_key(view)
	_profile = Dictionary(_section("profiles").get(_profile_key, {}))
	_safe = _compute_safe_rect(view)


## Which profile a viewport of this size gets, without fitting.
static func select_profile_key(view: Vector2) -> String:
	if view.x <= 0.0 or view.y <= 0.0:
		return "wide"
	var aspect: float = view.x / view.y
	var profiles: Dictionary = _section("profiles")
	var order: Array = Array(_data().get("order", profiles.keys()))
	var fallback: String = str(order[-1]) if not order.is_empty() else "wide"
	for raw in order:
		var key: String = str(raw)
		if not profiles.has(key):
			continue
		var candidate: Dictionary = profiles[key]
		if candidate.has("min_aspect") and aspect < float(candidate["min_aspect"]):
			continue
		if candidate.has("max_aspect") and aspect > float(candidate["max_aspect"]):
			continue
		if candidate.has("min_width_px") and view.x < float(candidate["min_width_px"]):
			continue
		if candidate.has("min_height_px") and view.y < float(candidate["min_height_px"]):
			continue
		return key
	return fallback


## Which layout profile is answering: wide, compact or tablet.
func profile_name() -> String:
	return _profile_key


## The viewport the layout was last fitted to.
func view_size() -> Vector2:
	return _view


## The area interactive controls may use, in viewport pixels.
func safe_rect() -> Rect2:
	return _safe


## The safe area: the viewport, minus the display's own safe-area insets where
## the platform has any (a notch, rounded corners), minus the fixed inset,
## minus as much decorative edge as the CRT targets leave room for.
func _compute_safe_rect(view: Vector2) -> Rect2:
	var rect := Rect2(Vector2.ZERO, view)
	rect = _apply_display_safe_area(rect, view)
	var inset: float = float(constraints().get("safe_inset_px", 16))
	rect = rect.grow(-inset)
	var edge: float = decorative_edge_px(rect)
	if edge > 0.0:
		rect = rect.grow(-edge)
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		rect = Rect2(Vector2.ZERO, view)
	return rect


## Display safe-area insets only mean something on a handset or tablet; on a
## desktop the "safe area" is the whole screen and the window is not it.
func _apply_display_safe_area(rect: Rect2, view: Vector2) -> Rect2:
	if not (OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")):
		return rect
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var window := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0 or safe.size.x <= 0.0 or window.x <= 0.0 or window.y <= 0.0:
		return rect
	var scale: Vector2 = view / window
	var left: float = maxf(0.0, safe.position.x) * scale.x
	var top: float = maxf(0.0, safe.position.y) * scale.y
	var right: float = maxf(0.0, screen.x - safe.end.x) * scale.x
	var bottom: float = maxf(0.0, screen.y - safe.end.y) * scale.y
	return rect.grow_individual(-left, -top, -right, -bottom)


## How much of the window edge may be left to the chassis art on this profile.
## Decorative edges crop before interactive regions shrink: the edge is the
## largest inset (up to the profile's `decorative_edge_max` of the short side)
## at which the CRT still clears its minimum width and height ratios.
func decorative_edge_px(inner: Rect2) -> float:
	var max_fraction: float = float(_profile.get("decorative_edge_max", 0.0))
	if max_fraction <= 0.0 or _view.x <= 0.0:
		return 0.0
	var limit: float = max_fraction * minf(_view.x, _view.y)
	var crt: Rect2 = region_fraction("crt")
	if crt.size.x <= 0.0:
		return 0.0
	# The edge only gets what the CRT can spare with a little in hand: it must
	# still clear its minimum ratios by `decorative_edge_slack_ratio`, so the
	# screen never sits right on the acceptance line for the sake of trim.
	var slack: float = float(constraints().get("decorative_edge_slack_ratio", 0.0))
	var min_w: float = (float(constraints().get("minimum_crt_width_ratio", 0.65)) + slack) * _view.x
	var min_h: float = (float(constraints().get("minimum_crt_height_ratio", 0.50)) + slack) * _view.y
	var steps: int = 8
	for step in range(steps, -1, -1):
		var edge: float = limit * float(step) / float(steps)
		var candidate: Rect2 = inner.grow(-edge)
		var region := Rect2(candidate.position + crt.position * candidate.size, crt.size * candidate.size)
		var lip: Array = frame_lip_px("crt_bezel", region.size)
		var screen_w: float = region.size.x - float(lip[0]) - float(lip[2])
		var screen_h: float = region.size.y - float(lip[1]) - float(lip[3])
		if screen_w >= min_w and screen_h >= min_h:
			return edge
	return 0.0


func decorative_edge_max() -> float:
	return float(_profile.get("decorative_edge_max", 0.0))


# --- Regions -------------------------------------------------------------------

## A region as a fraction of the safe area; empty when the profile has none.
func region_fraction(key: String) -> Rect2:
	if not _profile.has(key):
		return Rect2()
	var raw: Variant = _profile[key]
	if not raw is Array or Array(raw).size() < 4:
		return Rect2()
	var numbers: Array = raw
	return Rect2(float(numbers[0]), float(numbers[1]), float(numbers[2]), float(numbers[3]))


## A region in viewport pixels against the last fit.
func region_rect(key: String) -> Rect2:
	var fraction: Rect2 = region_fraction(key)
	if fraction.size.x <= 0.0:
		return Rect2()
	return Rect2(_safe.position + fraction.position * _safe.size, fraction.size * _safe.size)


## A region in pixels relative to the safe area's own origin, for children of
## the SafeArea control.
func region_rect_local(key: String) -> Rect2:
	var fraction: Rect2 = region_fraction(key)
	if fraction.size.x <= 0.0:
		return Rect2()
	return Rect2(fraction.position * _safe.size, fraction.size * _safe.size)


func dock_columns() -> int:
	return maxi(1, int(_profile.get("dock_columns", 10)))


func dock_rows() -> int:
	return maxi(1, int(_profile.get("dock_rows", 1)))


## Whether the telemetry rail stacks its instruments vertically (a side rail)
## or lays them in a strip (tablet, under the CRT).
func telemetry_vertical() -> bool:
	return str(_profile.get("telemetry_orientation", "vertical")) != "horizontal"


## The profile's type scale against the 1280x720 baseline.
func type_scale() -> float:
	return float(_profile.get("type_scale", 1.0))


func constraints() -> Dictionary:
	return _section("constraints")


## The smallest a touch target may be on this viewport, in pixels.
func min_touch_px() -> float:
	var table: Dictionary = constraints()
	var floor_px: float = float(table.get("minimum_touch_px", 48))
	if _view.x <= 854.0 and _view.y <= 480.0:
		floor_px = float(table.get("minimum_touch_px_at_854x480", 44))
	return floor_px


## Tuning tables for the parts that lay themselves out: the dock grid, the
## deck, the lever.
func dock_tuning() -> Dictionary:
	return _section("dock")


func deck_tuning() -> Dictionary:
	return _section("deck")


func lever_tuning() -> Dictionary:
	return _section("lever")


# --- Maintenance camera -------------------------------------------------------

## The maintenance block for the current profile: the shared table with the
## profile's own overrides laid over it. Keys: `zoom_scale`, `zoom_pivot`,
## `duration_s`, `wall_alpha`, `menu`, `caption`, `inspect`, `mount_<system>`.
func maintenance_tuning() -> Dictionary:
	var shared: Dictionary = _section("maintenance").duplicate()
	var overrides: Variant = shared.get("profiles")
	shared.erase("profiles")
	shared.erase("_doc")
	if overrides is Dictionary and Dictionary(overrides).has(_profile_key):
		var own: Variant = Dictionary(overrides)[_profile_key]
		if own is Dictionary:
			for key in Dictionary(own):
				shared[key] = Dictionary(own)[key]
	return shared


## A maintenance rect (`menu`, `caption`, `inspect`, `mount_compute`...) as a
## fraction of the safe area; empty when the block has none.
func maintenance_fraction(key: String) -> Rect2:
	var raw: Variant = maintenance_tuning().get(key)
	if not raw is Array or Array(raw).size() < 4:
		return Rect2()
	var numbers: Array = raw
	return Rect2(float(numbers[0]), float(numbers[1]), float(numbers[2]), float(numbers[3]))


## The same rect in pixels relative to the safe area's origin.
func maintenance_rect_local(key: String) -> Rect2:
	var fraction: Rect2 = maintenance_fraction(key)
	if fraction.size.x <= 0.0:
		return Rect2()
	return Rect2(fraction.position * _safe.size, fraction.size * _safe.size)


# --- Frames ------------------------------------------------------------------

## How a `cabinet_v2` 9-slice frame is fitted to a region of `region_size`:
## `{texture, margins: [l,t,r,b], scale, lip: [l,t,r,b]}` where `margins` are the
## texture's patch margins, `scale` is the uniform scale the NinePatchRect is
## drawn at so its rim lands at the wanted thickness, and `lip` is the rim's
## on-screen thickness per side (content stays clear of it). Empty when the
## kit has no such frame.
func frame_spec(key: String, region_size: Vector2) -> Dictionary:
	var frame: Dictionary = AssetCatalog.cabinet_v2_frame(key)
	if frame.is_empty():
		return {}
	var tuning: Dictionary = Dictionary(_section("frames").get(key, {}))
	var lip_px: Array = Array(tuning.get("lip", [0, 0, 0, 0]))
	while lip_px.size() < 4:
		lip_px.append(lip_px[-1] if not lip_px.is_empty() else 0)
	var lip_top: float = maxf(1.0, float(lip_px[1]))
	var wanted: float = clampf(
		region_size.y * float(tuning.get("lip_of_height", 0.04)),
		float(tuning.get("min_px", 2)),
		float(tuning.get("max_px", 24))
	)
	var scale: float = wanted / lip_top
	var lip: Array = [
		float(lip_px[0]) * scale, float(lip_px[1]) * scale,
		float(lip_px[2]) * scale, float(lip_px[3]) * scale,
	]
	return {
		"texture": frame["texture"],
		"margins": frame["margins"],
		"scale": scale,
		"lip": lip,
	}


## The on-screen rim thickness of a frame for a region of this size, per side.
func frame_lip_px(key: String, region_size: Vector2) -> Array:
	var spec: Dictionary = frame_spec(key, region_size)
	if spec.is_empty():
		return [0.0, 0.0, 0.0, 0.0]
	return Array(spec["lip"])


## The rect left inside a frame's rim, relative to the region's own origin.
func frame_content_rect(key: String, region_size: Vector2) -> Rect2:
	var lip: Array = frame_lip_px(key, region_size)
	var rect := Rect2(
		Vector2(float(lip[0]), float(lip[1])),
		Vector2(region_size.x - float(lip[0]) - float(lip[2]), region_size.y - float(lip[1]) - float(lip[3]))
	)
	if rect.size.x < 1.0 or rect.size.y < 1.0:
		return Rect2(Vector2.ZERO, region_size)
	return rect
