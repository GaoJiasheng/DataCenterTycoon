# 24 G4 · Toast 闪测高负载记录

- 日期：2026-08-30
- 测试基线：`f3f8719`
- 场景：后台持续运行标准画幅英文 `visual_smoke` 渲染，前台连续启动 20 个独立 `test_runner` 进程。
- 结果：20/20 轮均为 `TESTS: 243 passed, 0 failed`。
- 目标断言：`rejected operations stay visible above sheets and rapid retries restart friendly feedback` 为 20/20 通过。
- 诊断：没有出现 `feedback stage C mismatch` 或 `feedback stage D mismatch`；目标错误提示在 1.8 秒观察点保持可见，文本仍为 `REASON_NOT_ENOUGH_CASH` 的当前语言译文。
- 结论：本轮在持续渲染负载下未复现历史约 1/6 闪测。按 24 号规范保留 `tests/test_runner.gd` 现有可见性与文本诊断，不修改产品 toast 优先级，也不放宽断言。后台负载在 20 轮完成后人工停止。

逐轮完整日志保存在执行机 `/tmp/dct24_g4/test_1.log` 至 `/tmp/dct24_g4/test_20.log`，临时文件不纳入发布包。
