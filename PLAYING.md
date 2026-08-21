# Playing the slice

Written so the first five minutes go on whether you like it, rather than on
whether it works.

## Run it

```
powershell -ExecutionPolicy Bypass -File D:\Projects\Claudeguise\Tools\play.ps1
```

Use that rather than launching Godot directly. It rebuilds the import when
something has changed and tells you it is doing so. Launching Godot straight at
the project gives you a blank grey window for a minute or two with no
explanation, which is what happened to a playtester who reasonably concluded the
game was broken.

## Start here

**Floor 1, The Warden's Chamber** and **Floor 1, The Nest**, from the "Where to
fight" dropdown.

Not because the other four are broken, but because they hold ten enemies and the
screen cannot yet carry that many. This is measured rather than felt: the core of
a fight is about 200 x 210 world units **whatever the room**, because ranged
pawns settle at 160-165 units from their nearest opponent and melee at 16-19. So
ten enemies land in the same space five do. **At five units that space reads. At
fourteen it does not.** #421 has the numbers and the three ways out, and the
choice between them is yours.

## What to do

1. **Pick four pawns and start a fight. Do not touch anything else.** Watch it
   through without pausing.
2. **When it ends, ask yourself what you would change.** Then open **Plans**.
3. **Take a row from the Library**, or build one, and run the same seed again.

That third step is the game. Everything else is in service of it.

## What a stranger found

Six people who had never seen the code have played it. The fifth was the first to
finish a fight, form a complaint, act on it, and get a different fight back:

> "I added the library row `Heal - The ally with the lowest hp - An ally's hp
> below 50%` and clicked the spinner to 80%. **Did it change the fight? Yes, and
> it made it worse.** 3 survivors to 2. The Priest healed more, ran its mana bar
> to a sliver, and died. **I could reconstruct that whole story from the log and
> the team panel.**"

Making it worse is the good result. It was their decision, and they could see
why it cost them.

## Known broken, so you do not spend the morning finding it

- **Ten-enemy rooms are hard to watch.** Room 1, The Narrows, Broken Colonnade
  and The Burn Pit. #421.
- **`keep_distance` will send a pawn into fire.** It aims at a point without
  asking whether that point burns, so kiting in a hazard room is worse than no
  plan at all. Use **Move off harmful ground** instead. #424.
- **"Change party" discards plans you have written.** #380.
- **Two of five classes fight identically with no plan rows.** The Priest and the
  Geysermancer both heal and swing. #406.

## What changed since you last looked

- **The plan editor starts empty and the presets are a library you add from.**
  Your ruling. Player losses went from 0.8% to 9.2% as a consequence, with no
  number tuned.
- **Click any unit** and it tells you what it is doing and why: resource,
  wind-up, target, who is aiming at it, every status with its meaning and time
  left.
- **The log names the cause.** "48 raw, 23 stopped by its block" for mitigation,
  "28 raw, 18 more than it had left" for a killing blow that did not need all of
  itself.
- **Deaths name the casualty.** "You lost Warrior", not "3 of 4 survived".
- **A plan can talk about the ground** - "Standing on harmful ground", and "Move
  off harmful ground" to answer it.
