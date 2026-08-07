extends Control

## The round's free draft. Usually that is the angel phase, once the bills have
## cleared: somebody with more money than judgement offers the player something
## for nothing. The same screen also presents an Ascension Reward — the payout for
## climbing a rung of the ladder — which is wider, rarer, and worth as many picks
## as the contract promised rather than closing on the first one. Everything here
## is free either way; the Market tab is where things have prices.

const CARD_SCENE := preload("res://ui/common/card.tscn")
const DETAIL_SHEET := preload("res://ui/common/detail_sheet.tscn")

@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var subtitle_label: Label = $Panel/Margin/VBox/Subtitle
@onready var cards_list: VBoxContainer = $Panel/Margin/VBox/Scroll/CardsList
@onready var board_label: Label = $Panel/Margin/VBox/BoardLabel
@onready var bills_label: Label = $Panel/Margin/VBox/BillsLabel
@onready var decline_button: GameButton = $Panel/Margin/VBox/DeclineButton

var _detail_sheet: DetailSheet = null


func _ready() -> void:
	decline_button.pressed.connect(_on_decline)
	_detail_sheet = DETAIL_SHEET.instantiate()
	add_child(_detail_sheet)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("flow_overlay")
	Simulation.work_session_finished.connect(_maybe_show)
	EventBus.reward_calculated.connect(_maybe_show)


func _maybe_show(_payload: Variant = null) -> void:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND and Simulation.pending_choices.size() > 0:
		show_choices()


func show_choices() -> void:
	for child in cards_list.get_children():
		child.queue_free()
	_refresh_heading()
	_refresh_board_line()
	_refresh_bills_line()
	for offer in Simulation.pending_choices:
		var card: GameCard = CARD_SCENE.instantiate()
		var investor: Dictionary = offer.get("investor", {})
		var offer_type: String = str(offer.get("type", ""))
		var offer_id: String = str(offer.get("id", ""))
		card.setup(
			str(offer.get("label", "Offer")),
			_body_text(offer, investor),
			"",
			"TAKE IT",
			_offer_icon(offer_type, offer_id)
		)
		card.set_headline("FREE", "success")
		if not investor.is_empty():
			card.set_kicker(
				"%s · %s" % [str(investor.get("name", "")), str(investor.get("fund", ""))],
				UiThemeBuilder.semantic("perk")
			)
		card.set_chips([{
			"text": _kind_chip_text(offer_type),
			"role": "perk",
			"filled": true,
		}])
		if offer_type == "operation":
			card.set_warnings(_bench_warning())
		card.set_action_style("perks", "perk", "BoostButton")
		card.pressed.connect(_accept.bind(offer_type, offer_id))
		# Taking a module or perk is a decision, so only TAKE IT commits to it.
		# A tap on the card face reads the pitch in full instead.
		card.body_pressed.connect(_show_offer_detail.bind(offer, investor))
		cards_list.add_child(card)
	if Simulation.pending_choices.is_empty():
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		UiTransition.enter(self)
		UiTransition.stagger(cards_list)
		mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().call_group("main_ui", "sync_overlay_input")


## The two drafts read differently because they mean differently: an angel is
## handing out a favour, an Ascension Reward is being paid what a rung of the
## ladder promised. The pick counter only exists on the second, where taking one
## thing does not close the table.
func _refresh_heading() -> void:
	if not Simulation.draft_is_ascension_reward():
		title_label.text = "THE ANGEL ROUND"
		subtitle_label.text = "Nobody wants equity. Everybody wants to be in the story."
		decline_button.set_lines("TAKE NOTHING", "Thank everyone and leave")
		return
	var ladder: Dictionary = Simulation.ascension_ladder()
	var picks: int = Simulation.draft_picks_remaining()
	title_label.text = "ASCENSION REWARD"
	subtitle_label.text = (
		"Rung %d of %d is behind you. This is what it pays, and it pays into this run."
		% [int(ladder.get("highest_tier_completed", 1)), int(ladder.get("total", 3))]
	)
	decline_button.set_lines(
		"TAKE NOTHING",
		"Forfeits %d pick(s)" % picks if picks > 1 else "Forfeits the pick"
	)


func _kind_chip_text(offer_type: String) -> String:
	var noun: String = "module" if offer_type == "operation" else "perk"
	if not Simulation.draft_is_ascension_reward():
		return "Free %s" % noun
	return "%d pick(s) left · %s" % [Simulation.draft_picks_remaining(), noun.capitalize()]


func _show_offer_detail(offer: Dictionary, investor: Dictionary) -> void:
	var offer_type: String = str(offer.get("type", ""))
	var offer_id: String = str(offer.get("id", ""))
	var rows: Array = [
		{"stat": "Cost", "value": "Free", "role": "success"},
		{"text": str(offer.get("description", ""))},
	]
	if not investor.is_empty():
		rows.append({
			"rule": str(investor.get("name", "")),
			"text": "\"%s\"" % str(investor.get("patter", "")),
			"role": "perk",
		})
	for warning in _bench_warning():
		rows.append({"rule": str(warning.get("text", "")), "text": "", "role": "warning"})
	_detail_sheet.show_detail(
		str(offer.get("label", "Offer")),
		"Free module" if offer_type == "operation" else "Free perk",
		rows,
		[],
		"TAKE IT",
		UiThemeBuilder.semantic("perk")
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	_detail_sheet.action_confirmed.connect(_accept.bind(offer_type, offer_id))


func _body_text(offer: Dictionary, investor: Dictionary) -> String:
	var description: String = str(offer.get("description", ""))
	if investor.is_empty():
		return description
	return "%s\n\n\"%s\"" % [description, str(investor.get("patter", ""))]


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
	board_label.text = "%d of %d modules in the pipeline · %d slot(s)" % [
		Simulation.filled_slot_count(), owned, Simulation.board_slots().size()
	]


## Knowing rent is due while an investor talks about conviction is the whole joke.
func _refresh_bills_line() -> void:
	var outlook: Dictionary = Simulation.bills_outlook()
	bills_label.text = "%s in the bank · %s rent and bills due when the next round ends" % [
		NumberFormat.format_cash(float(outlook.get("cash", 0.0))),
		NumberFormat.format_cash(float(outlook.get("due", 0.0))),
	]


func hide_overlay() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().call_group("main_ui", "sync_overlay_input")


func _accept(offer_type: String, offer_id: String) -> void:
	if not Simulation.accept_offer(offer_type, offer_id):
		return
	# An Ascension Reward can still owe the run picks, in which case the table
	# stays up minus what was just taken off it.
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND and not Simulation.pending_choices.is_empty():
		show_choices()
	else:
		hide_overlay()
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
