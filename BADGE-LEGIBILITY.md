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
