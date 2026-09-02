class_name HelpOverlay
extends ConsoleOverlay

## First-run and on-demand help. Teaches the four verbs the 1.0 loop actually
## uses: take work, build a pipeline, burn tokens, pay the bills.

const PAGES := [
	{
		"title": "TAKE WORK",
		"body": "The Jobs board is the yellow notes on the desk. Accept a contract before you burn. Deadlines are in prompts, not real time.",
	},
	{
		"title": "BUILD A PIPELINE",
		"body": "Workflows are the modules a token batch walks through. Order matters: a cache before a model is not the same as after. Build is where hardware and perks live.",
	},
	{
		"title": "BURN",
		"body": "The Burn Board is the work itself. Read the forecast — multipliers, repeats, heat — before you commit. Heat that hits the cap ends the run.",
	},
	{
		"title": "PAY THE BILLS",
		"body": "Every round closes with a debrief, then rent and running costs. Miss twice in a row and you are evicted. Angel drafts come after the statement.",
	},
]

var _page: int = 0
var _copy: Label = null


func _ready() -> void:
	super._ready()
	setup("help")
	dismiss_on_scrim = true
	compact = false
	_copy = ConsoleStyle.paragraph("", ConsoleStyle.FONT_BODY, ConsoleStyle.PHOSPHOR)
	_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(_copy)
	set_close_label("GOT IT", "ESC")
	_show_page()


func open_help(first_run: bool = false) -> void:
	_page = 0
	set_context("FIRST RUN" if first_run else "HOW TO PLAY")
	_show_page()
	open()


func refresh() -> void:
	_show_page()


func _show_page() -> void:
	var page: Dictionary = PAGES[_page]
	set_context(str(page.get("title", "HOW TO PLAY")))
	if _copy != null:
		_copy.text = str(page.get("body", ""))
	var actions: Array = []
	if _page > 0:
		actions.append({
			"index": "1",
			"headline": "BACK",
			"pressed": _prev_page,
		})
	if _page < PAGES.size() - 1:
		actions.append({
			"index": "2",
			"headline": "NEXT",
			"pressed": _next_page,
		})
	set_actions(actions)
	set_close_label("GOT IT" if _page == PAGES.size() - 1 else "SKIP", "ESC")


func _next_page() -> void:
	_page = mini(_page + 1, PAGES.size() - 1)
	_show_page()


func _prev_page() -> void:
	_page = maxi(_page - 1, 0)
	_show_page()


func hide_overlay() -> void:
	MetaProgress.mark_onboarding_seen()
	super.hide_overlay()
