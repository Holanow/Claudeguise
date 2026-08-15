# What the badges need to be legible, measured

Answering PLAYTEST-FRESH-1: *"~12px pentagon badges … still meaningless, and
invisible at 1x"* and *"the fight screen needs about a third as much, drawn four
times larger."*

I cannot judge this by looking, because I know what every badge means and cannot
un-know it. **A reader who knows the answer cannot measure legibility.** So this
measures the thing underneath it: how much two badges physically differ in
pixels. Two badges differing in nine pixels are telling nobody apart, whatever
they depict.

Instrument: `Tools/BadgeLegibility.tscn`. Sheet: `Screenshots/badge_legibility.png`.

---

## 1. The playtest measured the wrong number, and so has everyone else

| | badge | wind-up icon |
|---|---|---|
| Shipped, 1280x720 | **17.4 px** | 19.9 px |
| Shipped, 844x390 | **9.4 px** | 10.8 px |
| `Tools/IconsOverlay.gd`, the diagnostic harness | 14.0 px | 16.0 px |

The harness hardcoded raw screen pixels; the game uses world units scaled by the
arena fit. **Every judgement about these badges has been made on a picture ~20%
smaller than the game draws.** Its own header already said it existed to stop
them "silently being drawn bigger than they are" — the intention was right and
the number was never derived. Fixed in this branch, with a test pinning the
harness to `UnitView`'s constants.

This does not overturn the playtest. It sharpens it: at 844x390 the badge really
is **9.4 px**, which is smaller than the figure they complained about.

## 2. Size is not the main problem. This is the finding.

Fraction of pixels on which two badges **disagree**, same-category pairs (rim
colour and plate direction already separate harmful from helpful, so within a
category the glyph is the only thing carrying identity):

```
  17.4 px SHIPPED    mean 15.9%   best pair 25.6% (stun/marked)
                                  worst pair 2.1% (bleed/burn)
```

**The two most distinct badges in the system share three quarters of their
pixels.** The average pair shares 84%.

That is a proportion, so it does not improve with size:

```
  12.0 px   bleed/burn  1.4%
  14.0 px   bleed/burn  2.6%
  17.4 px   bleed/burn  2.1%
  24.0 px   bleed/burn  2.1%
  32.0 px   bleed/burn  2.5%
```

**Bleed and burn are the same picture at every size tested.** Both are red
teardrops on a red down-pointing plate. Drawing them four times larger produces
two large identical badges.

**Where the pixels go.** A badge spends ~84% of itself on plate and rim — which
encode *harmful vs helpful*, a fact already carried twice over, by colour and by
plate direction, deliberately and correctly for colourblind safety. It spends the
remaining ~16% on the glyph, which is the only thing not encoded anywhere else.
**At 17 px that allocation is backwards.**

## 3. The badges are wider than the units

At 1280x720 a full row of 4 badges is **84 px** wide:

| unit | across | badges are |
|---|---|---|
| goblin | 27 px | **3.1x the unit** |
| ghoul | 40 px | 2.1x |
| the_warden | 55 px | 1.5x |

The playtest's *"a dozen 12px badges layered on top of each other"* is this. Also
`MAX_STATUS_BADGES` is 4, so a unit carrying five statuses silently drops one and
nothing says which.

## 4. Three of twelve stroked glyph parts are at the 1 px clamp

`UIArt._stroke` floors stroke width at 1.0 px. A clamped stroke means the glyph
has stopped scaling down and started fusing — the system is already at its
physical floor at the shipped size, and at 844x390 it is well past it.

## 5. The "single most confusing object on screen" is identified

The playtest's *"lone cream bar with a pen-nib icon at the very bottom-left,
floating below everything, attached to nothing"* is a **wind-up progress bar with
`priest_smite`'s icon**. Cream because that is the DIVINE damage colour. The
glyph, `_BEAM`, is a trapezoid over a horizontal bar — which is a pen nib. It is
mine and it needs redrawing; the "attached to nothing" half is placement.

---

## What I would drop, in order

Stated as recommendations, not decisions — routing is rook's.

1. **Redraw bleed or burn regardless of anything else.** 2.1% at 32 px is a
   defect no layout change fixes.
2. **Spend the plate on the glyph.** Drop the filled plate to a bare outline so
   the glyph gets the interior. The category channel survives on rim colour plus
   the direction of the outline, which is the same two channels as today — the
   redundancy that is worth paying for is *colour plus shape*, not *colour plus
   shape plus 84% of the pixels*.
3. **Cut the number of badges, hard.** Four badges at 3.1x the unit's width is
   not a labelling system. The honest options are: show only harmful statuses on
   the unit, or show only one, or replace the row with a single "afflicted" mark
   and put the detail in the pause-hover panel — which exists and is where 24 px
   and up is affordable.
4. **Nothing survives at 844x390.** At 9.4 px there is no badge design that
   works. That resolution needs the marks dropped entirely, not shrunk.

---

# Addendum, after PLAYTEST-FRESH-2

The rework shipped and a second cold reader saw it. **Both halves of my own
prediction held.** They could half-see the individual glyphs — *"a white diagonal
slash on red, a three-dot triangle, a `»` double-chevron in green, a plain white
shield in green, an asterisk"* — which is bleed, poison, haste, shield and stun,
correctly distinguished. That is the pixel-disagreement work paying off.

And then: *"At the size they render they are grey noise."* Section 2 above said
pixel disagreement is a floor and not legibility, and that the only real test was
another fresh pair of eyes. It was, and the answer is that **distinct is not the
same as readable.** Recommendation 3 — cut the number of badges — is the one that
matters now, and it is not a drawing change.

## 6. Every mark on a unit is sized from a radius the art does not fill

New measurement, and it explains the playtest's headline complaint in numbers.

Everything attached to a unit — health bar, badge row, impact ring, name plate —
is sized from `u.radius * DISPLAY_SCALE`. That is the **simulation's collision
radius**, not the size of the drawing. The silhouettes fill between 0.56 and 1.00
of it:

| shape | drawn width / nominal |
|---|---|
| rat_king, brute | 1.00 |
| the_warden, abomination | 0.99 |
| siege_master, warrior | 0.96 |
| ghoul, geysermancer | 0.86 |
| priest | 0.72 |
| stalker | 0.66 |
| **goblin** | **0.56** |

> ### CORRECTION, 2026-08-15. The table above is wrong. See section 8.
>
> **It measures polygons the game does not draw.** Ten shapes have real PNGs in
> `Assets/Units/` and take the texture path through `Silhouettes.draw_unit`; for
> those, `build_parts` is dead code. I measured the dead code and published it.
> The finding it supports survives and gets worse; the numbers do not. The
> corrected table is section 8 and the measurement now goes through
> `Silhouettes.fill_ratio`, which takes the same two paths `draw_unit` does.

At 1280x720, in real screen pixels:

| enemy | drawn body | impact ring ends at | ring / body |
|---|---|---|---|
| goblin | 15.3 px | 49.2 px | **3.2x** |
| goblin_archer | 16.1 px | 49.2 px | 3.1x |
| stalker | 16.4 px | 44.7 px | 2.7x |
| cultist | 22.6 px | 53.6 px | 2.4x |
| the_warden | 54.1 px | 98.3 px | 1.8x |

**The overshoot is worst on the smallest units**, which are the ones a player can
least identify. A goblin is a 15 px body wearing a 90 px health bar, an 84 px
badge row and a 49 px impact ring. *"A field of floating coloured dashes with
insects underneath them"* is this table.

**The goblin is not drawn wrong.** It is a small hunched creature and 0.56 is
what that shape is; widening it would make it not a goblin. The mismatch is that
decoration is scaled from a collision radius rather than from the drawing, and
that is not a change I can make inside `Scripts/Art/**`.

## 7. The impact flash is coloured by a fact about a different unit

PLAYTEST-FRESH-2 lists two symbols it could not interpret:

> *"The dark grey circle outline that briefly rings a unit. Impact flash? A taunt?
> A guard?"*
>
> *"The concentric purple rings around the Priest. Something firing, but purple
> reads as Profane, which is the Abomination's damage type, not the Priest's."*

**These are the same mechanism, and the reader could not tell.** Both are
`AttackFX.draw_impact_flash`. It is drawn on the unit that was **hit** and
coloured by the damage type of whoever **hit it** — so the purple ring on the
Priest is a Cultist's Dark Bolt landing (verified: `cultist_bolt` and every
`abomination_*` action are PROFANE; every Priest action is DIVINE).

Two consequences, and the second is the real one:

1. One mechanism wearing seven colours never becomes learnable. Grey and purple
   read as two different events.
2. **A ring centred on a unit reads as that unit acting.** Every other mark on a
   unit describes that unit; this one describes its attacker. The reader's
   instinct — *"something firing"* — is the correct reading of the picture and
   the wrong reading of the event.

The geometry is mine. Which damage type gets passed is `BattleView`'s. Whether an
impact should be recoloured, reshaped, or moved to the attacker is a design call
and is filed, not decided here.

## 8. The fill table, corrected — and the pawns are the worst of it

Section 6's table was taken off `Silhouettes.build_parts`. Ten shapes have PNGs
in `Assets/Units/` and draw the texture instead, so for those the polygons are
dead code. **The published number was a fact about art nobody sees.**

Re-measured through `Silhouettes.fill_ratio`, which branches exactly the way
`draw_unit` branches, and against the sprite's **opaque** pixels rather than its
file dimensions — pixel art carries transparent margin, and reading `get_width`
would have fixed part of the error while looking like it fixed all of it.

| shape | art? | **real x** | **real y** | polygon x (published) |
|---|---|---|---|---|
| **priest** | yes | **0.50** | 0.96 | 0.72 |
| **warrior** | yes | **0.54** | 0.71 | 0.96 |
| **geysermancer** | yes | **0.54** | 0.71 | 0.86 |
| ghoul | yes | 0.54 | 0.83 | 0.86 |
| cultist | yes | 0.58 | 0.79 | 0.76 |
| goblin_archer | yes | 0.58 | 0.71 | 0.59 |
| stalker | no | 0.66 | 0.91 | 0.66 |
| **goblin** | yes | **0.71** | 0.75 | **0.56** |
| abomination | yes | 0.79 | **0.50** | 0.99 |
| **siege_master** | yes | 0.83 | **0.33** | 0.97 |
| the_warden | yes | 0.88 | 0.79 | 0.99 |
| rat_king, brute | no | 1.00 | 0.97 | 1.00 |

Three things change, and two of them matter more than the original claim.

1. **The goblin is not the worst shape. It is one of the better ones** (0.71).
   I said *"the overshoot is worst on the smallest units"* and named the goblin;
   the direction was right and the example was wrong.
2. **The narrowest things on the field are the player's own pawns.** Priest
   0.50, Warrior 0.54, Geysermancer 0.54. Every published number said the pawns
   were nearly full (0.72 to 0.96). So the mismatch is worst on the four units
   the player is actually watching, which makes #190 a bigger fix than filed,
   not a smaller one.
3. **The vertical axis was never measured at all and is worse than the
   horizontal.** `siege_master` fills **0.33** of its box vertically, the
   abomination 0.50. Anything stacked *above* a unit — the whole bar and badge
   column — is offset from a radius the art misses by two thirds.

`Silhouettes.drawn_extent` returns the box, per axis, in the space `draw_unit`
draws into. That is the art half of #190 and it is all of it that is mine.

`priest.png` is twelve opaque columns of a twenty-four-wide file, so it lands on
exactly 0.50, which is where `test_no_silhouette_is_drawn_tiny_inside_its_own_
footprint` puts its floor. The floor did not move across the correction; the
worst shape moved onto it. The next shape drawn any narrower goes red.

---

## The rule this file exists to stop me forgetting

**The read is mass, not taper. A gentle taper is not a taper at 9 pixels.**

Every glyph defect I have shipped is one sentence: I drew a shape whose identity
lives in a gradual change of width, and at badge size the gradual part quantises
away and leaves a blob whose *area* is the only thing the eye gets. Bleed and
burn shared 98% of their pixels for exactly this reason — both are teardrops,
and a teardrop is a taper.

So when a glyph has to differ from another glyph, differ in **how much ink is
where**: solid versus hollow, one part versus three, ink at the top versus ink
at the bottom. Never in the *rate* at which an edge narrows.

And its corollary, which has cost more than the rule itself:

**Rendering has caught fifteen defects on this project. Reading has caught
none.** Including a glyph that rendered as the exact drawing the comment I had
just written said it was avoiding. If you have not looked at it at true size,
you do not know what it is.

## What I did not do

- **No drawing changed in this branch.** This is measurement plus the instrument
  fix, so the numbers can be re-run against whatever gets decided.
- **I did not measure a real fight frame's total mark count.** The playtest
  counted it by eye and I have no reason to doubt it; my numbers are per-badge.
- **Legibility itself is still unmeasured**, and by me it is unmeasurable. Pixel
  disagreement is a floor: badges that differ in 2% of pixels cannot be told
  apart, but badges that differ in 26% are not thereby legible. **The only real
  test is another fresh pair of eyes**, and that is worth spending one on once
  something changes.
