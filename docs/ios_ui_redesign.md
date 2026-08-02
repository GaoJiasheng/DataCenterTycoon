# iPhone UI interaction specification

## Reference device

- Reference: 6.3-inch iPhone 17 / iPhone 17 Pro, portrait.
- Native pixels: 1206×2622 at 3× scale.
- Logical reference: 402×874 points.
- Godot design viewport: 804×1748 units (2 units per point).
- Automated reference capture: 402×874 pixels.
- Interactive desktop preview: 880×1912 pixels, a 2× iPhone 17 Pro Max logical preview that fills most of a 4K desktop display without exceeding its height.

The runtime uses `canvas_items` stretch, so the layout scales to other portrait phones while retaining the reference aspect and safe-area behavior.

## Interaction model

- Park is a full-bleed world surface. The HUD, finance state, build queue, tutorial coach, and dynamic actions float above the world instead of consuming stacked document rows.
- Empty land, active data centers, ruins, and the next purchasable plot are direct touch targets on the map; there is no duplicate card grid below the world.
- The Park world is the only persistent home. There is no permanent tab bar.
- The default screen exposes at most seven persistent controls: company tier, cash, gems, settings, construction queue, one dynamic primary action, and Operations.
- Build comes from an empty plot or the dynamic primary action. Gems open Store; company tier opens Tech; market events become contextual alerts; secondary systems live in Operations.
- Frequently used controls are placed in the middle or lower half of each page where possible.
- Choice-heavy actions such as installing a building, rack, power unit, or cooler use a bottom action sheet with a clear close and cancel path.
- Complexity is disclosed in four layers: world, persistent HUD and primary action, object context drawer, then a focused system work surface that keeps the park visible behind it.
- Destructive confirmations use the same scoped sheet pattern rather than desktop-style centered popups.
- Re-selecting Park recenters and resets the map camera. Drag, pinch, mouse-wheel zoom, button press motion, and platform haptics all use the same interaction vocabulary.

## Size and hierarchy rules

- Standard interactive target: at least 88 Godot units / 44 points high.
- World utility target: 96 Godot units / 48 points. The dynamic primary action is 96 units / 48 points high.
- Page titles: 40 Godot units / 20 points.
- Body and button labels: 22–28 Godot units / 11–14 points depending on density.
- Outer horizontal margin: 32 Godot units / 16 points.
- Desktop safe-area simulation: 16pt left/right, 58pt top, and 34pt bottom.
- Panels use subtle one-unit borders, 1–2pt depth shadows, and consistent 18–32 unit radii; strong color is reserved for state and primary actions. Labels do not use outlines or drop shadows.
- Scroll-page minimum sizes are isolated from the root shell, so long Store or data-center pages cannot push the global HUD outside the device safe area.

## Page behavior

- Park is the visual home and occupies over 82% of the default screen. Buildings and plots carry actions and exception state directly.
- Normal buildings have no permanent caption. Construction, missing power, faults, ruins, and purchasable land surface compact state bubbles only while relevant.
- Multiple data centers form a compact two-column campus staggered along a shared isometric axis, with centered odd rows. Isometric wind, vegetation sway, active-building breath, and power glow give the persistent world visible life without changing gameplay state. Directional road art is withheld until a true 2:1 isometric set is available, so the world never mixes camera projections.
- Empty-plot selection opens a large-art horizontal building drawer. Data-center selection focuses the camera and opens a compact contextual drawer before exposing full management.
- The Operations drawer uses a 2×2 status-card overview for construction, market, technology, and store. Strong accent color is reserved for attention and state.
- Data-center management is split into Racks, Infrastructure, and Contracts task spaces; Technology is split into Upgrades and Achievements. Only one work context is exposed at a time.
- Market, Technology, Store, Settings, and Construction use the same high-opacity rounded work surface over the persistent park and share one predictable close action.
- Construction actions wrap into a two-column grid instead of squeezing three long actions into one row.
- Data-center attachments and contracts use two-column touch grids.
- The tutorial is a compact contextual coach banner, not a permanent large panel.
- Store, technology, and market content share the same flat page surface and card vocabulary.
- Empty states use a large visual, one clear explanation, and one primary action. Settings uses explicit selected-language states and iOS-style animated switches.

## Visual acceptance gate

`tests/visual_smoke.tscn` renders eighteen portrait states through Metal at 402×874: Park, plot confirmation, building drawer, construction queue, completed building, a six-data-center compact campus, data-center context, the three data-center task spaces, Operations, Market, Tech upgrades, Achievements, Store, Settings, era unlock, and game over. In addition to saving screenshots, the test rejects clipped typography, single-line width overflow, touch targets below 44pt, and persistent HUD or world actions outside the viewport.
