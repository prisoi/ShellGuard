# ShellGuard

ShellGuard is a visual server management tool for developers, self-hosters, and small teams. It connects to remote Linux servers over SSH and brings common operations such as asset management, streaming web terminal access, file transfer, resource monitoring, process and service inspection, firewall and port management, Docker operations, and AI-assisted workflows into one interface. The latest version also improves shared access with access-token verification, direct shared terminal workflows, and local security audit logs for remote access activities.

ShellGuard 是一个面向开发者、自托管用户和小团队的可视化服务器管理工具。它通过 SSH 连接远程 Linux 服务器，把资产管理、流式 Web 终端、文件传输、资源监控、进程与服务巡检、防火墙与端口管理、Docker 操作以及 AI 辅助能力整合到同一个界面中。当前版本还重点增强了共享体验和安全能力：你可以把共享服务器列表导出给团队成员，对方通过 access-token 校验导入后，会直接出现在顶部服务器选择器中，大家使用的是同一套终端入口和操作路径，可以从统一终端快速跳转到对应服务器开展运维操作；同时，共享连接、终端操作、文件访问以及相关远程行为都会写入本地审计记录，方便追溯和导出。

## Highlights

- SSH-based remote server connection and asset management
- Real-time streaming SSH terminal with interactive input, resize, and session continuity
- Export and import shared server groups with access-token verification
- Shared terminal and file operations with direct server jump from one unified selector
- Process, service, port, firewall, and Docker operations in one place
- Resource monitoring for CPU, memory, disk, and network usage
- Local security audit logs for shared access, terminal actions, and remote operations
- AI-assisted operation experience for common server tasks

## 功能亮点

- 基于 SSH 的远程服务器连接与资产管理
- 支持真正的流式 SSH 终端，具备实时输出、交互输入和窗口尺寸同步能力
- 支持共享服务器列表导出与导入，并通过 access-token 做导入校验
- 团队成员可复用同一套终端入口，从统一服务器选择器直接跳转目标服务器
- 提供进程、服务、端口、防火墙和 Docker 的统一管理入口
- 支持 CPU、内存、磁盘与网络资源监控
- 提供本地安全审计，记录共享连接、终端操作和远程访问行为
- 提供 AI 辅助运维体验，降低常见操作门槛

## Streaming SSH / 流式 SSH

ShellGuard now provides a true streaming SSH experience instead of a static command panel. Interactive terminal sessions are opened as PTY shells, stream stdout and stderr in real time, support input passthrough, terminal resize, and session lifecycle tracking, and fit naturally into the Web terminal workflow.

ShellGuard 现在提供的不是简单的命令执行面板，而是真正的流式 SSH 终端体验。终端会以交互式 PTY shell 方式建立连接，实时回传标准输出与错误输出，支持键盘输入透传、终端窗口尺寸同步，以及会话状态跟踪，更适合日常运维、排障和持续操作。

## Shared Access / 共享协作

You can export a shared server group as JSON and send it to other ShellGuard users. The receiver imports it with an access-token, and the shared servers then appear directly in the top server selector. This lets teammates reuse the same terminal entry points, shared terminal sessions, and file workflows without recreating local configurations one by one. The shared export is designed for collaboration and does not expose the real server IP, username, or password in the exported file.

你可以把共享服务器组导出为 JSON 发给其他 ShellGuard 用户。对方在导入时需要输入共享方提供的 access-token，校验通过后，这批共享服务器会直接出现在顶部服务器选择器中，不需要逐台重新录入本地配置，就能沿用同一套终端入口、共享终端能力和文件操作路径，直接跳转到目标服务器处理问题。这个能力非常适合团队协作、运维交接和多端同步使用；同时，分享导出的文件不会暴露真实服务器 IP、用户名和密码，更适合在协作场景中分发。

## Security Audit / 安全审计

ShellGuard includes built-in local audit logging for remote access workflows. Shared connection starts, token verification, terminal open/write/interrupt/close actions, read-only access, file upload and download, and related remote operations can be recorded locally and exported as CSV for review. This makes collaboration more traceable without forcing users into a heavy external audit system.

ShellGuard 内置了面向远程访问场景的本地安全审计能力。共享连接开始、token 校验、终端打开/输入/中断/关闭、只读访问、文件上传下载以及相关远程操作都可以写入本地审计日志，并支持导出为 CSV 进行复盘和留档。它让团队协作具备可追溯性，同时又不需要额外搭建笨重的外部审计系统。

## 📜 License
This repository contains only **ShellGuard Individual Open-Source Edition**, licensed under **GNU AGPLv3.0**.

> Important separation statement:
> Credential isolation gateway, multi-user permission management, approval workflows and enterprise governance modules belong to closed-source **ShellGuard Enterprise Edition**, which are NOT included in this open-source code.

Rules:
1. You are free to view, modify and run the software for personal non-public use.
2. If you deploy modified versions and provide services to third parties over a network, you must publish all modified source code under AGPLv3.
3. All derivative works must retain original copyright notices and clearly mark the source project: ShellGuard. You are not allowed to remove brand and copyright statements.

If you intend to build commercial products, SaaS services based on this project, please contact the author for independent commercial licensing.

---

## 📜 开源许可
本仓库仅开放 **ShellGuard 个人开源版**，采用 **GNU AGPLv3.0 协议**。

> 重要区分声明：
> 凭据隔离网关、多用户权限管控、审批流等企业级治理模块属于闭源【ShellGuard 企业版】，不包含在开源代码内。

协议约束：
1. 允许个人非公开场景阅读、修改、本地运行软件；
2. 如果你修改代码并通过网络向第三方提供服务，必须以AGPLv3协议公开全部修改后的源代码；
3. 所有衍生作品必须保留原始版权声明，清晰标注来源项目：ShellGuard，禁止移除品牌与版权信息。

若计划基于本项目开发商业产品、SaaS服务，欢迎联系作者洽谈独立商业授权。
