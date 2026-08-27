---
name: shader-craft
description: Write Claudeguise shaders that read as professional rather than amateur. Use when authoring or reviewing any .gdshader, any AbilityVFX layer, or any effect where geometry is a function of live state.
---

# Shader craft

For sable, and for anyone touching `Shaders/` or `Scripts/Art/VFX/`.

Three shaders ship today and they are the reference: `beam.gdshader`,
`charge_orb.gdshader`, `shockring.gdshader`. Both of the mistakes named under
"the tells" were made in those files and fixed; the fixed versions are in the
repo.

## First, the rule that decides whether a shader should exist

**If a picture is the same every frame, it is a PNG.** `CLAUDE.md` is explicit
and it is not negotiable. A shader is allowed only where the geometry is a
function of live state: the orb's `charge`, the beam's `extend`, the ring's
`progress`. Those cannot be baked because the asset would have to change every
frame.

A shader that draws a static glow is a PNG somebody made expensive.

## The tells: what makes a shader read as amateur

These are checkable. Look for them before anything else.

**One frequency.** Everything moving at the same speed reads as a screensaver.
Real effects have macro timing (the whole event) and micro timing (one particle's
size, one flicker). `beam.gdshader` scrolls its noise at `TIME * 7.0` while the
cross-beam term moves at `TIME * 1.5`; that ratio is the point.

**Raw noise, undressed.** `fbm` straight into alpha looks like television static.
Noise is a *modulator* — it perturbs an envelope that already has a shape. In the
beam, `turb` multiplies a `sin(along * PI)` taper. The taper is the effect; the
noise is the texture on it.

**Hard edges everywhere, or soft edges everywhere.** Professional work has both,
deliberately: a hot core with a knife edge inside a diffuse falloff.
`smoothstep(w, w * 0.15, across)` for the body and `smoothstep(w * 0.42, 0.0,
across)` for the core is two edges of different hardness in one pass.

**Uniform brightness.** The single biggest readability tool is **value range**.
An effect that is all mid-bright has nothing for the eye to land on. Push a small
area much brighter than everything around it.

**A ramp that is a `mix` of two colours.** Real fire is not orange lerped to red.
Use at least three stops and put the hottest one in a *small* part of the shape.
`CPUParticles2D` takes a `Gradient` with a mid-point — use it.

**No dissipation.** Amateur effects stop. Professional ones clear. Every layer
needs a fade whose length is authored, and it must finish before the next action
starts or the screen silts up.

**Additive on everything.** `blend_add` on a large area blows out to white and
loses all shape. It belongs on the hot, small parts.

## The four craft principles, in priority order

Taken from the League of Legends VFX guide, which is the most useful public
document on this and matches what this project keeps rediscovering.

1. **Timing.** An effect is half animation, half rhythm. Anticipation telegraphs,
   impact lands on the exact frame, dissipation clears. **This is where a bad
   effect is usually bad** — the shapes are fine and the beats are wrong.
2. **Silhouette.** Shape is how the player identifies *what* happened. A blob is
   not a shape. The shape must be readable in one frame, at the size it actually
   draws, against the arena's grey floor.
3. **Value.** Contrast is how the player's eye is *directed*. Value range is a
   more powerful attention tool than colour and it survives colourblindness.
4. **Colour.** Last, and it carries meaning rather than attention: fire reads
   warm, water cool. Colour must agree with the damage type the action actually
   deals — `DamageEffect.damage_type` is the source of truth, not a hex value
   somebody liked.

## Timing numbers that work here

The simulation runs at 15 ticks per second. These are the values in the shipped
`geyser_blast` and they are a good starting point rather than a law:

- **Beam extend: 0.07 s.** Fast enough to read as instant, slow enough to see.
- **Hold: 0.10 s.** The beam exists.
- **Fade: 0.22 s.** Longer than the extend, always — things arrive faster than
  they leave.
- **Impact layers delayed by the extend time.** Without this the target flinches
  *before* it is hit, which reads as wrong even when nobody can say why.
- **Hit stop: under 0.10 s.** Past that it stops feeling like impact and starts
  feeling like a stutter.
- **Wind-up tell: the whole wind-up.** It is a promise about when the hit lands.

## Performance

Claudeguise ships the **Compatibility (GL) renderer**. Assume the weakest target.

**Fill rate is the budget, and transparency is what spends it.** Godot's own GPU
optimization page: transparent objects must draw back-to-front, cannot use the
Z-buffer, and *"every item has to be drawn even if other transparent objects will
be drawn on top later."* Keep transparent areas **as small as possible**. A
full-screen additive quad at alpha 0.05 costs the same fill as one at alpha 1.0.

**Texture reads are the other cost.** *"Reading textures is an expensive
operation, especially when reading from several textures in a single fragment
shader."* All three shipped shaders generate value noise arithmetically and read
**zero** textures. Keep it that way unless a texture buys something noise cannot.

**Reuse materials.** Godot: 20,000 objects with 20,000 materials is slow; the same
objects with 100 materials is much faster. One `ShaderMaterial` per layer *type*,
parameterised — not one per instance.

**Prefer arithmetic to branching.** `smoothstep`, `step` and `mix` are free-ish
and uniform across the wavefront; an `if` on a varying value is not.

**`discard` early where it is genuinely free.** `beam.gdshader` does
`if (along > extend) { discard; }`, which skips the whole fragment for the part
of the beam that has not extended yet — real savings while the beam grows.

**fbm costs what its octaves cost.** Four is plenty at this size. Eight is a
smell, not a quality setting.

## Reviewing a shader: the checklist

- Could this be a PNG? If yes, it must be.
- Does anything move at exactly one frequency?
- Is there a bright core smaller than the diffuse part?
- Does it clear, and does the clear finish before the next action?
- Do the impact beats wait for the travel time?
- Does the colour agree with the action's `damage_type`?
- Is any transparent area larger than it needs to be?
- How many texture reads? Justify each.
- **Has it been looked at?** Render it in a real fight and put the frames in the
  PR. This project has shipped drawn geometry that tests passed and eyes had
  never seen — see #280.

## Two mistakes made in these exact files

Both shipped, both were caught by looking at a contact sheet, neither by a test.

**The unmasked head.** `beam.gdshader` has a bright head racing along as it
extends. The first version was `smoothstep(0.10, 0.0, abs(along - extend))` with
nothing constraining it across the beam's width — so it drew as **a hard white
slash straight across the screen**. The fix is one term:
`* smoothstep(w, w * 0.15, across)`. **Any term that varies along one axis must
be masked by the envelope on the other.**

**The squared falloff.** `shockring.gdshader` faded with `(1.0 - progress) *
(1.0 - progress)`. By the time the ring was large enough to notice it had already
faded to nothing. One falloff, not two: `(1.0 - progress * 0.85)`. **A thing that
grows must not dim as fast as it grows, or nobody sees it.**

## Where a shader hangs

Never keyed off an id in the view. A look is an `AbilityVFX` on the `ActionDef`,
composed of `VFXLayer` resources. Adding a new visual is a **new layer resource**,
not a new field and not a branch in `BattleView`. `AbilityVFX` and `VFXLayer` live
in `Scripts/Core/`; every layer that draws lives in `Scripts/Art/VFX/Layers/`,
and that split is load-bearing — a simulation file naming view code breaks what
the fingerprint proves.

## Sources

- [Godot GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html)
- [League of Legends VFX Guide 2017](https://www.deck.gallery/league-of-legends-2017/)
- [The importance of timing in VFX](https://www.vfxapprentice.com/blog/the-soul-of-effects-what-is-timing-in-vfx)
- [Artistic principles of game VFX](https://www.vfxapprentice.com/blog/five-artistic-principles-gaming-vfx)
