# Arcana Rules Reference (Set 1)

This document defines the complete game rules for Arcana as currently implemented.

## 1) Match Setup

- Two players each use a legal **40-card** deck.
- Determine starting player by any agreed random method (for example, a d20 challenge).
- Each player draws **5** cards.
- Each player may take **one** London mulligan:
  - Shuffle hand into deck.
  - Draw 5 new cards.
  - Put exactly 1 card from hand on the bottom of deck.
- After mulligans are complete, the starting player takes the first turn and performs the normal turn-start draw.

## 2) Zones

- **Deck**: face-down draw pile.
- **Hand**: private cards in hand.
- **Ritual Field**: your rituals in play.
- **Noble Field**: your nobles in play.
- **Temple Field**: your temples in play.
- **Crypt**: your discard pile; destroyed/sacrificed/discarded cards go here unless stated otherwise.
- **Abyss**: a separate pile for specific effects (primarily cards cast via Revive, and some temple costs).

## 3) Card Types

- **Ritual**: persistent card played to ritual field; contributes ritual power when active.
- **Incantation**: one-shot spell card played from hand, then put into crypt.
- **Noble**: persistent unit with static and/or activated/triggered abilities.
- **Temple**: persistent card played by sacrificing rituals; has once-per-turn activations.
- **Bird**: a supplemental unit type used for match points and bird combat.

## 4) Turn Structure

Each turn has three practical steps:

1. **Turn-start draw**
   - Active player draws 1 card.
   - Exception: if that player controls Gotha, they skip this draw.
2. **Main phase**
   - Active player may perform actions in any order, including:
     - Play any number of incantations (if legal and paid).
     - Play up to one ritual.
     - Play up to one noble.
     - Play up to one temple.
     - Perform one bird combat (optional, once per turn).
     - Activate eligible nobles (generally once each per turn).
     - Activate eligible temples (once each per turn).
     - Once per turn: discard one card to draw one card.
3. **End turn / hand cleanup**
   - Active player must discard down to **7** cards.
   - Then turn passes to opponent, who immediately starts their turn with turn-start draw.

## 5) Ritual Lanes and Active Rituals

Ritual values are 1, 2, 3, and 4.

- A **1-ritual is always active**.
- A ritual of value **N > 1** is active only if you also have at least one active ritual of every value from 1 to N-1.
- A ritual lane is active if you control at least one active ritual of that value.

**Ritual power** is the sum of values of your active rituals only.
**Match power** equals your ritual power plus 1 for each Bird you control (+1 extra if it's nested).

Example:

```
1 x 1R
2 x 2R
1 x 3R
2 x 4R
```

All are active, so ritual power is `1 + 2 + 2 + 3 + 4 + 4 = 16`.

Bird lane example:

- If you control 1 x Bird 1, 1 x Bird 2, and 1 x Bird 3, the summed Bird power is 6, so your 6-lane is active from birds.

## 6A) Birds

### 6A.1 Cost and Power

- Birds have costs **2-4** and powers **1-3**.
- A Bird with cost **N** has power **N-1** (2->1, 3->2, 4->3).
- Each Bird you control adds **+1** to your match power.

### 6A.2 Bird Combat (once per turn)

- Once per turn during your main phase, you may choose any set of your Birds and any set of opponent Birds to fight.
- A chosen attacking set may target only one opposing Bird in that combat.
- Simultaneously, each chosen side deals damage equal to its total chosen Bird power to the opposing chosen side.
- Damage on each side is divided among that side's chosen Birds as that side's controller decides.
- After damage is assigned, each Bird that has damage greater than or equal to its power is discarded.

### 6A.3 Bird Nesting

- Birds have the ability nest. A temple on your field may nest X birds in it where X is its cost. 
- Each bird nested in a temple adds an additional +1 to ritual power and cannot be involved in fighting.
- An un-nested bird is "wild".

## 6) Playing Cards and Paying Costs

### 6.1 Incantations

To play an incantation of value **N**, you must either:

- Have active lane N, or
- Sacrifice rituals with total value at least N.

If sacrificed, those rituals leave your field and go to your crypt.

### 6.2 Nobles

To play a noble, you must have the noble's cost lane active (no sacrifice payment for noble play).
Only one noble may be played from hand per turn.

### 6.3 Temples

To play a temple, you must sacrifice rituals with total value at least its temple cost:

- Most temples cost **7**.
- Ytria costs **9**.

Only one temple may be played from hand per turn.

### 6.4 Dethrone

Dethrone has value 4.
To play Dethrone, you must either have active lane 4 or sacrifice rituals totaling at least 4.
It destroys one target opposing noble.

## 7) Action Limits and Timing Locks

- During your turn, you may play:
  - At most 1 ritual from hand.
  - At most 1 noble from hand.
  - At most 1 temple from hand.
  - At most 1 bird from hand.
  - Any number of incantations (as long as each is legal and payable)
- `Discard-for-draw` may be used once per turn.
- `Bird combat` may be used once per turn.
- Each noble/temple activation is once per turn per permanent.
- You cannot take further proactive actions while waiting for a required response to a pending effect you created (for example, opponent discard choice from Woe, or your own optional scion trigger decision).

## 8) Win and Draw Conditions

Game ends immediately when any of the following occurs:

1. A player reaches **20 or more match power**.
2. A player attempts to draw from an empty deck.

If empty-deck draw is attempted:

- Compare both players' current match power.
- Higher match power wins.
- Equal match power is a draw.

## 9) Core Mechanics (Set 1)

- **Seek X**: Draw X cards. [comes in Seek 1 and Seek 2]
- **Insight X**: Look at top X cards of target player's deck; reorder any on top and/or move any number to bottom.
- **Burn X**: Mill `2 * X` cards from target player's deck into that player's crypt.
- **Woe X**: Target player discards X-2 chosen cards from hand. [comes in Woe 3 and 4]
- **Wrath 4**: Destroy 1 opponent ritual. That opponent draws a card.
- **Revive 1**: Cast 1 eligible incantation from your crypt.
  - Revive itself cannot be revived.
  - Wrath cannot be cast via revive.
  - Cards cast this way go to abyss (not crypt).
- **Dethrone 4**: Destroy one opposing noble.
- **Deluge X**: Destroy all Birds of power X-1 or less. [comes in Deluge 2, 3 and 4]
- **Tears 3**: Return a Bird from your crypt to the field. 
- **Void**: Can be played during the opponent's turn by discarding one other card from your hand to nullify a non-ritual card the opponent just played (it goes to their crypt with no effect; costs already paid such as sacrifices are not refunded). Void has no other cost — no lane or ritual sacrifice is required. Void may nullify another Void. The reactive decision window is 10 seconds, counted client-side; timing out auto-skips. The countdown is paused once the reactor begins picking a discard (so committing to Void gives unrestricted time to choose what to pitch). In networked PvP this leaks one bit of information ("I hold Void"), accepted as the cost of avoiding a universal delay on all card plays.

## 10) Noble Abilities (Set 1)

All noble static abilities apply while that noble remains on the field.

### 10.1 Cost 4

- **Yrss, Noble of Power**: Grants ritual lane 3 while on field (static).
- **Xytzr, Noble of Emanation** (static):
  - Your Seek effects draw +1 card.
  - Your Insight effects affect +1 card.
- **Yytzr, Noble of Occultation** (static):
  - Your Burn effects mill an additional 3 cards.
  - When you play Revive, you may additionally sacrifice rituals totaling at least 2 to add one extra revive step.
- **Zytzr, Noble of Annihilation** (static):
  - Your Wrath destroys 1 extra ritual.
  - Your Woe forces 1 additional discard.
- **Aeoiu, Scion of Rituals** (activated, once per turn):
  - Play one ritual from your crypt to your field.
  - This is in addition to your normal one ritual-from-hand per turn.

### 10.2 Cost 3

- **Trss, Noble of Power**: Grants ritual lane 2 while on field (static).
- **Bndrr, Noble of Incantation**: Once per turn, Burn 2.
- **Indrr, Noble of Incantation**: Once per turn, Insight 1.
- **Rndrr, Noble of Incantation**: Once per turn, Revive 1.
- **Sndrr, Noble of Incantation**: Once per turn, you may discard a card to Seek 1.
- **Wndrr, Noble of Incantation**: Once per turn, you may discard a card to Woe 3.

### 10.3 Cost 2

- **Rmrsk, Scion of Emanation** (triggered, optional):
  - After you resolve Insight, you may draw 1.
- **Smrsk, Scion of Occultation** (triggered, optional):
  - After you resolve Burn or Revive, you may sacrifice one ritual of value X, then Burn yourself X.
- **Tmrsk, Scion of Annihilation** (triggered, optional):
  - After you resolve Wrath, you may Woe 3.


- **Krss, Noble of Power**: Grants ritual lane 1 while on field (static).

## 11) Temple Abilities (Set 1)

Temple activations are once per turn per temple.

### 11.1 Cost 6 temples

**Eyrie, Temple of Feathers**:
  - When this Temple enters, search your deck for a Bird card and put it onto your field, then shuffle your deck.

### 11.2 Cost 7 temples

- **Phaedra, Temple of Illusion**:
  - Insight 1, then draw 1.
- **Delpha, Temple of Oracles**:
  - Sacrifice one ritual of value X from field (it goes to abyss), then Burn yourself X, then play one ritual from your crypt.
- **Gotha, Temple of Illness**:
  - Static: Skip your turn-start draw.
  - Activated: Discard one non-temple card, then draw cards equal to that card's cost (or power if Ritual).

### 11.3 Cost 9 temple

- **Ytria, Temple of Cycles**:
  - Discard your hand, then draw that many cards.

## 12) Clarifications and Edge Cases

- **Lane grants are static**: If a Noble of Power is on field, its granted lane is available continuously.
- **Woe with insufficient hand**: target discards as many as possible (up to required amount).
- **Wrath with too few enemy rituals**: destroys as many as possible, up to required amount.
- **Milling is not drawing**: Burn moving cards from deck to crypt does not trigger empty-deck loss by itself.
- **Empty deck loss check** only occurs when a player attempts to draw.
- **Revived cards to abyss**: an incantation cast via revive is placed in the abyss after resolution; if a revived noble is later destroyed, it goes to the abyss.
- **Temples and nobles cannot be revived**: revive only works on incantations.

## 13) Deck Construction Rules

For legal deck construction:

- Base deck: exactly **19 Ritual** cards and **21 non-Ritual** cards (**40 cards total**).
- At most **9 rituals of any one value** (for example, no more than 9 copies of value-4 rituals).
- At most **4 copies** of any named incantation or bird card.
- At most **1 copy** of any named temple card.
- For nobles, at most **1** card per noble first name (for example, max 1 "Yrss").