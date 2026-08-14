# Playtest notes, round two

The player's second playthrough, noted live. **The goal they set with it:**

> "the goal at the moment is to try and get single room combat *super satisfying
> and fun* I should be eager to try out every team combination"

Everything below is read against that. A note that does not make one fight better
to watch, understand, or replay with a different party is not urgent right now.

**The correction that reorders the list:**

> "This and the last comment are part of making the single room combat excellent
> before moving onto stringing rooms together"

I had held the post-fight summary and pre-fight positioning behind the run spec,
on the grounds they happen between fights. **That was wrong.** They are about
making one fight good, not about stringing fights together, and holding them cost
the player two playthroughs of raising the same note.

---

## The fight is unreadable

The largest cluster, and the one that most directly serves the goal.

1. **Fights are too fast to read — roughly half speed.** Everything is
   denominated in ticks at 30 per second, so this is likely one constant and it
   moves every balance number we have. **Nobody re-tunes balance until it lands**,
   or the pass is wasted.
2. **No clear visual for who is afflicted with what.** Statuses are currently
   legible only from the log, which scrolls, and which is also too fast to read.
3. **Countdowns should be progress bars, with an icon at the end showing what is
   coming.** The wind-up ring shipped hours ago; the substrate survives (the
   post-haste tick total, the damage-type colour, the timing) and only the
   presentation changes. **The icon is the better half of the note** — a ring says
   something is coming, an icon says what.
4. **On pause, hover any unit and inspect it.** Health, resource, statuses, what
   it is doing, what it is about to do. Pause is becoming the mode where the
   fight is actually read, which the speed note reinforces.
5. **Pause needs to be obvious** — grey the screen or similar. Nothing currently
   indicates it.

## The log

6. **Positive statuses use affliction language** — the Warrior is *"afflicted
   with Shielding"*. `CG.is_harmful()` already classifies exactly this; the log
   simply never asks.
7. **Every non-damaging action reads as an attack for zero damage** — a summon is
   the caster punching itself, a buff is the Priest attacking their own ally.
   Filed separately as issue 74.
8. **The log is too large.** Move it to a bottom corner, out of the way.

   Worth stating plainly: this reverses a layout an independent playtest once
   named as the one thing not to change. **That verdict was about the old build**,
   before larger units, travelling projectiles, attack visuals and hover existed.
   The log was carrying most of the game's legibility then and had earned its
   third of the screen. It no longer is, and the space is wanted for statuses,
   progress bars and unit inspection.

## Single-room combat, wrongly deferred

Both raised in round one, both held by rook behind the run spec, both actually
about one fight.

9. **No way to review the event log after a fight, or a summary of pawn
   performance.**
10. **No way to position pawns before a fight.** The deploy zone exists, the level
    editor already draws it, and `Encounter.party_spawns` already carries
    positions.

## Behaviour

11. **The Abomination runs away a lot. Tanks should move toward enemies.** Likely
    the kiting branch in the shared decision code treating a mid-range hook as a
    ranged weapon and backing off — exactly wrong for a class whose job is to
    close, hook, and hold. That code path decides approach and retreat for
    everyone, so a fix there touches every class.

## Things rook reported as fixed and are not

Both are rook's to re-investigate, and both are the same failure rook has flagged
in other people's work all day: **checking the artefact instead of the screen.**

12. **Siege engines are still invisible.** rook added a silhouette and verified
    *the shape existed in the registry* — never that a summoned engine draws it in
    a real fight. The real cause is therefore something else, most likely that a
    mid-fight summon never gets a view node at all.
13. **Hover definitions are missing on the Inspect classes screen** — *"the most
    important place for it to be"*. The PR reported wiring `InspectPanel.gd`. If
    it is not reaching the terms the player hovers, that is the eighth instance of
    built-and-unreachable on this project.

## Still outstanding from round one

14. **"Plans, in priority order" still appears on every class's inspect.** The
    general "how to play" has not replaced it.

## Forward-looking

15. **There must be a way to drop in artier UI elements later** — borders, icons.
    Unit art already works this way: a PNG in `Assets/Units/` replaces a unit with
    no code change, no import, no registration. **The interface has no
    equivalent** — every panel, button and border is drawn from code and colour
    constants. The same runtime-loading trick should work, and nothing does it
    yet. Worth building before there is a lot of interface rather than after.
