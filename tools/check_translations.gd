extends SceneTree

const CSV_PATH := "res://localization/ui.csv"
const TRANSLATION_PATHS := {
	"en": "res://localization/ui.en.translation",
	"zh_CN": "res://localization/ui.zh_CN.translation",
}

func _init() -> void:
	var source := FileAccess.open(CSV_PATH, FileAccess.READ)
	if source == null:
		push_error("TRANSLATION_CHECK: cannot read %s" % CSV_PATH)
		quit(1)
		return
	var header := source.get_csv_line()
	var generated: Dictionary = {}
	for column: int in range(1, header.size()):
		var locale := str(header[column])
		var translation := Translation.new()
		translation.locale = locale
		generated[locale] = translation
	while source.get_position() < source.get_length():
		var row := source.get_csv_line()
		if row.is_empty() or str(row[0]).is_empty():
			continue
		for column: int in range(1, mini(header.size(), row.size())):
			(generated[str(header[column])] as Translation).add_message(str(row[0]), str(row[column]))
	var valid := true
	for locale: String in TRANSLATION_PATHS:
		var compiled := load(TRANSLATION_PATHS[locale]) as Translation
		var expected := generated.get(locale) as Translation
		if compiled == null or expected == null:
			push_error("TRANSLATION_CHECK: missing locale %s" % locale)
			valid = false
			continue
		var expected_keys := Array(expected.get_message_list())
		expected_keys.sort()
		for key: StringName in expected_keys:
			if expected.get_message(key) != compiled.get_message(key):
				push_error("TRANSLATION_CHECK: %s differs at %s" % [locale, str(key)])
				valid = false
				break
	print("TRANSLATION_CHECK: %s CSV and compiled resources are semantically identical" % ("PASS" if valid else "FAIL"))
	quit(0 if valid else 1)
