# Wiring the turn loop into your real Arena scene

## 1. Drop in the files
- `scripts/CardData.gd` → **overwrite** your existing one (see "why" below)
- `scripts/Duelist.gd` → new file, put in `scripts/`
- `scripts/MatchUI.gd` → new file, put in `scripts/`
- `resources/cards/*.tres` (8 files) → put in `resources/cards/`, overwrite if you already made any of these by hand

### Why CardData.gd needs overwriting
Your current one (from Step 1) has `UNIVERSAL` living in the same enum as
`ATTACK`/`GUARD`/etc. That's a bug — a card can be Attack-type AND universal
at the same time, they're not mutually exclusive. This version splits it into
`card_type` (always Attack/Guard/Heal/Dot/Special) plus a separate
`is_universal: bool`. If you already hand-made any `.tres` cards against the
old script, they'll still load fine — `ATTACK` is still value `0` — just
double check the "Is Universal" checkbox on those once the new script's in.

## 2. Add the overlay nodes in Arena.tscn
Open `Arena.tscn`. In the Scene dock:

1. Right-click your **Arena** root node → **Add Child Node** → search
   `CanvasLayer` → add it. Rename it **UILayer**.
   (CanvasLayer draws as a flat 2D layer on top of the 3D viewport, completely
   independent of your cameras — this is what keeps your camera work
   untouched.)
2. Right-click **UILayer** → **Add Child Node** → search `Control` → add it.
   Rename it **MatchUI**.
3. Select **MatchUI**. In the top toolbar of the 2D/3D viewport area there's
   a **Layout** menu when a Control is selected — use it to set **Full Rect**,
   so it covers the whole screen (the script anchors its actual panel to the
   bottom itself, so covering the full screen here is fine and expected).
4. With **MatchUI** still selected, go to the **Script** icon in the
   Inspector's script slot (or right-click the node → **Attach Script**) →
   instead of creating a new one, browse to and select the existing
   `res://scripts/MatchUI.gd` you just copied in.

## 3. Test it
Save (Ctrl+S), then press **F6** (Play Current Scene) while `Arena.tscn` is
the open tab. You should see:
- Your full 3D arena, cameras, environment — untouched
- A dark panel anchored to the bottom of the screen with HP, taya, 8 card
  buttons, an End Turn button, and a scrolling log

Play a few full matches. This is still just the 8 universal cards — no
roosters wired in yet — the goal right now is purely: **does the turn
resolution work correctly, and does 3-taya actually feel like it's forcing
real trade-offs**, before we spend more time connecting it to the roosters
standing on your stage markers.

## If something looks wrong
- Buttons not appearing / errors in the Output panel → almost always a typo
  when copying file paths, or a card `.tres` file not actually landing in
  `resources/cards/`. Check the Output panel's error text, it'll usually name
  the exact missing resource path.
- UI appears but covers the arena entirely → the panel's `position.y = -320`
  in `_build_ui()` controls how tall the reserved bottom strip is; increase
  the magnitude (e.g. `-400`) if your card row needs more room, decrease it
  if too much arena is covered.

Come back with a screenshot once it's running, or with whatever error text
shows up if it doesn't.
