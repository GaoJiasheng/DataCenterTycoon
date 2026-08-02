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

## Design system and hierarchy rules

- Standard interactive target: at least 88 Godot units / 44 points high.
- World utility target: 96 Godot units / 48 points. The dynamic primary action is 96 units / 48 points high.
- The packaged typography chain is Baloo 2 → Noto Sans SC; numeric displays use tabular figures. No runtime system-font dependency is allowed.
- Page titles use the 36–44 unit display/title steps. Body and button labels use the 20–28 unit caption/body/heading steps depending on density.
- Outer horizontal margin: 32 Godot units / 16 points.
- Desktop safe-area simulation: 16pt left/right, 58pt top, and 34pt bottom.
- System work surfaces and cards use the delivered `panel_dark` nine-slice; paper dialogs and milestone presentations use `panel_main`; primary/secondary/warning/danger/ad controls use the matching `btn_*` nine-slices. Flat styles exist only as missing-asset fallbacks.
- Strong color is semantic: green primary, blue action, purple premium, orange warning and red danger. Red is never used for a neutral close action.
- World text may use a dark outline for readability. Text inside opaque work surfaces does not.
- Scroll-page minimum sizes are isolated from the root shell, so long Store or data-center pages cannot push the global HUD outside the device safe area.

## Page behavior

- Park is the visual home and occupies over 82% of the default screen. Buildings and plots carry actions and exception state directly.
- Normal buildings have no permanent caption. Construction, missing power, faults, ruins, and purchasable land surface compact state bubbles only while relevant.
- Multiple data centers form a compact two-column campus staggered along a shared isometric axis, with centered odd rows. Isometric wind, vegetation sway, active-building breath, and power glow give the persistent world visible life without changing gameplay state. Directional road art is withheld until a true 2:1 isometric set is available, so the world never mixes camera projections.
- Empty-plot selection opens a large-art horizontal building drawer. Data-center selection focuses the camera and opens a compact contextual drawer before exposing full management.
- The Operations drawer uses a 2×2 status-card overview for construction, market, technology, and store. Strong accent color is reserved for attention and state.
- Data-center context embeds a spatial 3×3 planning board: power is visible as a segmented meter, four coolers sit at their real edges, coverage appears on the affected tiles, and all nine slots expose placement viability before purchase. Board and Contracts are the only two management contexts.
- Market, Technology, Store, Settings, and Construction use the same high-opacity rounded work surface over the persistent park and share one predictable close action.
- Construction actions wrap into a two-column grid instead of squeezing three long actions into one row.
- Contract cards expose customer trend, C/S/G fit and authoritative projected monthly income. Signing confirms current → projected income, change percentage, breach state and term.
- Market exposes four toggleable series, reference bands, a Now marker, 24-point customer sparklines and event cards with customer impact, countdown and a direct contract route. Technology uses a three-era route with concrete next-era unlocks and a projected prestige multiplier.
- The tutorial uses a four-pane spotlight mask, target-only input gate, animated pointer and `dialog_bubble` coach. Missing targets degrade to a nonblocking bubble and can never deadlock progress.
- Store uses Limited Deals / Gem Vault / Permanent Perks merchandising regions. Offline reward, arrears, era unlock and game over each use purpose-built presentation layers rather than generic alerts.
- Empty states use a large visual, one clear explanation, and one primary action. Settings uses explicit selected-language states and iOS-style animated switches.

## Motion and live feedback

- Tick and offline-advance events update HUD/live controls only; they never rebuild the current page or reset scroll.
- Cash and gems roll numerically. Periodic income, building completion, contract signing and retirement use capped curved coin flights into the wallet.
- Construction uses a live timer and completes with dust, squash, coin and haptic feedback. Fault, power, heat, renewal and retirement alerts are actionable in the world.
- Sheets enter and leave with motion and can be closed by neutral close, backdrop or a 44pt drag handle.
- Era unlock is a paper headline rotation with unlock summary and reward count-up. Arrears is a persistent debt/timer/ad-rescue HUD with edge vignette; game over blacks out the park and reveals a four-stat restart card.

## Visual acceptance gate

`tests/visual_smoke.tscn` renders 30 portrait states through Metal at 402×874 in both English and Simplified Chinese. It covers Park/FTUE/action sheets/building/campus/world alerts, the board and placement states, contract comparison, rack actions, Operations, three market history densities, Tech/Achievements, Store/Settings, offline reward, arrears, era unlock and game over.

The gate rejects clipped typography, unsafe single-line overflow, touch targets below 44pt, missing glyphs, locked `×0.00`, broken scroll preservation, absent board overlays and missing presentation/merchandising structure. Run it with:

```sh
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=en
godot --disable-vsync --max-fps 60 --path . tests/visual_smoke.tscn -- --locale=zh_CN
godot --disable-vsync --max-fps 240 --path . tests/performance_smoke.tscn
```

The performance smoke stages six operating data centers plus 30 simultaneous coins. It runs with a 240fps cap to avoid benchmarking the sleep jitter of a 60fps limiter, requires a p95 below the 16.67ms 60fps budget, verifies particle cleanup and rejects node leaks. It supplements—but does not replace—the iPhone 12/17 Instruments run in the release checklist.
