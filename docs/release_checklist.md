# 1.0 Release Checklist

## Owner/account inputs

- [ ] P01 final product name and App Store uniqueness check（填入 `data/release_identity.json`）
- [ ] Bundle identifier, Apple Team ID, signing certificate and provisioning profile
- [ ] Public support/privacy emails, public policy/support URLs, effective date and exact ad-provider names（集中填入 `data/release_identity.json`，然后运行 `python3 tools/fill_release_identity.py`）
- [ ] App Store Connect app record and all eight IAP products
- [ ] P04 rewarded-ad provider selection and production ad unit IDs

## Automated gates

- [x] `python3 tools/validate_data.py`（2026-08-30：17 表、双语、180 art IDs）
- [x] `godot --headless --path . tests/test_runner.tscn`（2026-08-30：243 passed）
- [x] `flow_audit` / `midgame_audit` / 真实触摸 `tutorial_playthrough` / `full_campaign`（2026-08-30：全部通过；本轮首局第 119 月达 20 座、完成重组，二局第 11 月达 21 座并续跑至第 30 月 59 座）
- [x] `visual_smoke` 中英标准档各 49 态（990×2151），SE / iPad 中英各 8 个关键态（750×1334 / 1024×1366），2026-08-30 全量复跑通过裁剪、贴边、叠印与触控断言
- [x] `godot --disable-vsync --max-fps 240 --path . tests/performance_smoke.tscn`（2026-08-30：100 座机房、13 园区页、当前页 6 对象；average 7.67ms / p95 15.75ms / 30 粒子与猫特效零残留 / 节点差 0）
- [ ] iPhone 12 与 iPhone 17 各跑一次 Instruments：六机房 + 金币并发保持 60fps；本项不能用桌面烟测替代
- [x] `python3 tools/simulate_economy.py`（2026-08-28：三类 30 天 × 20 seed 全部门禁通过；输出 SHA-256 `4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`）
- [x] `python3 tools/check_assets.py --strict --audio`（2026-08-28：180 art / 6 font / 23 audio，纹理分类 45 无损 + 135 VRAM）
- [x] `python3 tools/check_app_store_assets.py`（2026-08-30：中英 × iPhone 6.9 / iPad 13 × 五屏，共 20 张原生离屏渲染截图；尺寸、组内一致性与无 alpha 全绿）
- [ ] `python3 tools/check_release.py`（当前按设计只阻断 `release_identity.json` 的所有者占位值与 IAP 插件描述符）
- [x] `tools/release_ios.sh --dry-run`（2026-08-28：build 9 完整导出、archive、codesign、IPA 导出与二次验签通过，未上传；空权限说明已在归档前移除）
- [x] `tools/release_ios.sh --bump --upload`（2026-08-29：build 10 完整导出、archive、codesign、IPA 二次验签并上传成功；Delivery UUID `65238845-4133-4dcd-999e-c5b33ae02195`）
- [x] GitHub Actions 完整绿色：[Project gates #33190809456](https://github.com/GaoJiasheng/DataCenterTycoon/actions/runs/33190809456)（243 项逻辑、四个流程/性能门禁及双语三画幅）

## Device and commerce

- [ ] iPhone SE-class, 6.7-inch iPhone, notched/Dynamic Island iPhone and iPad smoke tests
- [ ] Fresh install, upgrade from prior save schema, clock rollback and 8h/24h offline settlement
- [ ] All consumables purchase once; limited packs cannot be granted twice
- [ ] No Ads and Offline 24 restore after reinstall
- [ ] Reward granted only after completed video; frequency limits survive app restart
- [ ] UMP/ATT and privacy labels match the exact SDK build
- [ ] TestFlight external test for at least one week

## Store assets

- [x] Opaque 1024×1024 icon
- [x] Five ordered screenshots for 6.9-inch iPhone and 13-inch iPad in both languages; see `docs/store/README.md`
- [x] English and Chinese metadata copy complete and length-checked; region excludes mainland China
- [ ] Age rating owner confirmation and IAP review screenshots（双语问卷草稿、审核步骤与恢复购买说明已备齐）
