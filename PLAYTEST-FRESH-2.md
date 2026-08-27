# Playtest, cold, second fresh pair of eyes

No source read. No design docs read. Everything below is from screenshots of
`Tools/ScreenSweep.tscn`, `ContactSheet`, `IconsInFight`, `RoomPickerShot`,
`DeployShot`, `EquipShot`, `PopoutShot`, `SecondWindShot`, `ArtPreview`,
`AttackFXPreview`, `StackBadgeSheet`, `EquipmentIconSheet` at 1280x720 and
844x390.

---

## 1. What I think the game is

An auto-battler where **all of the play happens before the fight**, and the
fight itself is a replay you watch.

Reading it cold, the loop looks like:

1. Pick 4 of 5 classes on "Pick your party".
2. Optionally bolt gear onto them ("Equip your pawns") and write their combat
   AI ("Edit your pawns' plans").
3. Drag them onto the left band of the arena ("Place your party").
4. Press Start Fight and watch. You cannot touch anything except Pause.
5. Win, and you move along a floor map made of node types (Cell, Enemy, Trap,
   Miniboss, Boss) toward a boss.

The plan editor is the actual game. It is a top-down priority list of
`action / target / condition` rows with a budget, i.e. Final Fantasy XII
gambits. That screen is the most confident, best-explained thing in the build,
and it reads correctly on first contact. I understood "the first row whose
condition holds wins, the last row is a fallback you cannot edit" in one pass.
Good.

**Where I am probably wrong:** I have no idea what a "run" is versus a single
fight, what carries between rooms, what "Cell" or "Trap" nodes do, or what the
consequence of losing is. I never saw a fight resolve (see below), so the entire
back half of the loop is invisible to me.

---

## 2. Can I follow a fight? No.

This is the headline. **The fight screen is the worst screen in the build by a
wide margin,** and it is the screen the game is named after.

### Could I tell who was winning?

Only from the two summary bars top-left labelled Party and Enemies. Those work.
They are also the *only* thing that works — and they are parked in the corner,
far from the arena, so I was reading the corner and not the fight.

Inside the arena I could not tell. At tick 0 both sides are a scatter of
detached horizontal bars. Twenty units, twenty floating bars, nothing tying a
bar to a body.

### Could I tell why any unit did anything?

No. Never, at any moment, for any unit.

Units slide, a faint hairline appears between two of them, a number in an orange
circle pops, and text says "Miss". Which unit fired, which action it was, and
which plan row chose it are all invisible on the field. Every one of those facts
is available — but only in the scrolling text log on the right, which is
30 lines of prose per second. **The log is the game. The arena is decoration.**
That is backwards for an autobattler whose whole pitch is watching your plan
execute.

The single most valuable missing thing: when a unit acts, I should see *which
row of its plan fired*. That is the feedback loop that makes the plan editor
worth using, and it does not exist.

### The health bar problem

This is the specific thing that destroys the fight screen.

- Bars are drawn **roughly 40px above** the sprite they belong to, with nothing
  connecting them. In a crowd the bar of one unit sits directly over the body of
  another.
- Bars are **3 to 6 times wider than the sprite**. The Abomination's bar is
  ~57px wide over a ~14px body. A goblin's bar is ~30px over a ~6px body.
- With 20 units, the arena reads as a field of floating coloured dashes with
  insects underneath them. In `fight_02.png` and `finch_99_second_wind_01.png`
  the party's four bars at bottom-left overlap each other into a striped block
  and I cannot tell how many units are there.
- Some units carry **two stacked bars** (teal over orange, teal over blue,
  cream over nothing). I assume the second is resource/mana. Never explained,
  never labelled, and the second bar's colour changes per class (orange for
  Abomination, blue for Geysermancer and Priest) which made me think it meant
  different things.

### The units are too small to be units

`ArtPreview` states it outright: "true on-screen size in the arena" is a ~6px
smear. A goblin at true size is four brown pixels. `AttackFXPreview` says
projectiles are "~5-10px". I cannot distinguish a Ghoul from a Cultist from a
Goblin on the field. I only know there were Ghouls because the log said so.

Meanwhile the **party-select cards show large, clean, genuinely charming
silhouettes** — the Priest with the halo and staff, the Siege Master with the
angled arm. Those are good. Then the fight throws them away and draws 6px
blobs. Two different art qualities in one game, and the fight got the worse one.

---

## 3. Things I could not interpret. Specifically.

- **The orange circle with a number in it** (e.g. "2", "3", "4", "5") that
  follows one unit around mid-fight. Bleed stacks? Enemies remaining? A combo
  counter? Never resolved. It is the most prominent thing on the field and I
  never learned what it means.
- **The ~17px pentagon-shaped badges** in a row under a unit. I counted at least
  6 distinct ones and could read none of them. The ones I could half-see: a
  white diagonal slash on red, a three-dot triangle, a `»` double-chevron in
  green, a plain white shield in green, an asterisk. At the size they render
  they are grey noise.
- **A solid magenta square** used as one of the status badges. In every engine I
  have ever seen, a flat magenta square is a missing texture. If it is
  deliberate it looks exactly like a bug.
- **The tiny teal square and tiny blue square** floating to the left of some
  party bars (visible in `fight_05.png` around x=250-280). Different thing from
  the pentagon badges. No idea.
- **The dark grey circle outline** that briefly rings a unit. Impact flash? A
  taunt? A guard?
- **The concentric purple rings** around the Priest. Something firing, but
  purple reads as "Profane" on the party-select cards, which is the
  Abomination's damage type, not the Priest's.
- **Faint hairlines between units.** I assume "this unit is attacking that unit",
  but they persist for several frames and cross the whole arena, so they read
  more like a targeting web than an attack.
- **`Melee · Magical` vs `Ranged · Magical` vs `Summoner · Martial`.** Two axes,
  colour-coded, and the colours differ per class (Abomination's pair is purple,
  Geysermancer's is blue, Priest's is yellow-then-purple, Siege Master's and
  Warrior's are plain grey). I could not work out whether the colour encodes the
  class or the tag. Priest's two tags are *two different colours*, which broke
  whatever rule I had inferred.
- **"Anti Support"** as a role. I do not know what that does.
- **`ATN`** in the attribute row (STR DEX AGI CON INT ATN WIS). Six of seven are
  standard. `ATN` is not a stat abbreviation I recognise, and it is the only one
  with no hover text I found.
- **The bottom-left pile.** By mid-fight there are 2 to 4 large teal trapezoid
  shapes stacked on top of each other in the bottom-left corner, each with a
  cream bar and a small sword badge, all overlapping. They never move. Larger
  than my actual heroes. I assume Siege Master summons, but they look like a
  spawn bug — a heap of identical objects growing in a corner.
- **`piece_of_nothing`**, an equippable accessory whose icon is a dotted empty
  outline. Joke item, placeholder, or unimplemented? Cannot tell.
- **The floor map node types.** Cell, Trap, Miniboss are greyed out; two "Cell"
  and two "Enemy" nodes are lit. I do not know what a Cell is, why some are
  greyed, or whether greyed means "locked", "already done", or "not on my path".

---

## 4. What looks broken, ugly, cramped or accidental

**I never saw a fight end.** ScreenSweep names a shot
`sweep_battle_end_banner` and logs `outcome=UNRESOLVED tick=64`. The screenshot
has no banner. So the one screen that tells you whether you won is one I could
not reach at all. If a real player's fight can also hang unresolved, that is the
top bug in the build.

**Dead space.** At 1280x720 the arena occupies roughly the left half of a
1000px-wide column and the bottom 90px of the window is empty. The right log
panel is a full-height column that is *blank* for the first 10 seconds of the
fight, so the screen opens as: small arena, huge void, thin vertical rule,
another void.

**At 844x390 the fight screen is unusable.** Units are ~4px. The log panel
renders 2 lines and then stops. The arena sits in the top-left third with the
rest black. This resolution is not supported and it looks like nobody looked.

**"The Narrows" has a rendering seam.** A full-height pure-black vertical column
runs the height of the arena at roughly x=493-543, with one small hatched grey
box floating in the middle of it. The hatched box reads as a wall. The black
column reads as a hole in the render. If they are the same feature, they should
look the same.

**Overlapping floating text.** "Goblin dies" in large orange type sits across
the middle of the arena on top of live units, and "Miss" in large grey type sits
on top of it. In one shot "Goblin Archer dies" is drawn over a wall and a unit
simultaneously. Two large words competing for the same 200px.

**Pinned hover panels overlap each other.** In `wren_popout_two_pinned` a panel
for `DEX 1` is drawn directly on top of the panel for `STR 5`, hiding two of its
three lines, and both are drawn over the plan rows underneath. Pinning two
things makes both less readable than pinning one.

**Truncated dropdowns.** "An enemy within 45 un", "An enemy within 140 u",
"Self resource at least 4" (the value box next to it says 40, so the label lost
its own number). Three of the six condition dropdowns I saw were cut mid-word.

**Party-select spacing.** The five class cards stop at x=946 of 1280 and there
is a 250px empty column beside them, then a 90px vertical gap before the Room
row. The screen looks like a 6th card failed to load.

**The level editor is functionally blank.** It opens on "New Room" with an empty
grid, four unexplained teal dots down the left, a single "Rat" in the enemy
dropdown, and "Drag a rectangle to place a Wall." It is shipped in the main menu
alongside Start Run, so a new player will press it and find nothing.

**Balance smell.** Running one seed with three parties: balanced, four Warriors,
and four Geysermancers all won. Four identical Warriors beating floor 1 means
composition is not yet a decision on the first floor.

---

## 5. What is missing that I expected

- **A win/lose screen.** Never saw one.
- **Any tie between a plan row and what happens on screen.** The plan editor is
  the game's idea. The fight does not show it working.
- **Speed control.** There is Pause and nothing else. No 2x, no step, no
  rewind. For a fight I cannot read at 1x, a step button is not a luxury.
- **A legend, key, or hover on the arena.** Nothing on the fight screen explains
  one symbol. "What to show" exists as a button, but I would not expect a new
  player to guess that a *display options* menu is where symbols get explained.
- **Names on the field.** The deploy screen labels every unit. The fight screen
  labels none of them. Losing the labels at exactly the moment you need them is
  the wrong way round.
- **Health as a number anywhere.** The log tells me "hits Goblin for 19". Out of
  what? I never see a unit's HP total during a fight.
- **A title screen.** The game opens directly on "Pick your party". No name, no
  menu, no context. I did not learn what the game is called from playing it.
- **Any indication of what a Cell / Trap / Miniboss node does** before I commit
  to walking into it.
- **Feedback that my placement mattered.** The deploy screen is a real decision
  with a real constraint, but within two seconds of Start Fight everyone has
  moved and I cannot tell whether where I put them changed anything.

---

## 6. Blunt summary

Two screens are genuinely good: the plan editor and the equip screen. Both are
text-heavy, both explain themselves in a paragraph at the top, both work at
1280x720. The party-select art is charming.

The fight is not watchable. It is a spreadsheet with a screensaver next to it.
Everything that determines the outcome is in the right-hand text log; everything
in the arena is either too small to identify, unlabelled, or an unexplained
symbol. Fix one thing and it should be the health bars: attach them to their
unit, size them to the unit, and make the unit large enough to be a unit. Fix a
second thing and it should be showing which plan row fired, because that is the
only reason to watch at all.
