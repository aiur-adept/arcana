# Arcana Card Addition Checklist

Use this checklist whenever you add a new card, card variant, temple, or noble.

## 1) Design + rules text
- Add or update the card in `design_document.md`.
- Confirm the card has a stable internal id (`noble_id`, `temple_id`, or a normalized `verb` + `value` pair).

## 2) Deck editor (card gallery + deck save/load)
- Add the definition to the right list in `deck_editor.gd`:
  - `NOBLE_DEFS` for nobles
  - `TEMPLE_DEFS` for temples
  - `INCANTATION_VERBS` / `_incantation_values_for_verb()` for incantations
- Verify `_build_gallery_entries()` includes the new card.
- Verify `_ingest_deck_dictionary()` can read it from saved JSON.
- Verify `_build_deck_payload()` serializes it correctly.

## 3) Card preview text
- Add preview rules text in `card_preview_presenter.gd`:
  - `_noble_preview_text()` for nobles
  - `_temple_preview_text()` for temples
  - `card_rules_text()` logic for new incantation behavior if needed
- Check title/type line values (`card_title()`, `card_type_line()`) if cost/type formatting is unique.

## 4) Match engine (authoritative gameplay logic)
- Add constants/ids in `arcana_match_state.gd` (for new nobles/temples).
- Update validators (`_valid_temple_id`, play/cast guards, etc.).
- Add effect implementation (`apply_*` / `execute_*`) with legality checks.
- Add logging and once-per-turn exhaustion handling if the card activates.
- Ensure empty-deck, pending-response, and mulligan edge cases are respected.

## 5) Game UI action flow
- Wire activation/play interaction in `game.gd` (button paths, hand-pick flows, overlays).
- Add RPC plumbing in `game.gd` for multiplayer (`submit_*`).
- If temple/noble activation availability has special constraints, update `game_ritual_field_view.gd`.

## 6) Data and starter content
- If the card should exist in included decks, add/update a deck file in `included_decks/` and keep `included_decks/index.json` in sync.
- Keep `counts` blocks in sync when editing included deck payloads.
- If a new exported deck template is needed, export it from the deck editor into `included_decks/`.

## 7) Validation + sanity checks
- Run in solo and (if relevant) multiplayer host/client.
- Verify:
  - card appears in deck editor gallery
  - card can be saved/loaded in deck JSON
  - preview text matches intended rules
  - gameplay effect resolves correctly and once-per-turn limits apply
  - logs/status text are clear
