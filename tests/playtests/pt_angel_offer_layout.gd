extends PlaytestCase

## The investor table has to remain a choice screen, not three full detail
## sheets laid side by side. Card faces stay compact, actions share a baseline,
## and phones get a single scrollable column with the footer outside it.
## Perk-only: TAKE NOTHING remains; REROLL is gone.


func play(harness: UiHarness) -> void:
	await harness.boot(71)
	Simulation.debug_present_angel_offers()
	var shell: Node = harness.current_scene()
	var table: Control = shell._angel_investors
	table.show_choices()
	await harness.settle()

	await _desktop_table(harness, table)
	await _mobile_table(harness, table)

	table.hide_overlay()


func _desktop_table(harness: UiHarness, table: Control) -> void:
	await harness.set_viewport(UiHarness.VIEW_DESKTOP)
	assert_true(table.visible, "The investor table stays open during desktop reflow")
	assert_eq(table._cards_list.columns, 2, "Desktop offers give the cards two wide columns")
	assert_true(not table._board_label.visible, "All supporting copy is folded into one line")
	assert_true(
		"BILLS" in table._pitch.text,
		"The compact status line keeps the important bill warning"
	)
	assert_true("PERK" in table._pitch.text.to_upper(), "Header says the free pick is a perk")
	assert_true(table._inline_actions.visible, "Secondary actions share one footer line")
	assert_eq(table._action_rows.size(), 1, "Only TAKE NOTHING remains as a secondary action")
	assert_eq(table._action_rows[0].index_label, "", "Inline actions omit numbered prefixes")
	assert_eq(table._action_rows[0].value_text, "", "Inline actions omit explanatory descriptions")
	assert_eq(table._action_rows[0].headline, "TAKE NOTHING", "Decline remains available")

	var cards: Array[Node] = table._cards_list.get_children()
	assert_eq(cards.size(), 3, "The investor still deals three choices")
	var action_bottom: float = -1.0
	for card_index in cards.size():
		var card: Node = cards[card_index]
		var body: Label = card.get_node("Margin/VBox/BodyLabel")
		var action: Control = card.get_node("Margin/VBox/ActionButton")
		assert_eq(body.max_lines_visible, 2, "Offer copy is capped at two summary lines")
		assert_true(
			card.get_node_or_null("Margin/VBox/ActionSpacer") != null,
			"Each offer reserves flexible space above TAKE IT"
		)
		if card_index == 0:
			action_bottom = action.get_global_rect().end.y
		elif card_index == 1:
			assert_true(
				absf(action.get_global_rect().end.y - action_bottom) <= 1.0,
				"Desktop TAKE IT actions share a bottom baseline"
			)


func _mobile_table(harness: UiHarness, table: Control) -> void:
	await harness.set_viewport(Vector2i(2048, 921))
	assert_eq(table._cards_list.columns, 2, "A wide handset gets two offer columns")
	assert_eq(
		table._column_count(1800.0, 3, 2.6),
		2,
		"A high-resolution handset has room for two physically readable cards"
	)
	var scroll_rect: Rect2 = table._scroll.get_global_rect()
	var footer_rect: Rect2 = table._footer.get_global_rect()
	assert_true(
		scroll_rect.end.y <= footer_rect.position.y + 1.0,
		"The fixed footer does not overlap the scrollable offer cards"
	)
	assert_true(
		table._cards_list.size_flags_vertical == Control.SIZE_EXPAND_FILL,
		"The two-column card grid receives the screen's main content area"
	)
