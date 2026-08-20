# Dropping in interface art

Every icon in this game is a PNG in this folder, and every panel, border and
background can become one. This is how you replace any of it with your own
picture, and it works exactly the way `Assets/Units/` already works for units.

## The whole procedure

**Drop a PNG in here, under the name the game asks for.** That is all.

```
Assets/UI/status/bleed.png
Assets/UI/action/warrior_execute.png
Assets/UI/item/plate_mail.png
Assets/UI/panel_border.png
```

No code change. No scene to edit. No import step, no registration, no restart of
anything but the game. The moment a file with the right name exists, the game
draws it.

**Every icon in this folder is already one of these files.** They were drawn from
code until 2026-08-19; they were rendered out to PNGs and the drawing code was
deleted, so there is no longer a generated version underneath. Overwrite a file
to change a picture. **Delete one and the game draws a black square** -- on
purpose, so a missing picture looks like a missing picture rather than like the
feature being broken.

## Status badges

One per status effect. These draw above a unit at about 12-16 pixels, so they are
built around a shape you can still tell apart at that size.

| File | What it draws |
| --- | --- |
| `status/shield.png` | Shield — absorbs damage |
| `status/block.png` | Block — reduces damage taken |
| `status/shielding.png` | Directional Block — stops shots crossing the front |
| `status/sustaining.png` | Sustaining — holding an action open, paying for it every tick |
| `status/haste.png` | Haste — acts faster |
| `status/taunting.png` | Taunting — forces nearby enemies to attack this unit |
| `status/bleed.png` | Bleed |
| `status/burn.png` | Burn |
| `status/poison.png` | Poison |
| `status/stun.png` | Stun |
| `status/marked.png` | Marked — takes more damage |
| `status/slowed.png` | Slowed — moves slower |
| `status/taunted.png` | Taunted — forced to attack whoever taunted it |

The first six are helpful and the last seven are harmful, which is the split the
plate direction and rim colour below are drawn from.

**The badges follow a rule, and a replacement should keep it.** Helpful
statuses sit on a plate that points **up** with a **green** rim. Harmful ones sit
on a plate that points **down** with a **red** rim. Both cues carry the same
information on purpose: the colour is faster to read, and the direction still
works for a player who cannot separate red from green. If you drop in your own
art and only keep the colour, that second group loses the distinction entirely.

## Ability icons

One per action, shown at the end of a wind-up progress bar so you can see what
is coming rather than only that something is.

`action/warrior_strike.png`, `action/warrior_guard.png`,
`action/warrior_execute.png`, `action/warrior_taunt.png`,
`action/warrior_block.png`, `action/warrior_second_wind.png`,
`action/priest_heal.png`, `action/priest_bolt.png`, `action/priest_smite.png`,
`action/priest_haste.png`, `action/priest_ward.png`,
`action/geyser_blast.png`, `action/geyser_scald.png`,
`action/geyser_spout.png`, `action/geyser_cleanse.png`,
`action/siege_master_shot.png`, `action/siege_engine_bolt.png`,
`action/build_siege_engine.png`, `action/abomination_claw.png`,
`action/abomination_hook.png`, `action/abomination_grapple.png`,
`action/abomination_immolate.png`,
`action/goblin_stab.png`, `action/goblin_arrow.png`, `action/archer_shot.png`,
`action/ghoul_maul.png`, `action/grunt_smash.png`, `action/cultist_bolt.png`,
`action/spotter_mark.png`, `action/brute_slam.png`, `action/brute_roar.png`,
`action/rat_bite.png`,
`action/rat_king_lash.png`,
`action/stalker_dart.png`, `action/stalker_mark.png`,
`action/warden_axe.png`, `action/warden_chain_toss.png`

The filename is the action's id. **This list is checked by a test.**
`Tests/test_art.gd` walks the real content registry and fails if an action ships
without an icon, so nobody has to notice a blank square in a fight.

The icons are coloured by the action's damage type, the same colour the floating
damage numbers and the projectiles already use, and that colour is painted into
the file. A replacement is drawn exactly as you painted it, colour included.

**An action whose whole effect is a status carries that status's picture.** Guard
is the Block wall, Ward the Shield, Haste the chevrons. One picture learned
teaches both halves: the player sees what is coming, then sees the same thing
land. Nothing checks this any more -- it was checked while both were the same
array in code, and two PNGs cannot be compared that way -- so it is a rule for
whoever repaints them.

## Equipment icons

One per item, shown on the pre-fight equip screen at about 32 pixels.

`item/sword.png`, `item/wrench.png`, `item/sickle.png`, `item/orb.png`,
`item/bow.png`, `item/staff.png`,
`item/plate_mail.png`, `item/silk_wraps.png`, `item/robes.png`, `item/gown.png`,
`item/scrubs.png`, `item/whetstone.png`, `item/brown_ring.png`,
`item/red_ring.png`, `item/blue_ring.png`, `item/yellow_ring.png`,
`item/censer.png`, `item/fetish.png`, `item/piece_of_nothing.png`

The filename is the item's id, and **this list is checked by a test** the same
way the ability icons are: an item added to the game without an icon fails the
build rather than shipping as a blank square.

Three more are the empty plate on its own, one per slot, so an empty weapon slot
still reads as a weapon slot rather than as a hole in the layout:
`item/empty_weapon.png`, `item/empty_armor.png`, `item/empty_accessory.png`.

**The icons follow two rules, and a replacement is worth keeping them for.**

**The plate says which slot it is**, before you read anything inside it. A weapon
sits on a **diamond**, armor on a **broad flat slab**, an accessory on a
**circle**. The rim colour says the same thing a second time — warm, cool and
neutral — so the shape still carries it if the colours are hard to separate. An
empty slot draws the plate on its own, so a weapon slot with nothing in it still
looks like a weapon slot.

**An item that teaches an action shows which one.** Plate Mail teaches its wearer
to raise a Directional Block, and it carries a small badge in its corner holding
that ability's own icon — the same picture you will see on the wind-up bar when
the block is being raised, and again on the status badge once it is up. An item
that only changes numbers has no badge.

**The bottom-right corner is reserved, and your picture does not replace it.**
Everything else here works the other way round: drop a file in and it is what
you see. The badge is the exception because it is information rather
than decoration — which item teaches an ability is something you need to know
before you equip it, and a replacement picture that quietly removed it would
look perfectly fine and would have taken something away. Leave the lower right
of an ability-granting item fairly plain and the badge will sit on it cleanly.

## Borders and panels

| File | What it draws |
| --- | --- |
| `panel.png` | Every panel, card, tooltip and chip in the game |
| `panel_border.png` | Every border |
| `background.png` | Every screen background |

**One file changes everything of that kind.** Drop in `panel.png` and every
panel in the game is re-skinned at once. That is deliberate: a theme you have to
assemble out of nine files before anything looks different is a theme nobody
finishes.

**Then a second file changes one thing.** When you want a particular element to
look different from the rest, add it under a folder named after the kind:

```
Assets/UI/background/party_select.png   just the party select screen
Assets/UI/background/deploy.png         just the deploy screen
Assets/UI/background/floor_map.png      just the floor map
Assets/UI/background/level_editor.png   just the level editor
Assets/UI/background/arena.png          just the floor inside the arena
Assets/UI/border/arena.png              just the frame around the arena
Assets/UI/panel/inspect.png             just the inspect panel
```

The specific file wins for that element, the general one keeps covering
everything else, and neither step is a code change. Delete either and the game
falls back a level.

**That is the complete list of names.** A name that is not on it resolves to
nothing, silently, forever — the file sits on disk looking correct and the game
never reads it. This list is checked by a test, the same way the ability and
item lists above are, so a screen added later cannot quietly acquire a name
nobody could guess.

<!-- pending:  -->

**Every name above works.** Two tests keep that true rather than a sentence
doing it: one reads this file's specific names against the real call sites, and
one reads its general names the same way. A name printed here that nothing asks
for fails the build, and so does a file that nothing calls.

**One panel is on purpose not in the set: the seed field on the party screen.**
Its border is what tells you the seed is something you can type in, and a
picture that made it look like every other panel would take that away. The same
goes for anything else whose edge is saying more than "here is an edge" — see
the section below.

A border and a panel are **nine-sliced**: the corners are drawn at their own
size and the edges stretch between them, so one file works for a small tooltip
and a full panel. Draw it square, and put the corner detail inside the outer
third — a 24x24 file has 8-pixel corners.

A **background is different**: it is scaled to **cover** the screen and cropped,
rather than fitted inside it with bars down the sides. So its aspect ratio does
not have to match anything, but **keep anything you care about away from the
edges**, because which edge gets cropped depends on the window. Anything from
about 480x270 upward scales up cleanly; there is no maximum.

### What the borders are still saying

Some of these borders are carrying information as well as decoration. A party
card's border says whether that pawn is one of the four you picked. Where that
is true, the game keeps drawing the signal **inside** your border rather than
letting your file replace it, so a picked pawn still looks picked.

That is the rule everywhere here: **a picture replaces decoration, and does not
replace information.** It is worth knowing because the alternative would look
completely fine in a screenshot and would have quietly removed something you
need to see.

## Size and shape

- **Any size.** An icon is scaled so its longest side fits the box it is given.
- **Aspect ratio is preserved.** A tall image stays tall rather than being
  squashed.
- **Transparency works.** Whatever is behind shows through.
- **Nearest-neighbour scaling**, so pixel art stays crisp instead of blurring.
  Draw small and let it scale up.

## One thing worth knowing

These images are read with `Image.load()` and turned into textures at runtime,
rather than through Godot's normal import pipeline, for the same reason
`Assets/Units/` does it: the Godot editor does not currently run on this machine
(see the header of `Scripts/Core/CG.gd`), so anything requiring an import step
would be impossible to add here.

The upshot for you is good: **your PNG works whether or not the editor has ever
seen it.** If the editor becomes usable later, nothing about this changes and
nothing needs migrating.
