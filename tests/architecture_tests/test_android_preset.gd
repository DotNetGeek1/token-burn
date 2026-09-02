extends TestCase

## Pins the committed Android export template so Play target API, 64-bit, and
## version name cannot drift from project.godot without a failing test.


const PRESET := "res://export/android_export_presets.cfg"


func run() -> void:
	var cfg := ConfigFile.new()
	var err: Error = cfg.load(PRESET)
	assert_eq(err, OK, "Android export template loads")
	if err != OK:
		return
	assert_eq(str(cfg.get_value("preset.0", "name", "")), "Android", "preset 0 is Android")
	assert_true(bool(cfg.get_value("preset.0.options", "gradle_build/use_gradle_build", false)), "Gradle build is on")
	assert_eq(int(cfg.get_value("preset.0.options", "gradle_build/export_format", 0)), 1, "export format is AAB")
	assert_eq(str(cfg.get_value("preset.0.options", "gradle_build/target_sdk", "")), "36", "target SDK is 36")
	assert_eq(str(cfg.get_value("preset.0.options", "gradle_build/min_sdk", "")), "24", "min SDK is 24")
	assert_true(bool(cfg.get_value("preset.0.options", "architectures/arm64-v8a", false)), "arm64-v8a is enabled")
	assert_false(bool(cfg.get_value("preset.0.options", "architectures/armeabi-v7a", true)), "armeabi-v7a is off")
	assert_false(bool(cfg.get_value("preset.0.options", "architectures/x86", true)), "x86 is off")
	assert_false(bool(cfg.get_value("preset.0.options", "architectures/x86_64", true)), "x86_64 is off")
	assert_eq(
		str(cfg.get_value("preset.0.options", "package/unique_name", "")),
		"com.tokenburn.game",
		"package id is com.tokenburn.game"
	)
	assert_true(int(cfg.get_value("preset.0.options", "version/code", 0)) > 12, "version code is past the last playtest APK")
	assert_eq(
		str(cfg.get_value("preset.0.options", "version/name", "")),
		str(ProjectSettings.get_setting("application/config/version", "")),
		"version name matches project.godot"
	)
	for key in [
		"launcher_icons/main_192x192",
		"launcher_icons/adaptive_foreground_432x432",
		"launcher_icons/adaptive_background_432x432",
		"launcher_icons/adaptive_monochrome_432x432",
	]:
		var path: String = str(cfg.get_value("preset.0.options", key, ""))
		assert_true(not path.is_empty(), "%s is set" % key)
		assert_true(FileAccess.file_exists(path), "%s exists (%s)" % [key, path])
