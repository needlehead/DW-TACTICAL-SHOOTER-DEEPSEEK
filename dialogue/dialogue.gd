class_name Dialogue
extends Resource
## A conversation, written as plain text, one statement per line (blank lines are skipped):
##   Ingrid: You seem cool.        a line: "Speaker: text"
##   > It kicks like a mule. -> kick
##                                 a choice; consecutive ">" lines make one menu. Kei says the picked text, then
##                                 the conversation jumps to the label after "->"
##   # kick                        a label (where a choice or jump lands)
##   -> bar                        jump to a label; "-> end" ends the conversation
## Lines run in order; reaching the end of the text ends it too. DialogueBox shows it.

@export_multiline var script_text := ""


## Compiled script: {"steps": [step...], "labels": {name: step index}}. Steps:
##   ["say", speaker, text]   ["choose", [[text, label], ...]]   ["goto", label]
func compile() -> Dictionary:
	var steps := []
	var labels := {}
	for raw in script_text.split("\n"):
		var l := raw.strip_edges()
		if l.is_empty():
			continue
		if l.begins_with("#"):
			labels[l.substr(1).strip_edges()] = steps.size()
		elif l.begins_with("->"):
			steps.append(["goto", l.substr(2).strip_edges()])
		elif l.begins_with(">"):
			var parts := l.substr(1).split("->")
			if parts.size() != 2:
				push_error("Dialogue.compile: choice needs 'text -> label' in %s: %s" % [resource_path, l])
				continue
			var option := [parts[0].strip_edges(), parts[1].strip_edges()]
			if not steps.is_empty() and steps[-1][0] == "choose":
				steps[-1][1].append(option)
			else:
				steps.append(["choose", [option]])
		else:
			var i := l.find(":")
			if i <= 0:
				push_error("Dialogue.compile: no 'Speaker:' in %s: %s" % [resource_path, l])
				continue
			steps.append(["say", l.substr(0, i).strip_edges(), l.substr(i + 1).strip_edges()])
	for s: Array in steps:  # every jump target must exist
		var targets: Array = [s[1]] if s[0] == "goto" else (s[1].map(func(o: Array) -> String: return o[1]) if s[0] == "choose" else [])
		for target: String in targets:
			if target != "end" and not labels.has(target):
				push_error("Dialogue.compile: unknown label '%s' in %s" % [target, resource_path])
	return {"steps": steps, "labels": labels}
