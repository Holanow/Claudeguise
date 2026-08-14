# Release 2

## Run it

```
"D:/Projects/Claudeguise-team/tools/godot/Godot_v4.7.1-stable_win64.exe" --path D:/Projects/Claudeguise
```

**Forward slashes on purpose.** With backslashes this fails as
`Invalid project path specified: "D:ProjectsClaudeguise"` — an unquoted
Windows path is eaten by the shell, which reads each `\` as an escape and drops
it. Quoting the `--path` argument also works; forward slashes work everywhere
and need no quoting, so that is what is written here.

Every screen was swept on this build and works. Screenshots of all nine are in
`Screenshots/sweep_*_1280x720.png` if you want to see what I saw.

## What changed since you last played

Grouped by the note you raised, so you can check whether the answer was right.

### The fight should be readable

- **Fights run at half speed.** One tick-rate constant, so every timing relation
  is exactly as tuned. **Projectiles are half speed again on top of that**, at
  your request, so shots are four times slower on screen than they were.
- **Wind-up countdowns are progress bars with the ability's icon at the end.**
  You have already seen and liked these.
- **Status effects are badges on the unit.** Beneficial sits on an upward plate
  with a green rim, harmful on a downward plate with a red rim, so the split
  reads without knowing the icon.
- **Pause dims the screen**, and you can hover any unit while paused.
- **Positive statuses stopped reading as afflictions.** The Warrior "gains
  Shielding" rather than being "afflicted with" it.
- **Non-damaging actions stopped logging as zero-damage attacks.** A summon is
  no longer the caster punching itself.

### Things that were broken and now work

- **Siege engines are visible.** They were never drawn at all: unit views were
  built once at the start of a fight, so anything summoned later fought,
  took damage and died invisibly. **This was true of every summon, not just
  engines.**
- **Hover definitions work on the Inspect screen**, which you called the most
  important place for them. They were unreachable because `Label` defaults to
  ignoring the mouse where a plain control does not.
- **Siege engines are artillery now.** Unlimited reach, slow, immobile, and they
  only fire at marked targets. Before this, **65% of them never fired once** —
  they were built behind the fight, out of range, and cannot move.
- **Two abilities that could never fire now can.** The Warrior's Execute cost
  more Rage than a Warrior can hold, and the Geysermancer's Scald sat entirely
  inside another spell's window.

### New things to try

- **Four rooms with different layouts and rosters.** Terrain exists: walls,
  pillars, hazards and pits.
- **Plans are rows of blocks** — skill, target, condition — and you can **add
  and remove them**, not just reorder. Every pawn has an immutable last row
  showing the fallback it uses when nothing else matches.
- **Equipment.** Seventeen items, three slots, on a pre-fight screen. **Plate
  Mail grants Directional Block**, which is no longer a Warrior class ability.
- **Any popout can be pinned with right-click and dragged**, so you can hold two
  open and compare them.
- **The Geysermancer can strip harmful statuses.** Rarely useful today, which is
  known and measured, not an oversight.

## Known and not fixed

Listed so you do not spend notes on things already caught.

- **The Warrior's Directional Block is still invisible, and I told you it was
  fixed.** The block now emits an event, which is what I reported. But
  `CombatLogView` returns an empty string for that event kind and the caller
  drops empty lines, **so nothing reaches the screen.** swift found this by
  running the events through the renderer rather than reading the code, and
  they found it in their own merged work. The same is true of the sustained-
  action events. Correcting it here because "it is in the event stream" and "a
  player can see it" are not the same claim, and I passed the first off as the
  second.
- **The equipment screen draws no icons.** The art exists and nothing calls it.
- **Unit name labels overlap** where units meet. The arena is not too small —
  a fight uses about half of it — they simply pile up at the point of contact.
- **The log still takes the right third of the screen.** Moving it to a corner
  is queued.
- **There is still no post-fight damage summary**, which you have asked for
  twice. Queued.
- **You cannot position pawns before a fight yet.** Queued.
- **"Plans, in priority order" now appears once** at the top of Inspect rather
  than on every class.
- **No sound at all.** Hooks are being built now; you said composition later.

## What I would look at first

Your own definition of done: *watch a fight without pausing and broadly follow
what happened and why.* The half-speed change and the progress bars were aimed
straight at that, and nobody has checked whether they were enough.

**Balance is deliberately untouched.** Every number in the game was measured on
pawns wearing nothing, and equipment landed hours ago, so the whole table is
known to be provisional. Notes about difficulty are welcome but that is why it
has not been tuned.
