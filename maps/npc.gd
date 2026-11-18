class_name Npc
extends StaticBody3D
## A character standing in the world (a billboard sprite that turns to face you). Interact (F) to talk: opens the
## DialogueBox with `dialogue` over `portraits` (one full-screen image per character).

@export var dialogue: Dialogue
@export var portraits: Array[Texture2D] = []


func interact(_user: Node3D) -> void:
	if dialogue:
		DialogueBox.open(dialogue, portraits, get_tree())
