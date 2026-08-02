# iOS plugin delivery directory

Godot only discovers iOS plugin descriptors (`.gdip`) and their `.a`/`.xcframework` binaries from this directory or its children.

Before a release export:

1. install a Godot 4.7-compatible `InAppStore` plugin here and enable it in the iOS export preset;
2. after P04 is fixed, install the rewarded-ad adapter that registers `DataCenterAdsBridge`;
3. keep third-party licenses and exact version notes beside the binaries;
4. rerun sandbox purchase/restore, product-localization, rewarded completion/cancel, UMP/ATT, and `python3 tools/check_release.py`.

The release gate intentionally fails while no `.gdip` exists. Editor and automated tests continue to use the mock provider.
