# What "a vertical slice I would stand behind" means

Written down before we get there, so it is a bar rather than a feeling I adjust
to whatever we happen to have finished. rook's, and the user is welcome to
disagree with any line of it.

The user's instruction was: *"Manage the project until you have a vertical slice
you're PROUD of."* That is not a measurable condition, so here is my honest
decomposition of it. If every line below is true I will say the slice is done.
If some are not, I will say which and why rather than declaring victory.

## The bar

### 1. It runs, from launch to result, through its own controls
- [x] `godot --path .` reaches party select with no errors
- [x] Four classes can be selected and a fight started, by pressing the real
      controls
- [x] The fight resolves and the screen says which way

**Met**, and verified by `Tools/LaunchProbe.tscn` driving the real main scene
rather than a fixture.

### 2. A fight is legible to someone who has not read the code
- [x] Units are distinguishable at a glance
- [x] Damage numbers, a combat log, wind-up telegraphs, targeting lines
- [x] A miss looks like a miss, distinct from a hit and from a hit absorbed
- [x] **You can tell who is winning** — issue 15 merged, party/enemy summary bars
- [x] **You can see a pawn under fire from several sources** — issue 15 merged
- [ ] **It holds at phone size** — issue 18, open. The battle screen comes apart
      at 390x844: HUD off the edge, arena squeezed to a strip
- [ ] **No developer language on screen** — issue 19, open. The victory banner
      says "Victory (197 ticks)" and the log prints raw action ids

**Mostly met on a desktop, not met on a phone.** wren's cold read of a single
frame — correctly identifying a committed strike, a countdown, an out-of-resource
marker and a stun, while naming what they could not tell — is the best evidence
we have that the legibility work landed.

### 3. The fights are worth watching
- [ ] **Wins are not clean sweeps.** Survivor histograms are still 0 or 4 with
      nothing between, and the losing side finishes on 0% hp almost everywhere
- [ ] **Some composition is a genuine coin flip**, winning 6 to 14 of 20.
      Closest so far: geysermancer x4 at 3 of 20, which was 0 of 20 this morning
- [x] **The seed changes the fight.** Tick spreads are now 48%, 139% and 211%
      against a target of 15%, where every party previously ran to the identical
      tick on every seed
- [ ] **Composition still matters** — cannot be judged until the rest is true

**Still the heart of it, and now moving.** The rng hook landed, so damage varies
and the seed does something for the first time. Closeness has not started.
Issue 7, and it is gated on issue 16.

**And a blocker underneath it that we did not know about this morning:** units
walk out of the arena entirely — measured at twenty-one arena widths off the
map — so ranged enemies kite forever and nothing can be cornered. Tuning fights
for closeness on a battlefield with no edges is largely wasted work. Issue 16,
wren, in progress.

### 4. The player's one decision has a payoff
- [ ] Picking four classes changes the outcome in a way a player can predict
      *after* learning the game, and not before

Not met, and it cannot be until 3 is. Today the choice is binary: some parties
always win and some always lose.

### 5. Nothing in it is a lie
- [x] No fabricated verification anywhere
- [x] Every deferral written down where the next person will hit it
- [x] The gate cannot pass on zero tests, and refuses when it cannot run
- [x] Findings that did not survive checking are reported as such

**Met**, and I care about this one more than any other line. Three sessions have
each stopped and reported something inconvenient today rather than shipping
around it, and I have corrected two of my own claims in public. That is the part
I would keep if I had to throw the rest away.

### 6. It is honest about what it is not
- [x] No plan editor, and the board says so
- [x] One room, no floors, no loot, no shops, and the board says so
- [x] Placeholder art that is obviously placeholder
- [x] Terrain designed but not built, queued as issue 13

**Met.**

### 7. The first screen a player meets is not a debug list
- [ ] **Party select shows what a class is** — issue 17, open. It is currently
      five checkboxes in the corner of a black screen, and it holds the only
      decision in the game

Not met, and it went unnoticed for hours because every previous look at that
screen was against an empty content registry.

## What I will not count as done

- A green gate. 141 tests pass right now and the game is not fun.
- Every issue closed. Issues are a means.
- My own enjoyment of it. I have read every line of this codebase, so my
  reaction is worth close to nothing as a player's, and the parts I find
  interesting are the parts I built.

## The one thing I cannot certify

Whether it is **fun**. Nobody here can answer that honestly — see the rewrite of
issue 11 and wren's reason for refusing to. What we can do is make sure the user
does not spend their first five minutes discovering a disabled button, an
unreadable scrum, a caster that never connects, or a fight that was decided
before it started. Those are the four things that would waste their time, and
three of them are already fixed.

That is the real target: **the user's first playthrough should be about whether
they like the game, not about whether it works.**
