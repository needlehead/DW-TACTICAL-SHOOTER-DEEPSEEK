class_name Npc
extends StaticBody3D
## A character standing in the world (a billboard sprite that turns to face you). Interact (F) to talk: opens the
## DialogueBox with the next of `dialogues` (the last one repeats) and these character `portraits` (placed with F4
## in the dialogue screen).

@export var dialogues: Array[Dialogue] = []
@export var portraits: Array[Portrait] = []


var talks := 0


func interact(_user: Node3D) -> void:
	if dialogues.is_empty():
		return
	if DialogueBox.open(dialogues[mini(talks, dialogues.size() - 1)], portraits, get_tree()):
		talks += 1
