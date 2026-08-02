# 平台服务接入

玩法只依赖 `Monetization`，不会直接依赖任何第三方 SDK。

## IAP

`native_monetization_provider.gd` 已实现 Godot iOS `InAppStore` 单例协议：购买、恢复购买、异步事件轮询及自动完成交易。iOS 导出时启用兼容 Godot 4.7 的 InAppStore/StoreKit 插件即可，无需修改玩法层。SKU 必须与 `data/store.json` 完全一致。

启动时 provider 会调用 `request_product_info`，商店只在 iOS 返回有效商品后启用按钮，并使用 StoreKit 的 `localized_prices`，不会把美元配置价当作正式展示价。

购买使用手动结束交易：成功事件先同步发货并写入原子存档，signal 返回后 provider 才调用 `finish_transaction(product_id)`。若插件额外提供稳定的 `transaction_id`（兼容键 `transaction_identifier`），玩法层还会写入 `processed_transactions` 做幂等去重；Godot 传统 InAppStore 事件没有该字段时，依靠“先存档、后 finish”保证崩溃恢复。限购礼包另有购买前校验和单请求并发锁。若最终插件字段不同，只在 `native_monetization_provider.gd` 做一次规范化。

## 激励视频

广告插件仍是 `docs/00_decisions.md` 的 P04 待定项。原生侧只需暴露名为 `DataCenterAdsBridge` 的 Godot 单例：

```text
bool show_rewarded(String placement)
signal rewarded_completed(placement: String, earned: bool)
```

推荐适配 Poing Studios Godot AdMob 5.x：它支持 Godot 4.2+、iOS、Rewarded Ads、编辑器 mock 和 UMP 同意流程。适配器必须在收到 SDK 的 `OnUserEarnedReward` 回调后才发送 `earned=true`，关闭广告但未获得奖励时发送 `false`。

编辑器和无插件平台自动使用 `mock_monetization_provider.gd`。Release iOS 若缺少原生单例，商店请求会明确失败，不会误发商品；缺广告桥时激励请求也不会发放奖励。
