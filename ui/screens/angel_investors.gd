extends ConsoleOverlay

## The round's free perk draft. Once the bills have cleared, the investor puts
## three perks on the table and expects to be thanked for one of them — or for
## the honesty of walking away. Modules are sold on the Market; nothing here
## has a price, and the table cannot be rerolled.
##
## There is only one man doing the offering, so the table is his: the cards carry
## his patter rather than a different fictional fund on each one. On a landscape
## panel the offers sit side by side as columns rather than stacked.
##
## The shell around them is the console, because the standing — what is in the
## bank, what is due, how many perks are active — is the machine's reckoning and
## reads like it. The offers themselves are not: something handed to you across
## a table is a physical object, so those stay as cards.

const CARD_SCENE := preload("res://ui/common/card.tscn")
## Three cards side by side plus the gaps between them. Wider than an overlay
## of printed lines would ever want, but the offers are the content here.
const TABLE_WIDTH := 1040.0
## Narrower than this and a card is a column of two words per line, so the
## table stacks instead.
const CARD_MIN_WIDTH := 300.0

var _pitch: Label = null
var _board_label: Label = null
var _bills_label: Label = null
var _scroll: ScrollContainer = null
var _cards_list: GridContainer = null
var _sheet: ConsoleSheet = null


func _ready() -> void:
	super._ready()
	setup("His Table")
	# Free or not, which one he is handing over is a decision, and a stray tap
	# on the room behind should not answer it.
	dismiss_on_scrim = false
	set_closable(false)
	max_width = TABLE_WIDTH
	_build_body()
	_sheet = ConsoleSheet.new()
	add_child(_sheet)
	Simulation.work_session_finished.connect(_maybe_show)
	EventBus.reward_calculated.connect(_maybe_show)


func _build_body() -> void:
	var column: VBoxContainer = content()

	_pitch = ConsoleStyle.paragraph("", ConsoleStyle.FONT_SMALL, ConsoleStyle.PHOSPHOR)
	column.add_child(_pitch)

	_board_label = ConsoleStyle.paragraph("")
	column.add_child(_board_label)

	_bills_label = ConsoleStyle.paragraph("")
	column.add_child(_bills_label)

	column.add_child(ConsoleStyle.rule(0.22))

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.resized.connect(_fit_columns)
	column.add_child(_scroll)

	_cards_list = GridContainer.new()
	_cards_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_list.columns = 1
	_cards_list.add_theme_constant_override("h_separation", 12)
	_cards_list.add_theme_constant_override("v_separation", 12)
	_scroll.add_child(_cards_list)


func _maybe_show(_payload: Variant = null) -> void:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND and Simulation.pending_choices.size() > 0:
		show_choices()


func show_choices() -> void:
	if Simulation.pending_choices.is_empty():
		hide_overlay()
		return
	if visible:
		refresh()
		return
	open()


## `ConsoleOverlay.open` calls this, and so does every redraw while the table is
## up — taking one offer off it leaves the rest standing.
func refresh() -> void:
	if _cards_list == null:
		return
	_refresh_header_line()
	_deal_cards()
	set_actions([{
		"index": "",
		"headline": "TAKE NOTHING",
		"pressed": _on_decline,
	}], true)
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


func _apply_body_metrics() -> void:
	if _pitch == null:
		return
	var scale: float = console_scale()
	_pitch.add_theme_font_size_override("font_size", ConsoleMetrics.font_tiny(scale))
	_fit_columns()


## Offers read as columns when the table is wide enough to lay them out that
## way and as a list when it is not, rather than three cards being squeezed
## into a handset until each one is a word wide.
func _fit_columns() -> void:
	if _cards_list == null:
		return
	var available: float = _scroll.size.x
	if available <= 1.0:
		return
	_cards_list.columns = _column_count(
		available,
		Simulation.pending_choices.size(),
		console_scale()
	)
	var stretch_row: bool = _cards_list.columns > 1
	_cards_list.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if stretch_row else Control.SIZE_FILL
	)
	for card in _cards_list.get_children():
		if card is Control:
			card.size_flags_vertical = (
				Control.SIZE_EXPAND_FILL if stretch_row else Control.SIZE_FILL
			)


func _column_count(
	available: float, choice_count: int, scale: float
) -> int:
	var fits: int = maxi(1, int(available / (CARD_MIN_WIDTH * scale)))
	return clampi(mini(maxi(1, choice_count), fits), 1, 2)


func _deal_cards() -> void:
	for child in _cards_list.get_children():
		_cards_list.remove_child(child)
		child.queue_free()
	_fit_columns()
	var index: int = 0
	for offer in Simulation.pending_choices:
		var card: GameCard = CARD_SCENE.instantiate()
		var patter: String = InvestorVoice.offer_patter(index)
		index += 1
		var offer_id: String = str(offer.get("id", ""))
		card.setup(
			str(offer.get("label", "Offer")),
			str(offer.get("description", "")),
			"",
			"TAKE IT",
			AssetCatalog.perk_icon(offer_id)
		)
		card.set_headline("FREE", "success")
		card.set_chips([{
			"text": "Perk",
			"role": "perk",
			"filled": true,
		}])
		card.set_warnings(_perk_bench_warning())
		card.set_action_style("perks", "perk", "BoostButton")
		card.set_body_max_lines(2)
		card.set_action_pinned()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = (
			Control.SIZE_EXPAND_FILL if _cards_list.columns > 1 else Control.SIZE_FILL
		)
		card.pressed.connect(_accept.bind(offer_id))
		# Taking a perk is a decision, so only TAKE IT commits to it.
		# A tap on the card face reads the pitch in full instead.
		card.body_pressed.connect(_show_offer_detail.bind(offer, patter))
		_cards_list.add_child(card)
	UiTransition.stagger(_cards_list)


func _show_offer_detail(offer: Dictionary, patter: String) -> void:
	var offer_id: String = str(offer.get("id", ""))
	var rows: Array = [
		{"stat": "Cost", "value": "Free", "role": "success"},
		{"text": str(offer.get("description", ""))},
	]
	if patter != "":
		rows.append({
			"rule": InvestorVoice.investor_name(),
			"text": "\"%s\"" % patter,
			"role": "perk",
		})
	for warning in _perk_bench_warning():
		rows.append({"rule": str(warning.get("text", "")), "text": "", "role": "warning"})
	_sheet.show_detail(
		str(offer.get("label", "Offer")),
		"Free perk",
		rows,
		[],
		"TAKE IT",
		UiThemeBuilder.semantic("perk")
	)
	for connection in _sheet.action_confirmed.get_connections():
		_sheet.action_confirmed.disconnect(connection["callable"])
	_sheet.action_confirmed.connect(_accept.bind(offer_id))


func _refresh_header_line() -> void:
	var perks: Dictionary = Simulation.perk_capacity()
	var outlook: Dictionary = Simulation.bills_outlook()
	_pitch.text = "%s: PICK ONE PERK FREE  ·  PERKS %d/%d  ·  BANK %s  ·  BILLS %s" % [
		InvestorVoice.investor_name().to_upper(),
		int(perks.get("owned", 0)),
		int(perks.get("cap", 0)),
		NumberFormat.format_cash(float(outlook.get("cash", 0.0))),
		NumberFormat.format_cash(float(outlook.get("due", 0.0))),
	]
	_pitch.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pitch.clip_text = true
	_pitch.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_board_label.text = ""
	_board_label.visible = false
	_bills_label.text = ""
	_bills_label.visible = false
	set_context("NOTHING HERE HAS A PRICE")


func _accept(offer_id: String) -> void:
	if not Simulation.accept_offer("perk", offer_id):
		return
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND and not Simulation.pending_choices.is_empty():
		refresh()
	else:
		hide_overlay()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _perk_bench_warning() -> Array:
	var perks: Dictionary = Simulation.perk_capacity()
	if int(perks.get("active", 0)) < int(perks.get("cap", 0)):
		return []
	return [{"text": "Active full · goes to the bench", "role": "warning"}]


func _on_decline() -> void:
	Simulation.decline_offers()
	hide_overlay()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")
