extends TestCase


func run() -> void:
	FeatureFlags.reload()
	assert_true(FeatureFlags.is_enabled("ui_sound_enabled"), "Dev flags keep sound on")
	FeatureFlags.apply_release_overlay()
	assert_false(FeatureFlags.is_enabled("burn_lab_enabled"), "Release overlay disables Burn Lab")
	assert_false(FeatureFlags.is_enabled("analytics_enabled"), "Release overlay keeps analytics off")
	FeatureFlags.reload()
