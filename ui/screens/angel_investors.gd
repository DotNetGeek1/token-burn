extends PhoneOverlay

## The investor's perk draft. When a target is met he puts three (or,
## with a Rolodex, four or five) perks on the table and expects to be thanked
## for one of them — or for the honesty of walking away. Whatever is taken is
## permanent: there is no bench and no swap, so a pick is for the rest of the
## run. Modules are sold on the Market; nothing here has a price, and the table
## cannot be rerolled.
##
## The verdict screen raises this once the target is met, and the company
## cannot move on until the table is answered. The same overlay also serves a
## save written with the old round-end angel table still open.
##
## There is only one man doing the offering, so the table is his: the cards carry
## his patter rather than a different fictional fund on each one. On a landscape
## panel the offers sit side by side as columns rather than stacked.
##
## The shell around them is his handset — the same phone the call comes in on —
## with the standing (perks held, what is in the bank, what is due) as a row of
## chips under his name. The offers themselves are something handed to you
## across a table, a physical object, so those stay as cards.

const CARD_SCENE := preload("res://ui/common/card.tscn")
## Three cards side by side plus the gaps between them. Wider than a handset of
## printed lines would ever want, but the offers are the content here.
const TABLE_WIDTH := 1040.0
## Narrower than this and a card is a column of two words per line, so the
## table stacks instead. Low enough that a handset canvas (~620 of body) still
## seats two offers side by side, because there the height is what runs out.
const CARD_MIN_WIDTH := 280.0
const CARD_SEPARATION := 12
const CHIP_SEPARATION := 6

var _standing: HFlowContainer = null
var _cards_list: GridContainer = null
var _sheet: DecisionSheet = null


func _ready() -> void:
	super._ready()
	setup(InvestorVoice.investor_name())
	_apply_title()
	# The pitch restates the kicker; on a handset the offers need that height.
	compact_hides_context = true
	# Free or not, which one he is handing over is a decision, and a stray tap
	# on the room behind should not answer it.
	dismiss_on_scrim = false
	set_closable(false)
	max_width = TABLE_WIDTH
	_build_body()
	_sheet = DecisionSheet.new()
	add_child(_sheet)
	Simulation.work_session_finished.connect(_maybe_show)
	EventBus.reward_calculated.connect(_maybe_show)


func _build_body() -> void:
	var column: VBoxContainer = content()

	_standing = HFlowContainer.new()
	_standing.add_theme_constant_override("h_separation", CHIP_SEPARATION)
	_standing.add_theme_constant_override("v_separation", CHIP_SEPARATION)
	_standing.alignment = FlowContainer.ALIGNMENT_CENTER
	_standing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_standing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_standing)

	column.add_child(PhoneRows.rule())

	_cards_list = GridContainer.new()
	_cards_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_list.columns = 1
	_cards_list.add_theme_constant_override("h_separation", CARD_SEPARATION)
	_cards_list.add_theme_constant_override("v_separation", CARD_SEPARATION)
	column.add_child(_cards_list)
	# The body is as wide as the phone lets it be, and that decides how many
	# offers sit in a row.
	column.resized.connect(_fit_columns)


## Only the legacy round-end table opens itself; the investor's draft is raised
## by the verdict screen so the win is read before the reward.
func _maybe_show(_payload: Variant = null) -> void:
	if Simulation.phase == Simulation.Phase.ANGEL_ROUND and Simulation.pending_choices.size() > 0:
		show_choices()


## Titles the handset for whichever table is open.
func _apply_title() -> void:
	if Simulation.draft_kind() == Simulation.DRAFT_INVESTOR:
		set_kicker("THE INVESTOR'S TERMS")
		set_context("Goal met. Pick one perk: it is yours for the rest of the run.")
	else:
		set_kicker("HIS TABLE")
		set_context("Pick one perk. Nothing here has a price.")


func show_choices() -> void:
	if Simulation.pending_choices.is_empty():
		hide_overlay()
		return
	if visible:
		refresh()
		return
	open()


## `PhoneOverlay.open` calls this, and so does every redraw while the table is
## up — taking one offer off it leaves the rest standing.
func refresh() -> void:
	if _cards_list == null:
		return
	setup(InvestorVoice.investor_name())
	_apply_title()
	_refresh_standing()
	_deal_cards()
	set_actions([{
		"headline": "TAKE NOTHING",
		"secondary": true,
		"pressed": _on_decline,
	}])


## Offers read as columns when the table is wide enough to lay them out that
## way and as a list when it is not, rather than three cards being squeezed
## into a handset until each one is a word wide.
func _fit_columns() -> void:
	if _cards_list == null:
		return
	var available: float = content().size.x
	if available <= 1.0:
		return
	_cards_list.columns = _column_count(available, Simulation.pending_choices.size())
	var stretch_row: bool = _cards_list.columns > 1
	_cards_list.size_flags_vertical = (
		Control.SIZE_EXPAND_FILL if stretch_row else Control.SIZE_FILL
	)
	for card in _cards_list.get_children():
		if card is Control:
			card.size_flags_vertical = (
				Control.SIZE_EXPAND_FILL if stretch_row else Control.SIZE_FILL
			)


func _column_count(available: float, choice_count: int) -> int:
	var fits: int = maxi(1, int(available / CARD_MIN_WIDTH))
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
			"text": "Permanent perk",
			"role": "perk",
			"filled": true,
		}])
		card.set_warnings(_perk_warnings(offer_id))
		card.set_action_style("perks", "perk", "BoostButton")
		_fit_card(card)
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


## On a desktop the face is a summary and the sheet has the rest; on a handset
## the copy is small enough to print whole, and the key shrinks so it is not
## most of the card.
func _fit_card(card: GameCard) -> void:
	var compact: bool = is_compact()
	card.set_body_max_lines(0 if compact else 2)
	card.set_action_compact(compact)


func _on_compact_changed(_compact_now: bool) -> void:
	if _cards_list == null:
		return
	for card in _cards_list.get_children():
		if card is GameCard:
			_fit_card(card)


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
	for warning in _perk_warnings(offer_id):
		rows.append({"rule": str(warning.get("text", "")), "text": "", "role": "warning"})
	_sheet.show_detail(
		str(offer.get("label", "Offer")),
		"Permanent perk",
		rows,
		[],
		"TAKE IT",
		UiThemeBuilder.semantic("perk")
	)
	for connection in _sheet.action_confirmed.get_connections():
		_sheet.action_confirmed.disconnect(connection["callable"])
	_sheet.action_confirmed.connect(_accept.bind(offer_id))


## The standing, as chips: how many perks he already has you carrying, what is
## in the bank, and what the next bills come to.
func _refresh_standing() -> void:
	for child in _standing.get_children():
		_standing.remove_child(child)
		child.queue_free()
	var outlook: Dictionary = Simulation.bills_outlook()
	_standing.add_child(UiChip.create(
		"PERKS %d" % Simulation.owned_perk_ids().size(), "perk"
	))
	_standing.add_child(UiChip.create(
		"BANK %s" % NumberFormat.format_cash(float(outlook.get("cash", 0.0))), "money"
	))
	_standing.add_child(UiChip.create(
		"BILLS %s" % NumberFormat.format_cash(float(outlook.get("due", 0.0))), "warning"
	))


func _accept(offer_id: String) -> void:
	if not Simulation.accept_offer("perk", offer_id):
		UiSound.play("error")
		refresh()
		return
	if not Simulation.pending_choices.is_empty():
		refresh()
	else:
		hide_overlay()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")


## What the player should know before committing: the pick cannot be undone,
## and — should the table have gone stale under them — why it cannot be taken.
func _perk_warnings(offer_id: String) -> Array:
	var warnings: Array = [{"text": "Permanent · cannot be removed", "role": "warning"}]
	var reason: String = Simulation.perk_acquire_block_reason(offer_id)
	if reason != "":
		warnings.append({"text": reason, "role": "warning"})
	return warnings


func _on_decline() -> void:
	Simulation.decline_offers()
	hide_overlay()
	get_tree().call_group("ui_refresh", "refresh")
	get_tree().call_group("main_ui", "refresh_all")
