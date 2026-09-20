# Game design

## Pitch

A fast roguelite tower climber. Choose a door, fight, loot, upgrade, and climb. Every 10 floors, face a boss. Die, keep some progression, and try again.

Each floor is a small encounter, not a large map. The player starts at Floor 1 and tries to get as high as possible.

## Setting

Decided mid-build, deliberately before more content accreted on the old assumption: **the tower is a dead machine, not a dungeon.** Cyborg / industrial-apocalypse, in the spirit of MÖRK BORG — bleak, high-contrast, a little cruel, more chrome and rust than fantasy stone. You are not climbing a crypt; you are climbing the corpse of something that used to compute.

This changes what a room *reads as*, not what it *is*. The architecture stays exactly what Phases 0–10 already built — sealed rooms, two doors, encounter then reward then exit — because that structure was never fantasy-specific. What moves is the skin:

- Internal `kind` identifiers (`Skeleton`, `Archer`, `Boss = "Warden"`, ...) stay as stable technical names — they're load-bearing for `RoomConfig` encounters, loot tables and the seed's golden hash. **A player never sees a `kind` string.** What they see is `displayName`, rig colour/material, room trim and flavour text, and that's where the reskin lives.
- "Bone" becomes corroded plate. "Candles" become failing status lights. A dungeon's stone becomes a server-cathedral's scaffolding.
- A weapon swing, a dodge, a boss fight — the verbs don't change. Only what they're happening *to* does.

Applying a new setting through data (`displayName`, colours, materials) rather than renaming `kind` keys is possible only because of the Phase 0 decision that "content is Lua data, not Studio-authored instances" — the reskin is a diff, not a rebuild.

## The MVP

One run must work end to end before any content scaling:

> launch → Floor 1 → fight → choose a path → take loot → reach Floor 10 → fight the Warden → die → return to lobby → buy a permanent upgrade → start a new run

That is Phases 0–13. Everything after is content, polish, balancing, and retention.

## The MVP

One run must work end to end before any content scaling:

> launch → Floor 1 → fight → choose a path → take loot → reach Floor 10 → fight the Warden → die → return to lobby → buy a permanent upgrade → start a new run

That is Phases 0–13. Everything after is content, polish, balancing, and retention.

## Floor structure

A floor is Entrance → Encounter → Reward → Exit. From Phase 6 the floors form a small branching graph rather than a line:

```
        START
          │
     ┌────┴────┐
  COMBAT    TREASURE
     └────┬────┘
        ELITE
          │
         SHOP
          │
         EXIT
```

Each floor is one room, and clearing it opens **two doors offering two different seeded room types**. Which one you walk through is the choice the pitch promises, and it is recorded in the run's path.

Where a door leads is keyed on the room you are standing in, not just the depth — so arriving at floor 4 from a Treasure room can offer something different than arriving from an Elite. Keying it on the full history instead would make the run un-testable, since the number of possible paths doubles every floor.

## Room types

Combat (fight), Outpost (ranged-only fight — the Signal Sentry's room), Sanctum (the Signal Cultist's room), Elite (harder enemy, better reward), Treasure (no combat, choose one reward), Healing (restore), Shop (spend gold), Event (something unusual). Eight is enough.

## Seeds

Every run is seeded. The seed is shown in the HUD and logged, so a bug report can carry it without digging.

The guarantee is precise: **same seed *and same path* ⇒ identical geometry, encounters and rewards.** Which door you take is an input, not an output, so reproducing a run needs both halves — a report reads `seed:839271 path:1,2,1`. Combat outcomes still differ, because you fight differently.

Generation lives in `Shared/FloorPlan.luau` as a pure function of `(seed, depth, template)`, separate from the code that turns a plan into Instances. That split is what makes the reproducibility regression test pure arithmetic rather than a playthrough.

## Version 1.0 target

20 floors, 2 biomes, 2 bosses, 6 enemy types, 6 room types, 5 weapons, 15–20 relics, 20 permanent upgrades, 1–4 player co-op.

## Biomes

**The Corroded Choir** (floors 1–10) — a dead server-cathedral: rusted plate, exposed cabling, failing neon votives instead of candles, corridors that used to route signal instead of pilgrims. Enemies: Rust Husk (`Skeleton`) — a trade, stand and fight — Signal Sentry (`Archer`) — a tripod targeting drone, fires a neon rail-bolt from range, punishes standing still — Signal Cultist (`Cultist`) — a zealot that rushes and overloads its own battery on contact range, punishes standing *close*, its fuse a torso that heats to warning red as it counts down — and Chrome Husk (`SkeletonElite`), the same trade as the Rust Husk with the numbers turned up. Three enemies, three different reasons to move: back off, close in, or get clear. Boss: The Warden — reads equally well as a crypt guardian or a mad overseer AI, so it needed no rename, only a re-read.

**Biome 2** (floors 11–20) — different rooms, enemies, hazards, music, boss, same setting family as biome 1 rather than the original "Cursed Forest" (that name was written before the setting pivot and no longer fits). Not built until 1–10 is genuinely playable.

## Co-op

1–4 players enter the tower together. Enemy HP scales 100 / 160 / 220 / 280%, but scaling is not a flat multiplier — enemy count, elite chance, rewards, and boss mechanics all adjust. Services are written player-agnostic from Phase 0 so this is tuning, not rearchitecting.

## What we are not building

Not an MMO. Not a giant RPG — permanent progression stays restrained on purpose. No monetization until the MVP loop is proven fun.
