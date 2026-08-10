# Token Burn — Button Style Guide

This document defines the button styling system for **Token Burn**, a Godot-based roguelite / tycoon / engine-builder game.

The goal is to make the UI feel like part of the game world: **industrial terminal hardware, worn controls, restrained neon accents, and deliberate feedback**.

The guiding rule is:

> **90% dark hardware, 10% illumination.**

Colour should communicate state, importance, selection, danger, or interactivity. Avoid making every button brightly coloured.

---

## 1. Core Visual Language

Buttons should feel like controls built into a hacker workstation, not generic mobile or SaaS UI.

### Use

- Dark charcoal / near-black surfaces
- Thin hard-edged borders
- Very small corner radius
- Condensed uppercase labels
- Left-aligned content
- Small semantic accent colours
- Subtle inset highlights
- Minimal glow
- Short, snappy hover and press feedback

### Avoid

- Large rounded corners
- Bright full-button fills
- Heavy gradients
- Excessive bloom or neon glow
- Centred text everywhere
- Oversized cards
- Different visual treatment for every individual button

---

## 2. Base Button Geometry

Recommended baseline:

```text
Minimum height:      64 px
Horizontal padding:  16 px
Vertical padding:    12 px
Corner radius:       3 px
Border width:        1 px
Icon area:           32–40 px
Internal gap:        10–12 px
```

Godot theme guidance:

```gdscript
const BUTTON_MIN_HEIGHT := 64
const BUTTON_RADIUS := 3
const BUTTON_BORDER := 1
```

Buttons should generally be wider than they are tall and should read as **control modules** rather than cards.

---

## 3. Base Colour Palette

Recommended starting palette:

```text
Background           #0D1013
Background Hover     #14181B
Background Pressed   #090B0D

Border               #343A40
Border Hover         #596168

Primary Text         #E1E1DF
Secondary Text       #7E858A
Disabled Text        #4E5459

Cyan                 #18B7D8
Cyan Bright          #32D6F3

Burn Orange          #E45125
Burn Orange Bright   #FF6838

Legacy Violet        #9B70C8

Trophy Amber         #D7A624

Lab Teal             #3B9DAA

Danger Red           #C93847
Danger Bright        #E53E50
```

Treat these as semantic colours rather than decorative colours.

---

## 4. Standard Button

Use the standard button style for:

- Legacy
- Trophy Cabinet
- Burn Lab
- Settings
- Other secondary navigation

### Default

```text
Background:     #0D1013
Border:         #343A40
Text:           #E1E1DF
Secondary text: #7E858A
Radius:         3 px
```

Suggested Godot `StyleBoxFlat`:

```gdscript
var style := StyleBoxFlat.new()

style.bg_color = Color("#0D1013")

style.border_width_left = 1
style.border_width_top = 1
style.border_width_right = 1
style.border_width_bottom = 1

style.border_color = Color("#343A40")

style.corner_radius_top_left = 3
style.corner_radius_top_right = 3
style.corner_radius_bottom_left = 3
style.corner_radius_bottom_right = 3

style.content_margin_left = 16
style.content_margin_right = 16
style.content_margin_top = 12
style.content_margin_bottom = 12
```

---

## 5. Typography

### Main Label

Use a condensed display font where possible.

```text
Case:           UPPERCASE
Size:           16–18 px
Weight:         Medium / Semi-bold
Letter spacing: Slightly expanded
Colour:         #E1E1DF
```

Example:

```text
TROPHY CABINET
```

### Secondary Label

```text
Size:   11–13 px
Colour: #7E858A
```

Example:

```text
4 / 28 EARNED
```

### Alignment

Prefer:

```text
[ICON]  TROPHY CABINET
        4 / 28 EARNED
```

Avoid centring all button content unless the control specifically benefits from it.

---

## 6. Primary Action — Continue

`CONTINUE` should be the strongest menu action.

Do **not** fill the entire button cyan.

Instead use a dark surface with a cyan powered edge.

### Default

```text
Background:  #0C1519
Border:      #18B7D8
Accent rail: #18B7D8
```

Suggested layout:

```text
┌────────────────────────────────┐
│ ▌ ▶  CONTINUE                  │
│      ROUND 2 • PROMPT 10       │
└────────────────────────────────┘
```

The left accent rail can be 3 px wide.

Optional restrained glow:

```text
Cyan glow opacity: approximately 5–12%
```

The control should look **powered**, not painted.

---

## 7. New Run

`NEW RUN` uses the burn-orange semantic accent.

### Default

```text
Background:  #11100E
Border:      #7B3320
Accent rail: #E45125
Icon:        #E45125
```

### Hover

```text
Border:      #FF6838
Accent rail: #FF6838
```

Avoid filling the entire button orange.

Example:

```text
┌────────────────────────────────┐
│ ▌ 🔥 NEW RUN                   │
│      Start again from bedroom  │
└────────────────────────────────┘
```

---

## 8. Secondary Navigation Accents

Secondary menu items share the same structural style.

Only the accent changes.

### Legacy

```text
Accent: #9B70C8
```

### Trophy Cabinet

```text
Accent: #D7A624
```

### Burn Lab

```text
Accent: #3B9DAA
```

### Settings

```text
Accent: neutral grey
```

Example:

```text
┌───────────────────────┐
│ ◇ LEGACY              │
│   Permanent unlocks   │
└───────────────────────┘
```

Accent colour can be applied to:

- icon
- small left rail
- tiny status marker
- secondary value
- hover border

Do not colour the whole button.

---

## 9. Hover State

Hover should make the control feel like it has powered up.

Recommended behaviour:

```text
Background: slightly brighter
Border: brighter
Accent: brighter
Position: optional -1 px Y movement
Duration: 80–120 ms
```

Example style:

```gdscript
hover_style.bg_color = Color("#14181B")
hover_style.border_color = Color("#596168")
```

For a cyan primary control:

```gdscript
hover_style.border_color = Color("#32D6F3")
```

Optional effects:

- icon brightness increases
- tiny status LED activates
- extremely subtle glow appears
- short flicker when first hovered

Avoid long, floaty UI animations.

---

## 10. Pressed State

The pressed state should feel mechanical.

Recommended feedback:

```text
Move:       +1 px Y
Background: darker
Inset feel: stronger
Duration:   60–90 ms
```

Example:

```text
Default:  slightly raised
Pressed:  pushed inward
```

Avoid scaling the entire button dramatically.

---

## 11. Focus State

Keyboard/controller focus should be visually distinct from hover.

Recommended:

```text
Border: accent colour
Outer line: 1 px
Glow: very subtle
```

Do not rely on colour alone.

Consider adding:

```text
> CONTINUE
```

or a corner marker:

```text
┌─◢─────────────────────────────┐
```

This is particularly useful for controller navigation.

---

## 12. Difficulty Selector

`NORMAL` and `HARD` should behave like a segmented hardware selector rather than normal menu buttons.

Example:

```text
DIFFICULTY

┌─────────────────────────────────────┐
│  ● NORMAL            ○ HARD         │
└─────────────────────────────────────┘
```

### Selected

```text
Background: rgba cyan tint
Border:     #18B7D8
Text:       #E8FAFF
Indicator:  cyan
```

### Unselected

```text
Background: #101214
Border:     #30353A
Text:       #777D82
Indicator:  muted
```

The selected state should look latched or powered.

---

## 13. Destructive Actions

Use danger styling sparingly.

### Delete Save

Default:

```text
Background: dark
Border:     muted red
Icon:       muted red
Text:       normal light grey
```

Hover:

```text
Background: dark red tint
Border:     #E53E50
Text:       #FFCCD1
```

Example:

```text
⚠ DELETE SAVE
```

The button should become more threatening only when the user approaches it.

### Quit

`QUIT` should normally remain neutral.

Quitting is not equivalent to deleting progress.

Recommended:

```text
Background: neutral dark
Border:     neutral grey
Icon:       muted
```

---

## 14. Disabled State

Disabled buttons should feel unpowered.

```text
Background: #0A0C0E
Border:     #24282C
Text:       #4E5459
Accent:     heavily muted
Glow:       none
```

Avoid simply lowering the whole control opacity too far, as this can hurt readability.

---

## 15. Icon Rules

Icons should be:

- simple
- geometric
- mostly single-colour
- approximately 18–24 px
- aligned consistently

Use semantic accent colour on icons.

Example:

```text
▶ Continue      Cyan
🔥 New Run       Orange
◇ Legacy        Violet
🏆 Trophy        Amber
⚗ Burn Lab      Teal
⚙ Settings      Grey
⚠ Delete Save   Red
```

Avoid detailed illustrated icons inside navigation controls.

---

## 16. Physical Detail

A small repeated industrial motif will help the buttons feel manufactured.

Choose **one** primary motif.

Good options:

- 3 px illuminated left rail
- one clipped corner
- tiny corner notch
- terminal-style status LED
- small etched divider
- subtle inset top highlight

Example clipped shape:

```text
┌──────────────────────────────┐
│                              │
│                              │
└────────────────────────────╱
```

Do not combine multiple decorative motifs on every control.

---

## 17. Button Hierarchy

Recommended hierarchy:

```text
Tier 1
CONTINUE

Tier 2
NEW RUN

Tier 3
LEGACY
TROPHY CABINET
BURN LAB

Tier 4
SETTINGS
QUIT

Danger
DELETE SAVE
```

The visual weight should follow the same hierarchy.

`CONTINUE` should be the first thing the player sees.

`DELETE SAVE` should never compete with it.

---

## 18. Godot Scene Structure

For richer buttons, prefer a reusable scene rather than relying entirely on a standard `Button`.

Suggested scene:

```text
TokenBurnButton
└── Button
    └── MarginContainer
        └── HBoxContainer
            ├── AccentRail
            ├── Icon
            └── VBoxContainer
                ├── Title
                └── Subtitle
```

Alternatively:

```text
Control
├── Panel
├── AccentRail
├── TextureRect
├── Label
├── Label
└── Button
```

The `Button` can sit over the full control as the interaction target while child nodes handle visual presentation.

---

## 19. Reusable Button Variants

Recommended variants:

```gdscript
enum ButtonVariant {
    DEFAULT,
    PRIMARY,
    BURN,
    LEGACY,
    TROPHY,
    LAB,
    DANGER,
    NEUTRAL
}
```

Semantic accent mapping:

```gdscript
const ACCENTS := {
    ButtonVariant.DEFAULT: Color("#596168"),
    ButtonVariant.PRIMARY: Color("#18B7D8"),
    ButtonVariant.BURN: Color("#E45125"),
    ButtonVariant.LEGACY: Color("#9B70C8"),
    ButtonVariant.TROPHY: Color("#D7A624"),
    ButtonVariant.LAB: Color("#3B9DAA"),
    ButtonVariant.DANGER: Color("#C93847"),
    ButtonVariant.NEUTRAL: Color("#6B7176"),
}
```

---

## 20. Recommended Interaction Timing

Keep interaction tight.

```text
Hover transition:   100 ms
Press transition:    70 ms
Focus transition:   100 ms
Release transition:  90 ms
```

Avoid animations longer than roughly 150 ms for normal menu interaction.

Token Burn should feel responsive and mechanical.

---

## 21. Sound Design Guidance

Button styling will feel much stronger when paired with restrained UI audio.

### Hover

Use:

- tiny electrical tick
- relay activation
- CRT click
- quiet digital chirp

### Press

Use:

- mechanical switch
- keyboard clack
- relay snap
- muted terminal confirmation beep

### Destructive Action

Use:

- lower-pitched confirmation
- warning relay
- short distorted tone

Avoid generic mobile UI pops.

---

## 22. Final Design Rule

Every control should answer:

> Why is this colour illuminated?

Valid answers include:

- it is selected
- it is active
- it is dangerous
- it has progression value
- the player is hovering it
- it represents a specific game system

If the answer is simply “because it looks cool”, reduce the colour.

The target aesthetic is:

> **Dark industrial hardware that comes alive when the player interacts with it.**
