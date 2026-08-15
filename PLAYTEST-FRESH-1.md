# Fresh-eyes playtest, first contact

I have never seen this game. I read no code, no README, no notes, no issues. Everything
below comes from looking at rendered screens. Where I am wrong, the wrongness is the point.

---

## 0. I could not actually start the game

The sanctioned harness cannot get into a fight. Twice, at both resolutions:

```
ScreenSweep: Start Fight rect=[...] on_screen=true disabled=false
ScreenSweep: did not reach Battle from Start Fight
```

A second harness (`PlaytestRun`) fails harder and earlier:

```
no button starting with 'start' found
classes offered: []
pressed all 0 checkboxes; 0 ended up checked (want 4)
status label after selecting the balanced four: Party: 0/4
did not reach the battle screen after pressing Start; stopping phase 2
```

So the two tools whose whole job is "show a person the game" both stop at the front door.
The `sweep_battle_*.png` files in `Screenshots/` are committed leftovers from some earlier
run, not something I produced. I had to reach the fight through `ContactSheet.tscn`, which
builds one directly and skips the menu entirely.

**This is the finding that matters most.** Whether the button is dead for a human or only
for the harness, I cannot tell. But nobody can currently check, and that is the same
problem. Everything below the fold is decoration if the front door does not open.

---

## 1. What I think the game is

An auto-battler where you do not control anyone in the fight. You pick four of five classes,
place them on the left half of a room, press go, and watch. You lose or win, and either way
you did not press anything during the fight.

The actual game, I think, is the plan editor: each pawn gets an ordered list of if-this-then-that
rows, checked top down, first match wins, with a guaranteed fallback at the bottom. You are
writing the pawn's brain before the fight and then watching it run. The floor map suggests a
roguelike loop over that: rooms in a branching chain, loot, equip, boss at the end.

If that is right, then the fight screen is a **readout of whether your plan was any good**, and
it is the single most important screen in the game. It is also, by a wide margin, the worst.

---

## 2. The fight is unreadable. Not "could be clearer" — unreadable.

I watched six frames of one fight at 1280x720 and could not tell you who was winning at any
point, or why anyone did anything, without reading the text log on the right. And once I was
reading the log, the battlefield was doing nothing for me at all.

Specific failures:

**Health bars are enormous, detached, and anonymous.** A green bar is roughly 70px wide. The
figure it belongs to is roughly 8px tall. The bars do not sit on the figures — they float above
and to the left, often over empty grid, and often nearer to a different figure than their own.
In `fight_06` there is a green bar at the upper-left of "Priest" with no visible sprite anywhere
under it. In `fight_01` I count nine green bars and about eight sprites and cannot pair a single
one with confidence. Every bar is the same green whether it belongs to me or the enemy, so the
field reads as "green dashes" and nothing else. The one thing I need in an autobattler — *is my
side ahead* — is exactly the thing the bars refuse to tell me.

**Damage numbers overlap into garbage.** `fight_06` shows `111187` — that is an 11, an 18 and a
7 landing on the same pixels. `fight_03` has `74` and `18` fused into `7418`. The numbers are
also huge, grey, low-contrast, and drawn *behind* the name plates, so a big number is both
illegible and occluding.

**Name plates collide constantly.** "Goblin" printed straight through "Abomination"
(`fight_01`). "Siege Master" through "Geysermancer" (`fight_05`). "Siege Engine" over "Siege
Engine" over "Siege Master" (`icons_in_fight_every_status`). The plates have opaque dark
backgrounds, so the top one wins and the bottom one becomes noise. In `wren_deploy_room` a red
dot eats the C-u-l of "Cultist" and it renders as "ltist".

**Death text is drawn in the same place as everything else.** "Goblin Archer dies" appears
twice, in orange, straight across the middle of the arena and across other units, in
`fight_03`. It looks like an error message.

**`OOM`.** In `icons_in_fight_every_status` a pawn is labelled `OOM` in red. I assume "out of
mana", but my first read was "out of memory" and I genuinely could not rule out a crash
indicator. Pick a word.

**Everything happens in one corner.** The arena is ~795x450 and all combat takes place in a blob
roughly 250x250 in the upper-left third. The right 40% and bottom 30% of the room are empty grid
for the whole fight. Either the room is too big or the units never use it.

**At 844x390 the fight is not a display, it is texture.** The log is ~7px type. The arena is a
smear of green dashes with orange digits on it. I could extract nothing.

---

## 3. Symbols I could not interpret

Everything here is something I looked at and could not resolve. In arena order:

- **The `Party` and `Enemies` bars, top-left.** Two bars, teal and red, each partly filled
  against a dark trough. I *guessed* aggregate side health. But they are different lengths from
  each other at full (teal ~117px, red ~133px) at the start of the fight, which breaks the
  guess — if both sides start at full, why are they different sizes? So either it is not health,
  or the scale is per-side and comparing them is meaningless. I could not tell which.
- **The tan/khaki bars** under some green bars. Not on all units. Not obviously matched to
  anything in the log. Cast progress? Some second resource? No idea.
- **The blue bars** under the green ones on Priest and Geysermancer. Mana, I guessed, since
  those are the casters. Guess only.
- **The single yellow-then-grey bar** near Siege Master in `fight_01`, in a different position
  from all the others.
- **The lone white/cream bar with a small pen-nib icon at the very bottom-left**, floating
  below everything, attached to nothing I could see. It persists across frames. This is the
  single most confusing object on the screen.
- **Red circular badges with a white number** — `2`, `3`, `5`. Stack count of something? Which
  something? They sit next to units with no adjacent icon to count.
- **Pentagon-shaped badges, ~12px**, red-outlined and green-outlined. At 1x they are coloured
  specks. At 4x (`icons_at_true_size_zoom4x`) I can see a four-point star, a teardrop, a
  speaker, a heart. I still cannot tell you what any of them mean, and the red/green split
  might be good-vs-bad or might be something else. A player will never see these; they are
  below the resolution of the human eye at this scale.
- **Rounded-square badges with a right-arrow and with a double-headed arrow.** Different shape
  from the pentagons, so presumably a different category. Movement? Range? Unknown.
- **The thin grey diagonal lines** between figures. I guessed "who is targeting whom", which
  would be genuinely useful, but they are so faint and so tangled that at four-plus lines I
  cannot trace any of them to a source.
- **Faint grey circles** drawn around some units. Range indicator? Ability radius? They appear
  and vanish between frames with no legend.
- **`Miss` in huge grey letters** across the arena, same size and colour as the damage numbers,
  so it reads as another overlapping number until you squint.

---

## 4. Things I had to guess, and my guesses

| Thing | My guess |
|---|---|
| The whole fight | Fully automatic, no input, plan-driven |
| Teal vs red-orange sprites | Mine vs theirs |
| `Party: 4/4` | Pick exactly four |
| `Seed 0000002A` | Run RNG seed, shown so you can repeat a fight |
| `WIS` in the plan editor | Doubles as your plan-complexity budget, which is a nice idea and stated outright |
| `ATN` | No idea. Attunement? Attention? The only attribute I cannot expand |
| Grey rooms vs white rooms on the floor map | White = reachable next, grey = not. Never stated |
| "Siege Engine" appearing mid-fight | Summons from Siege Master, since it is tagged Summoner |
| `2 of 4 survived` while five teal shapes are on the field | Summons do not count as survivors |

The playtest report also says `survivors=5/4` for one party. Five of four survived. I do not
know what that means and I do not think the game does either.

---

## 5. What looks broken or accidental

- Start Fight does not start a fight (section 0).
- Overlapping name plates, overlapping damage numbers, overlapping death text (section 2).
- `Ceremonial Sword (weap` — the equip list clips its own item names mid-word
  (`equip_panel_1280x720`).
- The equip panel is a tall dark column that is 90% empty, with a stray horizontal scrollbar
  sitting alone at the bottom of all that emptiness.
- The plan editor's fallback rows are cut off by the bottom of the screen on first open, at
  both resolutions. The heading says "Fallback, always last and not yours to change" and then
  the thing you are being told about is half off-screen.
- Party select wastes the middle 250px of the screen on nothing, then crams Seed / Party count /
  Start Fight / four secondary buttons into the bottom 250px.
- Start Fight is a 1216px-wide full-bleed bar. It reads as a divider, not a button.
- The level editor opens with four teal dots already on the grid and a shaded left region, and
  says only "Drag a rectangle to place a Wall." It does not say what the dots are or what the
  shading means.
- The floor map's current room reads `Enemy (here)` in *dimmer* grey than the rooms around it.
  The room you are standing in is the least visible thing on the map.
- The seed changes between the empty and full party-select shots in the same sweep run, so the
  seed field appears to reroll when you touch the party. That makes it useless for the thing a
  seed is for.

---

## 6. What is missing that I expected

- **Any legend, key, or tooltip.** Nothing on any screen explains any icon, bar, or colour.
- **A distinct visual identity per class.** All five party-select portraits are the same teal
  blob with the same dark-green legs. Abomination has two purple wedges, Geysermancer two blue
  spikes, Priest a yellow halo, Siege Master a beige plank, Warrior a beige rectangle and a
  stick. I could not name any of them from silhouette. In the fight they collapse to identical
  8px teal specks and even the small distinctions are gone.
- **Any indication of who is winning**, other than counting green dashes.
- **Cause and effect on screen.** When something dies, nothing on the field marks it. The log
  says so, in a scrolling column, three lines after the hit that did it.
- **A reason to care about the fight at all.** With no readable field, the honest optimal play
  is to skip the animation and read the outcome line.
- Any sound, music, or feedback I could evaluate. There is a `sound_placeholders/` folder, so
  I assume there is none.

---

## 7. On the fight itself

**Could I follow it?** No. Not once, not at any moment, in either resolution.

**Could I tell who was winning?** Only from the log, and only by reading maybe fifteen lines and
holding a tally in my head. The two aggregate bars at the top-left should have answered this
instantly and I could not trust them, because they are different lengths at full.

**Did I understand why anyone did anything?** No, and this is the deepest problem. The plan
editor promises that I am the author of these decisions. The fight never once showed me a
decision being made. The log says "Priest begins Smite" — it never says *which plan row fired*,
or *why that condition was true*. I wrote the brain and then I was not shown the brain thinking.
For a game whose entire input is the plan, that is the missing feature, not a polish item.

---

## 8. The one screen that works

`Place your party` (`wren_deploy_room_1280x720`) is legible, calm, and immediately obvious.
Named dots, teal vs red, a shaded band, one line of instruction that actually explains the rule.
I understood it in two seconds with no prior knowledge.

It is legible because it is *sparse*: big dots, few of them, names beside them, nothing else.
The fight screen shows the same eight units in the same space with health bars, mana bars, two
unidentified extra bars, floating numbers, miss text, death text, target lines, range circles,
and a dozen 12px badges layered on top of each other — and it fails completely.

The fight screen does not need more information. It needs about a third as much, drawn four
times larger.

---

## Blunt summary

The parts all exist. Almost none of them read. The front door is shut, the main screen is a
smear, and the one thing you actually author — the plan — is never visible in the thing it
controls. Fix the Start Fight path, then throw away three quarters of the marks on the arena
and make the survivors big.
