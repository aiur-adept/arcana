import json

rituals = [0, 8, 4, 4, 3]

deck = []

for i in range(1,4+1):
    deck.append({
        "type": "Ritual",
        "power": f"Ritual {i+1}",
    })

inc_verbs = ['seek', 'insight', 'burn', 'woe', 'revive', 'wrath']

for inc_verb in inc_verbs:
    for i in range(1,4+1):
        deck.append({
            "type": "Incantation",
            "power": f"{inc_verb} {i}",
        })

print(json.dumps(deck, indent=4))