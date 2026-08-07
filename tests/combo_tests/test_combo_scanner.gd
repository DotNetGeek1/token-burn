extends TestCase


func run() -> void:
	if ContentDatabase.perks.is_empty():
		ContentDatabase.reload()
	assert_true(ContentDatabase.perks.size() >= 2, "Perk content loaded for combo scan")
	var scanner := ComboScanner.new()
	var results: Array = scanner.scan_pairings(ContentDatabase.perks.slice(0, 4), 3)
	assert_true(results is Array, "Combo scanner returns array")
