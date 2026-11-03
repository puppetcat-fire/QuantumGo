## Platform services: Steam when available, graceful no-op when not.
##
## Registered as the `Platform` autoload.
##
## The game must be fully playable without Steam — LAN/online matches use ENet,
## and the leaderboard is local. Steam only adds identity, achievements and the
## global leaderboard. Because GodotSteam is a GDExtension that is not present in
## a source checkout, every call here has to survive its absence; that is also
## what makes the game runnable in CI and in headless tests.
extends Node

signal overlay_state_changed(active: bool)

## Set this to the real Steam AppID when shipping. 480 is Spacewar, Valve's
## public test app, which is the right placeholder before you own an AppID.
const STEAM_APP_ID := 480

const ACHIEVEMENT_FIRST_QUANTUM := "FIRST_QUANTUM_SPLIT"
const ACHIEVEMENT_FIRST_COLLAPSE := "FIRST_COLLAPSE"
const ACHIEVEMENT_WIN_FIRST := "WIN_FIRST_MATCH"

## Steam Leaderboard API name. Create it on the Steamworks backend with the same
## name, type "Highest Score" (descending), and the game will fill it in.
const LEADERBOARD_SCORE := "TOTAL_WEIGHTED_SCORE"

## All achievements the game knows about, with player-facing names. Used by the
## achievements screen and by the docs/SHIPPING.md checklist.
const ACHIEVEMENTS := {
	ACHIEVEMENT_FIRST_QUANTUM: "第一次量子步：把棋盘分裂成两个宇宙",
	ACHIEVEMENT_FIRST_COLLAPSE: "第一次观测：提掉虚子，坍缩一个分支",
	ACHIEVEMENT_WIN_FIRST: "首胜：赢下第一局（单机或联机）",
}

var available: bool = false
var steam_id: String = ""
var persona_name: String = ""
var _steam: Object = null


func _ready() -> void:
	_init_steam()


func _init_steam() -> void:
	if not Engine.has_singleton("Steam"):
		available = false
		return
	_steam = Engine.get_singleton("Steam")
	if _steam == null:
		available = false
		return
	var result: Variant = _steam.call("steamInit", STEAM_APP_ID)
	# GodotSteam returns a dictionary with "status"; older builds return an int.
	if typeof(result) == TYPE_DICTIONARY:
		if int(result.get("status", 1)) != 0:
			available = false
			return
	elif typeof(result) == TYPE_INT and int(result) != 0:
		available = false
		return
	available = true
	steam_id = str(_steam.call("getSteamID"))
	persona_name = str(_steam.call("getPersonaName"))


## Records every achievement the game has ever asked for, with a count. Steam is
## the source of truth for whether it is already unlocked; this map exists so the
## game can show a local "achievements" list, and so the headless tests can prove
## the hooks fire without a Steam client.
var achievement_attempts: Dictionary = {}

## Number of leaderboard submissions the game has made this session.
var leaderboard_submissions: int = 0


## Called once per frame by the main scene. Without it Steam overlay and
## callbacks stop working.
func poll() -> void:
	if available and _steam != null:
		_steam.call("run_callbacks")


func is_available() -> bool:
	return available


## Name to greet the player with. Falls back to the local settings profile.
func player_display_name() -> String:
	if available and not persona_name.is_empty():
		return persona_name
	if has_node("/root/Settings"):
		var settings := get_node("/root/Settings")
		var stored := String(settings.get("player_name"))
		if not stored.strip_edges().is_empty():
			return stored
	return "玩家"


## Unlocks a Steam achievement. Safe to call every time the event happens — Steam
## ignores repeats, and the local counter is for UI/tests only.
func unlock_achievement(api_name: String) -> void:
	if not ACHIEVEMENTS.has(api_name):
		push_warning("unknown achievement: %s" % api_name)
		return
	achievement_attempts[api_name] = int(achievement_attempts.get(api_name, 0)) + 1
	if not available or _steam == null:
		return
	_steam.call("activateAchievement", api_name)


func has_achievement(api_name: String) -> bool:
	return int(achievement_attempts.get(api_name, 0)) > 0


## Submits a numeric score to a Steam leaderboard. The board has to be created on
## the Steamworks backend first; the API name is passed in by the caller.
func submit_leaderboard_score(board: String, score: int) -> bool:
	leaderboard_submissions += 1
	if not available or _steam == null:
		return false
	_steam.call("findOrCreateLeaderboard", board, 1, 1) # 1 = Ascending, 1 = KeepBest
	var result: Variant = _steam.call("uploadLeaderboardScore", score, true, PackedInt32Array())
	return typeof(result) == TYPE_DICTIONARY and bool(result.get("success", false))


func shows_overlay() -> bool:
	if not available or _steam == null:
		return false
	return bool(_steam.call("isOverlayEnabled"))


func open_overlay(page: String = "achievements") -> void:
	if available and _steam != null:
		_steam.call("activateGameOverlay", page)


func shutdown() -> void:
	if available and _steam != null:
		_steam.call("steamShutdown")
	available = false
