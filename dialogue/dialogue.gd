class_name Dialogue
extends Resource
## A conversation, written as plain text: one "Speaker: line" per line (blank lines are skipped).
## DialogueBox shows it; speakers it knows (Kei, Ingrid) get their side and colour there.

@export_multiline var script_text := ""


## [[speaker, text], ...] in order.
func lines() -> Array:
	var out := []
	for raw in script_text.split("\n"):
		var l := raw.strip_edges()
		if l.is_empty():
			continue
		var i := l.find(":")
		if i <= 0:
			push_error("Dialogue.lines: no 'Speaker:' in %s line: %s" % [resource_path, l])
			continue
		out.append([l.substr(0, i).strip_edges(), l.substr(i + 1).strip_edges()])
	return out
