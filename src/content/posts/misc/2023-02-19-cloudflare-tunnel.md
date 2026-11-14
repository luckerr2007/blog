---
title: 用 Cloudflare Tunnel 把家里的服务带出去
published: 2023-02-19
description: 没有公网 IP，也不想在路由器上开端口，最后用 cloudflared 把内网服务接到 Cloudflare。
tags: [Cloudflare Tunnel, 家庭服务器, 折腾]
category: 折腾
comment: false
---

> 旧文存档：写于 2023 年 2 月，命令和配置以当时的 cloudflared 版本为准。

家里的宽带没有公网 IP，以前用 frp 加一台小 VPS 做中转，能用，但多一台机器就多一份维护。后来看到 Cloudflare Tunnel，试了一下，把 frp 撤了。

安装很简单，macOS 上 `brew install cloudflared`，Linux 用官方仓库。登录、创建隧道、把服务写进配置：

```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/<tunnel-id>.json

ingress:
  - hostname: nas.example.com
    service: http://127.0.0.1:8080
  - service: http_status:404
```

然后 `cloudflared tunnel route dns <tunnel-id> nas.example.com`，DNS 会自动加一条 CNAME。路由器上不需要开任何端口，外面也扫不到。

需要登录的服务我都套了 Cloudflare Access，只允许自己的邮箱。没有验证的入口一律不暴露，包括路由器的管理页。

用下来的感受：

- 速度取决于到 Cloudflare 的线路，传大文件不如局域网；
- 隧道进程挂了服务就断，systemd 里记得 `Restart=always`；
- 不要把整个内网都挂上去，按服务逐个加；
- 免费版够个人用，但别拿它跑对外生产业务。

现在这套跑了几个月，最大的好处是安静：没有公网 IP，没有端口映射，也没有凌晨扫 SSH 的日志。
