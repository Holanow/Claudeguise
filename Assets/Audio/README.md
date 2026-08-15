# Dropping in sound

The game currently makes six short synthetic blips. They are placeholders and
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

## Events

These are the six with a placeholder today. Drop a file on any of them and it
replaces the blip.

| File | When it plays |
| --- | --- |
| `event/action_fire.ogg` | An ability goes off. The swing, the cast, the shot leaving. |
| `event/damage.ogg` | A hit lands. |
| `event/heal.ogg` | Healing lands. |
| `event/death.ogg` | A unit dies. |
| `event/miss.ogg` | An ability went off and reached nothing. |
| `event/blocked.ogg` | A shielding unit stepped in front of a shot and took it. |
| `event/interrupted.ogg` | A stun landed mid-cast. The wind-up is lost and the resource is not refunded, so this is the harshest thing that happens to a pawn and the strongest case in this table for a sound. |

These have **no sound at all** today. Drop a file on any of them and it gets
one, which is the same one-file operation as replacing a blip.

| File | When it would play, and why it is quiet |
| --- | --- |
| `event/damage_over_time.ogg` | Every tick of a burn, poison or bleed. **Read the warning below before you fill this one in.** |
| `event/status_applied.ogg` | A status lands: a stun, a taunt, a mark. The strongest candidate of these eight, and the note below says why it is not on. |
| `event/action_start.ogg` | A wind-up begins. Every one of these is followed by an `action_fire`. |
| `event/status_expired.ogg` | A status runs out. |
| `event/resource_spent.ogg` | A unit pays for an ability. Happens inside a hit you can already hear. |
| `event/fight_start.ogg` | The fight begins. |
| `event/fight_end.ogg` | The fight ends. |
| `event/sustain_start.ogg` | A unit begins holding a channelled ability. |
| `event/sustain_end.ogg` | A unit stops holding one. |
| `event/summoned.ogg` | A unit is built onto the field mid-fight: a siege engine, or one of the Rat King's rats. Measured at 53 across 15 fights, so treat it as frequent rather than a set piece. |

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

**And one open question that needs ears rather than a measurement.** A status
lands in the same tick as the swing and the landing of the hit that applied it.
Voicing `event/status_applied` therefore turns one hit into three sounds inside
a fifteenth of a second. Fourteen percent of the noisy moments in a fight
already carry more than one sound. Whether that reads as weight or as a stutter
is not something that can be settled by reading the code, so it ships silent and
you can turn it on with one file.
