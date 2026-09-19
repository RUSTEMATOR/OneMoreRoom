# Economy

Two economies that never mix.

## Run economy — lost on death

**Gold** — spent during the run, in shops.
**Equipment** — Weapon, Armor, Relic. Three categories, no more.
**Temporary upgrades** — picked up during the run.

## Meta economy — kept after death

**Soul Shards** → permanent upgrades. Deliberately restrained: `+5% HP`, `+3% damage`, `+5% gold`, `+1 starting relic`. The game should not become a giant RPG where meta progression replaces skill.

## Relics

Relics are where procedural combinations get interesting, because they interact.

- **Blood Charm** — +10% damage when below 30% HP
- **Iron Heart** — +25 maximum HP
- **Lucky Coin** — +10% chance for additional loot

## Persistence boundary

`PlayerData` (`Shared/PlayerDataSchema.luau`) holds meta state only: `soulShards`, `permanentUpgrades`, `unlockedWeapons`, `unlockedRelics`, `statistics`. **Run state is never persisted.** Death clears the run and preserves the meta.

The schema exists from Phase 0 with an in-memory stub so Phase 13 swaps a backend rather than inventing a shape after ten systems improvised their own. `SaveService.isPersistent()` reports whether DataStore is actually available — it is not until the place is published.

## Awards are server-granted

Every gold pickup, drop, purchase, and upgrade is computed and applied on the server. The client is told what it received; it never asks for a specific amount. Drop rolls come from `Shared/Rng.luau` keyed to the run seed, so loot is reproducible from a seed like everything else.

## Balancing

Phase 16 collects real numbers — run duration, floor reached, death floor, damage dealt and received, weapon and relic usage, kills, gold earned and spent, boss deaths — and balances from data rather than guesswork.

Balance values should be config-driven rather than hard-coded constants, so they can be tuned live without a server restart (see the `rbx-configs-experimentation` skill).
