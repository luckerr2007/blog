---
title: 用 ffmpeg 批量处理一批录音
published: 2024-01-21
description: 把几十段课程录音统一转成 m4a，做响度归一化，再按静音切段。
tags: [FFmpeg, 音频, 工具]
category: 工具
comment: false
---

> 旧文存档：写于 2024 年 1 月，命令在不同版本的 ffmpeg 上可能略有差异。

年底整理资料，发现手机里存了几十段课程录音，格式有 m4a、wav 和 mp3，音量忽大忽小，还有不少开头结尾的空白。手动处理不现实，写了个脚本用 ffmpeg 批量过一遍。

第一步是统一容器和码率。课程录音不需要无损，统一成 128kbps 的 m4a：

```bash
for f in *.wav *.mp3 *.m4a; do
  ffmpeg -i "$f" -vn -c:a aac -b:a 128k "out/${f%.*}.m4a"
done
```

`-vn` 是去掉封面图，不然有些文件会带一张很大的 jpeg。

第二步做响度归一化。用 `loudnorm` 把整体响度拉到 -16 LUFS：

```bash
ffmpeg -i input.m4a -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:a aac -b:a 128k output.m4a
```

第三步按静音切段。先用 `silencedetect` 看阈值，再决定要不要切：

```bash
ffmpeg -i input.m4a -af silencedetect=noise=-35dB:d=1.5 -f null -
```

试了几段之后发现，课程中间翻页和咳嗽的停顿也会被识别成静音，切得太碎反而不好用。最后只保留开头和结尾的裁剪，中间不切。

几个教训：先拿一个文件试参数，确认没问题再批量跑；保留原始文件，输出单独放目录；ffmpeg 的日志很多，重定向到文件里再查，别在终端里刷屏。

处理完几十段录音，最大的感受是：命令行的价值不在于快，而在于下次还能原样跑一遍。
