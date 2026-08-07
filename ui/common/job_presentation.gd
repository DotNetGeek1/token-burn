class_name JobPresentation
extends RefCounted

## Turns a job offer into the handful of things a player compares at a glance:
## a sector identity (colour, icon, client type) and three difficulty ratings.
##
## The rules are where a contract's personality lives, so they are surfaced as
## named chips rather than buried in a sentence.

const SECTORS := {
	"copy": {"label": "Copy", "client": "Content Agency", "color": "blue", "icon": "quality"},
	"marketing": {"label": "Marketing", "client": "Growth Agency", "color": "orange", "icon": "reputation"},
	"ecommerce": {"label": "Ecommerce", "client": "Online Retailer", "color": "yellow", "icon": "cash"},
	"fintech": {"label": "Fintech", "client": "Payments Startup", "color": "green", "icon": "cash"},
	"banking": {"label": "Banking", "client": "Retail Bank", "color": "red", "icon": "cash"},
	"enterprise": {"label": "Enterprise", "client": "Corporate IT", "color": "purple", "icon": "agents"},
	"gaming": {"label": "Gaming", "client": "Game Studio", "color": "yellow", "icon": "agents"},
	"ai": {"label": "AI", "client": "AI Startup", "color": "blue", "icon": "agents"},
	"frontend": {"label": "Frontend", "client": "Design Studio", "color": "purple", "icon": "quality"},
	"backend": {"label": "Backend", "client": "Platform Team", "color": "blue", "icon": "power"},
	"legacy": {"label": "Legacy", "client": "Nobody Left Who Knows", "color": "orange", "icon": "heat"},
	"mvp": {"label": "Startup", "client": "Pre-Seed Founder", "color": "green", "icon": "reputation"},
	"marketplace": {"label": "Marketplace", "client": "Two-Sided Startup", "color": "green", "icon": "cash"},
	"absurd": {"label": "Absurd", "client": "Unclear Entity", "color": "purple", "icon": "agents"},
	"capstone": {"label": "Capstone", "client": "The Simulation", "color": "red", "icon": "power"},
}

const DEFAULT_SECTOR := {"label": "Contract", "client": "Freelance Client", "color": "grey", "icon": "cash"}


## Sector identity for an offer: {label, client, color (Color), icon (Texture2D)}.
static func sector(offer: Dictionary) -> Dictionary:
	var entry: Dictionary = DEFAULT_SECTOR
	for tag in offer.get("tags", []):
		var key: String = str(tag).to_lower()
		if SECTORS.has(key):
			entry = SECTORS[key]
			break
	var icon: Texture2D = AssetCatalog.stat_icon(str(entry["icon"]))
	if icon == null:
		icon = AssetCatalog.stat_icon(str(DEFAULT_SECTOR["icon"]))
	return {
		"label": str(entry["label"]),
		"client": str(entry["client"]),
		"color": UiThemeBuilder.color(str(entry["color"])),
		"icon": icon,
	}


## Pay measured against what a round costs to run, so five dots always means
## "this changes the round" rather than an arbitrary cash threshold.
static func pay_rating(offer: Dictionary, round_costs: float) -> int:
	var ratio: float = float(offer.get("reward", 0.0)) / maxf(1.0, round_costs)
	if ratio < 0.4:
		return 1
	if ratio < 0.9:
		return 2
	if ratio < 2.0:
		return 3
	if ratio < 4.0:
		return 4
	return 5


## Risk combines scope creep odds with how many special rules can bite.
static func risk_rating(offer: Dictionary) -> int:
	var score: float = float(offer.get("revision_risk", 0.1)) / 0.25 * 3.0
	score += float(offer.get("complications", []).size()) * 0.6
	score += float(offer.get("board_rules", []).size()) * 0.9
	return clampi(int(round(score)), 1, 5)


## Workload, straight off the offer's tier.
static func token_rating(offer: Dictionary) -> int:
	return clampi(int(offer.get("tier", 0)) + 1, 1, 5)


## Named board rules and complications, ready to render as chips or rule blocks.
static func rules(offer: Dictionary) -> Array:
	var out: Array = []
	for complication in offer.get("complications", []):
		if complication is Dictionary and complication.has("label"):
			out.append({"rule": str(complication["label"]), "text": ""})
	for rule in offer.get("board_rules", []):
		if rule is Dictionary and rule.has("label"):
			out.append({"rule": _rule_name(str(rule.get("type", ""))), "text": str(rule["label"])})
	return out


## What this contract wants from the workflow it is given, as chip text. Offers
## are shown before a workflow is assigned, so this is the demand itself rather
## than a verdict on any particular pipeline.
static func demands(offer: Dictionary) -> Array:
	var out: Array = []
	var definitions: Dictionary = ContentDatabase.balance.get("job_demands", {})
	for demand_id in Array(offer.get("demands", [])):
		var definition: Variant = definitions.get(str(demand_id), null)
		if not definition is Dictionary:
			continue
		out.append({
			"id": str(demand_id),
			"rule": str(definition.get("name", demand_id)),
			"text": str(definition.get("requirement", "")),
		})
	return out


## One line summarising how a workflow answers a contract, for a job card or an
## assignment button. Empty when the contract asks for nothing in particular.
static func match_summary(match_report: Dictionary) -> String:
	var total: int = int(match_report.get("total", 0))
	if total <= 0:
		return "No particular demands"
	var met: int = int(match_report.get("met", 0))
	if met >= total:
		return "Answers all %d demand(s)" % total
	var missing: Array[String] = []
	for entry in Array(match_report.get("demands", [])):
		if not bool(entry.get("met", false)):
			missing.append(str(entry.get("short", entry.get("name", "something"))))
	return "%d of %d · missing %s" % [met, total, ", ".join(missing).to_lower()]


static func _rule_name(rule_type: String) -> String:
	match rule_type:
		"blocked_slots":
			return "Blocked slots"
		"tag_bonus":
			return "Module bonus"
		"feature_creep":
			return "Feature creep"
		"agent_scope":
			return "Agent scope"
		"max_hidden_bugs":
			return "Audited on delivery"
		"recursion_risk":
			return "Recursion risk"
		_:
			return "Special rule"
