class_name GameSession
extends RefCounted
## Abstracts how GameScreen drives a game: either directly against a
## local, fully-authoritative GameState (hot-seat), or through
## NetworkPeer talking to a server that owns the real state (online).
## GameScreen only ever talks to a GameSession -- it doesn't know or
## care which kind it has.

signal state_changed

var db: CardDatabase

func get_state() -> GameState:
	push_error("GameSession.get_state is abstract")
	return null

func get_legal_actions() -> Array[Action]:
	push_error("GameSession.get_legal_actions is abstract")
	return []

## Submit an action. Hot-seat mutates the local state immediately and
## emits state_changed synchronously. Network sends an intent to the
## server and returns immediately -- state_changed only fires once the
## server's resulting snapshot arrives; nothing here mutates state directly.
func submit_action(_action: Action) -> void:
	push_error("GameSession.submit_action is abstract")

## Which seat's board should be rendered on this device right now. For
## hot-seat this is whichever seat was most recently revealed via the
## pass-device screen (i.e. tracks current_player_index by construction).
## For network play it's fixed to this client's own assigned seat for the
## whole game, independent of whose turn it currently is.
func viewer_index() -> int:
	return -1

func is_seat_ai(_player_index: int) -> bool:
	return false
