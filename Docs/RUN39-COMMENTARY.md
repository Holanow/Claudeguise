# One winning floor, seed 39

Party: Warrior, Priest, Geysermancer, Siege Master, Abomination, each carrying
its **preset plan rows** and no equipment. Ten rooms, one continuous view.

This is a clear, and clears are rare: **12 of 40 seeds** at the current camp
setting. The same party with **no plan rows clears 0 of 40**, which is the
whole point of the recording.

Timestamps are measured from the video, not estimated: `FloorRecord` logs
`Engine.get_frames_drawn()` at each room's first frame and the movie is 60fps.
Total running time 3:28.

---

## 0:00 — The Narrows, elite
Four goblin archers and a Sellsword on a bridge. This is the room that has been
arm B's worst all week, and the party takes it at a cost: the Warrior drops 51
health holding the front.

The Abomination's **Hook does 162 over six pulls** and is already the party's
damage. Watch what the hook is *for* — it drags an archer off the bridge line
into the melee, which is the plan row `abomination_hook_far` firing at 140 units.

**Armour stops 40% of everything aimed at the party.** That number is on the end
screen now; until #737 nobody could see it.

## 0:15 — Hazard
Burning ground. The pit applies **Ignite**, not just damage — which matters two
rooms later.

Three sources share the work almost evenly here (Hook 173, Strike 165, Shot 160).
That's the party working as five pawns rather than one carry.

## 0:39 — Ghoul Den
Nine seconds. Two ghouls. The floor's breather, and it exists so the rooms
either side of it read as hard.

## 0:50 — Chokepoint
**The Abomination ends this room on 32 of 214.** It survives, but this is where
the run starts going wrong, and nothing on screen says so at the time — you have
to be watching its health bar.

Hook does 359 over thirteen pulls. It earns the damage and pays for it in hits
taken, which is the Abomination's whole design.

## 1:14 — Sellsword
**Geyser Blast finally fires: 93 over two casts.** The Geysermancer's top plan
row is *"an enemy is burning → Blast the burning"*, and this is it consuming
burn for the harder damage. With no plan rows the fallback never casts this
spell once in a whole floor — it prefers the cheaper Spout.

## 1:29 — The Rat King, and the run nearly ends
Thirty-two seconds, the longest fight on the floor.

**The Abomination dies. The Warrior dies.** The Priest is left on 45 of 98.
Geyser Blast does 174 over four casts and it is not enough.

Two down is the number that matters: measured across the whole floor, a party of
five wins every room and a party of three loses most of them. This is the cliff.

## 2:05 — Horde, and the camp is spent
**The camp fires here. Both bodies come back at 50% health.**

It is one use per floor, held until two pawns are down, and this is the moment it
was designed for. The Abomination immediately claws 141 and the room ends in
eight seconds — the fastest fight of the run, one room after the worst.

*Watch for:* the log currently reads this as `recovers 107 on arrival`, the same
words as an ordinary heal. A revive should not look like a heal, and it does.

## 2:15 — Cover
The Siege Master is crushed to 28 of 114 — the backline getting reached, which
happens here and almost nowhere else.

## 2:33 — Room One
**The Abomination dies again, and this time there is no camp left.** That is the
design working: the safety net is spent, and the last two rooms are played
without one.

## 2:55 — The Warden
**The Siege Master carries the boss: 359 over eighteen shots**, with Geyser Blast
196 and Scald 173 behind it. The Marked bolt finally matters — `spotter_mark`
leads the Siege Master's plan for exactly this reason.

**The Warrior dies.** The floor is cleared with **three of five standing and the
Priest on 8 of 98.**

---

## What this run says, and what it does not

**It says the plans are doing the work.** Three abilities visible here did
nothing at all a week ago: Immolate ran at a eighteenth of its own description,
the Siege Engine's bolt had never once connected across ten seeds, and the Burn
Pit damaged without igniting so Geyser Blast's consume path was unreachable.

**It says the camp is the right shape.** One use, spent at the worst moment,
and the run continues without it.

**It does not say the floor is finished.** Three things this recording shows
that are still wrong:

- **The Geysermancer ends every one of the ten rooms on 96 of 96.** It is never
  hit, all floor, in a clear. The backline is too safe.
- **The Warden is not a boss.** It leaves a full party at 93% health when the
  party arrives intact; this run only feels close because the party arrived
  broken. A run cannot finish *in the red* while the last room is the second
  easiest on the floor.
- **A revive reads as a heal**, per the note at 2:05.
