# Handbook

How to read this repo, and the minimum you need to copy for a fight that runs.

## The shape of it

The simulation knows nothing about the screen. It takes a `CombatState`, steps
it a tick at a time, and emits `CombatEvent`s. Everything you see is built from
those events and from nothing else, so a view can never show a number it cannot
explain.

    Content  ->  defines actions, classes, enemies, rooms
    Core     ->  the vocabulary all three layers share
    Plans    ->  decides what a unit intends this tick
    Combat   ->  applies intents, moves, resolves, emits events
    UI       ->  draws the events

Read it in that order. `Scripts/Core/CG.gd` first: it is the whole vocabulary,
every enum and tuning constant, and nothing else makes sense before it.

## The MVP: 1,150 lines that produce a running fight

Copy these and you have a headless fight you can step and assert on. No screen.

**Core, 254 lines.** The data shapes. Almost no logic.

    CG.gd            111   every enum and constant. Start here.
    Terrain.gd        82   walls, pillars, hazards, line of sight
    CombatUnit.gd     38   one combatant's live state
    CombatState.gd    34   the whole fight at one instant
    ActionDef.gd      33   what an action does
    Intent.gd         27   what a unit decided to do this tick
    PawnData.gd       21   a player character
    CombatEvent.gd    19   everything reported outward
    EnemyDef.gd       15   an enemy type
    ClassDef.gd       14   a player class
    Projectile.gd     12   a shot in flight
    Plan.gd            8   an ordered list of blocks
    Encounter.gd       8   one room: who, where
    PlanBlock.gd       6   one row of a plan

**The simulation, 1,451 lines.** This is the actual game.

    CombatSim.gd         809   the tick loop. Everything happens here.
    PlanInterpreter.gd   342   runs a pawn's authored plan
    DefaultBehavior.gd   218   what a unit does with no plan
    SimDeps.gd            82   injected content lookups, so the sim stays pure

**Content, the minimum, 484 lines.**

    core_actions.gd      167   every action in the game
    Balance.gd           150   every tuning number and formula
    Registry.gd          112   id -> definition
    starting_classes.gd   68   the five classes
    floor1_enemies.gd     82   the bestiary
    PawnFactory.gd        23   builds a starter pawn

Skip for an MVP: `Scripts/UI` (4,200 lines), `Scripts/Art`, `Scripts/Floor`,
`EncounterCodec`, `LootTables`, `authored_rooms`.

## The five things that will bite you

**Ticks, never seconds.** Nothing below the presentation layer knows about
delta time. A float delta makes the same fight play out differently on a
different frame rate, and re-running a fight identically is a requirement.
`CG.TICKS_PER_SECOND` is 15.

**Events are the only output.** If a view needs to know something, the sim has
to emit it. `Intent.source_plan` existed for weeks, was computed every tick, and
was thrown away because no event carried it, which is why the log could not say
why a pawn acted.

**Pawns must never do anything the player cannot see in their plans.** The
binding design rule. `DefaultBehavior` is the exception and only because enemies
have no plans. Every time it has been forgotten it cost real work, and twice it
was mistaken for a balance problem.

**Ids are indices and never change.** `CombatState.units` is append-only; a dead
unit stays in place. Anything that iterates mid-tick depends on this.

**Art is baked, not drawn.** If a picture is the same every frame it is a PNG in
`Assets/`. Draw in code only where geometry follows live state: aim lines, bar
fills, wind-up lengths.

## Running it

    powershell -ExecutionPolicy Bypass -File Tools\gate.ps1

Parse, discovery, the full suite, and a comment-density check. It builds the
editor class cache first and refuses rather than passing if it cannot.

`Tools/SampleFights.gd` is the instrument for single-encounter measurement.
`Tools/FloorRuns.gd` is not, and using it to argue about one room has misled
people before.
