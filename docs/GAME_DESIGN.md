# Game design

## Pitch

A fast roguelite tower climber. Choose a door, fight, loot, upgrade, and climb. Every 10 floors, face a boss. Die, keep some progression, and try again.

Each floor is a small encounter, not a large map. The player starts at Floor 1 and tries to get as high as possible.

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

Combat (fight), Elite (harder enemy, better reward), Treasure (no combat, choose one reward), Healing (restore), Shop (spend gold), Event (something unusual). Six is enough.

## Seeds

Every run is seeded. The seed is shown in the HUD and logged, so a bug report can carry it without digging.

The guarantee is precise: **same seed *and same path* ⇒ identical geometry, encounters and rewards.** Which door you take is an input, not an output, so reproducing a run needs both halves — a report reads `seed:839271 path:1,2,1`. Combat outcomes still differ, because you fight differently.

Generation lives in `Shared/FloorPlan.luau` as a pure function of `(seed, depth, template)`, separate from the code that turns a plan into Instances. That split is what makes the reproducibility regression test pure arithmetic rather than a playthrough.

## Version 1.0 target

20 floors, 2 biomes, 2 bosses, 6 enemy types, 6 room types, 5 weapons, 15–20 relics, 20 permanent upgrades, 1–4 player co-op.

## Biomes

**The Forgotten Crypt** (floors 1–10) — stone, candles, bones, underground architecture. Enemies: Skeleton, Archer, Cultist. Boss: The Warden.

**Cursed Forest** (floors 11–20) — different rooms, enemies, hazards, music, boss. Not built until 1–10 is genuinely playable.

## Co-op

1–4 players enter the tower together. Enemy HP scales 100 / 160 / 220 / 280%, but scaling is not a flat multiplier — enemy count, elite chance, rewards, and boss mechanics all adjust. Services are written player-agnostic from Phase 0 so this is tuning, not rearchitecting.

## What we are not building

Not an MMO. Not a giant RPG — permanent progression stays restrained on purpose. No monetization until the MVP loop is proven fun.
