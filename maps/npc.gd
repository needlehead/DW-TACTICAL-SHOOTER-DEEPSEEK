class_name Npc
extends StaticBody3D
## A character standing in the world (a billboard sprite that turns to face you). Interact (F) to talk: opens the
## DialogueBox with `dialogue` and these character `portraits` (placed with F4 in the dialogue screen).

@export var dialogue: Dialogue
@export var portraits: Array[Portrait] = []


func interact(_user: Node3D) -> void:
	if dialogue:
		DialogueBox.open(dialogue, portraits, get_tree())
