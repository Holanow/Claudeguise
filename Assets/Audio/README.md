# Dropping in sound

The game makes seven noises, and seven `.ogg` files in this folder are all seven
of them. They are stock sounds under CC0; the last section of this file says
which came from where. This folder is how you change any of them, and it works
exactly the way `Assets/Units/` and `Assets/UI/` already work for pictures.

## The whole procedure

**Put an audio file in here, under the name the game asks for.** That is all.

```
Assets/Audio/event/death.ogg
Assets/Audio/event/damage.ogg
Assets/Audio/action/warrior_execute.ogg
```

No code change. No scene to edit. No import step, no registration, no restart of
anything but the game. The moment a file with the right name exists, the game
plays it.

**A name the game already ships a sound for is changed by replacing that file,
not by adding one beside it.** `.ogg`, `.wav` and `.mp3` all work and are read
straight off disk at runtime, so a file works whether or not the editor has ever
seen it — but `.ogg` is looked for first, so a `.wav` next to a shipped `.ogg`
never plays. Overwrite `event/damage.ogg` with your own; do not add
`event/damage.wav`.

Delete a shipped file entirely and a short synthetic blip comes back in its
place. Every voiced name has one, which makes it safe to try a sound and change
your mind.

## The two levels, and which one wins

A sound is looked up twice, specific first.

1. `action/<action id>` plays for that one ability and nothing else.
2. `event/<kind>` covers everything that ability did not claim.

So `action/warrior_execute.ogg` gives the Warrior's finisher its own sound, and
every other attack in the game still uses `event/action_fire`. You do not have
to fill in the specific level at all. One file at `event/action_fire` is a
complete sound design for every attack in the game.

**A status landing is named per status**, `event/status_applied/<status>`, so a
stun can make a noise while a mark does not. There is no `event/status_applied`
covering all of them; the table below lists all thirteen names.

## Events

### With a placeholder today

**These seven are the sounds the game makes.** Each ships a real `.ogg` here;
each also has a synthetic blip behind it, which is what you hear if the file is
deleted. Replace the file and the game plays yours instead.

| File | When it plays |
| --- | --- |
| `event/action_fire.ogg` | An ability goes off. The swing, the cast, the shot leaving. |
| `event/damage.ogg` | A hit lands. |
| `event/heal.ogg` | Healing lands. |
| `event/death.ogg` | A unit dies. |
| `event/miss.ogg` | An ability went off and reached nothing. |
| `event/blocked.ogg` | A shielding unit stepped in front of a shot and took it. |
| `event/status_applied/stun.ogg` | A stun lands. The only status with a sound, because it is the only one that takes a pawn's turn away from it. |

### Silent until you drop a file in

Everything else, plus `damage_over_time`, which is a name rather than a kind of
its own. These have **no sound at all** today. Drop a file on any of them and it gets
one, which is the same one-file operation as replacing a blip.

| File | When it would play, and why it is quiet |
| --- | --- |
| `event/interrupted.ogg` | A stun landed mid-cast. The wind-up is lost and the resource is not refunded, so this is the harshest thing that happens to a pawn and the strongest case in this table for a sound. It is silent only because it arrives in the same tick as the stun that caused it, which now makes its own noise. |
| `event/damage_over_time.ogg` | Every tick of a burn, poison or bleed. **Read the warning below before you fill this one in.** |
| `event/action_start.ogg` | A wind-up begins. Every one of these is followed by an `action_fire`. |
| `event/status_expired.ogg` | A status runs out. |
| `event/resource_spent.ogg` | A unit pays for an ability. Happens inside a hit you can already hear. |
| `event/fight_start.ogg` | The fight begins. |
| `event/fight_end.ogg` | The fight ends. |
| `event/sustain_start.ogg` | A unit begins holding a channelled ability. |
| `event/sustain_end.ogg` | A unit stops holding one. |
| `event/summoned.ogg` | A unit is built onto the field mid-fight: a siege engine, or one of the Rat King's rats. Measured at 53 across 15 fights, so treat it as frequent rather than a set piece. |
| `event/terrain_added.ogg` | A pool of water is laid down, or a burning hazard comes back as the parts the pool did not cover. Issue 496 moved the small pool onto the Geysermancer's free basic attack, so this is now one of the most frequent events in the game: measured at 3,999 across 20 fights on the burn pit with four Geysermancers. Leave it silent unless the sound is very short and very quiet. |
| `event/terrain_removed.ogg` | Burning ground goes out under a pool. **The best candidate of the two**, and a hiss of steam is the sound a player would expect without being taught it, but it is no longer rare either: 1,077 across the same 20 fights. |

#### The twelve statuses that land quietly

A status landing is one name per status. Only `stun` is voiced; drop a file on
any of the rest and that one status starts making a noise, and the other eleven
do not.

| File | When it would play |
| --- | --- |
| `event/status_applied/shield.ogg` | A shield goes up. |
| `event/status_applied/bleed.ogg` | A bleed is applied. |
| `event/status_applied/taunted.ogg` | A unit is forced onto a taunter. |
| `event/status_applied/burn.ogg` | A burn is applied. |
| `event/status_applied/haste.ogg` | A unit is hastened. |
| `event/status_applied/block.ogg` | A unit takes a blocking stance. |
| `event/status_applied/marked.ogg` | A unit is marked. |
| `event/status_applied/poison.ogg` | A poison is applied. |
| `event/status_applied/slowed.ogg` | A unit is slowed. |
| `event/status_applied/taunting.ogg` | A unit starts taunting. |
| `event/status_applied/shielding.ogg` | A unit starts intercepting shots crossing its front arc. |
| `event/status_applied/sustaining.ogg` | A unit starts holding a channelled ability. |

## Abilities

Any action id works as `action/<id>.ogg`. The ids are the same ones
`Assets/UI/README.md` lists for ability icons, so a sound and an icon for the
same ability are named identically apart from the folder and the extension.

A file here claims that ability's **firing and its damage**, which arrive in the
same tick and therefore become one noise rather than two. It does not claim the
status the ability applies: a stun still makes the stun's own sound, so giving
one ability a signature swing cannot silence the cue that says a pawn lost its
turn.

## Turning a sound off

The pipeline adds. It has no switch. But the game plays whatever file is at the
name, so **a near-silent file is how you turn something off** — overwrite
`event/action_fire.ogg` with a quiet half-second of nothing and attacks stop
making a noise, without touching the ones that still should.

## Two things worth knowing before you record anything

**A fight is busier than it looks.** Measured over 80 full fights of every party
a player can assemble: 6.4 to 8.2 sounds per second, and up to five at once.
Sounds that are lovely alone stack badly at that rate. The shipped sounds are
between 0.10 and 0.50 seconds and peak between -17 and -6 dB for that reason,
quietest where they are most frequent, and a replacement that is long or loud
will behave very differently from the one it replaces.

**Damage over time is a drain, not a happening.** Of 1556 damage events in those
fights, 861 were burn and poison ticking. Those fire every tick for the whole
life of the status and they are the reason `event/damage_over_time` is a
separate name that starts silent: an earlier version played the ordinary damage
sound for them and the fight became a buzz. If you fill it in, make it very
quiet and very short, or expect a drone.

**A status lands in the same tick as the hit that applied it.** So the swing, the
landing and the status are three sounds inside a fifteenth of a second, and 23 to
25 percent of the noisy moments in a fight already carry more than one. That is
why only stun is voiced: it is the one status that takes a pawn's turn away, and
it is worth a third noise where a mark is not. Fill in any of the other twelve
and you are adding to that stack, so keep it short.

## Where the sounds came from

All seven are **CC0** (Creative Commons Zero, public domain), from packs by
**Kenney** at [kenney.nl](https://kenney.nl), downloaded 2026-08-24. CC0 asks
for nothing, and Kenney asks only to be credited, which this table does.

Each was cut to the length below and its peak set to the level below, so that
what is frequent is quiet and what is rare is loud. Nothing else was changed.

| File | Source file | Pack | Length | Peak |
| --- | --- | --- | --- | --- |
| `event/action_fire.ogg` | `knifeSlice.ogg` | [RPG Audio](https://kenney.nl/assets/rpg-audio) | 0.18 s | -16 dB |
| `event/damage.ogg` | `impactPunch_medium_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | 0.20 s | -12 dB |
| `event/heal.ogg` | `pluck_001.ogg` | [Interface Sounds](https://kenney.nl/assets/interface-sounds) | 0.10 s | -11 dB |
| `event/death.ogg` | `impactSoft_heavy_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | 0.50 s | -6 dB |
| `event/miss.ogg` | `cloth3.ogg` | [RPG Audio](https://kenney.nl/assets/rpg-audio) | 0.16 s | -17 dB |
| `event/blocked.ogg` | `impactMetal_light_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | 0.18 s | -13 dB |
| `event/status_applied/stun.ogg` | `impactBell_heavy_000.ogg` | [Impact Sounds](https://kenney.nl/assets/impact-sounds) | 0.40 s | -8 dB |

Every pack states its licence in its own `License.txt`:
*"License: (Creative Commons Zero, CC0)
http://creativecommons.org/publicdomain/zero/1.0/ — This content is free to use
in personal, educational and commercial projects."*
