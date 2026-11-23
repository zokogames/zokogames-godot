@tool
extends EditorPlugin
## Registers the `ZokoGames` autoload and the simulator project settings.

const AUTOLOAD_NAME := "ZokoGames"
const AUTOLOAD_PATH := "res://addons/zokogames/zokogames.gd"

const SETTINGS := {
	"zokogames/simulator/ad_behaviour": ["fill", TYPE_STRING, PROPERTY_HINT_ENUM, "fill,no_fill,error"],
	"zokogames/simulator/ad_duration_seconds": [1.5, TYPE_FLOAT, PROPERTY_HINT_RANGE, "0,30,0.1"],
	"zokogames/simulator/adblock": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/disabled": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/account_available": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/logged_in": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/username": ["SimPlayer", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/user_id": ["sim-user-1", TYPE_STRING, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/friend_count": [12, TYPE_INT, PROPERTY_HINT_RANGE, "0,500,1"],
	"zokogames/simulator/mute_audio": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/disable_chat": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/kids_mode": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/offline": [false, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/store_available": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
	"zokogames/simulator/verbose": [true, TYPE_BOOL, PROPERTY_HINT_NONE, ""],
}


func _enter_tree() -> void:
	for key in SETTINGS:  # untyped loop variable: typed ones need Godot 4.2
		var spec: Array = SETTINGS[key]
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, spec[0])
		ProjectSettings.set_initial_value(key, spec[0])
		ProjectSettings.add_property_info({
			"name": key, "type": spec[1], "hint": spec[2], "hint_string": spec[3],
		})
	# Projects set up by addon 1.6.0 and older lost the autoload whenever the editor closed (it was removed in _exit_tree).
	_ensure_autoload()


## The documented place to register an autoload: when the user enables the plugin (Project Settings > Plugins).
func _enable_plugin() -> void:
	_ensure_autoload()


## Unregister it only when the user disables the plugin, not every time the editor closes.
func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _ensure_autoload() -> void:
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
