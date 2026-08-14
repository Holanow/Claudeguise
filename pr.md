Agent: finch (engineer)

Issues #100 (equipment content) and #99 (the Warrior's replacement skill). One room only.

Full gate, not filtered, after merging `main`: **589 tests, 4424 assertions, green**, 138 scripts parse.

## The premise of #100 is wrong, and I stopped to check before building on it

> *"`grep '_equipment(&\"'` returns nothing: **zero items are defined**"*

**Seventeen items are defined, registered and tested**, and have been since issue #39. `Scripts/Content/Modules/core_items.gd`: 4 weapons, 5 armor, 8 accessories, in `Registry.MODULES`, covered by six tests in `Tests/test_content_items.gd`. **The grep found nothing because no helper named `_equipment` was ever written** — the constructors are `_weapon(&"`, `_armor(&"` and `_accessory(&"`. `allowed_methods` is populated on every weapon too (issue #40), which is the caster-in-plate gating the issue asks for.

I posted this to the board before writing any code, because wren was about to build an equip screen against "there are no items".

**The issue's conclusion survives; only its reason changes.** What was actually missing:

1. **No item granted any action.** `granted_actions` had been on `EquipmentDef` since #39 with all seventeen items leaving it empty. This is the load-bearing gap and it is fixed here.
2. **Nothing ever equips anything.** `PawnFactory.make_starter_pawn` sets no `weapon`, `armor` or `accessory`, so `PawnData.equipment()` returns empty for every pawn in every fight. *That* is why equipment is unreachable.
3. **No pre-fight equip UI.** wren's, unchanged.

None of the plumbing needed building: `Balance.attribute`, `Balance.damage_reduction` and `CombatSim._collect_player_actions` already read equipment correctly.

## What this changes

**Plate Mail grants Directional Block**, per README's own armor table (`Plate Mail | Tank | Block`). Block was always meant to come from armor.

**Two defects found on the way, and the first is why the field was untestable.**

- **Nothing checked that a unit owns the action a plan fires.** `PlanInterpreter` resolved straight out of `Registry` and `CombatSim._resolve_use_action` did the same. So a Warrior wearing plate and a Warrior wearing nothing both cast Block — **equipping the item changed nothing observable, which makes `granted_actions` impossible to test by construction.** Now gated on `unit.actions`. It is also the reverse of #98's principle: a pawn firing an ability it does not own is the same surprise seen from the other side.
- **"What a pawn can do" was computed in two places that had already diverged.** `CombatSim._collect_player_actions` = class actions **plus equipment grants**. `InspectPanel._available_actions` = class actions **only**. So the moment an item granted an action, the fight knew and the plan editor did not. `Registry.actions_for_pawn` is now the single definition.

**Issue #99:** `warrior_block` leaves the Warrior's kit and `warrior_second_wind` replaces it — a self-heal, 15 Rage, ~38 health, `cooldown 450` (30s). Block is not deleted; it moves to plate. WIS stays at 8 because a plan was replaced, not added. `DefaultBehavior` now treats a **zero-range heal as self-only** — without that, a Warrior carrying it walks toward a hurt ally forever trying to close a distance that can never be small enough, and stops fighting. That would not have failed loudly; a tank walking toward its hurt healer looks almost deliberate.

## What I could NOT prove, and it is the constraint the issue names

> *"A granted action must be reachable, meaning it appears in the plan editor and can actually fire."*

**It fires. It does not yet appear in the plan editor, and that half is not mine.** `InspectPanel._available_actions` (line 506, `Scripts/UI`, wren's) returns `pawn.pawn_class.starting_actions` and nothing else. Until it is repointed, a player who equips Plate Mail gets Block in the fight but cannot see or plan it.

**wren — this is the whole fix, one line:**

```gdscript
func _available_actions(pawn: PawnData) -> Array:
	return Registry.actions_for_pawn(pawn)
```

`Registry.actions_for_pawn` returns the deduplicated union in a stable order and handles a null pawn. I built it rather than describing it so the two definitions cannot drift again. `CombatSim._collect_player_actions` should be repointed at it too — one line, `Scripts/Combat`, also not mine.

So: **equipment is no longer the first built-and-unreachable thing, but it is not fully reachable either, and I am saying so rather than letting the PR imply otherwise.**

## Verification

`Tests/test_content_equipment_grants.gd`, 11 tests. The load-bearing pair is `test_a_warrior_without_plate_cannot_block` / `test_a_warrior_wearing_plate_can_block` — **either alone is worthless.** The first also passes if Block is broken for everybody; the second also passes if Block fires for everybody. Only together do they say the item is what did it. That is the habit from #93, where an assertion of mine passed while measuring nothing.

Screenshot after the last commit: `Screenshots/finch_99_second_wind_01.png`. Log reads "Warrior begins Second Wind" → "Warrior's Second Wind fires" → "Warrior heals Warrior for 38", with the heal floater on the Warrior. Produced by `Tools/SecondWindShot.gd`, which searches for a fight where the ability actually heals rather than trusting a pinned seed, and captures the HEAL tick rather than the wind-up — a fire with no heal behind it would be a screenshot of the ability doing nothing.

## Balance, measured not pre-flattened

`Tools/SampleFights.gd`, 35 buildable rows x 20 seeds = 700 single-room fights. **649 → 657 wins (+8).**

**The isolation is clean: every changed row carries a Warrior, and all seven rows without one are byte-identical.** That is the strongest evidence the change does what it claims and nothing else.

Warrior parties get durable in the rooms that were actually hard:

| encounter | party | wins | cost (median hp on a win) |
|---|---|---|---|
| `floor1_room1` | abomination, siege_master, priest, warrior | 16 → **20** | 46% → **69%** |
| `floor1_room1` | abomination, geysermancer, priest, warrior | 17 → **20** | 45% → **61%** |
| `floor1_room1` | abomination, siege_master, geysermancer, warrior | 18 → **20** | 48% → **66%** |
| `floor1_chokepoint` | abomination, siege_master, priest, warrior | 17 → **20** | 70% → 55% |

**Two rows get worse, and it is the same cause both times: losing Directional Block.** `siege_master, geysermancer, priest, warrior` — the only Warrior party with no Abomination, so the most ranged-heavy — drops **20 → 17** on `floor1_room1` and **20 → 18** on `floor1_chokepoint`. That party benefited most from a body intercepting shots. **They can get it back by wearing Plate Mail, and cannot until wren's equip screen exists.** Reported rather than compensated for.

**One thing I trimmed, and I want it on the record because trimming is the thing I was told not to do reflexively.** At my first numbers (power_scale 3.0, cooldown 300) `test_content_encounter.gd::test_the_warden_asks_something_of_every_real_party` went red at 75.9% against a 75% cap. **I did not loosen that cap**, even though that file documents its own precedent for doing so (70 → 75 on issue 79 for the same shape). The reason: the test measures one party order and was 0.9 of a point over, while `SampleFights` showed the same party's Warden cost moving 52% → 70% — an 18-point swing. Loosening a threshold by one point to hide an eighteen-point change is how a regression ships with a green checkmark. I tuned my own content instead (3.0 → 2.2, 300 → 450), which is mine to tune, and the cap now passes on its own terms.

**Disclosed anyway: the Warden cost swing is still 52% → 70% for `abomination, siege_master, priest, warrior` in `SampleFights` ordering.** The test does not catch it because it builds parties alphabetically and `SampleFights` builds them in `all_class_ids()` order — the order-dependence that file's own header already documents at length. **If a boss getting materially cheaper for one party is not wanted, second wind needs trimming further, and that is a balance call for rook or the player rather than one I should make quietly.**

## Disclosed edits in files I do not own

- `Scripts/Art/ActionIcons.gd`: one data line, `&"warrior_second_wind": _CROSS`. Same shape as my `geyser_cleanse` line on #87 — `test_every_reachable_action_has_an_icon` goes red the moment a reachable action lands.
- `Tests/test_art.gd`: one entry in `_DELIBERATE_SHARED_GLYPHS`, `"priest_heal|warrior_second_wind"`. **Using the mechanism that test's own failure message prescribes, not editing its assertion.** Every glyph in `ActionIcons` is already spoken for, so the choice was share one or author new art, and the art is sable's to draw. The two are never drawn side by side — different classes, and no pawn can carry both. sable: draw Second Wind its own shape and delete the entry; that test's negative half will fail if you forget.

## Also noticed, not fixed

- `PawnFactory` equipping nothing means **every balance number in this project was measured on pawns wearing no equipment.** Once the equip screen lands, the whole table moves. Worth knowing before anyone treats today's numbers as a baseline.
- I did not build the base type tables, per the issue. The existing seventeen items already cover all three slots.
- `allowed_methods` is deliberately left empty on `plate_mail`: README gates armor by role (`Tank`) and `allowed_methods` only speaks martial-versus-magical, so gating there would say something the design does not — the Abomination is a Tank and is MAGICAL.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
