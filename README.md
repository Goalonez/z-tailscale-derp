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

### 方案 A：自动申请证书（推荐公网 80/443 端口开放的服务器）

创建 `compose.yaml`：

```yaml
services:
  derper:
    image: goalonez/z-tailscale-derp:latest
    container_name: derper
    restart: unless-stopped
    ports:
      - "80:80/tcp"
      - "443:443/tcp"
      - "3478:3478/udp"
    command:
      - --hostname=derp.example.com
      - --c=/var/lib/derper/derper.key
      - --certdir=/var/lib/derper/certs
    volumes:
      - ./data:/var/lib/derper
```

启动容器：
```bash
docker compose up -d
```

> **提示**：首次启动会自动向 Let's Encrypt 申请证书，并持久化保存在 `./data/certs` 目录中。

---

### 方案 B：使用自有证书（国内云服务器或已有泛域名证书）

如果 80 端口不可用，或者已有 SSL 证书（如 acme.sh 签发）：

```yaml
services:
  derper:
    image: goalonez/z-tailscale-derp:latest
    container_name: derper
    restart: unless-stopped
    ports:
      - "443:443/tcp"
      - "3478:3478/udp"
    command:
      - --hostname=derp.example.com
      - --c=/var/lib/derper/derper.key
      - --certmode=manual
      - --certdir=/certs
      - --http-port=-1
    volumes:
      - ./data:/var/lib/derper
      # 挂载证书文件（宿主机按实际路径填写；容器内必须为 <hostname>.crt 和 <hostname>.key）
      - ./certs/derp.example.com.crt:/certs/derp.example.com.crt:ro
      - ./certs/derp.example.com.key:/certs/derp.example.com.key:ro
```

> **注意**：
> 1. 宿主机证书文件名（冒号左侧）按实际路径填写（无论是 `.crt`、`fullchain.pem` 还是泛域名证书均可）；容器内文件名称（冒号右侧）必须严格为 `<hostname>.crt` 与 `<hostname>.key`。
> 2. 证书必须是包含中间证书的完整证书链（fullchain），私钥需与域名匹配。
> 3. 外部证书更新后，执行 `docker compose up -d --force-recreate` 重建容器以读取最新证书。

## 进阶配置：客户端防蹭网验证（Verify Clients）

默认情况下，DERP 服务器不限制客户端，任何知道该域名的人都可以使用你的服务器中继流量。

如果你只希望**自己的 Tailnet 设备**使用该节点，可以开启客户端验证（**方案 A 和方案 B 均适用**，只需在原配置基础上追加对应参数）：

1. 确保宿主机已安装并运行 `tailscaled`，且已登录到你的 Tailnet。
2. 镜像版本建议与宿主机 `tailscaled` 版本保持一致（如 `goalonez/z-tailscale-derp:1.104.6`）。
3. 在 `command` 中追加验证参数，并在 `volumes` 中挂载宿主机的 `tailscaled.sock`（以下以方案 B 为例）：

```yaml
services:
  derper:
    image: goalonez/z-tailscale-derp:latest # 建议固定为与宿主机 tailscaled 相同的版本号
    container_name: derper
    restart: unless-stopped
    ports:
      - "443:443/tcp"
      - "3478:3478/udp"
    command:
      - --hostname=derp.example.com
      - --c=/var/lib/derper/derper.key
      - --certmode=manual
      - --certdir=/certs
      - --http-port=-1
      # 启用客户端验证
      - --verify-clients
      - --socket=/var/run/tailscale/tailscaled.sock
    volumes:
      - ./data:/var/lib/derper
      - ./certs/derp.example.com.crt:/certs/derp.example.com.crt:ro
      - ./certs/derp.example.com.key:/certs/derp.example.com.key:ro
      # 挂载宿主机 Tailscale Socket
      - /var/run/tailscale:/var/run/tailscale:ro
```

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
