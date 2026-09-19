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

Rooms per floor stay limited on purpose — it keeps procedural generation debuggable.

## Room types

Combat (fight), Elite (harder enemy, better reward), Treasure (no combat, choose one reward), Healing (restore), Shop (spend gold), Event (something unusual). Six is enough.

## Seeds

Every run is seeded and the seed is visible in-game and logged. Same seed ⇒ identical run. This is the backbone of the QA process: every bug report carries a seed, and `/repro <seed> <floor>` replays it exactly.

## Version 1.0 target

20 floors, 2 biomes, 2 bosses, 6 enemy types, 6 room types, 5 weapons, 15–20 relics, 20 permanent upgrades, 1–4 player co-op.

## Biomes

**The Forgotten Crypt** (floors 1–10) — stone, candles, bones, underground architecture. Enemies: Skeleton, Archer, Cultist. Boss: The Warden.

**Cursed Forest** (floors 11–20) — different rooms, enemies, hazards, music, boss. Not built until 1–10 is genuinely playable.

## Co-op

1–4 players enter the tower together. Enemy HP scales 100 / 160 / 220 / 280%, but scaling is not a flat multiplier — enemy count, elite chance, rewards, and boss mechanics all adjust. Services are written player-agnostic from Phase 0 so this is tuning, not rearchitecting.

## What we are not building

Not an MMO. Not a giant RPG — permanent progression stays restrained on purpose. No monetization until the MVP loop is proven fun.
