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
- [x] Units are distinguishable at a glance, at phone size
- [x] Damage numbers, a combat log, wind-up telegraphs, targeting lines
- [x] A miss looks like a miss, distinct from a hit and from a hit absorbed
- [ ] **You can tell who is winning** — issue 15, open
- [ ] **You can see one pawn being focused by three enemies** — issue 15, open

Not met. This is the one I would be most embarrassed to hand over, because the
dynamic that decides every fight is invisible.

### 3. The fights are worth watching
- [ ] **Wins are not clean sweeps.** Median survivors 2 or 3 of 4, not 4
- [ ] **Some composition is a genuine coin flip**, winning 6 to 14 of 20
- [ ] **The seed changes the fight.** Tick counts vary by 15% of the median
- [ ] **Composition still matters.** Best party beats worst by a wide margin

Not met, and this is the heart of it. Currently every party wins 20/20 with four
survivors or loses 20/20 with none, and the seed does nothing. Issue 7.

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
