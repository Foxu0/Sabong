extends Node

@onready var nm = get_node("/root/NetworkManager")
var connection_rejected: bool = false

func _ready() -> void:
	print("[CLIENT 3] Attempting unauthorized 3rd player join to active 1v1 match on port 17782...")
	nm.player_connected.connect(func(id: int):
		print("[CLIENT 3] Unexpectedly connected to peer: ", id)
	)
	nm.server_disconnected.connect(func():
		print("[CLIENT 3] Server disconnected / rejected us.")
		connection_rejected = true
	)
	nm.online_connection_failed.connect(func(reason: String):
		print("[CLIENT 3] Connection failed: ", reason)
		connection_rejected = true
	)

	var err: int = nm.join_match("127.0.0.1", 17782)
	if err != OK:
		print("[CLIENT 3] Could not initiate connection (err %d)" % err)
		print("[CLIENT3_BLOCKED]")
		get_tree().quit(0)
		return

	# Wait 2.0 seconds to observe rejection
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if connection_rejected or nm.peer == null or nm.peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			print("[CLIENT 3] Successfully blocked/rejected from 1v1 match!")
			print("[CLIENT3_BLOCKED]")
		else:
			print("[CLIENT 3] WARNING: Still connected!")
		get_tree().quit(0)
	)
