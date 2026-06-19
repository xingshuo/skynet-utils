# Timer 实现选择指南（游戏场景）

`timer` 模块提供 service 级定时器,底层有 5 种数据结构/算法实现,通过 `TIMER_IMPL` 选择。
它们复杂度与常数因子各不相同,**没有全场最优**——本指南给出按游戏业务场景的选型方案,
数据来自 `test/timer/benchmark`（ACCURACY=1, HASH_SIZE=1024, TW_LEVELS={256,64,64}, sim=60s, tick=100ms）。

> 术语:下文 `us/call` 指 **每次 `OnTick` 的平均微秒数**（不是每个 timer 触发的成本）。
> 游戏服一般每帧/每 tick 调一次 `OnTick`,这个值就是定时器系统每 tick 的 CPU 占用。

## 一、30 秒决策

```
定时器以短期 repeat 为主(技能CD/buff/战斗tick)?
├─ 是(典型游戏)
│   ├─ 活跃定时器 < ~5万,且 interval 种类少(<50)   → INTERVAL_QUEUE  ← 默认
│   ├─ 活跃定时器 ≥ ~5万,或 interval 种类可能涨到上百 → HASHED_WHEEL
│   └─ 内存极度敏感 + 超时跨度很大(分钟~小时混合)   → TIMING_WHEEL
└─ 否
    ├─ 海量散布的一次性到点任务(离线奖励/活动开关)  → HASHED 或 SIMPLE(批量 drain)
    └─ 远期稀疏长定时器为主(很少触发)              → INTERVAL_QUEUE / HEAP(idle 近乎免费)
```

## 二、实测依据

**稳态 repeat 单价（us / 每次 OnTick,越低越好）**
| N | INTERVAL_QUEUE | HASHED | TIMING | HEAP | SIMPLE |
|---|---|---|---|---|---|
| 1k | **2.5** | 3.1 | 8.4 | 6.1 | 33 |
| 10k | **17.0** | 18.8 | 62 | 77 | 364 |
| 100k | 265 | **234** | 663 | 1357 | 3845 |

**interval 种类敏感性（N=100k,us/OnTick）**
| 种类 | INTERVAL_QUEUE | HASHED |
|---|---|---|
| 11 | **262** | 284 |
| 100 | 682 | **369** |
| 1000 | 426 | **352** |

**内存（game 100k,KB）**：TIMING 1489 < HASHED 1688 < SEQ 1922 < HEAP 2048 < SIMPLE 3072

**空转开销（idle 100k,us/tick）**：SIMPLE/SEQ 0.03 < HEAP 0.045 < TIMING 0.22 ≪ **HASHED 3.66**

**一次性批量到期（drain 1M,ms）**：SIMPLE 68 < HASHED 274 < SEQ 319 < TIMING 730 ≪ HEAP 3192

## 三、各实现速查卡

### INTERVAL_QUEUE —— 游戏默认首选
- **选它**：短期 repeat 为主、interval 种类少（技能/buff 就那十几种）、N 在十万以内。
- **优势**：小/中规模单价最低,idle O(1) 近免费,内存省,无需调参。
- **避免**：interval 种类涨到上百（k100 退化到 682）。
- **前提**：同一 interval 的 timer 按创建顺序入队（真实 manager 天然满足:创建即 `now+interval`,同 interval 即按 `next_ts` 升序）。

### HASHED_WHEEL —— 大规模 / 多种类的稳健选择
- **选它**：活跃定时器 ≥ ~5万,或 interval 种类不可控（对种类不敏感:k100/k1000 稳定 ~350-370）。
- **优势**：100k 稳态单价最低（234）,drain 快。
- **代价**：
  - idle 随 N 退化（O(N/size),100k 时 3.66us/tick）——远期稀疏定时器多时别用;
  - 大跨度需调大 `HASH_SIZE`,换桶内存。

### TIMING_WHEEL —— 内存敏感 + 超大跨度
- **选它**：超时跨度从秒到小时混合、对内存敏感。
- **优势**：内存全场最低（1489KB）,GC 包袱已优化掉（节点不再包装,直接存 timer + 字符串键存到期 tick）,CPU 中游（663,优于 HEAP/SIMPLE）。
- **避免**：纯高频 repeat（单价是 SEQ/HASHED 的 ~3 倍）。

### HEAP_QUEUE —— 通用兜底
- **选它**：规模小、churn 低、要一个不挑场景的结构。
- **避免**：高频 repeat（每次 O(log n) Replace + cache miss,100k 到 1357）、大批 drain（O(N log N) 到 3192ms）。

### SIMPLE —— 仅原型 / 极小 N
- **选它**：N < ~1千、图实现简单。
- **避免**：任何规模化稳态（O(N)/tick,100k 时 3.8ms/tick 直接爆 tick 预算）。

## 四、落地建议

1. **不确定就上 INTERVAL_QUEUE** —— 游戏 90% 的定时器是少种类短 repeat,它在该区间单价最低、零调参、内存省。
2. **单服活跃定时器破 5 万,或玩法引入大量互异时长**,切 HASHED;注意远期定时器别堆太多（idle 成本）。
3. **INTERVAL_QUEUE 与 HASHED 在 ~11 种类 / 10 万级别已基本打平**（262 vs 284 / 265 vs 234）,互为备选,按"是否怕种类增长 + 是否有大量 idle 定时器"二选一。
4. HASHED 的 `HASH_SIZE` 按"绝大多数 interval / accuracy"量级设,覆盖热点区间让 rounds 趋近 0。

## 五、复杂度速查

| | SIMPLE | HEAP | INTERVAL_QUEUE | HASHED | TIMING |
|---|---|---|---|---|---|
| Push | O(1) | O(log n) | O(1)¹ | O(1) | O(1) |
| 每次触发（OnTick 内重挂载） | — | O(log n) | O(1) | O(1) | O(1) |
| 每 tick 固定开销 | O(1)² | O(1) | O(#组) | O(N/size) | O(层数) |
| Drain 全部到期 | O(N) | O(N log N) | O(N) | O(N+size) | O(N+级联) |

¹ 摊还 O(1);遇到新 interval 建一张组表。
² SIMPLE 有 `min_ts` 提前返回,空转 O(1);需触发时退化 O(N) 扫描。

---

> 数据随实现演进会变动,重跑 `./skynet/skynet test/timer/benchmark_config` 获取最新结果。
