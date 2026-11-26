---
title: Ember 深潜：一份 JSON 如何变成确定性粒子影片
published: 2026-11-26
description: 从 SceneDocument 的字段设计、六个形状采样器、0.82 生长窗口的推导，到顶点着色器里的解析运动、离线物理烘焙的 float16 布局、CDP 逐帧截图与 ffmpeg 分段拼接。这是一份 Ember 引擎的实现级说明，包含真实参数、公式、边界和未实现清单。
tags: [WebGL, 粒子动画, Three.js, TypeScript, 引擎设计]
category: 折腾
---

`Ember` 是一个确定性的 WebGL2 粒子动画引擎。当前版本 `0.1.0`，源码级 MVP：链路闭合，未发布 npm，没有跨设备性能承诺。

上一篇文章只讲了骨架，这篇讲实现：每个数字从哪来、每个公式为什么这么写、哪些地方是刻意的取舍、哪些边界现在还没有跨过去。

## 零、先看它要解决什么问题

粒子动画的常规做法是"实时预览，录屏出片"。这两件事其实是两条不同的代码路径：预览跑时间驱动循环，录屏靠屏幕捕获，于是预览的帧和成片的帧永远对不齐——掉一帧、补一帧、编码器采样时机不同，结果就是"预览很好看，导出后节奏变了"。

Ember 的答案是把动画变成**纯函数**：

```
frame(t) = f(document, t)
```

`t` 是绝对毫秒，不是"已经播放了多久"。只要 `f` 里没有任何跨帧状态，拖到 9.6 秒和播放到 9.6 秒就必然是同一帧，离线渲染可以放心地逐帧 seek，预览和成片共用同一条渲染路径。

这不是一句口号，四条不变量（`docs/ENGINE.md`）把它钉死：

1. **文档是唯一输入**：`EmberScene` 只读 `SceneDocument`，渲染器只读 `EmberScene`，没有全局可变单例。
2. **粒子数量守恒**：所有发射器合并成一个缓冲，构建后不增删；没有 morph 目标时目标就是 base。
3. **每帧只写 uniform**：CPU 在播放或 seek 时不重写任何粒子属性，位置、速度、风、旋涡、生长、morph 全在顶点着色器里解析计算。
4. **时间轴与播放解耦**：`EmberTimeline.seek(ms)` 可任意跳转，不依赖播放过的时间；播放器只是不断调用它。

后面所有设计都是这四条的推论。

## 一、单位、坐标与颜色

引擎里最容易出错的是单位。Ember 的约定：

| 量 | 单位 | 说明 |
| --- | --- | --- |
| 时间 | 毫秒 | 文档、关键帧、标签、事件全部 ms；HTTP job 的 `duration` 是秒（历史原因） |
| 长度 | 世界单位 u | 无真实物理含义；相机默认半径 18 u，`fir` 形状默认高 9 u（Studio 预设用 12.4 u） |
| 角度 | 弧度 | `camAz`、`camRoll`、`turn` 在 state 里是弧度；AI plan 的 `camAz` 是度，由 `applyCameraPlan` 转换 |
| 颜色 | sRGB hex | 文档写 `#ffd29a`；进缓冲前用 `hexToLinear` 转线性空间，**只转一次** |
| 速度 | u/s | 解析位移 `position + velocity * (uTime * uSpeed)` |
| 粒子尺寸 | u | 默认 0.055–0.099，再乘 emitter 的 `size` |

坐标系是 three.js 默认右手系：+Y 向上，相机看向 `(0, camTargetY, 0)`。`fir` 从 `y = 0` 长到 `y ≈ 9`。

## 二、文档模型：SceneDocument

一份 `SceneDocument` 就是一部片子。核心字段：

| 字段 | 作用 |
| --- | --- |
| `schemaVersion` | `1` 或 `2`；`2` 增加任意通道与可选 `physics` |
| `name` / `duration` | 名称与片长（ms） |
| `emitters[]` | 粒子发射器：形状、origin、颜色、morph、物理绑定 |
| `splats[]` | 2DGS 风格广告牌层 |
| `camera` | 初始相机与 shake |
| `post` | bloom / grade 等后期参数 |
| `timeline` | 轨道数组：23 个已知键 + 任意命名通道 |
| `labels[]` | 叙事标签（Intro / Grow / Bloom…） |
| `title?` | 片尾标题配置（v1/v2 的增量字段） |
| `physics?` | 物理烘焙 payload（v2 的增量字段） |
| `initialState` | 覆盖 `DEFAULT_STATE` 的初始值，未知键当作任意通道 |

一个真实的最小例子（取自 `examples/christmas/scene.json`，有删减）：

```json
{
  "name": "Fir",
  "duration": 18000,
  "emitters": [
    {
      "id": "tree",
      "shape": { "kind": "fir", "count": 28200, "radius": 3.6, "height": 12.4, "seed": 11, "jitter": 0.015 },
      "color": "#ffd29a",
      "colorEnd": "#ff7a45",
      "morph": { "kind": "spiral", "radius": 5.2, "arms": 3, "turns": 2.2, "seed": 19 },
      "size": 1.1
    }
  ],
  "camera": { "mode": "perspective", "radius": 18, "y": 4, "targetY": 1.5, "fov": 38 },
  "post": { "bloomStrength": 0.9, "bloomRadius": 0.52, "bloomThreshold": 0.32 },
  "timeline": [],
  "labels": [
    { "name": "Intro", "at": 0 },
    { "name": "Grow", "at": 3000 },
    { "name": "Morph", "at": 9800 }
  ],
  "title": {
    "kicker": "EMBER ENGINE · EXAMPLE",
    "text": "MERRY CHRISTMAS",
    "start": 15200,
    "end": 18000
  }
}
```

校验器 `parseSceneDocument` 做四件事：类型检查、必填字段、有限数值（拒绝 `NaN`/`Infinity`）、范围 clamp。错误按**字段路径**报告，例如 `emitters[0].shape.kind: unknown shape kind "cone"`；Studio 载入坏文档时直接显示这些路径，且不改变当前场景。

`serializeSceneDocument` 反向工作：补默认值、clamp、稳定排序，保证同一份文档序列化两次得到相同字节。

### v1 → v2 的迁移

v1 只允许时间轴驱动 23 个已知键；v2 允许任意命名通道。原片需要 `white`、`create`、`orbGlow` 这些自定义量，所以：

- `TrackConfig.key` 可以是任意字符串；已知键写入 `state`，其他写入 `channels`，读取用 `getChannel()`。
- `initialState` 里的未知数值键同样进入通道表。
- `migrateSceneDocumentV1ToV2()` 把 v1 文档提升为 v2，字段语义不变。
- 迁移和两版 schema 都由测试锁定：v1/v2 各有 valid/invalid fixtures，含一个 21800 ms 的硬切样例。

## 三、确定性随机：一个种子，多条流

`packages/core/src/random.ts` 只有 `mulberry32` 及其派生，没有 `Math.random`。

关键在**流分离**：

```ts
const rng = mulberry32(seedWith(seed, salt));
```

- `kindSalt(kind)` 给六种形状不同的盐，所以同一个 seed 在 `sphere` 和 `fir` 上不会产生同一串随机数。
- 几何采样与属性采样是两条流：`scene.ts` 用 `seedWith(seed, 0xc0ffee42)` 生成颜色、速度、尺寸、相位。
- 结果是：**给一个 emitter 增加粒子数，不会改变已有粒子的颜色或速度**。这在调参时很重要——加粒子不该让整片重新"洗牌"。

测试用 `Buffer.compare` 断言：同种子两次采样字节一致，换种子必不同。

## 四、形状系统：六种采样器

`sampleShape(config)` 返回 `{ count, positions: Float32Array, grow: Float32Array }`。

计数优先级：`config.count` → 形状默认（`fir` 8000，其余 1200）；半径缺省 3，种子缺省 1，`jitter` 缺省 0。

| kind | 采样方式 | `grow` 分布 |
| --- | --- | --- |
| `sphere` | 体积均匀：`r = radius * cbrt(u)`，`z = 2v-1` + 极角 | 由内向外 `0.06 + 0.86*(r/radius) ± 0.03` |
| `box` | 三轴独立均匀 | 自下而上 |
| `ring` | 圆环管：主圆 + `cos(phi)*thickness` 径向偏移 | 沿环扫过 |
| `disc` | 面积均匀：`r = radius * sqrt(u)`，薄盘 | 由圆心向外 |
| `spiral` | 对数感旋臂：`t = pow(u, 0.62)`，`r = t*radius`，角度含 `t*turns*TAU` 与臂偏移 | 核心先亮 |
| `fir` | 14 层 × 7 根轮生树 + 树干 + 顶芽 | 自下而上爬升 |

`grow` 不是装饰：它决定每颗粒子"什么时候出现"，是生长动画的全部信息来源。五种基础形状按几何距离给 grow，`fir` 按高度层给。

### fir：一棵有结构的树

`fir` 不是随机点云，是程序化建模：

- 层数 `FIR_TIERS = 14`，每层 7 根枝，共 98 根。
- 第 `tier` 层高度分数 `t = 0.035 + (tier / 13) * 0.835`，即 `0.035 → 0.87`；层半径 `tierRadius = radius * (1 - t)^0.85`——上窄下宽。
- 每根枝长度 `tierRadius * (0.90..1.00)`，下垂量 `(0.08 + 0.38*(1-t)^1.35) * (0.9..1.1)`，并 clamp 到 `baseY*0.55 + 0.04` 防止穿地。
- 权重 `(1-t)^1.15 * (0.85..1.15)`，方位角 `spoke/7 * TAU + tier * 0.47 + ±0.11`——层与层错开约 27°，看起来才像轮生而不是栅栏。
- 权重表归一后，树干额外占 7%，顶芽占 3%；按累计权重二分查找选枝。
- 枝上取 `u = 0.06 + pow(rng, 0.85) * 0.94`，半径 `r = length*u`，高度 `baseY - droop*u^1.6 + lift*sin(pi*u) + needleSpread`——下垂 + 抬起 + 针叶散布三项叠加。
- 顶芽 `y = h*(0.845 + pow(rng,0.8)*0.15)`，半径 `0.18*(1-u) + 0.012`，保证轮廓有尖。

测试对 6000 粒子断言 `minY >= -0.01`、`maxY <= 9.02`、`maxY > 8.37`（顶芽存在）、`maxR <= 3.48` 且 `> 3.128`（不会缩成一团），同时检查 grow 的低段和高段都存在。

## 五、生长：0.82 这个数字是怎么来的

这是整个引擎里**最容易被误改**的一处，值得单独讲。

缓冲区里写入的 grow 属性：

```ts
grow[i] = clamp01(growOffset + sample.grow[i] * growSpan) * MAX_PARTICLE_GROW;
```

`MAX_PARTICLE_GROW = 0.82`。着色器里：

```glsl
float g = smoothstep(aGrow, aGrow + 0.18, uGrowth);
```

为什么必须先 clamp 再乘 0.82？

- 假设直接把 `growOffset + sample.grow * growSpan` 写进属性。当 `growOffset + growSpan > 1` 时属性可能等于 1；此时 `smoothstep(1.0, 1.18, 1.0) = 0`，这颗粒子**永远不会落位**——它会一直停在发射器原点，成为画面里一个不动的亮点。
- 属性上限 0.82 配合 0.18 的过渡窗口，恰好让 `smoothstep(0.82, 1.0, 1.0) = 1`。所以 `uGrowth = 1` 时每颗粒子都到达目标，无论 offset 和 span 怎么设。

测试用五组 `{offset, span}`（含极端的 `0.6 + 0.8`）验证：`maxGrow <= 0.82`、映射后每个 `g` 都是 1、最高点误差 `< 1e-5`。`render-three` 对 splat 做同样的断言。

生长还带"未长出时可见但不显眼"的处理：`p = mix(uOrigin, p, g)`，alpha 压到 `mix(0.07, 1.0, g)`。所以种子阶段不是一片黑，而是一颗暗淡的核。

## 六、SoA 缓冲：一个场景，一个数组

`EmberScene` 构造顺序固定：

1. `_baseState = {...DEFAULT_STATE}`，写入 `document.initialState` 的有限数值。
2. `buildParticleBuffer(document.emitters)` 生成合并缓冲与 `EmitterRange[]`。
3. 编译时间轴，target 指向 `_baseState`。
4. `seek(0)` 把第 0 帧写进 `state`。

缓冲字段（全部是 `Float32Array`）：

| 字段 | 长度 | 内容 |
| --- | --- | --- |
| `position` | count×3 | base 位置（已加 emitter origin） |
| `velocity` | count×3 | 解析速度 u/s |
| `color` | count×3 | 线性色 |
| `morph` | count×3 | morph 目标（无 morph 时等于 position） |
| `morphColor` | count×3 | morph 色调 |
| `size` / `alpha` / `phase` / `grow` / `seed` | count | 逐粒子标量 |
| `origin` | count×3 | 每颗粒子的生长原点 |

构建细节：

- 每个 emitter 计数取 `floor(emitter.count ?? shape.count ?? default)`，为 0 时跳过且不产生 range。
- 颜色：`colorA = emitter.color ?? '#ffd29a'`，`colorB = emitter.colorEnd ?? emitter.color ?? '#ff7a45'`，`mix = pow(rng(), max(0.05, colorMix))`，亮度 `0.82–1.14`。
- 速度默认标量 0.1，`speed = scale * (0.3 + rng * 0.9)`，方向均匀分布球面。
- 尺寸 `(0.055 + rng*0.044) * emitter.size`；alpha `min(1, emitter.alpha * (0.72 + rng*0.28))`。

**零拷贝**是整个设计的关键：`PointsLayer` 的几何属性全是 `buffer.position.subarray(...)` 这样的视图，没有复制，也没有逐帧上传。

### override 层

Studio 拖动 slider 不写文档，而是写一层覆盖：

```ts
scene.setOverride('grow', 0.9);   // 盖住时间轴
scene.seek(750);                 // 时间轴继续写 _baseState
scene.getParam('grow')           // 仍是 0.9
scene.clearOverride('grow');     // 回到 750ms 的时间轴值
scene.resetOverrides();          // 全部回到时间轴
```

`_applyState()` 对每个键取值：有限 override 优先，否则取 `_baseState`。未知键和非有限值被忽略，不会污染状态。这就是"拖 slider 不破坏文档"的实现。

## 七、时间轴：为什么不直接用 anime.js 的 keyframes

`EmberTimeline` 是 anime.js v4 的薄封装，但**刻意不用 v4 的 keyframe 数组语法**。原因：keyframe 数组的求值依赖内部状态，逐段独立 tween 才能保证任意 seek 精确。

编译规则：

1. `createTimeline({ autoplay: false })`。
2. 跳过 `key` 不在 `DEFAULT_STATE` 里的轨道（v2 的任意通道走 `getChannel`）。
3. `start = max(0, track.start ?? 0)`；`end` 优先级：`end > duration > 场景总时长`。
4. 没有 keyframes：若 `end > start`，生成一段 `from = track.from ?? 默认值`、`to = track.to`、`ease = track.easing ?? 'linear'`。
5. 有 keyframes：过滤非有限值、按 `at` 排序；每个 `at` clamp 到 `[previousAt, max(previousAt, end)]`；只有 `at > previousAt` 且值变化才生成一段；循环结束若还有 `track.to`，补最后一段。
6. 每段都带**显式 `from`**：

```ts
timeline.add(
  target,
  { [key]: { from, to }, duration: Math.max(0.001, end - start), ease },
  segment.start,
);
```

显式 `from` 是刻意的：anime 默认会从"当前值"起算，那就有状态了；显式 from 让每段互不依赖。

7. 同一毫秒的双关键帧编译成零时长 setter，实现硬切；正反向 seek 都得到同一个值。
8. 标签：轨道上的 `label` 记在段起点；`document.labels` 后写，同名以文档为准。
9. 尾部：`duration = max(请求时长, 内容结束, timeline.duration)`；在 `duration - 1` 处加一个 1 ms 的 `{__emberTail: 0 → 1}` tween，让时间轴完整覆盖片长——即使最后一个可见变化更早结束。
10. `seek(ms)` 把时间 clamp 到 `[0, duration]`，调用 `timeline.seek(time, true)`。第二个参数 `muteCallbacks`：seek 不触发任何用户回调，只有状态值变化。

`resolveEnd` 的行为值得记住：一条轨道既没有 `end` 也没有 `duration` 时，默认持续到场景末尾，而不是停在最后一个 keyframe。

## 八、顶点着色器：运动全部解析

`PointsLayer` 为每个 `EmitterRange` 建一个 `Points`。材质默认是 `ShaderMaterial`：`transparent: true`、`depthWrite: false`、`depthTest: false`、`AdditiveBlending`、`toneMapped: false`、`frustumCulled = false`、`renderOrder = 2`。

顶点着色器的主干：

```glsl
float t = uTime * uSpeed;
float g = smoothstep(aGrow, aGrow + 0.18, uGrowth);
vec3 p = position + aVelocity * t;
p.y -= uGravity * t;
```

逐个效果：

- **重力**是线性位移，不是二次积分。`p.y -= gravity * t` 直接乘时间——因为它必须是 `t` 的闭式函数，不能依赖历史。
- **风**：三个轴各一条正弦，频率约 0.53–0.70，空间相位混入 `position.y/z/x` 与 `aPhase/aSeed`，幅度 `uWind * (0.35 + 0.65*aSeed)`。
- **旋涡**：三轴 curl 场，每个分量用两条 sin/cos 差分，乘 `0.06 + 0.18*uWind`。比噪声函数便宜得多。
- **swirl**：绕发射器轴做差速旋转，`angle = uSwirl * (0.35+0.65*aSeed) * t / (0.9 + radius*0.35)`——越靠外转得越慢，形成漩涡的剪切感。
- **burst**：`normalize(p - uOrigin) * uBurst * 0.35`。
- **生长**：`p = mix(uOrigin, p, g)`。
- **morph**：`p = mix(p, aMorph, clamp(uMorph, 0, 1))`。
- **turn**：绕发射器轴整体旋转 `uTurn`。

点尺寸：

```glsl
float projScale = projectionMatrix[1][1] * 0.5 * uViewport.y;
float growScale = mix(0.55, 1.0, g);
float pointSize = aSize * uSize * growScale * projScale;
if (uOrtho < 0.5) pointSize /= max(0.05, -mvPosition.z);
gl_PointSize = clamp(pointSize, 1.0, 160.0);
```

`uViewport` 是**物理像素**的 drawing buffer 尺寸，不是 CSS 像素。透视相机会按深度衰减尺寸，正交相机不除。160 px 是硬上限——防止近距离下一颗粒子糊满屏幕。

透明度：`aAlpha * uAlpha * twinkle * mix(0.07, 1.0, g)`，其中 `twinkle = 0.72 + 0.28*sin(t*3.1 + phase*TAU + seed*2.7)`。颜色：`mix(aColor, aMorphColor, morph)`。

片元着色器只有一个软圆：

```glsl
vec2 offset = gl_PointCoord - 0.5;
float dist = length(offset);
float mask = 1.0 - smoothstep(0.06, 0.5, dist);
float core = 0.55 + 0.45 * exp(-dist * dist * 12.0);
float alpha = vAlpha * mask;
if (alpha <= 0.001) discard;
gl_FragColor = vec4(vColor * core, alpha);
```

这段 shader 有一个**真实 WebGL 测试**：headless Chrome 里画一个 64 px 点，读回中心与边缘像素，断言中心 alpha > 0.8、边缘 < 0.2（本机实测 1.000 / 0.043）。另一个测试用正则锁住 `smoothstep(0.06, 0.5, dist)` 的参数顺序，防止有人把内外写反。

### 逐粒子出生与延迟

除了全局 grow，还有逐粒子 `aOrigin` / `aBirth`：

```glsl
float delayedFront = birth > 0.0
  ? clamp((front - birth) / max(1.0 - birth, 0.001), 0.0, 1.0)
  : front;
float g = smoothstep(aGrow, aGrow + 0.18, delayedFront);
```

这让同一 emitter 内的粒子可以错峰出现，而不是整体一起亮。`uHasOrigin = 0` 时退回旧的单 origin 路径，手工材质不受影响。

## 九、粒子材质层：默认逐位不变

`PointsLayer` / `SplatLayer` 支持可选材质，但不改文档、不进契约：

| 字段 | 默认 | 作用 |
| --- | --- | --- |
| `blend` | `additive` | 构建期选 `additive` / `alpha` |
| `opacity` | 1 | 最终 alpha 乘数 |
| `softness` | 0 | 边缘柔化 |
| `core` | 1 | 核心亮度 |
| `sizeCurve` / `alphaCurve` | `{1,1,1}` | `mix(start,end,g)^exp` |
| `twinkle` | 1 | 闪烁幅度，0 = 稳定 |

只有 `blend` 是构建期选择（换 blend 才重建材质）；其余全是 uniform。省略材质时编译原 shader，默认整帧的黄金 hash 仍是 `1001168103`、16 draw calls——**默认路径逐位不变**，这是加功能时最容易破坏、也最需要测试锁住的东西。

alpha blend 仍保持 `depthWrite: false` / `depthTest: false`，所以重叠粒子有顺序伪影；splat 必须配构建期 `depthSort`，points 的跨 emitter 透明排序不在这一层解决。

## 十、Splat：借了 2DGS 的视觉，不是 3DGS

先把边界说清楚：**这不是完整 3D Gaussian Splatting**。没有训练、没有球谐、没有逐 splat 深度排序、没有各向异性 3D 协方差投影。它是"视空间带旋转的各向异性 2D Gaussian billboard"，实现是 instanced quad + additive。

构建 `buildSplatCloud(config)`：

- 默认 `count = 256`（或 `shape.count`）、`size = 0.18`、`anisotropy = max(1, 3)`、`alpha = 0.55`、`sizeVariance = 0.35`。
- 中心点由 `sampleShape(config.shape ?? {kind:'sphere'})` 采样。
- 长轴 `baseSize * max(0.05, 1 + (rng*2-1)*sizeVariance)`；短轴 `longAxis / (anisotropy * (0.82 + rng*0.36))`。
- 每 splat 一个 `0–TAU` 的随机旋转；grow 归一化与 point 完全一致（同样的 0.82 窗口）。

渲染用 `InstancedBufferGeometry`（单位四边形 + 两三角形），每实例带 `aCenter`、`aMorphCenter`、`aVelocity`、`aScale(vec2)`、`aRotation`、`aGrow` 等。

顶点着色器里，中心点只走 `velocity → growth → morph → burst → turn`——**没有** gravity / wind / curl / swirl。而且 `burst` 在 `morph` 之后，与 points 的顺序相反。然后在视空间展开：

```glsl
float rotation = aRotation + uTurn * 0.35 + aPhase * 6.2831;
vec2 axis = vec2(cos(rotation), sin(rotation));
vec2 quad = position.xy * 2.0;
vec2 scaled = vec2(quad.x * aScale.x, quad.y * aScale.y) * max(uSize, 0.0);
scaled *= mix(0.55, 1.0, g);
vec2 offset = vec2(
  scaled.x * axis.x - scaled.y * axis.y,
  scaled.x * axis.y + scaled.y * axis.x
);
centerView.xy += offset;
```

注意 `max(uSize, 0.0)`：负尺寸会把四边形翻转，视觉上变成黑洞。片元用 `exp(-r2 * 2.5)` 做高斯衰减。

一个容易读反的细节：splat 的 `renderOrder = 1`，points 是 `2`，所以 **splat 先画**；但 additive 且无深度时，绘制顺序不影响最终叠加亮度。调试时不要把"先画"误读成"在上面"。

## 十一、后期链：默认链与电影链

默认顺序（所有 opt-in pass 关闭时）：

```
RenderPass → UnrealBloomPass → GradePass → OutputPass
```

启用电影感 pass 后：

```
RenderPass → [FilmBloomPass] → [LensPass] → [GradePass | FilmGradePass]
           → OutputPass → [FinishPass]
```

- **opt-in / 默认关闭**：`lens`、`filmGrade`、`finish`、`bloom.film` 构造函数即 `enabled = false`；默认渲染、显式 `{}`、`setPostFx(null)` 都不绘制它们。
- **懒分配**：`FilmBloomPass` 只是 composer 里的占位；第一次 `applyFilm()` 才创建第二套 5 级 mip 链。未启用时零 render target——省掉 720p/DPR2 约 46 MB、1080p/DPR2 约 105 MB 的闲置显存。
- **film bloom** 用软膝高光提取 + 宽 mip 降权替换 stock high-pass，与 stock bloom 互斥。
- **lens** 是 1/4 分辨率的暖 halation + 冷横向拉丝，唯一消费者是 `FilmGradePass`；只开 lens 不产生画面变化，解析时自动关闭。
- **filmGrade** 在 ACES 之前做色差、径向 zoom、filmic S 曲线、分离色调、抬黑、暗角、白场；启用时替换 `GradePass`，二者不叠加。
- **finish** 在 `OutputPass` 之后做显示空间 5-tap 边缘感知 AA + 24 fps 颗粒 + dither。

默认 `GradePass` 里的几个公式：

- 色散：`ca = chromatic * (0.35 + dot(center,center)*2)`，R/B 向两侧偏移。
- 暗角：按画幅角距离归一化，`1 - smoothstep(0.28, 0.98, dist)`，再按 `vignette` 混合。
- 颗粒：`hash12(uv * (1920,1080) + fract(time)*137) - 0.5`，乘 `grain * (0.35 + maxChannel)`。同一时间 + 同一像素永远得到同一个值——颗粒也是确定性的。
- 最后 `max(color, 0)`，alpha 固定 1。

`OutputPass` 做 ACES tone mapping + sRGB 传递；`renderer.toneMappingExposure` 保持 1，曝光已经在 Grade 里做过，避免乘两次。

### Look 只有两档

Studio 不把调色参数散在 UI 里，而是两个共享预设：

- `neutral` → `{}`：完全不覆盖后期字段，与省略等价，预设帧逐位不变（hash `1001168103`）。
- `filmic` → film bloom + lens（halation 0.6 / streak 0.14）+ filmGrade（S 曲线 0.78 / cool 0.34 / lift 1.05 / zoom 0.08）+ finish（AA 0.45 / grain 0.035 / 24 fps）。

主预览和 `?render=1` 页面都通过 `StudioEngine` 的同一份配置使用 look；`setLook()` 只调 `setPostFx`，不重建粒子。选择存 `localStorage['ember.studio.look.v1']`，未知值回落 `neutral`；服务端只保存 look id 白名单，不 import 引擎包。

## 十二、相机

`CameraRig` 支持透视与正交，参数来自 state：`camAz`（方位角）、`camRadius`（轨道半径）、`camY`、`camTargetY`、`camFov`、`camZoom`、`camRoll`（Dutch roll）、`camShake`（0–1 handheld 抖动）。

`camShake = 0` 时完全静止——这是刻意的，确定性要求"没开就别动"。开了之后也用确定性噪声，不用 `Math.random`。

`cinematic.ts` 里还有一套电影相机：偏轴构图、呼吸、三次冲击包络、`followOrb`、`freeze`、`roll`。它和 `Demo/src/camera.js` 的关键时间点误差为 0——这是移植正确性的验收标准。

## 十三、物理：为什么运行时不积分

这是全项目最硬的架构约束，值得单独一节。

用户原话是"加上轻量物理引擎以增加真实感和流体感"。常规做法是运行时每帧积分，但那条路和"seek 到 T == 播放到 T"直接冲突：积分依赖历史，跳帧就崩。

Ember 的方案（ADR-0004）：

```
解析场（纯函数） → 离线固定步长烘焙 → float16 payload → 运行时 floor + lerp
```

预算先算清楚（M2 Pro / Node 26.7 实测）：

- 168k 粒子 CPU 步进 6.03 ms/帧；
- 物理态 24 B/粒子；
- 1 Hz 快照 × 258 s × 168k 粒子 ≈ 1.04 GB，不可行；
- VAT float16、64 节点、258 s、30 Hz ≈ 3 MB，可行。

所以选 float16 track-major 布局。

### 四种解析场

- `gravityPoint`：带 softening 的反平方吸引；
- `vortex`：绕轴切向加速度；
- `curlNoise`：种子化 value-noise 势场的 curl，近似无散度；
- `drag`：`-strength * velocity`。

`evaluateField` / `evaluateFields` 是 `(field, position, velocity, time)` 的纯函数，不修改输入，可复用调用方的 `out`。

### 烘焙

`bakePhysics(config)` 用 symplectic Euler（`v += a*dt; p += v*dt`）在 `hz` 上积分，帧 `i` 表示 `from + i/hz` 秒的状态，**先存状态再积分**。只能在 Node / CLI / 离线工具里调用；`@ember/core` 只 import 纯校验与采样函数。

碰撞（plane / sphere / box + restitution/friction）也只发生在烘焙循环内：位置修正 + 法向反射 + Coulomb 摩擦。省略 `colliders` 的 bake 与加入碰撞前逐字节一致。

### 数据格式

- `data` 是 little-endian float16 位置的 base64：先 track、再 frame、每帧 x/y/z。
- `frameCount = floor((to - from)/1000 * hz) + 1`。
- `hash` 是解码字节的 SHA-256，解析时重算——**payload 不可静默篡改**。
- 上限：4096 tracks、64 fields、32 colliders、1000 Hz、64 MiB payload。
- 包内自带 base64、float16、SHA-256 实现，所以 Node、浏览器、worker 行为一致；源码禁止 `Math.random` / `Date.now` / `performance.now` / `process.env`。

### 运行时

`samplePhysics(bake, t)` 只做 floor + lerp：时间 clamp 到 `[from, to]`，非有限时间按 `from`，正序、逆序、随机 seek **逐位一致**。`createPhysicsSampler` 把解码结果缓存一次，供逐帧采样复用——否则每次 seek 解码 3 MB，帧率直接崩。

渲染层只有声明了 `physics` 的 emitter 才编译 `EMBER_PHYSICS` 变体，每帧写一个 `uPhysicsOffset` uniform。没有 bake 的文档不产生任何字节变化。

`packages/core` 里，`createScene({ physicsBake })` 把 bake 挂在场景上，`seek` 时刷新 `physicsOffsets`；CLI 的 `bake --physics` 产出 `physics.json`。

## 十四、无头采样器：不需要 WebGL 的确定性帧

`@ember/headless` 是一个反直觉但很有用的包：**不渲染，只采样**。

`createHeadlessAdapter(scene)` 提供 `seek` / `frame` / `sampleFrames`，复刻 points 的解析运动（含逐粒子 origin/birth）与 physics bake 采样。它只允许 `import type` 消费 `@ember/core`，运行时依赖为零，禁止 DOM、canvas、`fs`、`http`、时钟、随机数。

用途有三个：

1. **CI 里验证运动学**：不需要 Chrome/GPU 就能断言"第 3000 ms 第 42 颗粒子的位置"。
2. **回归对比**：把采样结果 hash 起来，改 shader 前先确认 CPU 侧的语义没变。
3. **离线工具**：Python `physics_previs.py` 的 64 节点尾迹预演和它对齐。

这是"确定性"从口号变成可测事实的关键一环：GPU 像素可以因驱动不同而不同，但 CPU 侧的解析求值应该永远一致。

## 十五、资产层：读 3DGS 文件，但不假装是 3DGS

`@ember/splat-io` 零依赖解析两种格式。

### 3DGS `.ply`

只接受 `format binary_little_endian 1.0`。按属性名读取，列顺序、法线、`f_rest_*`、未知属性都不影响结果；列表属性不支持。

| 属性 | 语义 | 变换 |
| --- | --- | --- |
| `x,y,z` | 世界坐标 | 原样 |
| `f_dc_0..2` | 球谐 0 阶 | `color = clamp01(0.5 + 0.28209479177387814 * f_dc)` |
| `opacity` | logit | `1/(1+exp(-x))` |
| `scale_0..2` | 对数标准差 | `exp(logScale)` 逐轴 |
| `rot_0..3` | 四元数 `(w,x,y,z)` | 归一化后存 `(x,y,z,w)` |
| `f_rest_*` | 高阶球谐 | 跳过，只导入 DC，`meta.shDegree` 记录最高阶 |

支持全部标准 PLY 标量类型；缺必需属性、未知类型、ASCII/BE、截断 header 抛 `SPLAT_IO_HEADER`，截断数据抛 `SPLAT_IO_TRUNCATED`，都带 `code` 与位置。

### antimatter15 `.splat`

无 header、无 magic；文件长度必须是 32 的整数倍，每行 32 字节：`position` 3×float32 LE、`scale` 3×float32（**已是线性标准差**，不再取 exp）、`RGBA` 4×uint8（A 是已 sigmoid 的 opacity）、`quaternion` 4×uint8（文件顺序 `(w,x,y,z)`，解码 `(byte-128)/128` 后重新归一化）。解析后 `toSplatCloud` 投影成与 `SplatCloud` 同字段的二维广告牌数据。

P0 验收做过 5 万点的实测；仍没有球谐高阶、逐帧深度排序与深度正确 alpha。

## 十六、契约层：一份 schema，三种语言

`docs/contracts/schema/*.ts` 是唯一事实源（TypeBox）：

```
scene.v1.ts + scene.v1.shared.ts   # v1
scene.v2.ts                        # v2：任意通道 + 可选 physics
physics.v1.ts                      # 物理烘焙
migrations/v1_to_v2.ts             # 迁移
fixtures/**                        # valid / invalid 样例
```

codegen 产出 **11 个文件**：两版 scene 与 physics 各一份 JSON Schema、TS 类型、Pydantic 模型，加物理 README 和总 README。`pnpm codegen:check` 做**逐字节比对**——生成器改一个空格都会失败。

意义在于跨语言一致性：TypeScript 的 `parseSceneDocument`、Python 的 Pydantic 校验、JSON Schema 三方对同一份文件必须得出同一结论。测试里同时跑 TS 与 Python（缺 pydantic 时明确 SKIP，而不是静默通过）。

CLI 的 `validate` 做同样的双检：contracts 与 runtime 各验一遍，结论不一致就报 `MISMATCH` 并退出 1。这是防止"schema 说可以、运行时说不行"这类漂移的唯一办法。

## 十七、Studio：编辑器的边界

`@ember/studio` 是 React 19 + Vite 8 的宿主，**不是 runtime**。它负责：

- 时间轴：点击 seek、拖拽 playhead、`←`/`→` 前后 1 秒、空格暂停、`R` 重播；
- 参数面板：23 个键里暴露 15 个 slider，其余走时间轴；
- 4 个 18 秒预设：`fir`（42k）、`embers`（26k）、`galaxy`（50k）、`splats`（2k + 14k）；
- `Document` 面板：保存/载入 JSON，支持文件选择与拖拽，坏文件不改变当前场景；
- `Title` 面板：文字、字号（片高百分比）、模式（DOM / Particles）、seed；
- 撤销/重做（50 步）与 localStorage 单份自动保存；
- `Render` 面板：Chrome / ffmpeg / 队列状态，场景/FPS/时长/Format/Aspect/Look 选择；
- `AI director`：生成镜头规划、对当前帧做评审。

几个边界：

- **切场景写回 URL**，`?scene=fir|embers|galaxy|splats` 可分享。
- 预设仍写死在 `apps/studio/src/engine/scenes.ts`，没有项目库/多文档管理。
- look 只有 `neutral` / `filmic`，新增要同时改 Studio 与 server 白名单。
- Studio 不编码视频、不启动 Chrome；它只提供渲染模式页面。

### 标题原语：文字粒子化

标题分两层：**光栅化在宿主，采样在引擎**。`@ember/core` 从不碰 canvas 或 DOM。

1. 文档根字段 `title` 保存配置；缺省时文档与加入标题前逐字节一致。
2. 宿主把文字画成 `Uint8Array` alpha mask（Studio 用 `apps/studio/src/lib/title-raster.ts`）。`getImageData` 失败、无 DOM、空文字都返回 `null`，不抛错。
3. `sampleTextMask(mask, options)` 产生确定性点云：同 mask + 同 config（含 seed）得到字节级相同的数组。
4. `particles` 模式下文档只存配置，**运行期**由宿主派生保留 id 为 `title` 的 emitter。不能把 emitter 写进文档：`parseSceneDocument` 会给每个 emitter 补默认 `shape.count`（1200），与真实点云永远对不上。
5. 窗口默认是片尾最后 2.8 s；`startMs` 淡入，只有 `endMs < duration` 才淡出，所以缺省卡片保持到最后一帧。
6. 光栅化不可用时回落 DOM 卡片，影片始终有标题。
7. 不裁剪：超过 8 行、或超过 2048×1024 / 2,000,000 像素时直接返回 `null` 并回落 DOM。

标题不声明 morph target：`morph = 1` 时留在原位，而不是折进场景形状。字号按片高百分比（默认 9.5），画布按固定参考高度 540 px 光栅化，所以 1280×720 与 1920×1080 的相对大小一致。

## 十八、后端：一个页面契约 + Chrome + ffmpeg

`@ember/server` 是 Fastify 5，它**不 import 引擎代码**，只认三件事：

```js
window.__emberReady === true;
typeof window.__emberRender.seek === 'function';
window.__emberRender.seek(atMs);   // 同步或返回 Promise
```

加上 URL 契约：

```
http://<studio>/?render=1&scene=<id>&look=<neutral|filmic>&w=<w>&h=<h>
http://<studio>/?render=1&document=<jobId>&look=<look>&w=<w>&h=<h>
```

任何实现这三件事的页面都能被渲染；仓库里只有 Studio 一个实现。

### CDP 逐帧

Chrome 启动参数里有几个关键项：

```
--headless=new
--remote-debugging-port=<free port>
--user-data-dir=<tmp>/ember-chrome-*
--window-size=<w>,<h>
--hide-scrollbars
--force-device-scale-factor=1
--enable-unsafe-swiftshader
--disable-background-timer-throttling
--disable-renderer-backgrounding
--mute-audio
```

`--enable-unsafe-swiftshader` 让没有 GPU 的 CI 也能跑 WebGL（软件光栅化，慢但可用）。`--force-device-scale-factor=1` 与 `Emulation.setDeviceMetricsOverride(deviceScaleFactor: 1)` 保证截图 1:1。

连接流程：取空闲端口 → 轮询 `/json/list` 找 `type === 'page'` 且路径匹配的 target → WebSocket 连 `webSocketDebuggerUrl` → `Page.enable` / `Runtime.enable` / deviceMetrics → 每帧 `Runtime.evaluate` 调 `seek(atMs)` → 等**两帧** `requestAnimationFrame`（让 React 状态与 WebGL 绘制都落地）→ `Page.captureScreenshot`（jpeg、quality、`fromSurface: true`、`captureBeyondViewport: false`、`optimizeForSpeed: true`，超时 30 s，失败重试一次）→ 收尾关 CDP、SIGKILL Chrome、删临时 profile。

**时间轴公式**：全局第 `index` 帧的时间是

```
round(fromMs + index * 1000 / fps)
```

18 s @ 30 fps → 540 帧，最后一帧在 17,967 ms，不是 18,000 ms。分段渲染不改变这个公式——否则拼接处会重复或丢帧。

### 分段、拼接与编码

长片按 `chunkSeconds`（默认 24 s）分段，每段自己的 JPEG 目录与 H.264 文件，最后无损拼接：

```bash
# 单段
ffmpeg -hide_banner -loglevel error -y \
  -framerate 30 -i <tmp>/seg-000/frame-%05d.jpg \
  -c:v libx264 -preset veryfast -crf 18 \
  -pix_fmt yuv420p -color_range tv -an \
  -progress pipe:1 -nostats <tmp>/segment-000.mp4

# 拼接（流拷贝，不重编码）
ffmpeg -hide_banner -loglevel error -y \
  -f concat -safe 0 -i <tmp>/concat.txt \
  -c copy -movflags +faststart -an \
  -progress pipe:1 -nostats -f mp4 <artifacts>/<jobId>.mp4.part
```

细节：

- 所有段用同一套编码参数，所以 `-c copy` 是真正的流拷贝，无代际损失。
- 输出显式 `-f mp4`，因为临时文件后缀是 `.part`，不能靠扩展名推断封装。
- `-pix_fmt yuv420p` 保证 Safari/QuickTime 可播；`+faststart` 只在最终成片加，把 moov atom 前移。
- 拼接成功后 `rename` 为 `<jobId>.mp4`，下载端永远看不到半截文件。
- `concat.txt` 里的单引号按 demuxer 规则转义为 `'\''`。

WebM 与 GIF 是从 H.264 中间片转码的：

```bash
# WebM：VP9
ffmpeg -i visual.mp4 -c:v libvpx-vp9 -crf 30 -b:v 0 \
  -row-mt 1 -deadline good -cpu-used 2 -pix_fmt yuv420p \
  -an -f webm <jobId>.webm.part

# GIF：256 色调色板
ffmpeg -i visual.mp4 \
  -filter_complex "[0:v]split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  -an -loop 0 -f gif <jobId>.gif.part
```

所以 WebM/GIF 有一次代际损失；GIF 的色带与无 alpha 是格式上限，不是渲染丢帧。

### 状态机、进度与取消

```
queued ──#pump──▶ rendering ──第一段编码──▶ encoding ──concat+rename──▶ done
  │                  │                        │
  └──cancel──────────┴──cancelRequested───────┴──▶ cancelled
任何阶段异常 ──▶ error（带段号/时间区间、ffmpeg stderr 或 CDP 错误）
```

- 进度：开始渲染 `0.01` → `__emberReady` 后 `0.04` → 每段采集占该段区间前 85%（段区间 0.04–0.93）→ 每段编码占后 15% → concat `0.93–0.96` → `1`。
- `framesRendered` 只在采集时增长；`chunksDone` 在该段编码完成后 +1。
- 取消语义分三态：`queued` 立即移除；`rendering` 在每帧采集前与段边界检查；`encoding` 每 200 ms 检查并 `SIGKILL` ffmpeg。
- 整任务看门狗 `EMBER_JOB_TIMEOUT_MS`（默认 2 h）覆盖 Chrome 启动、页面等待、采集、编码、concat 与混音；单段看门狗 `EMBER_SEGMENT_TIMEOUT_MS`（默认 20 min）独立生效。
- 服务器重启时未完成的 job 标 `error`（附原因），不自动续跑。
- 队列 FIFO、单槽、`jobs.json` 原子写；`SIGINT`/`SIGTERM` 时给运行中 job 设 `cancelRequested`，最多等 8 s 收尾。

### 读取与持久化

- `GET /api/jobs/:id/events` 是 SSE，事件含 snapshot / status / progress / log / done。
- `GET /api/jobs/:id/artifact` 支持 Range，返回 206，可拖进播放器边下边播。
- 数据目录：`jobs.json`、`artifacts/<jobId>.mp4`、`documents/<jobId>.json`、`tmp/<jobId>/`。`tmp` 在 job 结束时整体删除。
- 保留策略：`EMBER_JOB_RETENTION_DAYS`（默认 7 天）与 `EMBER_MAX_JOBS`（默认 50）；`queued`/`rendering`/`encoding` 永不删除。

## 十九、出片格式与画幅

| format | 编码 | 适合 | 限制 |
| --- | --- | --- | --- |
| `mp4` | H.264 | 任何播放器 / 社交上传 | ≤1920×1920，可带 AAC |
| `webm` | VP9 | 浏览器 / 网页 | ≤1920×1920，可带 Opus，无 alpha |
| `gif` | 256 色 | 聊天 / 预览循环 | ≤15 s、≤30 fps、≤1.2 MP，无音轨/alpha |

画幅：`16:9`（1280×720）、`9:16`（720×1280）、`1:1`（1080×1080）、`4:5`（864×1080）或 `custom`；显式宽高必须与声明比例一致，否则 `400 invalid_render_request`。

一个实测边界：schema 允许 64×64，但 headless 下 64×64 在 45 s 内等不到 `__emberReady`；128×128 与 320×180 可用。这类"文档没写、但实际会踩"的限制，README 里单独列了出来。

## 二十、AI 接口：明确说清能力边界

两个接口，能力不同，不能混为一谈。

**camera-plan**：

```bash
curl -s -X POST http://127.0.0.1:8787/api/ai/camera-plan \
  -H 'content-type: application/json' \
  -d '{"brief":"慢速、庄重的圣诞粒子短片，暖色余烬，深空背景","duration":18,"bpm":96}'
```

返回固定五镜头（`establish → orbit → push → hold → reveal`）和五条相机轨道。`source` 有三种：`heuristic`（无 key，纯哈希 + BPM 生成）、`llm`（调 OpenAI 兼容接口并通过结构校验）、`llm-fallback`（配置了 key 但失败，回退并在 `notes` 写原因）。

**critique**：`source` **永远是 `heuristic`**。四项分数（composition / contrast / readability / motion，25–98）由 brief 关键词与确定性哈希决定，没有任何模型推理。带图片时只校验 data URL 格式并回显 `imageReceived: true`，`notes` 明确写"像素级评测未配置，图片没有改变分数"。

这是一份基于文案的检查清单，不是看图评审。把它当"AI 点评画面"会误导——README 里用加粗写了这一点。

## 二十一、CLI：三个命令

```bash
pnpm validate <file>    # contracts + runtime 双检；mismatch 退出 1
pnpm inspect <file>     # counts / duration / labels / tracks / buffer
pnpm bake <file> --out <dir>   # bake.json + particles.bin（layout provisional）
```

`bake` 的二进制布局是 **provisional**，不是正式 buffer 契约——用词很谨慎：能跑、有测试，但不承诺跨版本兼容。加 `--physics` 会额外产出 `physics.json`。

`pnpm lint` 是 `tools/check-boundaries.mjs`，扫描 core / studio 的 import 边界（数量随分支变化，不写死）。

## 二十二、测试：381 + 103 + 87 + 38

| 命令 | 覆盖 | 外部依赖 |
| --- | --- | --- |
| `pnpm test` | 381 个包测试（physics 49 / core 86 / render-three 107 / headless 15 / splat-io 37 / studio 87） | Chrome（真实 WebGL 用例） |
| `pnpm test:server` | 103 个，含真实 Chrome + ffmpeg/ffprobe 的 MP4/WebM/GIF 出片 | Chrome + ffmpeg |
| `pnpm test:studio` | 87 个纯 `node:test` 逻辑测试（撤销/自动保存/look/格式/渲染请求） | 无 |
| `pnpm test:cli` | 38 个 validate / inspect / bake 测试 | 无 |
| `pnpm test:contract` | TypeBox + fixtures + Pydantic 契约 | pydantic（缺失时明确 SKIP） |
| `pnpm typecheck` | 9 个 `tsc --noEmit` | 无 |
| `pnpm codegen:check` | 11 个生成物逐字节比对 | 无 |

CI 分两条 lane：

- **static**：Node 26 + pnpm 12.6.0，装 `pydantic>=2,<3` 后跑 typecheck、lint、codegen:check、contract、CLI、Studio 逻辑测试、Python 工具。出现 `[contract] SKIP` 或"全部 Python 用例 skip"都让 lane 失败。
- **runtime**：解析 `google-chrome`、导出 `CHROME_BIN`、确保 ffmpeg 可用，跑 `pnpm test` 与 `pnpm test:server`。出现 `Google Chrome not found` 或任何 skipped 测试都让 lane 失败。

**"skip 即失败"**是这套 CI 最重要的规则：环境缺依赖时本地可以 skip，CI 不行——否则绿灯只是说明"什么都没跑"。

还有两个值得一提的验证手法：

- **黄金 hash**：默认后期链渲染出的整帧 hash 固定为 `1001168103`、16 draw calls。任何改 shader 的 PR 如果无意中改了这个数，测试立刻红。
- **路径等价**：同一帧下 `?render=1&scene=fir&look=filmic` 与 `?render=1&document=<jobId>&look=filmic` 的截图 SHA-256 完全相同（`3952bbe3…`），证明自定义文档传输不改变画面；`neutral` 版本同样相同（`6021e4ee…`），且与 `filmic` 不同，证明 look 确实进入画面。

## 二十三、三个示例：三种量级

| 示例 | 规模 | 回答的问题 |
| --- | --- | --- |
| `christmas` | 1 个 `scene.json`、1 个 canvas、4 emitter、15 track | 拿到 Ember 后第一个项目怎么写 |
| `cosmos`（《此刻》） | 258.267528 s、六幕、30 fps、绝对时钟 | 长篇、多幕、需要精确时间轴时怎么写 |
| `last-light` | 258.267528 s、35 tracks、五幕、接回原片音轨 | 把一部已有影片完整迁移到新引擎，每帧是否还是同一帧 |

`cosmos` 的六幕边界写在表里（`prologue` 0–21.8 s、`bigbang` 21.8–72.5 s、`firstlight` 72.5–145 s、`solar` 145–168 s、`earth` 168–233.5 s、`now` 233.5–258.267528 s），边界属于后一幕——`actAt(21800)` 是 `bigbang`。这类"边界归属"必须有明确约定，否则跨幕特效会在接缝处抖动。

`last-light` 的验收更硬：把原片的 GSAP 时间轴和五层相机公式换成 Ember 之后，258 秒里每一帧状态、每一个机位与 `Demo/src/camera.js` 的关键时间点误差为 **0**。

## 二十四、当前限制

- **未发布**：全部 `private: true`，源码入口，无 semver；仓库没有 `LICENSE`，按保留所有权利对待。
- **单机单任务**：一个渲染槽，无集群、无优先级、无重试；默认只听 `127.0.0.1`，无鉴权。
- **Splat 不是完整 3DGS**：视空间各向异性 Gaussian billboard + additive；无 SH 高阶、无逐帧深度排序、无深度正确 alpha；静态层不参与 morph。
- **没有真实遮挡**：points 与 splats 都关闭 depthTest/depthWrite，画面是发光叠加。
- **引擎无音轨**：不读音乐、不做卡点；`render --audio` 只为 MP4 在成片后混 AAC，WebM+Opus 只能走 `POST /api/render`。
- **Look 只有两档**：`neutral` / `filmic` 是宿主层固定预设，不是任意调色节点。
- **标题只有一个**：片尾一个标题，字体依赖宿主解析，无字形级布局/SDF/逐字动画。
- **确定性有边界**：同一台机器相同输入 → 相同 CPU 状态与相同绘制指令；不同 GPU/驱动/抗锯齿下像素可能不同。
- **性能只有一个观测值**：Fir 42,000 粒子 @ 1440×900 约 60 fps、18 draw calls（3 个 emitter），开发机实测，不是跨设备承诺。
- **质量分级是 opt-in**：`quality` 省略时保持旧路径（固定 DPR、无质量控制器与 GPU timer）。`auto` 按 `WEBGL_debug_renderer_info` 选档；M2 Pro 实测 GPU timer 扩展存在但拿不到可用结果，`gpuMs` 记为 `null`，不声称 GPU 时间。
- **未实现**：WebGPU compute、node graph、2D adapter（Canvas/SVG）、协作/云渲染、项目库。

路线图对"做完"的定义是四条同时满足：真实调用路径、自动化测试、文档诚实、可复现验收命令。缺一条只能叫原型。

## 二十五、复盘：确定性是设计出来的

写下来最深的体会：**"同一帧"不是运气好，而是每一层都拒绝跨帧状态**。

具体到代码：

- 随机数用种子流，并且按形状/属性分流，所以加粒子不会洗牌；
- grow 先 clamp 再乘 0.82，给 `smoothstep` 留出恰好 0.18 的窗口，保证 `grow = 1` 时所有粒子落位；
- 时间轴逐段编译、带显式 `from`、seek 静音回调，所以任意跳转都不依赖历史；
- 运动全在顶点着色器里解析，重力是线性位移而不是二次积分；
- 物理只在离线烘焙，运行时只做 floor + lerp；
- 颗粒噪声用 `hash12(uv + time)`，不读随机源；
- 契约生成物逐字节比对，跨语言结论一致；
- CI 把 skip 判为失败，黄金 hash 锁住默认路径。

任何一处放松，"拖到第 N 秒和播到第 N 秒是不是同一帧"这个问题的答案就会变成"看情况"。而一旦答案是"看情况"，离线渲染的每一帧都变得不可信。

这也是这个项目目前最想守住的东西：功能可以少，边界可以窄，但那条 `frame(t) = f(document, t)` 的等式不能破。

仓库目前是私有实验项目。如果要继续，优先级最高的是 3DGS 资产层的闭环（真实协方差投影 + 深度正确排序），其次是 WebGPU compute——它能把"粒子数上限"这个最硬的限制往后推一大截。
