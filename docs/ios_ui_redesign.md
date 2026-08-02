# iPhone UI interaction specification

## Reference device

- Reference: iPhone 17 Pro Max, portrait.
- Native pixels: 1320×2868 at 3× scale.
- Logical reference: 440×956 points.
- Godot design viewport: 880×1912 units (2 units per point).
- Desktop preview override: 440×956 pixels.

The runtime uses `canvas_items` stretch, so the layout scales to other portrait phones while retaining the reference aspect and safe-area behavior.

## Interaction model

- Five persistent destinations live in the bottom tab bar: Park, Build, Market, Tech, and Store.
- Settings is a secondary action in the top-right HUD instead of a sixth competing tab.
- The active tab uses a filled pill, brighter label, and full-color icon; inactive destinations remain visible and stable.
- Frequently used controls are placed in the middle or lower half of each page where possible.
- Choice-heavy actions such as installing a building, rack, power unit, or cooler use a bottom action sheet with a clear close and cancel path.
- Destructive confirmations use the same scoped sheet pattern rather than desktop-style centered popups.

## Size and hierarchy rules

- Standard interactive target: at least 88 Godot units / 44 points high.
- Bottom navigation target: 104 Godot units / 52 points high inside a 66-point bar.
- Page titles: 40 Godot units / 20 points.
- Body and button labels: 22–28 Godot units / 11–14 points depending on density.
- Outer horizontal margin: 32 Godot units / 16 points.
- Desktop safe-area simulation: 16pt left/right, 58pt top, and 34pt bottom.
- Panels use subtle one-unit borders and consistent 18–32 unit radii; strong color is reserved for state and primary actions.

## Page behavior

- Park is the visual home. The map is the main interaction surface; the duplicate plot-card grid was removed.
- Park financial metrics are compact chips above the map and the next-plot purchase is a single contextual action below it.
- Construction actions wrap into a two-column grid instead of squeezing three long actions into one row.
- Data-center attachments and contracts use two-column touch grids.
- The tutorial is a compact contextual coach banner, not a permanent large panel.
- Store, technology, and market content share the same flat page surface and card vocabulary.
