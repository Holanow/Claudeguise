# Playtest notes, 2026-08-13

The player's first full playthrough of the build, noted live while playing.
Recorded verbatim in intent, grouped by what they are rather than the order they
arrived. Nothing here is my paraphrase of what I think they meant.

**One is tabled by the player's own instruction and must not be worked on:**
note 17, the run.

---

## Things that are missing, not broken

These all exist in the simulation and have no path to the player. **That pattern
has now happened seven times on this project** — `EquipmentDef`, the wrong-room
encounter, treasure drops, the unreachable floor, uncalled recovery, two class
abilities, and now the projectile visuals. Every one looked finished from the
inside.

1. **The Warrior's directional block and the Abomination's hook and slow do not
   exist as abilities.** All three mechanisms are built, tested and merged; no
   action sets `pull_distance`, applies `SLOWED`, or grants `SHIELDING`. The
   Abomination's action list is unchanged from before its own rebuild.
   *(Issue 52, finch.)*
2. **Shots are simulated as travelling projectiles and the screen draws beams.**
   *"I'm still seeing beams and not projectiles."* Every ranged action travels at
   65 units per tick and nothing draws it.
3. **Siege engines were invisible** — no silhouette, drawing the unknown-shape
   fallback. *(Fixed, `af7e0a9`.)*
4. **Every class needs an attack asset or animation** so the player can tell what
   is happening.

## Balance direction

5. **Fights are too close.** A party of four should win most single battles;
   **losses should come from attrition.** This reverses the single-fight target
   the whole project was tuned to — wins costing 17-23% of the party with deaths
   in most fights. The individual fight should be comfortable; the floor should
   be what kills you.
6. **The Priest and the Siege Master need a basic attack that costs no resource
   and generates it instead.** Same trap the Abomination was in: a pawn that
   cannot afford its own actions stands still.
7. **The Priest needs two buff spells** — one for attack speed, one for damage
   resistance. Both have mechanism already: `HASTE` scales wind-up and recovery
   through a `SimDeps` seam, and `damage_reduction` is a field `Balance` reads.

## The game does not explain itself

8. **Everything needs descriptive terms.** What Poison does, what Burn does, what
   the stats mean, how far a range actually is.
9. **Every game term gets a hover info box** — class tags, statuses, stats.
10. **Inspect-classes should be replaced almost entirely by a hover popout**,
    not a separate screen.
11. **"Start Fight" and "Start Run" do not say what they do.**
12. **Not every class needs a plans-in-priority-order section.** There should be
    a general "how to play".

### Two copy rules, binding everywhere

13. **Just say what a thing does. No intent asides.** Their example, with the
    strike-through theirs: *"A reliable melee swing that costs nothing.
    ~~The Warrior's bread and butter~~"*
14. **Never use qualitative words for scale. Give specific, highlighted
    numbers.** Not "most", not "nearby", not "a real fraction".
    *"Absorbs 8% of every hit."*

**Rule 14 reverses guidance I gave the team.** I told engineers to write what a
thing does to the pawn rather than to the numbers — "Heavy, and slows you down"
rather than "AGI -0.15" — and the result is descriptions that read well and
cannot be planned with. Mine was wrong; the descriptions in the game now are the
product of my rule, not of carelessness.

## The plan system

15. **More conditions** — "the strongest enemy", "the enemy healer". Not
    necessarily from the start, but **found in Libraries.** This also gives
    Library a purpose; it is currently the one room type that resolves to
    nothing.
16. **Conditions should read as the editable sentence** — "an enemy within
    `[range]` units" with the selector inline. **Maximum range bounded by WIS.**
17. **WIS should also govern plan complexity** — more compounding conditions, or
    a higher ceiling on how elaborate a plan can be.

Together, 16 and 17 make WIS the plan-system attribute end to end: how far you
can specify, and how sophisticated a plan you can write at all. It is currently
one of the least load-bearing stats in the game.

## Interface faults

18. **The Start Fight button is not visible or clickable at the default aspect
    ratio.** The UI has to work on desktop **and** phone.
19. **The plan of action editor is visually broken** — section names overlap the
    options.
20. **The Goblin Archer's name flickers, and some enemies never get names.** A
    direct consequence of showing enemy labels only while focused or winding up.
21. **Siege engines are counted as allies on the end screen.** A summon is not a
    party member.
22. **After every combat**, the player wants to read the log plus a summary of
    which units dealt and took damage, and how much.

## Play

23. **The player should choose where their units start before a battle.** The
    deploy zone already exists, the level editor already draws it, and
    `Encounter.party_spawns` already carries positions.

## Tabled by the player

24. **The run is very broken.** *"It doesn't actually let me do a run, it just
    lets me click through a map without any feedback."* **The player is writing
    clearer guidance on what a run should look like. Nobody works on this until
    that arrives.**

## Explained, not a fault

25. **The Siege Master's art changed between launch and now.** True: I merged
    sable's pixel art while the player was mid-session, so the polygon was
    replaced under them.

---

## The process finding, which is worth more than any single note

> *"You should be taking screenshots of every screen to review."*

Both interface faults above shipped through review. Engineers screenshot the
screen they changed; **nobody sweeps every screen after a merge**, so each pull
request looked correct in its own frame while the build as a whole did not. A
screen nobody touched drifts unwatched.

That is now part of review rather than something a session does for its own
change.
