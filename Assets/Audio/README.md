# Dropping in sound

The game currently makes seven short synthetic blips. They are placeholders and
they are meant to sound like placeholders. This folder is how you replace any of
them with a real sound, and it works exactly the way `Assets/Units/` and
`Assets/UI/` already work for pictures.

## The whole procedure

**Drop an audio file in here, under the name the game asks for.** That is all.

```
Assets/Audio/event/death.ogg
Assets/Audio/event/damage.ogg
Assets/Audio/action/warrior_execute.ogg
```

No code change. No scene to edit. No import step, no registration, no restart of
anything but the game. The moment a file with the right name exists, the game
plays it instead of the generated blip.

Delete the file and the blip comes back, which makes it safe to try one and
change your mind.

`.ogg`, `.wav` and `.mp3` all work. Prefer `.ogg`. All three are read straight
off disk at runtime, so a file works whether or not the editor has ever seen it.

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

Drop a file on any of these and it replaces the blip.

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

## Turning a sound off

The pipeline adds. It has no switch. But a dropped-in file always beats the
generated blip, so **a near-silent file is how you turn something off** — drop a
quiet half-second of nothing at `event/action_fire.ogg` and attacks stop making
a noise, without touching the ones that still should.

## Two things worth knowing before you record anything

**A fight is busier than it looks.** Measured over eight full fights: 6.7 sounds
per second, and up to four at once. Sounds that are lovely alone stack badly at
that rate. The blips are short and quiet for that reason, and a replacement that
is long or loud will behave very differently from the placeholder it replaces.

**Damage over time is a drain, not a happening.** Of 1556 damage events in those
fights, 861 were burn and poison ticking. Those fire every tick for the whole
life of the status and they are the reason `event/damage_over_time` is a
separate name that starts silent: an earlier version played the ordinary damage
sound for them and the fight became a buzz. If you fill it in, make it very
quiet and very short, or expect a drone.

**A status lands in the same tick as the hit that applied it.** So the swing, the
landing and the status are three sounds inside a fifteenth of a second, and
fifteen percent of the noisy moments in a fight already carry more than one.
That is why only stun is voiced: it is the one status that takes a pawn's turn
away, and it is worth a third noise where a mark is not. Fill in any of the other
twelve and you are adding to that stack, so keep it short.
