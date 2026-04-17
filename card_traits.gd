extends RefCounted
class_name CardTraits


static func effective_kind(card: Dictionary) -> String:
	var raw := str(card.get("type", card.get("kind", ""))).strip_edges().to_lower()
	if not raw.is_empty():
		if raw == "dethrone":
			return "dethrone"
		if raw == "incantation":
			if str(card.get("verb", "")).to_lower() == "dethrone":
				return "dethrone"
			return "incantation"
		if raw == "ritual":
			return "ritual"
		if raw == "noble":
			return "noble"
		if raw == "temple":
			return "temple"
		return raw
	if card.has("temple_id"):
		return "temple"
	if card.has("noble_id"):
		return "noble"
	var verb := str(card.get("verb", "")).strip_edges()
	if not verb.is_empty():
		return "dethrone" if verb.to_lower() == "dethrone" else "incantation"
	if card.has("mid") and card.has("value"):
		return "ritual"
	return ""
