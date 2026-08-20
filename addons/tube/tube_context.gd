@icon("./icons/tube_context.svg")
@tool
class_name TubeContext extends Resource
## A resource that holds configuration and helper methods for managing simple multiplayer session.

## Character set to generate app IDs. Contains most printable ASCII characters.
const _APP_ID_CHARACTER_SET := "!#$%&()*+,-./ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890:;<=>?@[]^_{|}~"

@export_tool_button("Generate app id", "RandomNumberGenerator") var _generate_app_id_tool_button = (func():
	app_id = _get_random_string(15, _APP_ID_CHARACTER_SET)
)

## Application identifier for this multiplayer context.
## Must be exactly 15 ASCII characters long.
@export var app_id: String

## Character set used to generate session IDs.
## Must not be empty and should only contain ASCII characters.
## A larger set reduces the probability of collision. With 62 characters
## (A–Z, a–z, 0–9), the chance of two random 5-character IDs matching is approximately 1 in 916 million.
## For readability by players, consider removing ambiguous characters (e.g., oO0, ilj1I, z2).
@export_multiline var session_id_characters_set: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890"

## List of tracker server URLs used for session signaling.
@export var trackers_urls: Array[String] = []

## List of STUN server URLs used for WebRTC ICE candidate resolution.
@export var stun_servers_urls: Array[String] = []

## List of TURN servers (optional). Turn server are dictionnary in the form:
## [codeblock]
## {
##		"urls": "turn:turn.example.com:3478",
##		"username: "my-username",
##		"credential": "my-credential",
## }
@export var turn_servers: Array[Dictionary] = []

## --- Project extension (not part of upstream Tube) -----------------------
## TubeClient exposes peer_signaling_timeout/peer_signaling_max_attempts as
## plain Node properties with no Resource-backed config, so tuning them
## meant a code change. Mirrored here so NetworkPeer can copy them onto
## TubeClient at startup and this project can tune them from the Inspector
## instead. See TubeClient's own doc comment on these two properties for
## what each one controls.

## Applied to TubeClient.peer_signaling_timeout. Tube's own default (2.0s)
## can be too tight when UPnP is involved: the README notes the port can
## open only after this timeout has already elapsed, so a slower-than-
## typical UPnP negotiation needs a longer per-attempt window to have a
## chance of landing inside it.
@export var peer_signaling_timeout: float = 4.0

## Applied to TubeClient.peer_signaling_max_attempts. Raised alongside
## peer_signaling_timeout for the same reason -- more, longer attempts
## give a slow UPnP port mapping more total time to open before signaling
## gives up on a peer entirely.
@export var peer_signaling_max_attempts: int = 5


func _to_string() -> String:
	return "AppID: %s | Trackers: %s | STUN: %s" % [app_id, str(trackers_urls), str(stun_servers_urls)]


func _is_ascii(string: String) -> bool:
	for char_index in range(string.length()):
		if string.unicode_at(char_index) >= 128:
			return false
	return true

## Checks if the context configuration is valid.
func is_valid() -> bool:
	if 0 == session_id_characters_set.length():
		printerr("Session ID Character Set is empty")
		return false

	if not _is_ascii(session_id_characters_set):
		printerr("Session ID Character Set can only contain ASCII characters")
		return false
	
	if null == app_id or 15 != app_id.length() or not _is_ascii(app_id):
		printerr("App id is invalid")
		return false
	
	return true

## Returns ICE server configuration dictionary for WebRTC peer connection.
## 
## Example:
## [codeblock]
## {
## 	"iceServers": [
## 		{
## 			"urls": [ "stun:stun.example.com:3478" ], # One or more STUN servers.
## 		},
## 		{
## 			"urls": [ "turn:turn.example.com:3478" ], # One or more TURN servers.
## 			"username": "a_username", # Optional username for the TURN server.
## 			"credential": "a_password", # Optional password for the TURN server.
## 		}
## 	]
## }

## [/codeblock]
func get_ice_servers() -> Dictionary:
	var ice_servers := []
	
	if null != stun_servers_urls:
		for url in stun_servers_urls:
			ice_servers.append({
				"urls": url
			})
	
	if null != turn_servers:
		for turn_server in turn_servers:
			ice_servers.append(turn_server)
	
	if ice_servers.is_empty():
		return {}
	
	return {
		"iceServers": ice_servers
	}


func _get_random_string(p_size: int, character_set: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	var character_set_length := character_set.length()
	
	var out := ""
	for i in range(p_size):
		var index := rng.randi()%character_set_length
		out += character_set[index]
	
	return out
	

## Generates a random 5-character session ID.
func generate_session_id() -> String:
	return _get_random_string(5, session_id_characters_set)


## Validates if a session ID is correct
func is_session_id_valid(p_session_id: String) -> bool:
	return 5 == p_session_id.length()


## Validates if a peer ID hash is the right shape: exactly 20 numeric
## characters. is_valid_int() alone is a format check, not a range check --
## a 20-digit value comfortably exceeds int64, which is fine here since
## get_peer_id() only ever parses the last 6 digits, never the full
## string (see get_peer_id_hash() for why).
func is_peer_id_hash_valid(p_peer_id_hash: String) -> bool:
	return 20 == p_peer_id_hash.length() and p_peer_id_hash.is_valid_int()

## Returns the combined "info hash" (app ID and session ID) for tracker usage.
func get_info_hash(p_session_id: String) -> String:
	if not is_session_id_valid(p_session_id):
		printerr("Invalid session id")
		return ""

	return app_id + p_session_id


## Deterministically derives a 14-digit, non-zero-leading nonce from the
## session id -- identical wherever it's computed (host or any joiner,
## before or after any peer contact, since a joiner must already know the
## session id to join at all) yet different between concurrent sessions.
## Session ids are unique per session (5 characters from
## session_id_characters_set, ~916 million combinations at the default
## 62-character set), so this is what actually prevents two concurrent
## hosts -- both always peer id 1 -- from colliding on the tracker; see
## get_peer_id_hash().
func _session_nonce(p_session_id: String) -> String:
	var digest := p_session_id.sha256_text()
	var value := ("0x" + digest.substr(0, 15)).hex_to_int()
	return str(value % 90000000000000 + 10000000000000)


## Converts an integer peer ID into a peer ID hash for tracker usage.
##
## The BitTorrent tracker protocol treats peer_id as a globally unique
## identifier, but a Tube session host is always multiplayer peer id 1 (see
## TubeClient._SERVER_PEER_ID) -- every host, on every device, used to
## announce the exact same "00000000000000000001", which the tracker sees
## as a collision: only one device could ever host at a time. The first 14
## digits are now a per-session nonce (see _session_nonce()) and the last 6
## are the peer id itself, zero-padded -- still exactly 20 numeric
## characters, still fully self-contained (no coordination with the other
## device needed), but no longer identical across different sessions.
func get_peer_id_hash(p_peer_id: int, p_session_id: String) -> String:
	return _session_nonce(p_session_id) + str(p_peer_id).pad_zeros(6)


## Converts a peer ID hash into an integer peer ID. Reads only the last 6
## digits, ignoring the session-nonce prefix entirely -- so this correctly
## recovers the peer id from a hash minted by ANY device for this session,
## not just the local one.
func get_peer_id(p_peer_id_hash: String) -> int:
	if not is_peer_id_hash_valid(p_peer_id_hash):
		return 0

	return int(p_peer_id_hash.right(6))
