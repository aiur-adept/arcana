extends RefCounted
class_name CardRarity

const BRONZE := "bronze"
const SILVER := "silver"
const GOLD := "gold"


static func rarity(card: Dictionary) -> String:
	var k := CardTraits.effective_kind(card)
	match k:
		"noble", "temple", "ring":
			return GOLD
		"ritual":
			return BRONZE
		"bird":
			var c := int(card.get("cost", 0))
			if c == 4:
				return SILVER
			return BRONZE
		"incantation":
			var verb := str(card.get("verb", "")).strip_edges().to_lower()
			if verb == "void":
				return SILVER
			var v := int(card.get("value", 0))
			if v >= 1 and v <= 3:
				return BRONZE
			if v == 4:
				return SILVER
			return BRONZE
		_:
			return BRONZE
