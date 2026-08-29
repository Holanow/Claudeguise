# Fonts

Two vendored faces, both SIL Open Font License 1.1, each with its `OFL.txt`
next to it. They are loaded at run time by `Scripts/Art/FontLibrary.gd` with
`FontFile.load_dynamic_font`, the same way `Assets/UI/` PNGs are loaded with
`Image.load` and for the same reason: nothing here needs Godot's import step,
so a dropped-in file works whether or not the editor has ever seen it.
`*.import` is gitignored, so a `.tres` reference would not survive anyway.

| Family | File | Role |
| --- | --- | --- |
| EB Garamond | `EBGaramond/EBGaramond.ttf` (variable, `wght`) | **The printed form.** Screen titles, column headings, section labels, button faces. Set in caps and letterspaced, the way a ledger's pre-printed furniture was engraved. |
| Spectral | `Spectral/Spectral-Regular.ttf`, `Spectral-SemiBold.ttf` | **The clerk's entry.** Everything that is data: pawn names, figures, the combat log, tooltips. |

**Both have tabular figures by default, and that was measured rather than
assumed.** At 20px every digit advance is identical: EB Garamond 10.0 for all
ten, Spectral Regular 10.0, Spectral SemiBold 11.0. So a column of damage
numbers aligns with no OpenType feature override. Libre Baskerville and IM Fell
English were rejected on exactly this test -- their digits are proportional
(Libre Baskerville ran 9.0 to 14.0) and a ledger cannot use a face whose
figures will not stack.

To replace a face, drop a `.ttf` in and point `FontLibrary` at it. Keep the
licence file with it.
