# ShellGuard

ShellGuard is a visual server management tool for developers, self-hosters, and small teams. It connects to remote Linux servers over SSH and brings common operations such as asset management, web terminal access, file transfer, resource monitoring, process and service inspection, firewall and port management, Docker operations, and AI-assisted workflows into one interface. It also supports exporting shared server groups so teammates can import the same list, see the same terminal entry points, and jump directly to the target servers from a unified workflow.

ShellGuard 是一个面向开发者、自托管用户和小团队的可视化服务器管理工具。它通过 SSH 连接远程 Linux 服务器，把资产管理、Web 终端、文件传输、资源监控、进程与服务巡检、防火墙与端口管理、Docker 操作以及 AI 辅助能力整合到同一个界面中。除此之外，你还可以把共享服务器列表导出给团队成员，对方导入后会直接出现在顶部服务器选择器中，大家使用的是同一套终端入口和操作路径，可以从统一终端快速跳转到对应服务器开展运维操作，明显降低团队协作和交接成本。

## Highlights

- SSH-based remote server connection and asset management
- Export and import shared server groups for a consistent team terminal workflow
- Web terminal and file management with upload/download support
- Process, service, port, firewall, and Docker operations in one place
- Resource monitoring for CPU, memory, disk, and network usage
- AI-assisted operation experience for common server tasks

## 功能亮点

- 基于 SSH 的远程服务器连接与资产管理
- 支持共享服务器列表导出与导入，团队成员可复用同一套终端入口
- 集成 Web 终端与文件管理，支持上传、下载与目录传输
- 提供进程、服务、端口、防火墙和 Docker 的统一管理入口
- 支持 CPU、内存、磁盘与网络资源监控
- 提供 AI 辅助运维体验，降低常见操作门槛

## Shared Access / 共享协作

You can export a shared server group as JSON and send it to other ShellGuard users. After import, the shared servers appear directly in the top server selector, allowing teammates to use the same terminal entry points and jump to the target servers without recreating local configurations one by one. The shared export is designed for collaboration and does not expose the real server IP, username, or password in the exported file.

你可以把共享服务器组导出为 JSON 发给其他 ShellGuard 用户。对方导入后，这批共享服务器会直接出现在顶部服务器选择器中，不需要逐台重新录入本地配置，就能沿用同一套终端入口和操作路径，直接跳转到目标服务器处理问题。这个能力非常适合团队协作、运维交接和多端同步使用；同时，分享导出的文件不会暴露真实服务器 IP、用户名和密码，更适合在协作场景中分发。

## 📜 License
This repository contains only **ShellGuard Individual Open-Source Edition**, licensed under **GNU AGPLv3.0**.

> Important separation statement:
> Credential isolation gateway, multi-user permission management, operation audit and enterprise security modules belong to closed-source **ShellGuard Enterprise Edition**, which are NOT included in this open-source code.

Rules:
1. You are free to view, modify and run the software for personal non-public use.
2. If you deploy modified versions and provide services to third parties over a network, you must publish all modified source code under AGPLv3.
3. All derivative works must retain original copyright notices and clearly mark the source project: ShellGuard. You are not allowed to remove brand and copyright statements.

If you intend to build commercial products, SaaS services based on this project, please contact the author for independent commercial licensing.

---

## 📜 开源许可
本仓库仅开放 **ShellGuard 个人开源版**，采用 **GNU AGPLv3.0 协议**。

> 重要区分声明：
> 凭据隔离网关、多用户权限管控、操作审计等企业安全模块属于闭源【ShellGuard 企业版】，不包含在开源代码内。

协议约束：
1. 允许个人非公开场景阅读、修改、本地运行软件；
2. 如果你修改代码并通过网络向第三方提供服务，必须以AGPLv3协议公开全部修改后的源代码；
3. 所有衍生作品必须保留原始版权声明，清晰标注来源项目：ShellGuard，禁止移除品牌与版权信息。

若计划基于本项目开发商业产品、SaaS服务，欢迎联系作者洽谈独立商业授权。
