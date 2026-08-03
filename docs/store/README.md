# App Store 交付接口

正式截图必须来自已接入最终美术的真实游戏画面，不接受纯概念图。每个语言、每个设备档位固定交付下列五张无透明通道 PNG：

1. `01_park.png`：园区扩张与多机房
2. `02_datacenter.png`：3×3 机柜、供电和冷却
3. `03_market.png`：行情曲线与新闻事件
4. `04_technology.png`：时代、网络和维修科技
5. `05_prestige.png`：后期规模与上市重组

目录契约：

```text
docs/store/screenshots/
  en/iphone_69/*.png
  en/ipad_13/*.png
  zh_CN/iphone_69/*.png
  zh_CN/ipad_13/*.png
```

`iphone_69` 接受 Apple 当前列出的任一竖屏最高档尺寸：1260×2736、1290×2796 或 1320×2868；`ipad_13` 接受 2064×2752 或 2048×2732。同一组五张必须使用同一尺寸。工程导出为 iPhone/iPad 通用包，因此 iPad 截图也是发布必需项。

§10 final-look 的桌面审片归档位于 `docs/ui_review/10_final_{en,zh_CN}_*.png`，固定 660×1434，只用于游戏内 UI 验收；它们不是本目录要求的正式 App Store Connect 尺寸，也不冒充真机截图。

运行 `python3 tools/check_app_store_assets.py` 做机器验收。规格来源：[Apple App Store Connect Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)，发布前仍需重新核对 Apple 的最新要求。
