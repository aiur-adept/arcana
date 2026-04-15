Design document

Game name: Arcana

Two 40-card decks.

Players determine who goes first based on a challenge (ie. D20)

Starting hands: 5 cards

Card types: ritual, incantation, noble

At the start of a player's turn, they draw a card from their deck.

During a player’s turn, they may play any number of incantation cards from their hand and up to one ritual and one noble. Once during a player's turn, they may discard a card to draw a card.

Rituals stay on the field when played. Rituals are marked with a number, which is their ritual number. Rituals are active when all ritual numbers between their number and 1 are also active. 1-Rituals are always active. There are 4 ritual powers: 1, 2, 3, and 4. 

Incantations are used a single time and discarded, and they can typically* only be played if the player has an active ritual in play that matches the incantation’s number. For example if the player had rituals 1, 2 and 3, then 3 would be active, and they could play incantations with value 3.

\* Incantations worth N can be played - if a player doesn’t have the ritual for them - by sacrificing rituals worth at least that much. For example, you could sacrifice two 2-Ritual cards to play a 4-Incantation, although you didn’t have a 4-Ritual in play. You could also sacrifice four 1-Rituals, or one 1-Ritual and one 3-Ritual, etc.

Nobles are special cards with a certain ability on them.

When a player has finished their turn, they discard down to 7 cards.

A player wins the game when they have 20 ritual power on the field, or when a player attempts to draw from the empty deck, the player with the most ritual power wins. 

Deckbuilding constraints:

Every legal deck must have 19 Ritual cards and 21 non-Ritual cards, with a maximum of 3 Nobles

There can be no more than 9 of one ritual card value in the deck, for example you may have 9 4-Rituals.

—

Mechanics of Set 1

inc_verbs = ['seek', 'insight', 'burn', 'woe', 'revive', 'wrath']
inc_values = [1, 2, 3, 4]

set_1_incantations = cartesian_product(inc_verbs, inc_values).



Seek X: draw X cards from your deck

Insight X: rearrange the top X cards of a chosen player's deck.

Burn X: discard the top 2*X cards of a chosen player's deck

Woe X: a chosen player discards X cards

Wrath 2/4: Choose and destroy 1/2 opponent rituals

Revive 1: return 1 discarded incantation to hand

Dethrone: Choose and destroy an opponent's noble