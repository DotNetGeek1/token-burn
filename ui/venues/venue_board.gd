class_name VenueBoard
extends ScrollContainer

## The grid of tiles on a venue's main board.
##
## How many tiles fit across is a question about the width the artwork gave the
## board, so it is answered on every layout pass rather than declared. Tiles are
## pooled: a board that rebuilds on every purchase, and the market does, should
## not be dropping and reallocating thirty controls to change one price.

signal tile_selected(meta: Variant)

## Narrowest a tile can be and still fit a machine's name on two lines with its
## rate beside it. Below this the board drops a column.
const MIN_TILE := 190.0
const MAX_COLUMNS := 4
const GAP := 8

const ConsoleMetrics := preload("res://ui/common/console_metrics.gd")

var _body: VBoxContainer = null
var _note: Label = null
var _grid: GridContainer = null
var _tiles: Array[VenueTile] = []
var _selected: Variant = null
var _scale: float = 1.0
var _available: float = 0.0
## Whether the board is inside somebody else's scroll, and so must report its
## full height rather than scroll within a fixed rect.
var _inline: bool = false
var _max_columns: int = MAX_COLUMNS
var _compact: bool = false


func _init() -> void:
	_build()


func _build() -> void:
	if _body != null:
		return
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", GAP)
	add_child(_body)

	_note = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR_DIM)
	_note.visible = false
	_body.add_child(_note)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_body.add_child(_grid)


## Prints `entries` onto the board, one tile each. See `VenueTile.set_entry` for
## what an entry carries. `note` is what the board says when there is nothing on
## it, or a standing caption above the grid.
func set_entries(entries: Array, note: String = "") -> void:
	_build()
	while _tiles.size() < entries.size():
		var tile := VenueTile.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.pressed.connect(_on_tile_pressed.bind(tile))
		_grid.add_child(tile)
		_tiles.append(tile)
	for index in range(_tiles.size()):
		var tile: VenueTile = _tiles[index]
		if index >= entries.size():
			tile.visible = false
			continue
		tile.visible = true
		tile.set_compact(_compact)
		tile.set_entry(Dictionary(entries[index]))
		tile.set_metrics(_scale)
		tile.set_selected(_selected != null and tile.meta == _selected)
	_note.text = note
	_note.visible = note != ""
	_sync_height()


func select(meta: Variant) -> void:
	_selected = meta
	for tile in _tiles:
		tile.set_selected(meta != null and tile.meta == meta)


func clear_selection() -> void:
	select(null)


func selected() -> Variant:
	return _selected


func _on_tile_pressed(tile: VenueTile) -> void:
	select(tile.meta)
	tile_selected.emit(tile.meta)


## `available_width` is what the venue knows the board was given, which is worth
## more than what this control can measure about itself: the panel's rect is set
## the instant the venue lays out, whereas the width reaching a scroll container
## three containers down is a frame or two behind and settles on the wrong column
## count in between.
func set_metrics(scale: float, available_width: float = 0.0) -> void:
	_build()
	_scale = scale
	if available_width > 1.0:
		_available = available_width
	var gap: int = ConsoleMetrics.px(GAP, scale)
	_body.add_theme_constant_override("separation", gap)
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	_note.add_theme_font_size_override("font_size", ConsoleMetrics.font_small(scale))
	for tile in _tiles:
		tile.set_metrics(scale)
	_fit_columns()
	_sync_height()


## Which of the venue's two layouts the board is in.
##
## On the wall it is a fixed rectangle in a photograph, so a long shelf scrolls
## inside it and the tiles run several across.
##
## In the console column it is neither. It must not scroll, because the column is
## already a scroll view and a scroll view inside a scroll view is a trap — the
## inner one swallows the drag and the player cannot get past it — so the board
## reports its full height and the column grows instead. And it drops to one tile
## per row: two fit across a handset arithmetically, but only by wrapping every
## status onto a second line, and one column is the whole point of the reflow.
func set_console(console: bool) -> void:
	set_inline(console, 1 if console else MAX_COLUMNS)


## Whether the board carries its own scrolling, and how many tiles it will run
## across at most.
##
## Split from `set_console` because the two are not always the same request. A
## venue that stacks several boards inside one scroll — the workflow editor puts
## its pipeline above its module bench — needs every one of them inline, but the
## bench still wants the full width it was given.
## A board one tile wide is a listing rather than a grid, and a listing wants rows:
## see `VenueTile.set_compact`. Followed from the column count rather than asked
## for, because the column count is the thing that decides it.
func _apply_compact(compact: bool) -> void:
	if _compact == compact:
		return
	_compact = compact
	for tile in _tiles:
		tile.set_compact(compact)
	_sync_height()


func set_inline(inline: bool, max_columns: int = MAX_COLUMNS) -> void:
	_build()
	if _inline == inline and _max_columns == max_columns:
		return
	_inline = inline
	_max_columns = maxi(1, max_columns)
	vertical_scroll_mode = (
		ScrollContainer.SCROLL_MODE_DISABLED if inline else ScrollContainer.SCROLL_MODE_AUTO
	)
	_fit_columns()
	_sync_height()


func _sync_height() -> void:
	if _body == null:
		return
	# A scroll container reports almost no minimum height of its own, so the panel
	# holding it would keep the floor it was given and clip the tail of the grid.
	custom_minimum_size.y = (
		_body.get_combined_minimum_size().y if _inline else 0.0
	)


## Called once the board has a width worth measuring. A tile has a minimum it
## reads at, and that minimum grows with the type, so a handset ends up with the
## single column it needs without anything having asked for one.
func _fit_columns() -> void:
	if _grid == null:
		return
	var available: float = _available
	if available <= 1.0:
		available = size.x
	if available <= 1.0:
		available = get_parent_area_size().x
	if available <= 1.0:
		return
	var minimum: float = MIN_TILE * _scale
	var columns: int = clampi(int(available / minimum), 1, _max_columns)
	if _grid.columns != columns:
		_grid.columns = columns
	_apply_compact(columns == 1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit_columns()
