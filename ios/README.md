# iOS 15+ 导出与原生服务

当前工程以 Godot 4.7 stable、竖屏、iPhone/iPad 通用为基线。首次真机包需要项目所有者完成以下账号相关步骤：

1. 在 `export_presets.cfg` 替换 bundle identifier、Apple Team ID 和签名配置。
2. 安装 Godot 4.7 兼容的 iOS InAppStore/StoreKit 插件，并在导出预设中启用。
3. 在 App Store Connect 创建 `data/store.json` 中的八个 SKU，完成税务与沙盒测试账号配置。
4. P04 确认后安装广告插件并实现 `platform/README.md` 的 `DataCenterAdsBridge`。AdMob 方案必须同时接入 UMP 同意流程，并按发行地区决定 ATT 展示策略。
5. 一旦加入广告 SDK，必须根据 SDK 实际收集行为更新 `PrivacyInfo.xcprivacy` 和 App Store 隐私标签；仓库当前的空收集清单只适用于未嵌入广告 SDK 的构建。
6. 将 `ios/PrivacyInfo.xcprivacy` 添加到导出后的 Xcode target，确认 Copy Bundle Resources 中只有一份清单。

正式资源、截图和账号值齐备后运行：

```sh
python3 tools/check_assets.py --strict --audio
python3 tools/check_app_store_assets.py
python3 tools/check_release.py
godot --headless --path . --export-release "iOS Release Candidate" builds/ios/DataCenterTycoon.zip
```

Godot 的 iOS 导出产物是 Xcode 工程 ZIP，不是已签名 IPA。解压后在 Xcode 中加入最终插件与 `PrivacyInfo.xcprivacy`，选择真实 Team/Profile，执行 Archive，再由 Organizer 导出或上传 App Store Connect。

第三方版本基线（2026-08-02）：Poing Studios AdMob 5.x；Godot 4.7 compatible StoreKit/InAppStore plugin。升级 Godot 或插件后必须重新跑真机沙盒购买、恢复购买和四类激励入口。
