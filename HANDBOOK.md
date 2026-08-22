# How to build this game again

Order of operations, and the traps. Not much code — the code is in the repo and
you are rewriting it anyway. What is worth carrying over is the sequence, and
the things that cost us weeks.

## The one rule everything else follows from

**The simulation knows nothing about the screen.** It takes a state, steps it a
tick at a time, and emits events. Everything the player sees is built from those
events and nothing else.

Get this wrong and you spend a month untangling it. Get it right and the view
can never show a number it cannot explain, a fight replays from a seed, and you
can measure the game without rendering it.

    Content  ->  actions, classes, enemies, rooms
    Core     ->  the vocabulary all layers share
    Plans    ->  what a unit intends this tick
    Combat   ->  applies intents, resolves, emits events
    UI       ->  draws the events

Nothing points left to right except through that vocabulary.

---

# Part 1: one room

## Step 0 — the gate, before any game code

Write the thing that runs your tests and refuses to lie. Ours grew six checks
and every one was added the day something slipped past:

- **parse** — every script loads.
- **discovery** — a file named `test_*` outside the test directory is a failure,
  not a file that silently never runs.
- **tests** — and when a file fails to parse, report the count as **not
  trusted** rather than printing a smaller pass. We lost 233 tests behind a
  green line.
- **scene** — grep the run for missing-node errors. A screen that renders
  nothing passes every test that never looks at it.
- **comment block length** — see Step 9.

**A gate that cannot fail is not a gate.** For every check you add, break
something deliberately and watch it go red before you trust it.

## Step 1 — the vocabulary

One file of enums and constants: damage types, statuses, event kinds, teams,
tick rate. Everything imports it. Write it first and expect to read it
constantly.

**Ticks, never seconds.** The simulation counts ticks; seconds exist only in
text the player reads. Every duration bug we had came from mixing them.

## Step 2 — state and events

Two shapes: **the unit** (position, hp, resource, statuses, what it is doing)
and **the state** (units, terrain, tick, rng, outcome, events).

Then the event. Make it carry **everything a view could want to say**, not the
minimum today's view needs:

    kind, tick, source_id, target_id, action_id,
    amount, amount_before_mitigation, amount_after_mitigation, cause,
    status, source_plan

We shipped the raw roll and the applied figure and threw away the number
between them. Every reader then subtracted the wrong two and called the
difference mitigation — **13.4% of hits were mislabelled**, and a playtester's
loudest complaint turned out to be a target with 1 hp left, not armour.

**Put the rng in the state and seed it.** One seed, one fight, byte-identical
every time. Check it early and keep checking it; every measurement you take
later rests on it.

## Step 3 — the tick loop

    decide  -> each free unit produces an intent
    resolve -> intents become movement, actions, damage
    tick    -> statuses, cooldowns, regeneration, hazards
    check   -> is the fight over

Keep the phases separate and named. When something is wrong you will want to
know which phase it was wrong in.

**A busy unit does not decide.** Wind-up, recovery and channels all mean "not
free". Get this wrong and units re-decide every tick and finish nothing.

## Step 4 — one action, end to end

Not five. One. A melee attack: wind-up, fire, damage event, recovery.

Then write the test that says a fight between two units ends. **That test is
worth more than the next five actions.**

## Step 5 — the plan layer

This is the game. A plan is an ordered list of rows; a row is blocks:

    ACTION      what to do
    TARGETING   who to do it to
    MOVEMENT    where to stand
    CONDITION   when

A unit runs **the first row whose condition holds**, top down. If none holds, a
fallback decides.

Three things we learned expensively:

- **The fallback must be visible** — an immutable row the player can read but
  not edit. A pawn doing something the player cannot find in the plans breaks
  the loop twice: once when it happens, again when there is nowhere to change it.
- **Every block costs one, a condition costs zero, and the budget is an
  attribute.** Do the arithmetic by construction, from the block count, so no
  second copy can drift.
- **Start the editor empty and offer the presets as a library.** We shipped
  preset rows first; every class then sat exactly at its budget, so the Add
  button was always refused and the editor's central affordance was dead on
  arrival.

## Step 6 — content, and the reachability test

Now write five classes and a dozen enemies.

**Then write the test that fails when an action never fires in a real fight.**
Write it before you think you need it. We found seven mechanics that existed and
never fired — a block, an execute, a cleanse, a claw, a chain toss, a taunt
aura, and a movement block a player could not add. **Every one was found by a
probe. None was found by looking.**

What it catches:

- the fallback cannot reach ally-targeted, zero-power or sustained actions
- a row gated below the fallback's own threshold can never fire first
- an action listed after one that is always affordable never gets a turn

## Step 7 — the screen, events only

Arena, units, bars, and **a combat log that names the row which chose each
action**:

    Warrior begins Taunt [plan 3]
    Priest begins Bolt [no plan]

That tag is the most valuable thing on the screen. Four blind playtesters
independently used it to find a row worth changing.

**Two words, not one.** `[no plan]` when the editor is empty, `[default]` when
rows exist and all missed. We shipped one word for both and hid the difference
between "you wrote nothing" and "what you wrote did not apply".

**Then make units clickable**, and let the click answer everything: resource,
wind-up, target, who is aiming at it, statuses with time left. Two testers
called ours the best thing in the game — and **six never found it**, because the
click target was an 11px body under a 20px name plate.

## Step 8 — measure before you tune

Build these before touching a balance number:

- a **sample runner** — every party against every room over many seeds, printing
  wins, health and fight length
- a **cost table** — what each room costs each party
- an **arena probe** — how much of the room the fight actually uses

**Then never change a number to move a win rate.** Measure, report, act — in
that order and separately. Every number we got wrong was got wrong by acting
first.

## Step 9 — comments, once, early

**A comment block keeps its first sentence.** Reasoning goes in the commit or
the issue, where it can be read on demand and cannot rot against the code.

We let it slide and removed **6,339 lines** in one pass. A 28-line block
insisted a field was "NOT YET WIRED" for days after it was wired. Enforce it in
the gate; ours fails any block over ten lines.

---

# Part 2: the first floor

Do not start until one room is genuinely good. Ours took seven blind playtests,
and the last four were the ones that mattered.

## Step 10 — what "good" means, and how you know

The bar: **watch a fight without pausing, broadly follow what happened and why,
and want to do it again.**

**The only instrument for that is somebody who has never seen the code.** Not
you. Give them the build and ask one thing specifically: *did you finish a fight
holding a complaint you could act on, and did acting change the fight?*

What ours found that no test could:

- name plates larger than the units, landing on the wrong unit
- the default settings hiding the game — one checkbox made it legible
- a promise printed on screen the player could not fulfil
- the log drowning in one repeated line for a third of a fight

## Step 11 — rooms, then a floor

A room is enemies, spawn points and terrain. That is all it needs to be.

**Terrain earns its place or it goes.** Ours had a colonnade whose pillars sat
200 units from where anyone fought. The measurement that found it compared the
room against **the same room with the terrain removed** — keep that control, it
is the only honest comparison.

**Watch the enemy count.** A fight collapses into roughly the same small area
whatever the room, because ranged units settle at their commit range and melee
at contact. **Ten enemies land in the space five do.**

## Step 12 — the floor

Only now: a sequence of rooms, resources that persist between them, and a reason
to pick one room over another.

**Everything you deferred arrives at once here** — healing between fights,
whether a run can be lost, what carries forward. Write each one down as you
defer it.

---

# The five traps, in the order they will bite

**1. An instrument that measures the wrong thing.** Eight times for us. A test
measured polygons after the renderer switched to sprites. A tool picked classes
alphabetically and could never photograph the fifth. A probe called the decision
layer to observe, consumed the rng, and changed the fight it was measuring. A
pixel diff compared two *moments* rather than two *states*, and the floaters had
animated between them.

**Ask what object, and what moment.** Then break the instrument deliberately and
confirm it notices.

**2. A test green for a reason unrelated to its name.** Seven of ours. A fixture
set hp to zero expecting a unit to die; `alive` was a stored flag and it did
not. A threshold passed because the world drifted past it. **Compare against a
control arm, not a constant** — a control moves when the world moves.

**3. A mechanic that exists and never fires.** Seven. Test reachability from day
one.

**4. Guessing a default instead of giving the player a word.** We tried three
times to make units leave burning ground automatically. Two attempts were
bit-identical to no change; one was aimed at a population of zero. Then we added
a condition — "standing on harmful ground" — and a playtester used it within one
session.

**5. Fixing the number instead of the cause.** The fight was too easy at 1.7%
losses and every candidate fix was a balance edit. The real fix was structural —
start the plan editor empty — and losses went to 9.2% with no number moving.

---

# What to carry over, honestly

**Keep:** the layering, events as the only channel, seeded determinism, the
plan-block vocabulary, the `[plan n]` log tag, the click inspector, the gate.

**Rewrite:** the UI. Ours is 7,475 lines against 990 of Core and 1,398 of
simulation, and that ratio is the whole story of where the time went.

**Do earlier:** the reachability test, the blind playtests, the comment rule.
All three are cheap on day one and expensive on day ninety.
