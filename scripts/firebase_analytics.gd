extends Node
# Firebase Analytics for Android. Collection stays disabled until the player opts in.

const CONSENT_PATH := "user://analytics_consent.cfg"
const MAX_PENDING_EVENTS := 32

var consent_answered := false
var consent_granted := false
var _firebase_core: Object
var _firebase_analytics: Object
var _analytics_ready := false
var _pending_events: Array[Dictionary] = []


func _ready() -> void:
	_load_consent()
	if OS.get_name() != "Android":
		return
	if not Engine.has_singleton("GodotxFirebaseCore") or not Engine.has_singleton("GodotxFirebaseAnalytics"):
		push_warning("Firebase Analytics Android plugin is not available in this build.")
		return

	_firebase_core = Engine.get_singleton("GodotxFirebaseCore")
	_firebase_analytics = Engine.get_singleton("GodotxFirebaseAnalytics")
	_firebase_core.core_initialized.connect(_on_core_initialized)
	_firebase_core.initialize()


func _load_consent() -> void:
	var config := ConfigFile.new()
	if config.load(CONSENT_PATH) != OK:
		return
	consent_answered = bool(config.get_value("analytics", "answered", false))
	consent_granted = consent_answered and bool(config.get_value("analytics", "granted", false))


func _save_consent() -> void:
	var config := ConfigFile.new()
	config.set_value("analytics", "answered", consent_answered)
	config.set_value("analytics", "granted", consent_granted)
	var error := config.save(CONSENT_PATH)
	if error != OK:
		push_warning("Could not save the Analytics privacy choice: %s" % error_string(error))


func should_show_consent_prompt() -> bool:
	return OS.get_name() == "Android" and not consent_answered


func set_user_consent(granted: bool) -> void:
	consent_answered = true
	consent_granted = granted
	_save_consent()
	_apply_consent()


func _on_core_initialized(success: bool) -> void:
	if not success:
		push_warning("Firebase Core failed to initialize; Analytics is unavailable.")
		return
	_firebase_analytics.analytics_initialized.connect(_on_analytics_initialized)
	_firebase_analytics.initialize()


func _on_analytics_initialized(success: bool) -> void:
	if not success:
		push_warning("Firebase Analytics failed to initialize.")
		return
	_analytics_ready = true
	_apply_consent()
	if consent_granted:
		for event in _pending_events:
			_firebase_analytics.log_event(str(event["name"]), event["params"])
	_pending_events.clear()


func _apply_consent() -> void:
	if not _analytics_ready:
		return
	var analytics_state := "granted" if consent_granted else "denied"
	_firebase_analytics.set_consent({
		"analytics_storage": analytics_state,
		"ad_storage": "denied",
		"ad_user_data": "denied",
		"ad_personalization": "denied",
	})
	_firebase_analytics.set_analytics_collection_enabled(consent_granted)
	if not consent_granted:
		_pending_events.clear()


func track_event(event_name: String, parameters: Dictionary = {}) -> void:
	if not consent_granted or OS.get_name() != "Android":
		return
	if not _analytics_ready:
		if _pending_events.size() < MAX_PENDING_EVENTS:
			_pending_events.append({"name": event_name, "params": parameters.duplicate()})
		return
	_firebase_analytics.log_event(event_name, parameters)


func track_screen(screen_name: String) -> void:
	track_event("game_screen_view", {"screen_name": screen_name})
