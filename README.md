# skynet-utils
基于skynet框架封装的工具箱

## 运行测试用例
* 将编译后的skynet仓库连接到工程目录下
```bash
# ln -sf $YOUR_SKYNET_PATH skynet
```
* 运行timer测试用例
```bash
# ./skynet/skynet test/timer/config
```
* 运行timer各实现的性能benchmark（对比5种实现 Push/OnTick 在不同量级下的耗时与内存）
```bash
# ./skynet/skynet test/timer/benchmark_config
```

## Timer
service 级定时器,底层提供 5 种基础实现（`HASHED_WHEEL` / `HEAP_QUEUE` / `INTERVAL_QUEUE` / `SIMPLE` / `TIMING_WHEEL`）+ 1 种混合实现（`HYBRID`，按 interval 量级路由到短桶/长桶），按场景选择。

**30 秒决策：**
```
定时器以短期 repeat 为主(技能CD/buff/战斗tick)?
├─ 是(典型游戏)
│   ├─ 短 repeat + 远期长 timer 并存(绝大多数游戏服)    → HYBRID  ← 默认
│   ├─ 几乎只有短 repeat、interval 种类少、要最简单单结构 → INTERVAL_QUEUE
│   ├─ 活跃定时器 ≥ ~5万,或 interval 种类可能涨到上百   → HASHED_WHEEL
│   └─ 内存极度敏感 + 超时跨度很大(分钟~小时混合)       → TIMING_WHEEL
└─ 否
    ├─ 海量散布的一次性到点任务(离线奖励/活动开关)      → HASHED 或 SIMPLE(批量 drain)
    └─ 远期稀疏长定时器为主(很少触发)                  → HEAP(idle 近乎免费)
```

完整选型依据（实测数据、各实现速查卡、复杂度速查）见 [doc/timer-impl-guide.md](doc/timer-impl-guide.md)。