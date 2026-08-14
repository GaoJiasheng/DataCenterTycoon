# 19 · 公司成长闭环改造记录

## 1. 范围

所有者确认实施：公司路线图、园区定位、客户关系与合约期限、行情复盘、董事会专长/公司复盘/纪念册、企业典藏。批量建设与配置蓝图暂缓（D34）。本轮没有加入日常任务、限时窗口、关系衰减或离线惩罚。

## 2. 闭环

```text
建设真实资产 → 园区形成经营定位 → 服务客户积累关系
       ↑                                  ↓
下一家公司 ← 董事会永久专长 ← 传承复盘 ← 锁价决策与行情复盘
       └──────── 路线图 / 典藏 / 公司纪念册留下永久记录 ────────┘
```

每一层都读取已有经营数据，不额外要求玩家刷一套脱离主玩法的资源。所有领取可补领，定位与董事会可免费重选。

## 3. 落地清单

- `data/meta_progression.json`：六项路线图、四种园区定位、四级关系、三档期限、三条董事会专长、四套典藏。
- `core/game.gd` / `gameplay/game_rules.gd`：权威收益、关系累计、定位条件、签约预测、行情决策、永久点数、发现/领取、传承复盘。
- `core/save_manager.gd`：存档 v3；老档补齐期限与永久元进度，不覆盖已有账号资产。
- `ui/main_view.gd`：公司四页签、园区定位、三档签约、行情复盘、传承结算；所有文案走 `tr()`。
- `gameplay/map/park_map.gd`：传承后在世界层显示正式纪念地标。
- `tools/validate_data.py` / `tools/simulate_economy.py`：数据约束、三策略 20 种子、三档期限探针。
- `tests/test_runner.gd`：路线图、期限/关系、园区条件、董事会、典藏、迁移七组新断言。
- `tests/visual_smoke.gd`：路线图、典藏、董事会、园区定位四张双语新状态。

## 4. 正式美术交付

新增 7 件 1024² 透明正式渲染资产：`company_roadmap`、`campus_strategy`、`customer_portfolio`、`market_review`、`board_specialties`、`company_collection`、`legacy_memorial`。原稿位于 `art-renders/visual/work/meta/`，成品位于 `art-renders/visual/final/meta/`，运行时副本位于 `assets/art/meta/`。

统一生成约束：premium 2.5D casual mobile-game render；圆润蓝/奶油/金材质；上左暖光；单一清晰主体；无文字、字母、数字、品牌、UI 外框或水印；纯 `#ff00ff` 色键背景；禁止线框、扁平矢量、几何占位和草图原型。

逐件主体：金色路线标桩连接微缩数据中心；带四个方向徽记的园区沙盘；四枚不同材质的正式客户印章；数据中心与行情卷轴组成的复盘奖章；蓝金董事会桌与三枚部门徽章；蓝色档案柜与设施/客户/行情藏品；带月桂与蓝色数据中心缩影的纪念碑。完整可复建提示同步在 `art-renders/briefs/final_prompt_record.md`。

## 5. 验收

- 数据校验：12 张数据表、本地化、159 个美术 ID。
- 逻辑：162/162。
- 数值：20 种子 × 3 策略 30 日全部核心目标通过，详见 `balance_report.md`。
- 视觉：中英各 41 态，包含四个新增页面；截图归档在 `docs/ui_review/19_meta_*`。
- 资产：新系统没有任何线条/几何原型占位；缺失时仍保留通用运行时回退，正式 manifest 全部可加载。
