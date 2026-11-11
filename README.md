# z-tailscale-derp

基于 Tailscale 官方源码构建的高性能、轻量级 DERP 中继服务器 Docker 镜像。

支持 `linux/amd64` 与 `linux/arm64` 双架构，开箱即用，支持 Let's Encrypt 自动证书、自有 SSL 证书挂载以及客户端身份验证（防止被蹭网）。

## 特性

- **官方纯净**：基于 Tailscale 官方源码编译，版本紧跟上游稳定版。
- **多架构支持**：原生支持 `linux/amd64` 和 `linux/arm64`。
- **证书开箱即用**：支持 Let's Encrypt 自动申请与续期，亦可便捷挂载自有证书。
- **防蹭网鉴权**：原生支持 `--verify-clients`，仅允许自己 Tailnet 内的设备中继流量。

## 准备工作

在部署前，请确保：
1. **域名解析**：已将域名（如 `derp.example.com`）解析至服务器公网 IP。
2. **开放端口**：
   - `443/tcp`：DERP HTTPS 流量
   - `3478/udp`：STUN 探测（NAT 穿透打洞必需）
   - `80/tcp`：Let's Encrypt 证书申请与续期（使用自有证书时不需要）

## 快速部署

创建 `compose.yaml`，以下默认使用自有证书并开启客户端验证，两个服务通过共享 Socket 通信，其他用法按注释调整。Tailscale 示例适用于支持 `/dev/net/tun` 的 Linux 宿主机；已有可用的 Tailscale 时可复用，无需重复部署：

```yaml
services:
  z-tailscale-derp:
    image: goalonez/z-tailscale-derp:latest # 长期使用建议固定版本号
    container_name: z-tailscale-derp
    ports:
      - "443:443/tcp"
      - "3478:3478/udp"
      # 使用 Let's Encrypt 自动证书时取消下一行注释，并开放宿主机 80/tcp
      # - "80:80/tcp"
    volumes:
      # 持久化 DERP 配置及自动证书
      - /docker/z-tailscale-derp:/var/lib/derper
      # 自有证书：左侧替换为实际路径（可用泛域名证书），右侧文件名必须与 --hostname 匹配
      # 证书需包含完整证书链；使用自动证书时移除以下两项挂载
      - /docker/certs/derp.example.com.crt:/certs/derp.example.com.crt:ro
      - /docker/certs/derp.example.com.key:/certs/derp.example.com.key:ro
      # 客户端验证：与下方 tailscale 服务共享同一个宿主机目录（冒号左侧），DERP 侧只读挂载
      # 不开启验证时移除此挂载及下方两个验证参数，也无需部署 tailscale 服务
      - /var/run/tailscale:/var/run/tailscale:ro
    command:
      - --hostname=derp.example.com
      - --c=/var/lib/derper/derper.key
      # 自有证书；自动证书改为 --certmode=letsencrypt
      - --certmode=manual
      # 自动证书改为 --certdir=/var/lib/derper/certs，以持久化证书
      - --certdir=/certs
      # 禁用 HTTP；自动证书时移除此行，恢复默认 80 端口
      - --http-port=-1
      # 仅允许自己的 Tailnet 设备使用；移除以下两项会开放中继给其他客户端
      - --verify-clients
      - --socket=/var/run/tailscale/tailscaled.sock
    restart: unless-stopped

  # 为 DERP 提供客户端验证；已有可用的 Tailscale 时可移除此服务，并调整上方 Socket 挂载
  tailscale:
    image: tailscale/tailscale:latest # 长期使用建议固定版本号
    container_name: tailscale
    network_mode: host
    hostname: derp-server
    volumes:
      # 持久化登录状态
      - /docker/tailscale:/var/lib/tailscale
      # 与 DERP 共享同一个宿主机目录，Tailscale 在此创建 Socket，需可写
      - /var/run/tailscale:/var/run/tailscale
    environment:
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_SOCKET=/var/run/tailscale/tailscaled.sock
      - TS_USERSPACE=false
      - TS_AUTH_ONCE=true
      # 可选：通过环境变量传入 Auth Key 自动登录；不设置时按下方步骤打开登录链接
      # - TS_AUTHKEY=${TS_AUTHKEY}
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - net_admin
      - net_raw
    restart: unless-stopped
```

首次部署先启动 Tailscale，查看日志中的登录链接并登录自己的 Tailnet（已通过 Auth Key 登录可跳过手动登录）：

```bash
docker compose up -d tailscale
docker compose logs tailscale
```

完成登录后启动 DERP；复用已有 Tailscale 时可直接执行：

```bash
docker compose up -d z-tailscale-derp
```

> **提示**：自有证书更新后，执行 `docker compose up -d --force-recreate` 重建容器以读取最新证书；自动证书由 DERP 申请与续期。

## 在 Tailscale 中配置

部署完成后，需要将自建 DERP 节点配置到你的 Tailnet 中。

### Tailscale 官方控制台配置

打开 [Tailscale 控制台 ACL 规则设置](https://login.tailscale.com/admin/acls/file)，在 JSON 配置中加入 `derpMap`：

```json
{
  "derpMap": {
    "Regions": {
      "900": {
        "RegionID": 900,
        "RegionCode": "custom-derp",
        "RegionName": "My Custom DERP",
        "Nodes": [
          {
            "Name": "900a",
            "RegionID": 900,
            "HostName": "derp.example.com",
            "DERPPort": 443,
            "STUNPort": 3478
          }
        ]
      }
    }
  }
}
```

### 验证连通性

在任意已登录该 Tailnet 的终端上执行：

```bash
tailscale netcheck
```

若输出中包含自定义的 Region（如 `custom-derp: 900`）且能测得延迟，即表示中继服务器工作正常。

## 本地离线构建（可选）

如需自行构建离线 Docker tar 包（需要本地安装 Docker 与 Buildx）：

```bash
# 构建官方最新稳定版 (linux/amd64)
bash scripts/build.sh

# 指定版本与架构 (支持 linux/amd64, linux/arm64)
bash scripts/build.sh --tailscale-version 1.104.6 --platform linux/arm64
```

产物将输出在 `dist/` 目录，在目标机器上通过 `docker load -i <产物路径>` 即可导入使用。

## 许可证

- 打包脚本与配置遵循 [MIT License](LICENSE)。
- 镜像内包含的 Tailscale 官方代码遵循其 [BSD-3-Clause License](https://github.com/tailscale/tailscale/blob/main/LICENSE)。
