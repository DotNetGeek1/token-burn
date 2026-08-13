extends ConsoleOverlay

## The round's free draft. Usually that is the angel phase, once the bills have
## cleared: the investor puts a few things on the table and expects to be thanked
## for them. The same screen also presents a contract reward — the payout for
## finishing a location — which is worth as many picks as the contract promised
## rather than closing on the first one. Everything here is free either way; the
## Market tab is where things have prices.
##
## There is only one man doing the offering, so the table is his: the cards carry
## his patter rather than a different fictional fund on each one. On a landscape
## panel the offers sit side by side as columns rather than stacked.
##
## The shell around them is the console, because the standing — what is in the
## pipeline, what is in the bank, what is due — is the machine's reckoning and
## reads like it. The offers themselves are not: something handed to you across
## a table is a physical object, so those stay as cards, the same way the run's
## parting gift does on the debrief.

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
	_refresh_heading()
	_refresh_board_line()
	_refresh_bills_line()
	_deal_cards()
	var actions: Array = [{
		"index": "1",
		"headline": "TAKE NOTHING",
		"value": "Tell him you are fine",
		"pressed": _on_decline,
	}]
	if Simulation.can_reroll_angel():
		actions.append({
			"index": "2",
			"headline": "REROLL — %s" % NumberFormat.format_cash(Simulation.angel_reroll_cost()),
			"value": "Pay for a fresh table",
			"pressed": _on_reroll,
		})
	elif Simulation.phase == Simulation.Phase.ANGEL_ROUND:
		actions.append({
			"index": "2",
			"headline": "REROLL — %s" % NumberFormat.format_cash(Simulation.angel_reroll_cost()),
			"value": "Not enough cash",
			"enabled": false,
		})
	set_actions(actions)
	_apply_body_metrics()


func fit_console() -> void:
	super.fit_console()
	_apply_body_metrics()


func _apply_body_metrics() -> void:
	if _pitch == null:
		return
	var scale: float = console_scale()
	var small: int = ConsoleMetrics.font_small(scale)
	_pitch.add_theme_font_size_override("font_size", small)
	_board_label.add_theme_font_size_override("font_size", small)
	_bills_label.add_theme_font_size_override("font_size", small)
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
	var fits: int = maxi(1, int(available / (CARD_MIN_WIDTH * console_scale())))
	_cards_list.columns = clampi(
		mini(maxi(1, Simulation.pending_choices.size()), fits), 1, 3
	)


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
		var offer_type: String = str(offer.get("type", ""))
		var offer_id: String = str(offer.get("id", ""))
		card.setup(
			str(offer.get("label", "Offer")),
			_body_text(offer, patter),
			"",
			"TAKE IT",
			_offer_icon(offer_type, offer_id)
		)
		card.set_headline("FREE", "success")
		card.set_chips([{
			"text": _kind_chip_text(offer_type),
			"role": "perk",
			"filled": true,
		}])
		if offer_type == "operation":
			card.set_warnings(_bench_warning())
		elif offer_type == "perk":
			card.set_warnings(_perk_bench_warning())
		card.set_action_style("perks", "perk", "BoostButton")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_accept.bind(offer_type, offer_id))
		# Taking a module or perk is a decision, so only TAKE IT commits to it.
		# A tap on the card face reads the pitch in full instead.
		card.body_pressed.connect(_show_offer_detail.bind(offer, patter))
		_cards_list.add_child(card)
	UiTransition.stagger(_cards_list)


func _refresh_heading() -> void:
	_pitch.text = "%s is feeling generous. Take one." % InvestorVoice.investor_name()
	set_context("NOTHING HERE HAS A PRICE")


func _kind_chip_text(offer_type: String) -> String:
	return "Free %s" % ("module" if offer_type == "operation" else "perk")


func _show_offer_detail(offer: Dictionary, patter: String) -> void:
	var offer_type: String = str(offer.get("type", ""))
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
	for warning in _bench_warning():
		rows.append({"rule": str(warning.get("text", "")), "text": "", "role": "warning"})
	_sheet.show_detail(
		str(offer.get("label", "Offer")),
		"Free module" if offer_type == "operation" else "Free perk",
		rows,
		[],
		"TAKE IT",
		UiThemeBuilder.semantic("perk")
	)
	for connection in _sheet.action_confirmed.get_connections():
		_sheet.action_confirmed.disconnect(connection["callable"])
	_sheet.action_confirmed.connect(_accept.bind(offer_type, offer_id))


func _body_text(offer: Dictionary, patter: String) -> String:
	var description: String = str(offer.get("description", ""))
	if patter == "":
		return description
	return "%s\n\n\"%s\"" % [description, patter]


## A module arriving on a full board is a decision, not a gift, and the screen
## says so before the player takes it.
func _bench_warning() -> Array:
	var placed: int = Simulation.filled_slot_count()
	var slots: int = Simulation.board_slots().size()
	if placed < slots:
		return []
	return [{"text": "Pipeline full · waits on the bench", "role": "warning"}]


func _refresh_board_line() -> void:
	var owned: int = Simulation.owned_operations().size()
	# The perk count belongs next to the offers: a build is capped, so the last
	# free perk of a run should not be taken by accident.
	var perks: Dictionary = Simulation.perk_capacity()
	_board_label.text = "%d of %d modules in the pipeline · %d slot(s) · %d of %d perks" % [
		Simulation.filled_slot_count(), owned, Simulation.board_slots().size(),
		int(perks.get("owned", 0)), int(perks.get("cap", 0))
	]


## Knowing rent is due while an investor talks about conviction is the whole joke.
func _refresh_bills_line() -> void:
	var outlook: Dictionary = Simulation.bills_outlook()
	_bills_label.text = "%s in the bank · %s rent and bills due when the next round ends" % [
		NumberFormat.format_cash(float(outlook.get("cash", 0.0))),
		NumberFormat.format_cash(float(outlook.get("due", 0.0))),
	]


func _accept(offer_type: String, offer_id: String) -> void:
	if not Simulation.accept_offer(offer_type, offer_id):
		return
	# A contract reward can still owe the run picks, in which case the table
	# stays up minus what was just taken off it.
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


func _on_reroll() -> void:
	if not Simulation.reroll_angel_offers():
		return
	refresh()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _on_decline() -> void:
	Simulation.decline_offers()
	hide_overlay()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


func _offer_icon(offer_type: String, offer_id: String) -> Texture2D:
	if offer_type == "perk":
		return AssetCatalog.perk_icon(offer_id)
	var operation: OperationDefinition = ContentDatabase.get_operation(offer_id)
	return AssetCatalog.operation_icon(operation.category) if operation != null else null
