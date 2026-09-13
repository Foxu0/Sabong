extends Node

func _ready() -> void:
	print("--- TESTING LOBBY UI INSTANTIATION ---")
	var lobby = LobbyUI.new()
	add_child(lobby)
	print("[SUCCESS] LobbyUI created and added to scene tree!")
	get_tree().quit(0)
