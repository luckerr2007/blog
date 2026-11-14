---
title: LEMOM：从一首歌到能进 Logic 的多轨 MIDI
published: 2026-11-14
description: 音频转 MIDI 的模型只是起点。LEMOM 把云端分离、节拍分析、逐轨转写、声部清理和钢琴后处理串起来，目标是产出能直接拖进 Logic 的工程素材。
tags: [LEMOM, MIDI, MuScriptor, Apple Silicon]
category: 音频工具
series: 音频工具三件套
seriesOrder: 2
comment: false
---

LEMOM 是 LuckErrMusicOfMidi 的简称。它做的事听起来很直接：上传一首歌，选择分离或整曲转写，最后拿到 MIDI。

但「能响的 MIDI」和「能编辑的 MIDI」差得很远。模型给出的是一堆音符事件，Logic 需要的是稳定的 tempo map、正确的通道、按乐器分开的轨道、不会互相打架的 note-off。模型不会替你考虑这些。LEMOM 的大部分代码其实花在后者。

这篇文章按一条任务的实际路径走：音频怎么进来、在哪一步用哪个模型、云端分离怎么降级、MIDI 后处理为什么这么重，以及目前的验证到了什么程度。

## 目标环境与边界

当前分支只支持 macOS 13 Ventura 及以上，Apple Silicon（M1–M4），内存 16GB 起，磁盘约 9GB。Python 3.12，Node 18 只用于构建前端。

验证机是 M2 Pro、19 核 GPU、16GB、macOS 15.8.1、PyTorch 2.7.0。Linux、Windows、CUDA、Docker、Colab 的适配已经删掉，不是「没测」，是代码里不再保留。

产品边界也写得很明确：不做本地分离、不做乐谱导出、不做和弦分析、不做音色库，也没有 CLI。分离交给 MVSEP 或 TelkNet；本地只做解码、节拍、转写、后处理和导出。

## 一条任务的三条路径

工作台把入口拆成三层，避免「音源」「音频来源」「分离路由」混在一起：

- 音源：本地上传，或网易云搜索；
- 音频来源：云端分离，或直接上传已分离的多轨；
- 分离路由：智能推荐、强力、快速、直通。

对应到任务模型，是三种模式：

1. `direct`：整首混音直接转写，不上传云端；
2. `separate`：先云端分离，再逐轨转写；
3. `bypass`：上传已经分好的 1–12 条分轨，跳过云端，直接做角色映射和转写。

三条路径共用同一套解码、节拍、MIDI 写出和产物打包。区别只在中间有没有分离层。

## 模型各管一段

把模型堆在一起很容易，难的是说清楚每个模型的权威边界。

**Beat This final0** 负责 BPM、beat grid、downbeat 和拍号。它默认只在原始混音上跑一次，所有分轨共享同一个 tempo map；bypass 没有 mix 时退回音符最密的分轨。这样做的原因很实际：一条稀疏的贝斯轨可能被检测成半速，一条只有镲片的鼓轨可能被检测成双速，逐轨分析会让六条轨的 BPM 互相打架。

**MuScriptor** 是默认转写引擎，分 Small 103M、Medium 307M、Large 1.4B 三档。整曲直接转写默认 Large；分轨默认 Medium，想要 Large 要显式打开「精细（慢）」。推理按 5 秒 chunk 走，重叠区做边界连续性处理。

Large 在 16GB 机器上以 INT8 加载：权重按 64 宽分组做对称量化，head 保留 FP16，conditioner 保持 FP32。常驻约 1.7GB，准入约 3.6GB。M2 Pro 上同一段测试音频，FP16 与 INT8 的音符数一致（10/10、50/50）。

分轨模式下，MuScriptor 的乐器条件是硬约束：贝斯轨只允许 acoustic/electric bass，鼓轨只允许 drums，吉他轨只允许三种吉他，钢琴轨只允许 acoustic/electric piano。模型如果仍然写出别的轨道，后处理会按 track name/program 再删一次。

分轨模式下，人声不进入 MIDI 链。念白、气声、和声堆叠很容易被写成假旋律，听感比没有 MIDI 更糟。人声分轨只保留音频试听。

**TransKun V2 Aug** 是钢琴专用入口，输出音符和 CC64。它和 MuScriptor 不是主备关系：显式选择 TransKun 后，即使质量提示不通过也不会自动改跑 MuScriptor；只有推理失败或没有音符才报错。

**ByteDance Pedal** 是可选的踏板层，只取 CC64，不采用它的音符。它把踏板区间清洗、裁剪、合并后，替换 TransKun 钢琴轨里的旧 CC64，不生成单独文件。checkpoint 不随 DMG 分发，缺失或推理失败时保留 TransKun 原来的踏板，任务不失败。

**ADTOF** 是可选的鼓专用后端，只输出五类鼓：kick、snare、closed hi-hat、low tom、crash/ride。开镲并入闭镲，ride 并入镲片，所有 tom 归为低通鼓。原始输出固定 120 BPM、0.1 秒时值，写回时只改 tempo 元数据，音符绝对秒不变。285 秒真实鼓轨在 CPU 上跑 3.7 秒，MPS 反而要 6.4 秒，所以它固定用 CPU，也避免和常驻的 MuScriptor 抢统一内存。

在 284.9 秒鼓轨上，50ms onset 的 F1 是 0.929，旧 MuScriptor 结果是 472 个音符。ADTOF 的击打贴合更好，但鼓件语义更粗，所以默认关闭，交给用户 A/B。

**YourMT3+** 保留为备选引擎，不参与默认工作流。旧版的「双模型交叉校验」已经从界面移除：两遍完整推理约 2 倍耗时，取并集还会把第二模型的误检一起带进来。代码里留了环境变量开关，只用于排障。

**LLM** 只做符号层审阅。DeepSeek V4.1 Flash 是默认，GLM 5.3 Flash 备选。它收到的是 MIDI 统计和紧凑 note table，不是音频、Cookie 或 Key。返回必须是 JSON plan，操作限定在删除短音、低力度、去重、量化、复音限制、力度缩放、按 id 删除、移调这些白名单里。执行器会校验范围和 note id，清空结果会回退到执行前，任何操作都不允许新增音符。

自动模式只在本地结果偏弱时调用：没有音符、密度低于 0.3、质量分低于 0.35、时长不足 2 秒，或单轨且音符数少于 `max(8, duration * 0.5)`。这不是模型准确率，只是「要不要再看一眼」的启发式。

## 云端分离的抽象

MVSEP 和 TelkNet 的契约完全不同，但上层不应该知道这些差异。`BaseSeparator` 定义了统一生命周期：available → quote → submit → poll → download → cancel；`Capabilities`、`Quote`、`Submission`、`Status`、`Result` 是跨 provider 的数据契约。

异常分类是路由的唯一判据：

- `TransientError`：429、503、其他 5xx、网络超时、下载大小不符；
- `AuthError`：401/403；
- `BudgetError`：402；
- `PriceChangedError`：409 `PRICE_CHANGED`；
- `ProtocolError`：413、参数/schema 错误；
- `CancelledError`。

只有 transient 才降级。显式选择 MVSEP 或 TelkNet 时，即使 transient 也直接失败，不偷偷换 provider。鉴权、预算、价格变化、请求过大、用户取消都不降级，否则会把「Key 失效」掩盖成「另一个云可用」。

还有一条容易忽略的规则：POST 超时可能已经在云端建了任务，客户端会标记 `request_may_have_succeeded` 并停止降级，避免两个云各建一个任务、重复扣费。TelkNet 的预签名上传只带 Content-Type，绝不带 Authorization；提交带 `Idempotency-Key`；409 不自动接受新价格；429 尊重 `Retry-After` 但上限 30 秒。

SmartRouter 只做决策，不发请求。`auto` 不自动切 bypass；`cost_optimized` 优先 TelkNet（余额和报价可查），不可用时回退 MVSEP；`quality_first` 才尝试 `music-mega-53-stem`，而且必须从工具列表里精确确认存在，不能按名字猜。mega 不可用时回退标准六轨，清空 quality，并把 `fallback_reason` 写进任务。

## MIDI 后处理才是主战场

分轨模式的后处理顺序是固定的：跳过人声 → 保留原始通道 → 按 stem 做乐器过滤 → 轨内去重 → 复音限制 → 本地清理 → 可选 LLM → 音频证据跨轨裁决 → 合并/导出。

几个具体问题能说明为什么这层不能省。

**通道 0 被当成缺失。** 早期代码把 channel 0 判为「没有通道」，然后按最低音高猜成鼓通道 9。结果是钢琴、贝斯、人声在 Logic 里全变成鼓。现在逐字保留 event channel，并加了回归测试。

**跨轨去重不能按 tick 比。** 不同 MIDI 的 PPQ 可能是 480 或 960，按原始 tick 比较会错位。现在每份 MIDI 用自己的 PPQ 和 tempo map 换成绝对秒，同 pitch、30ms 内聚簇，再回写到各自文档。

**低电平分轨会漏检。** 峰值低于 0.5 的分轨会生成一份转写专用副本，提升到约 0.89 峰值，最多 +24dB；原始分轨、试听、Logic 对齐不变。真实贝斯分轨 +21.27dB 后，音符从 1 个恢复到 80 个，完整分轨 E2E 是 109 个。

**空轨要在清理后重新判。** 跨轨裁决可能把一条只有串音的分轨清空。清空后仍留在 ZIP 或合并 MIDI 里，Logic 会多出空轨。现在 `_midi_note_count <= 0` 会删除文件、移出产物、标记 `skipped` 并计入 `empty_stems`。

**合并 MIDI 要统一 PPQ。** 480 和 960 混在一起时，钢琴会被拉长 2 倍，整曲错位。合并时统一到最大 PPQ，按比例缩放音符、控制器和 tempo，同时保留 piano 的 program 0。

**鼓的力度不能固定 100。** ADTOF 输出固定力度，MuScriptor 的鼓也未必贴合音频。导出前按分轨音频峰值重建 velocity，音高、时间和鼓件不变。

## 钢琴：从「能响」到「能弹」

钢琴是最难的一块。TransKun 的 note-off 经常跟着声音衰减走，而不是手指离键；踏板下会把整段跑动连成三十多个同时按键。只在最后删几个短音解决不了。

当前的处理链是：

1. 25ms 内近似重复起音合并；
2. note-off 按 1/16 网格对齐，无踏板最多缩短 15ms，踏板下 40ms；
3. 左右手分轨，50ms 起音簇，动态规划 + beam search，代价包含跨度、越界、移动、交叉和单手大和弦；
4. 精确重复起音合并；
5. 手距转移：单手超过 14 半音时，只接受能严格降低最大跨度的拆分，禁止交叉、单手超过 5 音、左手超过 72；
6. 声部识别：按同 tick 起音组标记 BASS/MELODY/INNER/SINGLE，踏板内重断句只找同声部或同音高的目标；
7. 跨手同音高去重；
8. 物理复音上限：每手 5 个同时按键，未分轨时全局 10 个，截断最早按下、且释放代价最低的音，不删除 note-on；
9. 写回并重新生成质量报告。

这些规则不是拍脑袋定的。三首高难度钢琴曲的真实 MIDI 结果：

| 曲目 | 音符数 | 全局峰值（前→后） | 宽和弦（前→后） | 最大手距（前→后） |
| --- | ---: | ---: | ---: | ---: |
| Chopin Op.10 No.4 | 2126 | 36 → 9 | 18 → 2 | 24 → 18 |
| Ravel Ondine | 4424 | 49 → 10 | 40 → 6 | 31 → 29 |
| Balakirev Islamey | 7555 | 37 → 10 | 103 → 11 | 31 → 24 |

三首的音符数量完全不变，说明没有删 note-on；quality 从 `ok=false`、有 issues 变成 `ok=true`、issues 为空。Ondine 仍保留一个 28.099 秒的低音长音：没有同手后续起音，踏板也没抬起，仅凭音频无法判断手指何时离键，强行截断会改变真实长音，所以只报告，不处理。

## 工程与验证

后端 FastAPI，前端 Vue 3 + Vite + Pinia，打包用 PyInstaller。DMG 约 430MiB，内置前端、i18n、MuScriptor 源码、Beat This 权重、YourMT3 源码和 cryptography；MuScriptor 权重太大，首次运行按需下载。

本地同一时间只允许一个 MPS 推理。任务管理器有两个 worker，但 `acquire_accelerator_lock` 用文件锁做跨进程互斥，避免桌面应用和 HTTP 服务同时抢 Metal。等待锁时可以取消，退出时 macOS 会释放 flock，不会留下死锁。

测试记录是 511 passed / 1 skipped，skip 是需要真实 TelkNet Key 的只读烟测。钢琴专项 36 个测试，覆盖声部角色、长音/外声部保护、踏板提前抬起、复音牺牲者、1 tick 伪影、宽和弦拆分和手部交叉。

真实 TelkNet 烟测曾返回 401 `API_KEY_INVALID`，没有创建任务、没有付费，所以线上契约记为未验证。这类外部凭据状态由用户处理，不是路由代码的问题。

## 仍然存在的问题

- 只支持 Apple Silicon。Intel Mac、Windows、Linux 不在当前分支的支持范围。
- 不做本地分离，MVSEP/TelkNet 不可用时只能走 direct 或 bypass。
- 没有乐谱、和弦、音色库导出；目标是 MIDI 工程素材，不是制谱软件。
- ADTOF 和 ByteDance Pedal 的权重不随包分发，许可和下载要用户自己处理。
- 钢琴质量报告是符号指标，不能替代在 Logic 里逐音试听。验证记录里也明确写了没做这一步。
- 手距 14 半音、50ms 簇、五指上限这些阈值来自当前三首样本，需要更多曲目校准。
- 本地推理串行是性能取舍，云端等待和下载可以并行；六轨 Large 旧版接近 30 分钟，新版默认 Medium，Large 要显式开。

同系列：[MVSEP Studio](/posts/audio/mvsep-studio-local-pipeline/) 负责取歌和云端分离，[MusicParser](/posts/audio/musicparser-local-service/) 把同一套解析核心拆成了独立的本机服务。
