extends Control

const CARD_SCENE := preload("res://ui/common/card.tscn")
const DETAIL_SHEET := preload("res://ui/common/detail_sheet.tscn")
const RiskQuips := preload("res://ui/common/risk_quips.gd")

@onready var header: ScreenHeader = $Margin/VBox/Header
@onready var ascend_button: GameButton = $Margin/VBox/AscendButton
@onready var risk_bar: ResourceBar = $Margin/VBox/RiskBar
@onready var risk_label: Label = $Margin/VBox/RiskLabel
@onready var offers_list: VBoxContainer = $Margin/VBox/Scroll/OffersList
@onready var empty_label: Label = $Margin/VBox/EmptyLabel

var _detail_sheet: DetailSheet = null


func _ready() -> void:
	add_to_group("ui_refresh")
	header.setup("Job Board")
	header.action_pressed.connect(_on_edit_ad_spend)
	ascend_button.pressed.connect(_on_ascend_pressed)
	_detail_sheet = DETAIL_SHEET.instantiate()
	add_child(_detail_sheet)
	EventBus.run_started.connect(refresh)
	EventBus.round_started.connect(refresh)
	EventBus.job_accepted.connect(func(_id): refresh())
	Simulation.work_session_finished.connect(func(_result): refresh())
	refresh()


func refresh() -> void:
	if Simulation.phase == Simulation.Phase.ROUND_PREP:
		Simulation.ensure_job_offers()
	var state := Simulation.run_state
	header.set_context("Demand %d" % int(state.business.get("demand", 0.0)))
	header.set_sub_line(
		"Ad Spend: %s/day · %s" % [
			NumberFormat.format_cash(float(state.business.get("advertising", 0.0))),
			_reputation_line(),
		],
		"EDIT"
	)
	for child in offers_list.get_children():
		child.queue_free()

	var offers: Array = state.business.get("job_offers", [])
	var queued: Array = state.business.get("job_queue", [])
	_refresh_risk(queued)
	var in_upgrade: bool = Simulation.phase == Simulation.Phase.ANGEL_ROUND
	empty_label.visible = true
	if in_upgrade:
		empty_label.text = "Choose your upgrade first — new contracts appear after."
	elif queued.size() > 0:
		empty_label.text = "%d contract(s) taken for this round. Take more, or open WORK and press START WORK — the round runs until they all resolve." % queued.size()
	elif offers.is_empty() and Simulation.is_work_running():
		empty_label.text = "The round is under way. Open the WORK tab."
	elif offers.is_empty():
		empty_label.text = "No contracts available. Finish this round or increase demand."
	else:
		empty_label.visible = false

	_refresh_ascend_button()
	var round_costs: float = _round_costs()
	for offer in offers:
		offers_list.add_child(_build_offer_card(offer, queued, in_upgrade, round_costs))

	for job in queued:
		var card: GameCard = CARD_SCENE.instantiate()
		var identity: Dictionary = JobPresentation.sector(job)
		card.setup(str(job.get("name", "Job")), "", "", "", identity["icon"])
		card.set_accent(identity["color"])
		card.set_kicker("Taken · %s" % identity["client"], identity["color"])
		card.set_headline(NumberFormat.format_cash(float(job.get("reward", 0.0))), "money")
		card.set_chips([{"text": "On this round's slate", "role": "success", "filled": true}])
		offers_list.add_child(card)
	UiTransition.stagger(offers_list)


## The card face carries four things only: who it is for, what it pays, how long
## it runs, and the one rule that will surprise the player. The rest is a tap
## away in the detail sheet.
func _build_offer_card(offer: Dictionary, queued: Array, in_upgrade: bool, round_costs: float) -> GameCard:
	var card: GameCard = CARD_SCENE.instantiate()
	var identity: Dictionary = JobPresentation.sector(offer)
	var rules: Array = JobPresentation.rules(offer)
	var can_accept: bool = Simulation.phase == Simulation.Phase.ROUND_PREP and not Simulation.is_work_running()
	var at_capacity: bool = can_accept and not Simulation.can_accept_offer(str(offer.get("id", "")))
	if at_capacity:
		can_accept = false
	var action_label: String = "UPGRADE FIRST" if in_upgrade else ("ACCEPT CONTRACT" if can_accept else ("AT CAPACITY" if at_capacity else "BUSY"))

	card.setup(str(offer.get("name", "Job")), "", "", action_label, identity["icon"])
	card.set_accent(identity["color"])
	card.set_kicker("%s · %s" % [identity["label"], identity["client"]], identity["color"])
	card.set_headline(NumberFormat.format_cash(float(offer.get("reward", 0.0))), "money")
	card.set_chips(_offer_chips(offer, rules))
	card.set_ratings([
		{"label": "Pay", "filled": JobPresentation.pay_rating(offer, round_costs), "role": "money"},
		{"label": "Risk", "filled": JobPresentation.risk_rating(offer), "role": "danger"},
		{"label": "Tokens", "filled": JobPresentation.token_rating(offer), "role": "compute"},
	])
	card.set_warnings(_capacity_warnings(offer, queued))
	card.set_disabled(not can_accept)
	if can_accept:
		card.set_action_style("ship_it", "action")
	else:
		card.set_action_style("warning", "neutral", "SecondaryButton")
	card.body_pressed.connect(_show_offer_detail.bind(offer, can_accept, round_costs))
	if can_accept:
		card.pressed.connect(_accept_job.bind(str(offer.get("id", "")), card))
	return card


func _offer_chips(offer: Dictionary, rules: Array) -> Array:
	var chips: Array = []
	if "urgent" in offer.get("tags", []):
		chips.append({"text": "Urgent", "role": "danger", "filled": true})
	chips.append({
		"text": "%d prompts" % int(offer.get("deadline_prompts", 0)),
		"role": "warning",
		"icon": AssetCatalog.stat_icon("deadline"),
	})
	chips.append({
		"text": "Quality %d" % int(offer.get("quality_threshold", 0.0)),
		"role": "energy",
		"icon": AssetCatalog.stat_icon("quality"),
	})
	# What the contract wants from the workflow it is given. Loud on purpose:
	# choosing or building the right pipeline for it is the decision the offer
	# is really asking the player to make.
	for demand in JobPresentation.demands(offer):
		chips.append({"text": str(demand["rule"]), "role": "danger", "filled": true})
	if not rules.is_empty():
		chips.append({"text": str(rules[0]["rule"]), "role": "perk", "filled": true})
	return chips


func _show_offer_detail(offer: Dictionary, can_accept: bool, round_costs: float) -> void:
	var identity: Dictionary = JobPresentation.sector(offer)
	var rows: Array = [
		{"stat": "Reward", "value": NumberFormat.format_cash(float(offer.get("reward", 0.0))), "role": "money"},
		{"stat": "Tokens", "value": NumberFormat.format(float(offer.get("token_requirement", 0.0))), "role": "compute"},
		{"stat": "Quality target", "value": str(int(offer.get("quality_threshold", 0.0))), "role": "energy"},
		{"stat": "Deadline", "value": "%d prompts" % int(offer.get("deadline_prompts", 0)), "role": "warning"},
		{"stat": "Pays for", "value": "%.1f rounds of bills" % (float(offer.get("reward", 0.0)) / maxf(1.0, round_costs))},
		{"text": "Deliver with prompts to spare and the client pays a premium on top of the fee."},
	]
	if str(offer.get("description", "")) != "":
		rows.append({"text": str(offer.get("description", ""))})
	var demands: Array = JobPresentation.demands(offer)
	if not demands.is_empty():
		rows.append({"text": "This contract expects certain things from the workflow you put it through. Ignore them and it will cost you."})
		rows.append_array(demands)
	rows.append_array(JobPresentation.rules(offer))
	_detail_sheet.show_detail(
		str(offer.get("name", "Job")),
		"%s contract · %s" % [str(identity["label"]), str(identity["client"])],
		rows,
		[{"text": str(identity["label"]), "accent": identity["color"]}],
		"ACCEPT CONTRACT" if can_accept else "",
		identity["color"]
	)
	for connection in _detail_sheet.action_confirmed.get_connections():
		_detail_sheet.action_confirmed.disconnect(connection["callable"])
	if can_accept:
		_detail_sheet.action_confirmed.connect(_accept_job.bind(str(offer.get("id", "")), null))


## Reputation on the job board, said in terms of what it is for: the fee it adds
## to every offer, and the client tier the next few points would open.
func _reputation_line() -> String:
	var state := Simulation.run_state
	var reputation: float = float(state.business.get("reputation", 0.0))
	if reputation <= -3.0:
		return "Reputation %d — below -5 the run is over" % int(reputation)
	var bonus: float = JobSystem.reputation_reward_multiplier(state, ContentDatabase) - 1.0
	var line: String = "Reputation %d" % int(reputation)
	if bonus > 0.005:
		line += " (+%d%% fees)" % int(round(bonus * 100.0))
	var next_tier: Dictionary = JobSystem.next_reputation_tier(state, ContentDatabase)
	if not next_tier.is_empty():
		line += " · %d opens tier %d clients" % [
			int(ceil(float(next_tier["reputation"]))), int(next_tier["tier"]),
		]
	return line


## What a round costs to run, which is what a fee is worth measuring against.
func _round_costs() -> float:
	var costs: Dictionary = Simulation.cost_forecast()
	return maxf(1.0, float(costs.get("fixed_due", 0.0)))


func _refresh_risk(queued: Array) -> void:
	var info: Dictionary = Simulation.queue_load_info()
	var deadline: int = int(info.get("deadline_prompts", 0))
	if queued.is_empty() or deadline <= 0:
		risk_bar.visible = false
		risk_label.visible = false
		return
	var ratio: float = float(info.get("ratio", 0.0))
	var prompts_needed: float = float(info.get("prompts_needed", 0.0))
	risk_bar.visible = true
	risk_bar.setup(
		"Round load · %s" % RiskQuips.severity(ratio),
		minf(prompts_needed, float(deadline)),
		float(deadline),
		"",
		"%.1f of %d prompts needed" % [prompts_needed, deadline]
	)
	risk_bar.set_fill_color(UiThemeBuilder.color(RiskQuips.color_key(ratio)))
	var warning: String = RiskQuips.warning(ratio, int(info.get("jobs", 0)))
	risk_label.text = warning
	risk_label.visible = warning != ""


## Warns when taking this contract on top of the queue would outrun throughput.
func _capacity_warnings(offer: Dictionary, queued: Array) -> Array:
	if queued.is_empty():
		return []
	var info: Dictionary = Simulation.queue_load_info(offer)
	var ratio: float = float(info.get("ratio", 0.0))
	if ratio <= 1.0:
		return []
	if ratio > float(info.get("cap", 2.0)):
		return [{"text": "Queue full", "role": "danger"}]
	return [{"text": "Queue at %.0f%% capacity" % (ratio * 100.0), "role": "warning"}]


## Always on the board, because the endgame cannot be something the player only
## discovers by accidentally qualifying for it. Before the bars are cleared it
## is a progress readout; after, it is the way in. Once a contract is underway,
## the burn board's own tracker takes over.
func _refresh_ascend_button() -> void:
	ascend_button.visible = true
	var summary: Dictionary = Simulation.ascension_summary()
	var boss: String = str(Dictionary(summary.get("contract", {})).get("name", "Ascension Contract"))
	if Simulation.ascension_active():
		ascend_button.set_lines("ASCENSION UNDERWAY", "%s · follow it on the burn board" % boss)
		ascend_button.disabled = true
		return
	ascend_button.disabled = false
	if Simulation.in_overtime():
		ascend_button.set_lines(boss.to_upper(), "OVERTIME — the run only ends when this is done")
		return
	var qualification: Dictionary = Dictionary(summary.get("qualification", {}))
	if bool(summary.get("qualified", false)):
		ascend_button.set_lines(boss.to_upper(), "ASCENSION READY — commit when you are")
		return
	ascend_button.set_lines(
		boss.to_upper(),
		"%d/%d requirements · %s · %d round(s) left in the year" % [
			int(summary.get("requirements_met", 0)),
			int(summary.get("requirements_total", 0)),
			_qualification_summary(qualification),
			Simulation.rounds_remaining(),
		]
	)


## The one bar furthest from being met, so the sub-line is a next step rather
## than a list. The full checklist is in the overlay behind the button.
func _qualification_summary(qualification: Dictionary) -> String:
	if not bool(qualification.get("round_ok", true)):
		return "Opens in round %d" % int(qualification.get("earliest_round", 1))
	if not bool(qualification.get("peak_ok", true)):
		return "Needs %s peak throughput" % NumberFormat.format_token_rate(
			float(qualification.get("min_peak_token_rate", 0.0))
		)
	if not bool(qualification.get("income_ok", true)):
		return "Needs income to cover the round's costs"
	return "Not qualified yet"


func _on_ascend_pressed() -> void:
	get_tree().call_group("main_ui", "open_ascension_select")


func _on_edit_ad_spend() -> void:
	# Ad spend comes from advertising upgrades; take the player there.
	get_tree().call_group("main_ui", "switch_tab", "market")


func _accept_job(job_id: String, card: GameCard) -> void:
	# The card compresses under the finger before the screen changes, so the
	# contract visibly leaves the board rather than the list just redrawing.
	UiSound.play("accept")
	if card != null:
		card.play_press_feedback()
		await get_tree().create_timer(0.12).timeout
	if Simulation.accept_job(job_id):
		get_tree().call_group("main_ui", "switch_tab", "work")
		get_tree().call_group("ui_refresh", "refresh")
		get_tree().call_group("main_ui", "refresh_all")
