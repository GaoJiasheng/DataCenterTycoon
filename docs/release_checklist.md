# 1.0 Release Checklist

## Owner/account inputs

- [ ] P01 final product name and App Store uniqueness check
- [ ] Bundle identifier, Apple Team ID, signing certificate and provisioning profile
- [ ] Public support email, privacy email, privacy-policy URL and support URL
- [ ] App Store Connect app record and all eight IAP products
- [ ] P04 rewarded-ad provider selection and production ad unit IDs

## Automated gates

- [ ] `python3 tools/validate_data.py`
- [ ] `godot --headless --path . tests/test_runner.tscn`
- [ ] `godot --path . tests/visual_smoke.tscn`（9 个竖屏状态，含移动端 action sheet）
- [ ] `python3 tools/simulate_economy.py`
- [ ] `python3 tools/check_assets.py --strict --audio`
- [ ] `python3 tools/check_app_store_assets.py`
- [ ] `python3 tools/check_release.py`
- [ ] Godot iOS Xcode-project ZIP export completes without warnings; Xcode Archive then signs/uploads the app

## Device and commerce

- [ ] iPhone SE-class, 6.7-inch iPhone, notched/Dynamic Island iPhone and iPad smoke tests
- [ ] Fresh install, upgrade from prior save schema, clock rollback and 8h/24h offline settlement
- [ ] All consumables purchase once; limited packs cannot be granted twice
- [ ] No Ads and Offline 24 restore after reinstall
- [ ] Reward granted only after completed video; frequency limits survive app restart
- [ ] UMP/ATT and privacy labels match the exact SDK build
- [ ] TestFlight external test for at least one week

## Store assets

- [ ] Opaque 1024×1024 icon
- [ ] Five ordered screenshots for 6.9-inch iPhone and 13-inch iPad in both languages; see `docs/store/README.md`
- [ ] English and Chinese metadata proofread; region excludes mainland China
- [ ] Age rating, review notes, IAP review screenshots and restore-purchase instructions
