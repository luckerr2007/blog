---
title: MusicParser：把 LEMOM 的转写核心拆成本机 HTTP 服务
published: 2026-11-14
updated: 2026-11-14
description: MusicParser 复用 LEMOM 的分离与转写核心，在 127.0.0.1:8777 提供一个 FastAPI 服务，包含任务队列、能力探测、单文件控制台和产物下载。本文记录它的接口契约、并发模型、进程管理与已知限制。
tags: [MusicParser, FastAPI, 音频解析, 本地服务]
category: 音频工具
series: 音频工具三件套
seriesOrder: 3
comment: false
---

LEMOM 面向普通使用者：Vue 界面、PyInstaller 打包、任务卡、模型下载和设置页一应俱全。

但有些场景只需要一个接口：把音频传进去，取回分轨和 MIDI；调用方可能是脚本，也可能是另一个程序。为此启动完整产品太重，而模型和依赖已经装在本机。

MusicParser 就是这一层。它复用 LEMOM 的核心代码，单独启动一个 FastAPI 服务，默认监听 `127.0.0.1:8777`，附带一个单文件 HTML 控制台。没有 Node 构建，也没有音乐库、网易云搜索这些上层功能。

## 与另外两个项目的关系

三个项目的分工是串联的：

- MVSEP 工作区负责取歌和云端分离，解决“先有干净音源”；
- LEMOM 负责完整产品体验，解决“把歌变成可编辑 MIDI”；
- MusicParser 把同一套解析核心提出来，解决“别的程序如何调用”。

它不复制模型权重，也不重新实现转写。MuScriptor、Beat This、TransKun、ADTOF、ByteDance Pedal、云端分离适配器和 MIDI 后处理全部来自 LEMOM 的 `src/core`。MusicParser 自己提供三样东西：HTTP 契约、任务队列、控制台。

## 启动与进程管理

`./start.command` 先读取 `config.env`，然后按顺序查找 Python：

1. `MUSIC_PARSER_PYTHON`；
2. 项目自己的 `.venv`；
3. `MUSIC_PARSER_SHARED_VENV` 指向的环境，默认 `../Music/.venv`；
4. 系统的 `python3`。

候选环境必须能 `import fastapi, uvicorn, torch`，否则跳过。默认复用 LEMOM 的虚拟环境，省掉一份约 1.3GB 的依赖。

服务启动后，脚本轮询 `/api/v1/health`，最多等待 80 秒（160 次 × 0.5 秒）。健康检查不只看端口，还检查响应中的 `"app":"MusicParser"`，避免把同端口的其他服务误认成自己。

后台模式用 `nohup` 启动进程，PID 和启动时间写入 `~/Library/Application Support/MusicParser/run/server.json`。停止脚本不会直接 `kill` 这个 PID：它先确认进程命令包含 `src.main`，再检查端口占用者是否属于当前目录，确认后才发 SIGTERM，10 秒不退才 SIGKILL。这样不会误杀同端口的其他 Python 服务。

配置项都在 `config.env`：

- `MUSIC_PARSER_HOST` / `MUSIC_PARSER_PORT`；
- 共享虚拟环境路径；
- 支持、日志、输出和模型目录；
- 单文件上传上限，默认 4GB；
- 最大排队任务数，默认 8。

默认目录分别是 `~/Library/Application Support/MusicParser`、`~/Library/Logs/MusicParser`、`~/Music/MusicParser`；模型目录只读复用 `~/Library/Application Support/MusicToMidi/Models`。

## API 契约

所有接口挂在 `/api/v1`，分为四组。

系统与设置：

```text
GET  /health
GET  /ready
GET  /capabilities?refresh=1
GET  /defaults
GET  /settings
PUT  /settings
POST /settings/mvsep/test
POST /settings/telknet/test
POST /settings/llm/test
GET  /mvsep/models
```

任务：

```text
GET    /jobs
POST   /jobs                 multipart: audio + options
POST   /jobs/bypass          multipart: files + mapping + options
GET    /jobs/{id}
POST   /jobs/{id}/cancel
POST   /jobs/{id}/retry
DELETE /jobs/{id}
GET    /jobs/{id}/files/{artifact_id}
GET    /jobs/{id}/midi/{artifact_id}
```

`/jobs` 的 `options` 是 JSON 字符串，最终解析成 Pydantic 的 `JobOptions`。这个模型设置了 `extra="forbid"`，多传一个字段就返回 422，不会静默忽略。常用字段包括 mode、separation_mode、provider、routing_strategy、transcription_backend、MuScriptor 档位、tempo 模式、鼓后端、钢琴后处理和 LLM 模式。

BPM 限制在 20–400；手动模式必须提供 `custom_bpm`；分离模型必须是已知的 render id。这些校验在提交前完成，避免任务运行到一半才报参数错误。

上传格式白名单为 WAV、MP3、FLAC、OGG、M4A、AAC、WMA、AIFF。文件按 1MB 块写入，边写边累计，超过上限立即返回 413 并删除半成品；空文件返回 400。

多轨直通额外校验 mapping：文件名不能重复，角色只能是 vocals/drums/bass/guitar/piano/other/mix，角色必须唯一，至少有一个可转写乐器。人声和 mix 只保留音频；只有人声而没有乐器会直接拒绝。

队列满返回 429，磁盘不足返回 507。默认 `min_free_bytes=0`，即不主动检查剩余空间；需要这条保护时，在创建 app 时传入阈值。

## 队列与持久化

任务目录结构如下：

```text
<job_id>/
  input/source.wav
  output/
  job.json
```

`job.json` 是 schema 2，记录状态、请求、进度、结果、产物和源文件。写入采用临时文件 + `replace`，避免进程崩溃留下半个 JSON。

任务状态为 queued / running / cancelling / succeeded / failed / cancelled。服务重启时，所有 running、cancelling、queued 的记录会被标记为 failed，错误写成“服务重启，任务中断”；succeeded 的历史和产物继续可用。

队列有两个 worker，但本地推理并不并行。`acquire_accelerator_lock` 用 `flock` 做进程级和线程级互斥，LEMOM 桌面端和 MusicParser 同时运行时也只有一个能拿到 Metal。等待锁期间可以取消，进程退出时操作系统释放锁，不依赖清理代码。

两个 worker 的意义在于把“等云端分离”“下载”和“本地转写”交错起来；真正占用 GPU 的部分仍然串行。任务进度中，分离和下载阶段不显示 ETA，只显示已等待秒数，因为云端排队无法由本地估算。

取消分两种：queued 直接变 cancelled；running 先变 cancelling，再调用处理器的 `cancel()`，等推理或下载退出后落终态。关闭服务时会取消所有活跃任务，并等待 worker 最多 12 秒，避免服务退出后进程仍在运行。

重试会复制原文件到新任务目录，允许覆盖部分选项；bypass 任务不支持原地重试，因为它包含多条分轨，必须重新上传并核对 mapping。

删除只允许终态任务，删除时整个任务目录一起移除。产物下载前会校验解析后的路径仍在任务目录内，防止 `artifact.path` 被构造出目录穿越。

## 能力探测

`/capabilities` 是控制台渲染表单的依据，也是外部调用方判断能否提交任务的依据。它返回：

- 三种模式及说明；
- MuScriptor 三档是否就绪、缺什么、加载策略和内存预估；
- YourMT3+、TransKun、ADTOF 的可用性与原因；
- ByteDance Pedal 的 checkpoint 路径；
- MVSEP/TelkNet 是否配置、区域、模型列表；
- 当前机器的芯片、Metal 版本、PyTorch、设备和内存；
- LLM provider 和配置状态；
- 上传上限、队列上限、支持的扩展名。

模型可用性用 `lru_cache` 缓存，修改设置或手动 `?refresh=1` 时清空。控制台会直接禁用不可用的后端，而不是等提交后返回 409。

`/ready` 更严格：MuScriptor、YourMT3、TransKun 全部不可用时返回 503 并带上原因；只要有一个可用就算 ready。`/health` 只证明服务存活，不代表模型齐全。

## 模型安装与共享

`install.command` 只支持 macOS，要求 Python 3.12+。它优先使用 `uv pip install`，没有 uv 就退回 pip。MuScriptor 不在 PyPI，安装时固定 commit `8a1ef88672cc23c26619adaff37ec48d82c0b906`，并按 GitHub 主站、ghfast、gh-proxy 依次尝试。

模型可以用 `scripts/prepare_models.py` 按 profile 下载：

- `minimal` / `recommended`：Beat This final0（约 0.08GB）+ MuScriptor Large（约 5.47GB）；
- `full`：再加 YourMT3+ 默认权重（约 0.76GB）；
- `yourmt3`：只下载 Beat This 和 YourMT3。

每个 downloader 都校验大小和 SHA-256，失败会留下日志，不会把半个 checkpoint 当成成功。

这些权重默认落在 LEMOM 的模型目录，MusicParser 只读使用。两个项目不必各存一份几 GB 的模型，也不会因为版本不同各下一套。

## 控制台

`console/index.html` 是一个文件，CSS 和 JS 都在里面，不需要 Node 构建。打开根路径就是控制台，`/docs` 是 FastAPI 自带的 OpenAPI 页面。

界面分三块：

- 上传音频或多轨直通；
- 任务列表，带进度条、阶段、产物下载和 MIDI 查看；
- 设置弹窗，配置 MVSEP、TelkNet、LLM 和默认转写后端。

任务卡会显示失败原因、跳过原因、产物类型和大小；MIDI 产物可以打开钢琴卷帘预览。轮询使用普通 `fetch`，没有 WebSocket，适合本机低频查看。

它没有做网易云搜索。虽然设置模型里有相关字段，当前路由没有暴露音乐库接口，定位仍然是“本地文件 → 解析 → 产物”。

## 已知限制

- 仓库没有 `tests/`。核心代码来自 LEMOM，但 MusicParser 自己的 API、队列和启动脚本没有同等规模的测试，改动后主要靠手工冒烟。
- 核心代码是复制而不是共享包。LEMOM 修了 bug，MusicParser 不会自动获得，需要同步 `src/core`、`src/utils` 和 `src/platform_macos`。
- API 版本是 1.0，LEMOM 是 2.4.3，两边契约不同步；调用方不能假设接口一致。
- 没有鉴权，只靠绑定 `127.0.0.1`。不要改成 `0.0.0.0` 后暴露到局域网。
- 默认不检查磁盘剩余空间，长时间跑大批任务需要自行清理任务目录。
- 模型目录与 LEMOM 共用，版本不匹配时会出现“模型未就绪”，先跑 `--doctor` 或 `prepare_models.py --dry-run`。

如果只是想在脚本里批量跑转写，这个服务比启动完整产品轻得多；如果要给普通用户使用，LEMOM 的界面和错误提示更完整。

同系列：[MVSEP Studio](/posts/audio/mvsep-studio-local-pipeline/) 负责取歌和分离，[LEMOM](/posts/audio/lemom-audio-to-midi/) 是完整的产品链路。
