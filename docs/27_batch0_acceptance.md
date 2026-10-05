# 27 · 批次 0 验收记录（2026-10-05）

本记录记录已完成的历史改动及本次补验收，不是追补的执行规格。这批建设进度环、地图手势与队列反馈改动当初没有执行文档，来自用户截图和交互反馈。本次依据 `27_visible_decisions.md` 修订版只收口，没有重写它们。

## 源码与上传事实

- 基线：`df65ce7` 加收口前工作区现存改动。
- `7627b87`：进度环、独立设备定位、保留原始时长、地图手势与节点保留断言。
- `a5de8d3`：休眠教程期间已购地块可建、现金/队列反馈、原位刷新及 CI 门禁。
- `59d76c3`：记录 `export_presets` 已为 13 的原因：1.0.0 build 13 于 2026-10-01 上传成功，Delivery UUID `5beca694-20e5-4548-b5f7-48b29c4d15c2`。证据为 `builds/ipa/upload-13.log` 的 `UPLOAD SUCCEEDED with no errors`；本次没有制作或上传新包。

## 门禁

用户已独立复跑：18 表数据、249/249 单测、flow_audit PASS、map_gestures 0 failures、construction_rings 0 failures。本次不重复改写断言。

- [x] `check_assets --strict --audio`：180 张美术、45 个无损 UI / 135 个场景纹理、6/6 字体 cmap、23/23 音频。
- [x] 中期流程 PASS；新手完整流程 PASS；完整战役 PASS，二周目 11 月到达 21 座（首局 113 月），完成 30 月持续运行。
- [x] 六档视觉：标准 zh_CN / en 各 51 态；SE 750×1334 和大画幅 1024×1366 中英各 8 态；全部尺寸、触摸、容器断言通过。macOS 后台窗口暂停绘制时，临时夹具以一次布局帧 + force_draw 获取截图，未更改产品代码或断言；过早同步绘制造成的英文两态布局未完成已重跑全 51 态通过。
- [x] 性能硬绿：average 6.20ms、p90 8.57ms、p95 10.34ms；13 页 / 6 可见对象、30 粒子归零、猫爱心 1→0、node_delta 0。
- [x] 商店资源：不透明图标与 10 张本地化 iPhone 截图通过。
- [x] 发布门禁隔离复核：CSV/编译翻译语义一致、打包法务正文等通过；预期红灯为 8 个所有者字段（较 26 号新增 copyright_holder）及 StoreKit/IAP 插件，无其他阻塞。未填造任何占位值。

## 退出泄漏来源

原样复跑 `construction_rings --verbose`：0 failures，退出 10 个对象；逐个均为音频类型：4 个 AudioStreamPlayback（3 WAV、1 OggVorbis）、3 个 AudioStreamWAV、1 个 AudioStreamOggVorbis、OggPacketSequence 与其 Playback 各 1。涉及 `music_main`、`sfx_power_on`、`sfx_build_complete`、`sfx_build_start`，无 ProgressBar/Control/进度环节点。

临时释放探针在销毁原 main 后逐个检查进度环 WeakRef，存活数为 0。仅调用 stop_all 后 headless 仍有同一组音频对象；无音频对照夹具保留全部原断言并检查相同 WeakRef，0 failures、0 存活、退出无 ObjectDB 或资源警告。这是 headless Dummy 音频播放在夹具退出时的持有，不是 sheet 或 FX 生命周期泄漏。正式测试及产品代码均未因此改写；实际渲染性能门禁仍须验证粒子、猫爱心与节点增量。

## 零漂移证据（批次 0 独立证据）

`python3 tools/simulate_economy.py --seed-count 20 --no-write` 完整 stdout 的 SHA-256：

`4e8d551354da4bff23232b454abb9253f2ae96e5a3f8c03b60b8fe732a227e04`

与基线逐字一致。20 座中位 19.3 天，活跃/挂机净值比 23.67×，询价归因收入 2.5%，挂机 0 接管/0 欠费月，激进接管率 25%。完整 stdout 另存 `docs/acceptance/27_batch0/economy_20_seeds.txt`。K1–K4 与 K5 的证据会在本批后续记录中分开，不以本次运行冒充后续运行。

验收日志与模拟 stdout：`docs/acceptance/27_batch0/`。测试使用独立项目名与存档，未覆盖玩家正式存档。
