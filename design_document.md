# Arcana Design document

## Rules

Two **40-card** decks.

Players determine who goes first based on a challenge (ie. D20)

Starting hands: **5 cards** (with a single london mulligan allowed (draw 5 put one on the bottom of library))

### Game zones 

- player hand
- player field [where rituals and nobles go]
- player crypt [where discarded cards go]
- the abyss [cards revived go here instead of the crypt]

Card types: **ritual**, **incantation**, **noble**

### Draw phase, Main phase

At the start of a player's turn, they draw a card from their deck.

During a player’s turn, they may play any number of incantation cards from their hand and up to one ritual and one noble. Once during a player's turn, they may discard a card to draw a card.

### Rituals 

Rituals stay on the field when played. Rituals are marked with a number, which is their ritual number. Rituals are active when all ritual numbers between their number and 1 are also active. 1-Rituals are always active. There are 4 ritual powers: 1, 2, 3, and 4. 

### Incantations 
Incantations are used a single time and discarded, and they can typically* only be played if the player has an active ritual in play that matches the incantation’s number. For example if the player had rituals 1, 2 and 3, then incantation lane 3 would be active, and they could play incantations with value 3.

\* Incantations worth N can be played - if a player doesn’t have the ritual for them - by sacrificing rituals worth at least that much. For example, you could sacrifice two 2-Ritual cards to play a 4-Incantation, although you didn’t have a 4-Ritual in play. You could also sacrifice four 1-Rituals, or one 1-Ritual and one 3-Ritual, etc.

### Nobles 

Nobles are special cards with a certain ability on them.

### Discard phase 

When a player has finished their turn, they discard down to 7 cards.

### Winning the game

A player wins the game when they have 20 ritual power on the field (only Rituals count toward ritual power, Nobles don't add to ritual power), or when a player attempts to draw from the empty deck, the player with the most ritual power wins. Ritual power counts active rituals only. So for example, the below represents 16 ritual power:

```
1 x 1R
2 x 2R
1 x 3R
2 x 4R
```

## Deckbuilding constraints

Every legal deck must have 19 Ritual cards and 21 non-Ritual cards, with a maximum of 4 Nobles of each first name, eg. 4 x "Yrss"

There can be no more than 9 of one ritual card value in the deck, for example you may have 9 4-Rituals.

You may only have 4 copies of a given incantation. For example you can have 4x seek-1, 4x seek-2, and 4x wrath

—

## Mechanics of Set 1

*Seek* X: draw X cards from your deck

*Insight* X: rearrange the top X cards of a chosen player's deck.

*Burn* X: discard the top 2*X cards of a chosen player's deck

*Woe* X: a chosen player discards X cards

*Wrath 4*: Choose and destroy 2 opponent rituals

*Revive 1*: you may play 1 incantation or noble from your crypt (Wrath cannot be revived). Cards played this way go to the abyss instead of the crypt (a revived noble dethroned will go to the abyss).

*Dethrone 4*: Choose and destroy an opponent's noble

### Nobles:

#### Cost 4

*Krss, Noble of Power*: A low-cost power noble that grants access to incantation lane 1.

*Trss, Noble of Power*: A mid-cost power noble that grants access to incantation lane 2.

*Yrss, Noble of Power*: A higher-cost power noble that grants access to incantation lane 3.

*Xytzr, Noble of Emanation*: Whenever you *Seek*, draw an additional card. Whenever you *Insight*, look at and additional card.

*Yytzr, Noble of Occultation*: Whenever you *Burn*, add 3 to the number to be discarded. Whenever you *Revive*, you may sacrifice {2} or more. If you do, you may play an additional card from the crypt.

*Zytzr, Noble of Annihilation*: Whenever you *Wrath*, destroy an extra ritual. Whenever you *Woe*, the player discards an additional card.

*Aeoiu, Noble of Rituals*: Once per turn, you may play a Ritual from your crypt.

#### Cost 3 

*Bndrr, Noble of Incantation*: Once per turn, it can activate to cast a spell-like *Burn 1* effect.

*Indrr, Noble of Incantation*: Once per turn, it can activate to cast a spell-like *Insight 2* effect.

*Rndrr, Noble of Incantation*: Once per turn, it can activate to cast a spell-like *Revive 1* effect.

*Sndrr, Noble of Incantation*: Once per turn, it can activate to cast a spell-like *Seek 1* effect.

*Wndrr, Noble of Incantation*: Once per turn, it can activate to cast a spell-like *Woe 1* effect.

#### Cost 2

*Rmrsk, Scion of Emanation*: Whenever you Seek or Insight, you may then draw a card.

*Smrsk, Scion of Occultation*: Whenever you Burn or Revive, you may then sacrifice a Ritual of power X to burn yourself X (discard 2X cards from deck).

*Tmrsk, Scion of Annihilation*: Whenever you Wrath, you may then Woe 1.