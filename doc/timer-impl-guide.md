# Timer 实现选择指南（游戏场景）

`timer` 模块提供 service 级定时器,底层有 5 种基础数据结构/算法实现 + 1 种混合实现（`HYBRID`），通过 `TIMER_IMPL` 选择。
它们复杂度与常数因子各不相同,**没有全场最优**——本指南给出按游戏业务场景的选型方案,
数据来自 `test/timer/benchmark`（ACCURACY=1, HASH_SIZE=1024, TW_LEVELS={256,64,64}, sim=60s, tick=100ms）。

> 术语:下文 `us/call` 指 **每次 `OnTick` 的平均微秒数**（不是每个 timer 触发的成本）。
> 游戏服一般每帧/每 tick 调一次 `OnTick`,这个值就是定时器系统每 tick 的 CPU 占用。

## 一、30 秒决策

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

## 二、实测依据

**稳态 repeat 单价（us / 每次 OnTick,越低越好;game 场景 95% 短 + 5% 长）**
| N | HYBRID | INTERVAL_QUEUE | HASHED | TIMING | HEAP | SIMPLE |
|---|---|---|---|---|---|---|
| 1k | **2.4** | 2.5 | 2.6 | 8.4 | 6.5 | 32 |
| 10k | 14.9 | **14.3** | 18.9 | 60 | 84 | 320 |
| 100k | 294 | 296 | **238** | 700 | 1416 | 3216 |

> HYBRID 与 INTERVAL_QUEUE 在每个量级基本持平(各档互有微小高低,差距在测量噪声内),且内存几乎相同。
> 本表长期 timer 只有 4 种 distinct interval,INTERVAL_QUEUE 仅多建 4 组、差距未拉开;
> 真实场景长期 timer 是大量互异到点,HYBRID 的优势(短桶不被长期空组污染)远大于此(见种类表与第六节)。

**Push 单价（us / 每次创建定时器,随机 interval∈[1,65536] 的一次性 timer,HASH_SIZE=65536）**
| N | SIMPLE | HEAP | HYBRID | INTERVAL_QUEUE | HASHED | TIMING |
|---|---|---|---|---|---|---|
| 1k | **0.12** | 0.14 | 0.16 | 0.34 | 0.40 | 0.40 |
| 10k | **0.06** | 0.11 | 0.15 | 0.16 | 0.29 | 0.37 |
| 100k | **0.07** | 0.12 | 0.15 | 0.26 | 0.29 | 0.38 |
| 1M | **0.07** | 0.12 | 0.16 | 0.21 | 0.38 | 0.43 |

> Push 是每个 timer 的一次性成本,只在"启动期批量装载 / 每帧大量新建"才成为瓶颈;稳态下 OnTick 才是主成本。
> 全部实现都在亚微秒级(0.06~0.43us),绝对差异极小。HEAP 虽 O(log n),但 sift-up 常数小、极少到底,
> 反而快过几个 O(1) 实现(HASHED/TIMING 要算 deadline tick / 轮位,INTERVAL 要查/建组表)。
> HYBRID 的 push 单价是两桶按你的 interval 分布加权:本表随机 interval 下约 92% 落 heap 桶,故贴近 HEAP;
> 真实游戏里 95% 是短 repeat 会落短桶,HYBRID push 将贴近 INTERVAL_QUEUE。

**interval 种类敏感性（N=100k,us/OnTick,种类跨度可能横跨 HYBRID 阈值）**
| 种类 | HYBRID | INTERVAL_QUEUE | HASHED |
|---|---|---|---|
| 11 | **269** | 324 | 298 |
| 100 | 695 | 704 | **366** |
| 1000 | 491 | **448** | 531 |

> HASHED 在中等种类(~100)对种类最不敏感(366,胜出),但种类涨到 1000 时自身退化到 531、被 INTERVAL/HYBRID 反超;
> HYBRID 在少种类(11)因把长 interval 卸到 heap 桶、短桶组数更少,反而快过单跑的 INTERVAL_QUEUE。

**内存（game 100k,KB）**：TIMING 1489 < HASHED 1676 < HYBRID 1922 ≈ INTERVAL_QUEUE 1922 < HEAP 2048 < SIMPLE 3072

**空转开销（idle 100k,us/tick）**：SIMPLE/INTERVAL_QUEUE 0.026 < HEAP 0.044 < **HYBRID 0.090** < TIMING 0.22 ≪ **HASHED 3.58**

**一次性批量到期（drain 1M,ms）**：SIMPLE 65 < HASHED 278 < INTERVAL_QUEUE 307 < TIMING 758 ≪ **HYBRID 2754 < HEAP 3080**（HYBRID 长桶=HEAP,继承其慢 drain,**勿用于 drain storm**）

## 三、各实现速查卡

### HYBRID —— 游戏默认首选（详见第六节）
- **选它**：短 repeat 与远期长 timer 并存的典型游戏服。
- **优势**：热路径 ≈ INTERVAL_QUEUE（短桶）,长期 timer 卸到 heap 桶不污染短桶、idle 近免费(0.090us vs HASHED 3.58),内存与 INTERVAL_QUEUE 持平。
- **避免**：drain storm（长桶=HEAP,大批一次性到期慢）；短桶种类爆炸时仍会退化(同 INTERVAL_QUEUE)。

### INTERVAL_QUEUE —— 纯短期 repeat 的最简单选择
- **选它**：几乎没有长期 timer、interval 种类少（技能/buff 就那十几种）、N 在十万以内、想要单结构零分桶。
- **优势**：小/中规模单价最低,idle O(1) 近免费,内存省,无需调参。
- **避免**：interval 种类涨到上百（k100 退化到 704）；有大量远期稀疏 timer 时改用 HYBRID(否则空组拖累每 tick)。
- **前提**：同一 interval 的 timer 按创建顺序入队（真实 manager 天然满足:创建即 `now+interval`,同 interval 即按 `next_ts` 升序）。

### HASHED_WHEEL —— 大规模 / 多种类的稳健选择
- **选它**：活跃定时器 ≥ ~5万,或 interval 种类不可控（中等种类下最稳:k11/k100 ≈ 298/366;但 k1000 会退化到 531）。
- **优势**：100k 稳态单价最低（238）,drain 快。
- **代价**：
  - idle 随 N 退化（O(N/size),100k 时 3.66us/tick）——远期稀疏定时器多时别用;
  - 大跨度需调大 `HASH_SIZE`,换桶内存。

### TIMING_WHEEL —— 内存敏感 + 超大跨度
- **选它**：超时跨度从秒到小时混合、对内存敏感。
- **优势**：内存全场最低（1489KB）,GC 包袱已优化掉（节点不再包装,直接存 timer + 字符串键存到期 tick）,CPU 中游（700,优于 HEAP/SIMPLE）。
- **避免**：纯高频 repeat（单价是 INTERVAL_QUEUE/HASHED 的 ~3 倍）。

### HEAP_QUEUE —— 通用兜底
- **选它**：规模小、churn 低、要一个不挑场景的结构。
- **避免**：高频 repeat（每次 O(log n) Replace + cache miss,100k 到 1416）、大批 drain（O(N log N) 到 3080ms）。

### SIMPLE —— 仅原型 / 极小 N
- **选它**：N < ~1千、图实现简单。
- **避免**：任何规模化稳态（O(N)/tick,100k 时 3.2ms/tick 直接爆 tick 预算）。

## 四、落地建议

1. **不确定就上 HYBRID** —— 游戏定时器天然是"少种类短 repeat + 远期稀疏长 timer"双峰,HYBRID 热路径不输 INTERVAL_QUEUE,又用 heap 桶把长期 timer 的 idle 成本压到近零、且不污染短桶组数。几乎只有短 repeat 时退回 INTERVAL_QUEUE 求简单。
2. **单服活跃定时器破 5 万,或(短桶)interval 种类涨到上百**,切 HASHED;注意远期定时器别全堆 HASHED（idle 成本 O(N/size)）。
3. **INTERVAL_QUEUE/HYBRID 与 HASHED 在 ~11 种类 / 10 万级别同档**（kinds11 HYBRID/INTERVAL 269/324 vs HASHED 298;100k game HYBRID/INTERVAL 294/296 略逊 HASHED 238）,互为备选,按"是否怕种类增长 + 是否有大量 idle 定时器"二选一;HASHED 稳态略快但 idle 重(3.58us)、内存随 HASH_SIZE 涨。
4. **drain storm（海量一次性到点齐射）别用 HYBRID/HEAP**,用 HASHED 或 SIMPLE 批量 drain。
5. HASHED 的 `HASH_SIZE` 按"绝大多数 interval / accuracy"量级设,覆盖热点区间让 rounds 趋近 0。

## 五、复杂度速查

| | SIMPLE | HEAP | INTERVAL_QUEUE | HASHED | TIMING |
|---|---|---|---|---|---|
| Push | O(1) | O(log n) | O(1)¹ | O(1) | O(1) |
| 每次触发（OnTick 内重挂载） | — | O(log n) | O(1) | O(1) | O(1) |
| 每 tick 固定开销 | O(1)² | O(1) | O(#组) | O(N/size) | O(层数) |
| Drain 全部到期 | O(N) | O(N log N) | O(N) | O(N+size) | O(N+级联) |

¹ 摊还 O(1);遇到新 interval 建一张组表。
² SIMPLE 有 `min_ts` 提前返回,空转 O(1);需触发时退化 O(N) 扫描。

## 六、混合模式（HYBRID）

游戏定时器人口天然"双峰":一类是**少种类、高频的短 repeat**(技能CD/buff/战斗tick),
一类是**大量互异、远期稀疏的 timer**(离线奖励/建造完成/活动开关)。这两类对结构的诉求相反,
任何单一实现都顾此失彼:

- 单 `INTERVAL_QUEUE`:远期 timer 的海量互异 interval 各建一个组,而每个到期 tick 是 **O(#组) 全扫**——短 repeat 每 tick 都在烧,等于每 tick 都被上百个长期空组拖累。
- 单 `HEAP_QUEUE`:短 repeat 每次触发付 O(log N)(N 含全部长期 timer),热路径单价是 INTERVAL_QUEUE 的 5~6 倍。
- 单 `HASHED_WHEEL`:远期稀疏 timer 被反复访问只为递减 rounds,idle 成本 O(N/size) 白交。

`HYBRID` 按 `interval` 量级把定时器**静态路由**到两个子实现,各取所长:

```
interval <= threshold(默认 15s/1500cs)  → 短桶 INTERVAL_QUEUE   (O(1) FIFO,热路径单价最低)
interval >  threshold                    → 长桶 HEAP_QUEUE       (idle 近乎免费,不怕种类爆炸)
```

- **路由轴取 interval(静态)**:timer 一旦入桶终身不迁移,无跨桶搬迁开销;repeat / 一次性都按 interval 量级分。
- **零额外契约**:两子实现共享 `manager.__timers`,都遵循"`func=nil` 惰性删除 + `OnRemove` no-op",seq 由 manager 全局分配天然唯一,两桶互不干扰。
- **拆分后**:短桶组数不再被长期 timer 污染(热路径≈INTERVAL_QUEUE 单跑),长桶 idle≈免费。双峰越明显收益越大;即使人口均匀,顶多是对半分到两个都不退化的结构,也不会比单选更差。

**实测（game 场景,95% 短 repeat + 5% 长 timer）**:稳态单价 1k/10k/100k = 2.4/14.9/294 us,与 INTERVAL_QUEUE 基本持平(2.5/14.3/296),内存与其持平(100k 1922KB);idle 100k 0.090us/tick(对比 HASHED 3.58,低约 40 倍)。注:本测长期 timer 仅 4 种 distinct interval,INTERVAL_QUEUE 只多建 4 组,差距尚小;长期 timer 越是"大量互异到点",HYBRID 相对 INTERVAL_QUEUE 的优势越大 —— 上述数字是优势下界。代价是 drain 继承长桶 HEAP 的 O(N log n)(1M drain 2754ms),**不可用于一次性到点齐射**。

**选它**:短/长定时器并存且界限清晰(绝大多数游戏服)。
**调参**:`threshold` 单位 centisecond,构造时传入(`Timer.CTimerManager:New(TIMER_IMPL.HYBRID, threshold)`),缺省 1500(15s);取值 ≈ "你的 timer 在此值以下基本是少种类高频"的拐点。游戏里 sub-15s(战斗tick/短CD)是少种类超高频,留短桶吃 O(1);过 15s 种类发散且触发稀疏,丢 heap 更省。若你的中频段(15~60s)恰是少种类高 count,可调大。
**注意**:① 若短桶 interval 种类可能涨到上百,短桶退化(参见种类敏感性表),此时该把短桶换成 HASHED(需改 `hybrid.lua`);② 长桶用 HEAP 而非 TIMING_WHEEL,是为了规避多层时间轮的级联补帧;若长期 timer 存在整点惊群(同一刻大批到期),HEAP 的 O(N log N) drain 会偏疼,届时再权衡。

---

> 数据随实现演进会变动,重跑 `./skynet/skynet test/timer/benchmark_config` 获取最新结果。
