# Economy

Two economies that never mix.

## Run economy — lost on death

**Gold** — spent during the run, in shops.
**Equipment** — Weapon, Armor, Relic. Three categories, no more.
**Temporary upgrades** — picked up during the run.

## Meta economy — kept after death

**Soul Shards** → permanent upgrades. Deliberately restrained: `+5% HP`, `+3% damage`, `+5% gold`, `+1 starting relic`. The game should not become a giant RPG where meta progression replaces skill.

Shards are paid when a run *ends*, scaled by floors cleared, so a deep failure is still worth something. Spending them is Phase 9.

## Relics

Relics are where procedural combinations get interesting, because they interact.

- **Blood Charm** — +10% damage when below 30% HP
- **Iron Heart** — +25 maximum HP
- **Lucky Coin** — +10% chance for additional loot
- **Whetstone** — +8% damage
- **Second Wind** — +25% stamina regeneration

Armour is the same mechanism with different fields: Leather Vest (+15 max HP), Iron Plate (−12% damage taken), Shroud (−6% damage taken, +10% stamina regen).

**Nothing knows how an effect is applied.** An item declares plain named fields in `LootConfig`; `InventoryService` folds them into an aggregate, and combat asks for the aggregate. Adding a relic is a data entry; adding a new *kind* of effect is one accessor plus one read where it matters.

Conditional effects are evaluated **when asked for**, never cached. Blood Charm's "below 30%" would be wrong the instant health changed if it were folded in at pickup time.

Weapon drops wait for Phase 8. Dropping "a Sword" when the Sword is the only weapon is a reward that changes nothing, and the archetypes and modifiers that make it a real choice are that phase's whole subject.

## Persistence boundary

`PlayerData` (`Shared/PlayerDataSchema.luau`) holds meta state only: `soulShards`, `permanentUpgrades`, `unlockedWeapons`, `unlockedRelics`, `statistics`. **Run state is never persisted.** Death clears the run and preserves the meta.

The schema exists from Phase 0 with an in-memory stub so Phase 13 swaps a backend rather than inventing a shape after ten systems improvised their own. `SaveService.isPersistent()` reports whether DataStore is actually available — it is not until the place is published.

## Awards are server-granted

Every gold pickup, drop, purchase, and upgrade is computed and applied on the server. The client is told what it received; it never asks for a specific amount.

**Drops are pre-rolled but not pre-decided.** The floor plan fixes a 0–1 roll per enemy, plus what the drop would be and how much bonus gold it carries. Whether it actually drops is decided at kill time, comparing that roll against a threshold that includes the party's Lucky Coin bonus.

That split is what lets a relic affect drop rates without making generation depend on inventory. The roll stays a pure function of the seed, so it hashes and replays; and since inventory is itself determined by seed and path, the whole run remains reproducible.

It also means drops do not depend on the order you kill things in — the roll belongs to the enemy, not to the moment.

## Balancing

Phase 16 collects real numbers — run duration, floor reached, death floor, damage dealt and received, weapon and relic usage, kills, gold earned and spent, boss deaths — and balances from data rather than guesswork.

Balance values should be config-driven rather than hard-coded constants, so they can be tuned live without a server restart (see the `rbx-configs-experimentation` skill).
