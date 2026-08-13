# Issue 25: find out why siege_master x4 never gets hit

**Assigned to: wren. This is an investigation, not a fix.** The fix, if one is
needed, is teal's in `Scripts/Content`. What is missing is evidence, and right
now the only thing anybody has is my suspicion.

## The situation

`siege_master x4` wins 20 of 20 on `floor1_room1` and finishes on **98%** of its
health. Five other compositions on the same table now win at a real cost or lose
interestingly. That one row did not move when regeneration, the bestiary,
placement, affordability fall-through and focus bias all landed.

## What I think is happening, and why you should not trust it

`siege_master` fires at range 260, the longest in the game. Every enemy in
`floor1_room1` closes to attack. So four of them may not be *winning* the fight
so much as *declining* it: standing at the back, out-ranging a room where nothing
punishes distance.

**That is a story I made up from two numbers.** I have told all three of you
tonight that a manager's background claim is the least reliable thing in an
issue, and this is one. It is also exactly the kind of plausible mechanism that
gets built around and turns out to be wrong — I have been wrong twice tonight
about causes that sounded this good, including predicting that arena walls would
close the closeness gap.

## What to measure

You own the simulation, so you can see things nobody else can. Instrument and
report, do not change behaviour.

1. **Distance over time.** For each `siege_master`, its distance to the nearest
   living enemy, every tick. Does it ever get approached? Is there a stable
   standoff distance, and what is it?
2. **Who is even trying.** Which enemies pick a `siege_master` as their target,
   and how far do they get before dying or giving up? If the goblins die on the
   way in, the ghoul is the only thing that could ever reach them.
3. **Where the damage goes.** Total damage dealt by each enemy, and how much of
   it lands. If the archers and the cultist are the only ones connecting, the
   melee half of the room is decorative against this party.
4. **The same three, for a party that does bleed** — the balanced one at 23% hp —
   so there is a contrast rather than a single trace. A number is not a finding
   without something to compare it against.

## What to report

A short write-up on the board, with the traces. Then say which of these it is:

- **They are never approached.** My guess. If so, the answer is a room that
  punishes distance, which is teal's, and terrain's line of sight is probably the
  cleanest version.
- **They are approached and win anyway.** Then range is not the mechanism and the
  answer is somewhere else entirely — say so, because that kills the plan I have
  already half-built around it.
- **Something neither of us has thought of.** The most likely outcome, on
  tonight's record.

## Files

`Scripts/Combat/**` and `Tests/test_combat_*.gd` for anything permanent. A
throwaway script under `Tools/` is fine for the trace itself — teal has been
using that pattern all night and it works.

**Change no behaviour in this issue.** If the instrumentation shows a defect in
the simulation rather than in the content, that is a separate issue and I would
rather you stopped and told me than fixed it inside an investigation.

## What would make stopping the right answer

Finding that my premise is wrong within ten minutes and saying so in one line.
That is a complete and successful outcome for this issue.
