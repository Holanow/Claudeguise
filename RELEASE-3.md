# Release 3

```
"D:/Projects/Claudeguise-team/tools/godot/Godot_v4.7.1-stable_win64.exe" --path D:/Projects/Claudeguise
```

Forward slashes on purpose: an unquoted Windows path gets eaten by the shell.

**927 tests, no open pull requests, every screen swept and working.**

## What is new since you played

### You can reach the game now
- **Five rooms, and you pick one.** Open ground, a colonnade, a burn pit, a chokepoint with a tar pit, and the Rat King's nest. **Three of the four existing rooms had been unreachable** — the picker did not exist and party select was hardcoded to one room.
- **You place your pawns before the fight**, on the terrain, with the enemy line visible. Asked for three times.

### The fight reads
- **Damage numbers and name plates are off by default**, both re-enableable under "What to show".
- **Health bars carry team colour** and fit the drawn body rather than the collision radius — a goblin's bar went from 33px to 20px against an 18.5px body.
- **Status badges are 16px, not 8.7px**, in a row that got *narrower* by reserving two slots instead of four.
- **Bleed no longer reports itself as terrain damage.** The Rat King's nest was printing 951 false "damage from the ground" lines per twenty fights, in a room with no terrain.
- **Every event kind now prints something or is on an explicit silent list**, so a mechanism can no longer be added, fire in real fights, and render nothing.

### New mechanics
- **Statuses have real sources.** Burn from Scald, consumed by Blast for bonus damage scaled off the burn. Stun from the Brute, and **stun now interrupts a cast** — wind-up lost, resource not refunded. Bleed stacks infinitely from the rats. Slow from a tar pit.
- **Three specialty enemies**: a Brute that stuns and taunts, a Stalker that marks, and rats that bleed. Plus **the Rat King**, floor 1's miniboss.
- **Taunt is a compulsion** — a taunted pawn abandons its plan and attacks the taunter. Cleansing frees it.
- **Rage and energy start at 0**, mana starts full, and rage is earned by taking hits.
- **Units step around fire** rather than walking through it.

## Known and not fixed

- **The Rat King's swarm is not a swarm.** It is in range and *forbidden to fire* 40-60% of the fight, because the ranged firing band is narrow and it moves slowly. Four rats at a time, not a horde.
- **`stalker_dart` has never fired**, because the action filter ignores cooldowns.
- **The block, and both sustain events, never occur** — the log lines exist, the content that would trigger them does not.
- **The log still never says which plan row fired.** You can see *what* a pawn did and not *why*, which is the demanding half of your own definition of done.
- **No sound**, though the hooks and placeholders are in.
- **844x390 is still bad.** Badges are 8.7px there.

## What I would look at

Your finish line: *watch a fight without pausing and broadly follow what happened and why.* Most of this release is aimed at the first half. **The "and why" is still missing** and is the largest thing left.

Two decisions are waiting on you, neither blocking: whether The Warden should be pickable from the menu, and whether a dropped-in status PNG may replace the colourblind-safe plate.
