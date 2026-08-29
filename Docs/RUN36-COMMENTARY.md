# One winning floor, seed 36, a party of four

Party: Abomination, Priest, Siege Master, Warrior, each carrying its **preset
plan rows**. Ten rooms on a generated grid floor, one continuous view.

This is a clear, and clears are earned: **15 of 40 seeds, 38%**, for this
composition. The same four pawns with **no plan rows clear 0 of 40** — and have
never cleared once, in any configuration measured this week.

Timestamps are measured from the video, not estimated: `FloorRecord` logs
`Engine.get_frames_drawn()` at each room's first frame and the movie is 60fps.
Running time 3:36.

---

## 0:00 — The Narrows, elite
**Armour stops 55% of everything aimed at the party**, the highest reading of
the run. The Abomination's Hook does 306 over nine pulls and is immediately the
party's damage.

Note the room is not the one that was authored. Every room now scales to the
party actually present — a floor written for five pawns presenting its authored
difficulty to four.

## 0:16 — Chokepoint
Hook again, 295 over thirteen. `spotter_mark` appears in the top three, which is
the Siege Master's plan doing its job: Mark leads its rows because the engine's
bolt is marked-only and has nothing to shoot at otherwise.

## 0:38 — Sellsword · 0:55 — Horde · 1:07 — Hazard
Three rooms the party takes cleanly, and the run looks comfortable. The Warrior
is at 181 of 246 leaving the Hazard.

Watch the Abomination's health across these three rather than the fights: 168,
160, 144. Nothing dramatic happens and it is losing ground the whole time.

## 1:27 — The Rat King, and the run nearly ends here
**Sixty seconds. Four times the length of any other room on the floor.**

**The Abomination, the Priest and the Warrior all die.** The Siege Master
finishes the fight alone, having done 554 over thirty-one shots — more damage
than any pawn deals in any other room of the run.

Three of four down. One more and the run is over.

## 2:31 — Ghoul Den, and the camp is spent
**The camp fires. All three come back at 50% health.**

One use per floor, held until two are down, and this is the moment it exists
for. It is also spent — the last three rooms are played without it.

*Two things to watch for, both defects:* the revive reads in the log as
`recovers N on arrival`, the same words as an ordinary heal — the most important
mechanic on the floor is invisible at the moment it fires. And the item that
drops here is a **censer**, which the code records as granting nothing.

## 2:44 — Room One · 3:01 — Cover
The Abomination bottoms out at 49 of 214 in Room One, then recovers to 188 in
Cover — the between-room heal is 50% of missing health now, so the worse the
shape, the more it gives back.

Cover is the room that was killing 40% of all runs three days ago. It is now a
room the party walks through.

## 3:16 — The Warden
**The Abomination dies killing it.** Grapple does 249 over three, the single
hardest thing any pawn does all run.

The floor is cleared with **three of four standing** — Priest 95/98, Siege
Master 105/114, Warrior 184/246.

---

## What this run says, and what it does not

**The plans are the difference and it is not close.** These four pawns without
plan rows have never cleared this floor, in any of the eight configurations
measured this week. With them, 38%.

**The camp is the right shape.** One use, spent at the exact moment three pawns
died, and the last three rooms played without a net.

**It does not say the floor is finished.** Three things this recording shows
that are still wrong:

- **The Warden is not a boss.** Fourteen seconds, and it leaves three pawns
  standing at 97%, 92% and 75%. A run cannot end in the red while the last room
  is one of the easiest on the floor.
- **Every item that drops is a censer, and the censer grants nothing.** The loot
  count is healthy at 1.65 a run; the substance is zero. With `main_hand`,
  `body` and `off_hand` filled and no head items in the game, it is the only
  item in a fourteen-item library that can land.
- **A revive still reads as a heal**, per 2:31.

**And one honest correction.** The sweep that picked this seed reported it
ending with one pawn alive at 9% health. The recorded run ends with three alive.
The sweep walks the floor in a different order than the game does, so its per-seed
final states do not describe what a player would see. The clear *rates* are
unaffected — both arms are read the same way — but that ordering difference is
worth an issue.
