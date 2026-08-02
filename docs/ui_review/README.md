# UI polish visual review

- Baseline: `1d8997e` (`Complete WP7 bilingual UI release gates`)
- After: `daf9de4` (`Polish market store and milestone UI`)
- Capture viewport: iPhone 17 Pro Max logical portrait, 440×956
- Coverage: English 30 states + Simplified Chinese 30 states

`all_30_{before|after}_{locale}.png` contains the complete state matrix. `compare_{locale}_{state}.png` keeps the same state side by side for the ten highest-risk screens: HUD/map, contracts, settings, datacenter board, FTUE, market, store, offline reward, arrears, and era unlock.

The automated capture also runs clipping, sibling-label overlap, panel compression, button contrast/outline, touch-target, single-primary-CTA, and screen-specific semantic assertions before saving each image.
