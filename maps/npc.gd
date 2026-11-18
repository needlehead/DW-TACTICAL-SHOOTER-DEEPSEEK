class_name Npc
extends StaticBody3D
## A character standing in the world (a billboard sprite that turns to face you). Interact (F) to talk: opens the
## DialogueBox with `dialogue` over `portraits`.

@export var dialogue: Dialogue
@export var portraits: Texture2D


func interact(_user: Node3D) -> void:
	if dialogue:
		DialogueBox.open(dialogue, portraits, get_tree())
