---
title: Ember：把一支粒子短片写成一份 JSON
published: 2026-11-26
description: Ember 是一个确定性的 WebGL2 粒子动画引擎：一份 SceneDocument JSON 描述发射器、形状、相机与时间轴，Studio 负责实时预览，headless Chrome 加 ffmpeg 负责离线出片。本文介绍它的链路、包结构、确定性设计与当前边界。
tags: [WebGL, 粒子动画, Three.js, TypeScript, 开源项目]
category: 折腾
---

最近写了一个新项目：Ember，一个确定性的 WebGL2 粒子动画引擎。

一句话定位：**把一支粒子短片写成一份 JSON 文档，再把它实时播出来，或者离屏渲染成 MP4 / WebM / GIF。**

当前版本 `0.1.0`，源码级 MVP 收口：功能闭环已经打通，但还没有发布 npm 包，也没有跨设备性能承诺。下面按"链路 → 设计 → 包结构 → 工具链 → 边界"的顺序介绍它。

## 一、整条链路长什么样

```
SceneDocument（JSON）
  → 形状采样（6 种，种子确定）
  → SoA 粒子缓冲（守恒 + morph）
  → anime.js 时间轴（精确 seek）
  → WebGL2 点精灵 / 2DGS 风格 splat
  → Bloom + Grade + ACES/sRGB 后期
  → Studio 编辑（预设、参数覆盖、时间轴、渲染面板）
  → headless Chrome 逐帧截图
  → ffmpeg 编码 MP4 / WebM / GIF
  → SSE 进度 + Range 下载
```

核心是一个 `SceneDocument`（纯 JSON）：发射器、形状、morph 目标、相机、后期参数，外加 23 个已知参数和任意命名状态通道的时间轴。`@ember/core` 的 `parseSceneDocument` 先校验类型、必填字段和数值范围，再交给引擎。引擎把这份文档编译成两样东西：

1. **一条可精确 seek 的时间轴**：每个关键帧段都被编译成独立的 anime.js v4 tween，`seek(ms)` 直接落到任意毫秒，不依赖播放过的时长。同一毫秒的双关键帧编译为零时长 setter（硬切），正反向 seek 一致。
2. **一个合并的 SoA 粒子缓冲**：所有发射器写进同一组 `Float32Array`，每个发射器只保留 `[start, end)` 区间。粒子永不删除，morph 没有目标时就把 base 位置当作目标——所以换形状、切 morph 时粒子数量守恒。

渲染时 CPU 每帧只更新 uniform，粒子的速度、重力、风、旋涡、生长、morph 全部在顶点着色器里解析计算。这意味着**拖到 9.6 秒和播放到 9.6 秒是同一帧**，离线渲染可以安心逐帧 seek。这是整个项目"确定性"承诺的落点。

## 二、三个贯穿始终的设计约束

- **确定性**：所有随机数来自 `mulberry32` 种子流，没有 `Math.random`；同样的文档字节级复现同样的点云。
- **守恒**：一颗粒子从生到死只有一条轨迹，morph 是"变成另一个自己"，不是"销毁再生成"。
- **边界清晰**：`core` 不碰 DOM 和 three.js；`server` 不 import 引擎代码，前后端只通过一个 URL 契约和 HTTP API 通信。

边界是用 lint 强制执行的，不是靠约定：`packages/core` 禁止 import `three` / `pixi.js` / `fs` / `http` / DOM；`packages/headless` 只允许 `import type` 消费 `@ember/core`，运行时依赖为零；`packages/splat-io` 只解析调用方传入的 buffer。`pnpm lint` 跑的是 `tools/check-boundaries.mjs`，违规直接失败。

物理模拟也遵循同一个思路：任何"从 0 积分到 t"的模拟都不进运行时 seek。`@ember/physics` 提供解析场（gravityPoint / vortex / curlNoise / drag）加离线固定步长 bake，运行时只允许 `Scene.seek` 用 floor+lerp 刷新 `physicsOffsets`，适配层每帧只写 uniform。CLI 的 `bake --physics` 会产出 `physics.json`，与 provisional 二进制一起作为烘焙产物。

## 三、包结构：单向依赖

依赖方向是单向的，`packages/*` 不依赖 `apps/*`：

| 包 | 职责 | 明确不做 |
| --- | --- | --- |
| `@ember/core` | 文档类型与 JSON 校验/序列化、23 键状态 + 任意通道、6 种形状采样、时间轴编译、SoA 缓冲 | DOM、WebGL、three.js、网络 |
| `@ember/render-three` | 相机、点精灵、splat、后期、DPR/resize、播放时钟 | 业务 UI、任务队列、文件 IO |
| `@ember/studio` | 时间轴、参数面板、4 个预设、JSON 保存/加载、渲染/AI 面板、渲染模式页面 | 编码视频、启动 Chrome |
| `@ember/server` | 渲染队列、CDP 逐帧截图、ffmpeg 编码、SSE、artifact、AI 代理 | 引用引擎代码；只认 `?render=1` 契约与 HTTP |
| `@ember/headless` | 无 WebGL/DOM 的确定性帧采样：`createHeadlessAdapter` 提供 seek/frame/sampleFrames，复刻 points 解析运动（含逐粒子 origin/birth）与 physics 采样 | 渲染、网络、时钟 |
| `@ember/splat-io` | 零依赖 3DGS 资产导入：binary little-endian `.ply` 与 antimatter15 `.splat` 解析成 `SplatAsset`，再投影成二维广告牌数据 | 修改 schema、反向依赖 core |
| `@ember/physics` | 解析场 + 离线 bake + 运行时采样 | 渲染库、IO、环境变量 |
| `@ember/contracts` | TypeBox v1/v2 schema、codegen（两版 JSON Schema / TS / Pydantic）、fixtures、TS/Python 契约测试、v1→v2 迁移 | — |

## 四、Studio：30 秒上手

```bash
cd ember-engine
pnpm install --frozen-lockfile
pnpm dev
```

`pnpm dev` 用 `concurrently` 同时拉起两个进程：Studio（Vite，`http://127.0.0.1:5173/`）和 Server（Fastify，`http://127.0.0.1:8787/`）。端口被占用会直接报错而不是静默换端口。

打开默认是 `Fir`：42,000 颗粒子，18 秒，5 个叙事标签（Intro / Grow / Bloom / Morph / Collapse）。空格暂停/播放，`R` 重播，`←`/`→` 前后 1 秒；左侧参数面板拖任意 slider 会写入一个 override 覆盖时间轴值。四个预设共用同一套 23 键状态：

| 场景 | 粒子 | 一句话 |
| --- | --- | --- |
| `fir` | 42,000 | 种子光长成一棵冷杉，最后折成螺旋星系 |
| `embers` | 26,000 | 余烬绕着一颗熔化的心升起，收成金色花环 |
| `galaxy` | 50,000 | 四条旋臂从一点点燃，塌回冻结的核 |
| `splats` | 2,000 + 14,000 splat | 各向异性 Gaussian splat 云与星点互相缠绕 |

`Document` 面板可以把当前标准化文档存成 `.json`，也支持文件选择或拖拽载入；坏文件会显示字段路径，且不会改变当前场景。

## 五、离线渲染：一个页面契约

渲染后端只依赖一个页面契约，任何实现它的页面都能被渲染：

```
http://<studio>/?render=1&scene=<fir|embers|galaxy|splats>&w=<width>&h=<height>
window.__emberReady === true            // 第一帧已经排好
window.__emberRender.seek(ms)           // 同步 seek
```

排队一条 18 秒、30 fps 的 `fir`：

```bash
curl -s -X POST http://127.0.0.1:8787/api/render \
  -H 'content-type: application/json' \
  -d '{"scene":"fir","fps":30,"duration":18,"width":1280,"height":720,"quality":92}'
```

返回 `202` 和 job 对象，之后可以用 SSE 看实时事件，完成后用支持 Range 的接口下载成片。队列一次只跑一个任务；服务端重启时未完成的 job 会被标记为 `error`，不会自动续跑。

输出格式有三档：H.264 MP4（可带 AAC 音轨）、VP9 WebM（可带 Opus）、256 色 GIF（≤15 s / ≤30 fps / ≤1.2 MP）。WebM/GIF 是从 H.264 中间片转码的，存在一次代际损失——这是格式上限，不是渲染丢帧。分享画幅预设有 `16:9`、`9:16`、`1:1`、`4:5` 和自定义宽高，显式宽高必须与声明的预设比例一致。

AI 方面有两个接口，但能力不同：camera-plan 无 key 时是纯 heuristic，有 `AI_API_KEY` 时调 OpenAI 兼容接口，失败回退并标记 `llm-fallback`；critique 则始终是 heuristic——按 brief 关键词打分的检查清单，明确不分析像素。

## 六、验证：诚实的数量

`pnpm verify` 按顺序跑 typecheck → lint → codegen:check → contract → CLI → test → server，一条命令覆盖全部。当前数量级：

- `pnpm test`：381 个包测试（physics 49 / core 86 / render-three 107 / headless 15 / splat-io 37 / studio 87），render-three 含 headless Chrome 真实 WebGL 与电影相机；
- `pnpm test:server`：103 个，含真实 Chrome + ffmpeg/ffprobe 的 MP4/WebM/GIF 出片；
- `pnpm test:contract`：TypeBox + fixtures + Pydantic 契约，TS 与 Python 结论一致；
- `pnpm test:cli`：38 个 validate / inspect / bake 测试。

CI 分 static 与 runtime 两条 lane，runtime 要求 Chrome 与 ffmpeg 真实执行，**任何 skipped 测试都视为失败**。缺少 Chrome 时 WebGL 用例会明确 skip，CI 会把这种 skip 判失败——这是故意的：静默跳过等于没测。

另外有一个容易被忽略的实测结论：预设路径与文档路径在同一帧的截图 SHA-256 完全相同（`?render=1&scene=fir` vs `?render=1&document=<jobId>`），证明自定义文档传输不改变画面；`filmic` 与 `neutral` 同一帧 hash 不同，证明 look 确实进入画面。

## 七、例子：从 christmas 到 last-light

`examples/` 里有三个不同量级的例子：

- **christmas**：一支 18 秒圣诞短片的最小实现——一个 `scene.json`（4 个 emitter、15 条 track、5 个 label、片尾标题）、一个 `<canvas>`，以及 `core` + `render-three` 的公共 API。没有 React，没有 UI 库。回答的问题是：拿到 Ember 之后，第一个项目怎么写。
- **cosmos**（《此刻》）：258 秒、六幕、从宇宙诞生到现在的粒子微电影，绝对时钟驱动，引擎源码通过 Vite alias 直接引用，不复制不改引擎包。
- **last-light**：把一部原片的时间轴、电影相机与五幕画面完整跑在 Ember v2 上，258.267528 秒，同一份 tracks、同一个 `EmberRenderer`、同一个 WebGL context，还把原片音轨接了回去。

## 八、当前限制（&&&&&&&&）

- **未发布**：所有包 `private: true`，没有 npm 发布、没有 semver 承诺，只能从源码 workspace 使用；仓库没有 `LICENSE`，按保留所有权利对待。
- **单机单任务**：一次只跑一个渲染 job，无集群、无鉴权，默认只监听 `127.0.0.1`。
- **Splat 不是完整 3DGS**：渲染层是视空间各向异性 Gaussian billboard + additive，没有球谐高阶、逐帧深度排序或深度正确 alpha。
- **没有真实遮挡**：points 与 splats 都关掉 depthTest/depthWrite，画面是发光叠加。
- **引擎无音轨**：不读音乐、不做卡点；音轨只在成片后混入。
- **Look 只有两档**：`neutral` / `filmic` 是宿主层固定预设，不是任意调色节点。
- **确定性有边界**：同一台机器相同输入 → 相同结果；不同 GPU/驱动/抗锯齿下的像素可能不同。
- **性能只有一个观测值**：Fir 42,000 粒子 @ 1440×900 约 60 fps、18 draw calls，开发机实测，不是跨设备承诺。

路线图上排着 3DGS 资产层、WebGPU compute、node graph、2D adapter、协作/云渲染，但每项都只有"做完的标准"（真实调用路径 + 自动化测试 + 文档诚实 + 可复现验收命令），没有排期。

---

写这个项目的过程里，最大的体会是：**确定性不是顺带得到的，是设计出来的**。seeded 随机、守恒缓冲、解析式运动、floor+lerp 采样、逐字节 codegen 校验——每一处都在回答同一个问题："拖到第 N 秒，和播到第 N 秒，是不是同一帧？"只要有一个环节答不上来，离线渲染就不可信。

仓库目前是私有的实验项目；如果哪天补上 LICENSE 并发布，第一件事会是把那四个"未实现"里最痛的 3DGS 资产层先闭环。后续有进展再写。
