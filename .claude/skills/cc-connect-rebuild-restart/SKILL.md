---
name: cc-connect-rebuild-restart
description: Rebuild cc-connect with embedded web UI and restart the detached service. Use when the user asks to recompile, rebuild, redeploy, or restart cc-connect after code changes.
---

# cc-connect 编译并重启

在 **cc-connect 仓库根目录** 执行（以下命令均假定当前目录为仓库根）。

## 一键命令（推荐）

```bash
scripts/cc-rebuild-restart.sh
```

等价于：`make build` → `scripts/ccctl.sh restart` → 检查 Web 是否 200。

跳过自检：`scripts/cc-rebuild-restart.sh --no-verify`

## 分步命令

```bash
make build                  # 必须带 web；不要用 make build-noweb
scripts/ccctl.sh restart    # detached 重启，终端关掉也不影响
```

仅重启、不重新编译：

```bash
scripts/ccctl.sh restart
```

## 验证

```bash
scripts/ccctl.sh status
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:9820/   # 期望 200
go version -m ./cc-connect | grep tags                             # 不应含 no_web
scripts/ccctl.sh logs 20
```

| 现象 | 含义 |
|------|------|
| `web: 200` | Web 管理界面正常 |
| `web: 404` | 二进制用了 `no_web`，重新 `make build` 后再重启 |
| `cc-connect not running` 后 `started` | 旧进程已停，新实例已拉起 |

## 注意

- **始终用 `make build`**，不要用 `make build-noweb` 或 `go build -tags no_web`。
- 重启用 **`scripts/ccctl.sh restart`**，不要在 cc-connect 进程内 kill 自身（cron/agent 会话会一起挂掉）。
- Web 地址：`http://<host>:9820/`（`host` 为服务器 IP 或域名，默认端口 9820）。

更完整的开发说明见 [cc-connect-dev](../cc-connect-dev/SKILL.md)。
