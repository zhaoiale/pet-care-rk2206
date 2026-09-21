# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

智宠管家 App — HarmonyOS ArkTS 应用（DevEco Studio），与 RK2206 硬件通过 MQTT 通信。

## 关键路径

- 源码：`entry/src/main/ets/`
- 构建工具：DevEco Studio（Windows GUI）
- 包名：`com.zz.petcare`
- 调试：真机或模拟器通过 DevEco Studio 运行

## 架构

```
pages/          — UI 页面（ArkTS）
services/       — MQTT 客户端 + 通知服务
database/       — SQLite 数据库
model/          — 数据模型
utils/          — 工具类
```

### 核心数据流

```
MQTT(petcare/device/data) → SimpleMqttClient → MqttService.parseAndStore()
  → SQLite(sensor_records) + NotificationService 焦虑检查
  → 各页面从 SQLite 读取展示
```

用户操作（安抚/刷新）→ MqttService 发布到 `petcare/device/command` → 硬件 MQTT 订阅接收。

### 核心文件

| 文件 | 职责 |
|------|------|
| `services/SimpleMqttClient.ets` | MQTT-over-TCP 客户端，连接 HiveMQ broker.hivemq.com:1883，50s 心跳 |
| `services/MqttService.ets` | 消息解析 + SQLite 入库 + 命令下发 |
| `services/NotificationService.ets` | 焦虑 > 70 系统通知，上升沿触发，5 分钟去重 |
| `database/DatabaseService.ets` | SQLite 数据库：sensor_records / pets / users / feeding_plans / feeding_records |
| `pages/Index.ets` | Tab 导航根页面 |
| `pages/HomePage.ets` | 首页：焦虑指数、温湿度、设备状态 |
| `pages/ComfortPage.ets` | 安抚页：三个安抚按钮（呼吸灯/主人语音/白噪音） |
| `pages/FeedingPage.ets` | 投喂页（框架已搭建，待完善） |
| `pages/HistoryPage.ets` | 历史数据页 |
| `pages/ProfilePage.ets` | 宠物档案页（框架已搭建，待完善） |

### MQTT 协议

- Broker: `broker.hivemq.com:1883`
- ClientID: `petcare_app_<timestamp>`
- 订阅: `petcare/device/data`（接收硬件上报）
- 发布: `petcare/device/command`（下发指令）
- 指令格式: `{"cmd":"comfort","type":1|2|3}` / `{"cmd":"refresh"}`

### 数据库

SQLite 数据库 `petcare.db`，5 张表：
- `sensor_records` — 传感器历史（最多保留 500 条）
- `pets` — 宠物档案
- `users` — 用户
- `feeding_plans` / `feeding_records` — 投喂计划与记录

<!-- superpowers-zh:begin (do not edit between these markers) -->
# Superpowers-ZH 中文增强版

本项目已安装 superpowers-zh 技能框架（20 个 skills）。

## 核心规则

1. **收到任务时，先检查是否有匹配的 skill** — 哪怕只有 1% 的可能性也要检查
2. **设计先于编码** — 收到功能需求时，先用 brainstorming skill 做需求分析
3. **测试先于实现** — 写代码前先写测试（TDD）
4. **验证先于完成** — 声称完成前必须运行验证命令

## 可用 Skills

Skills 位于 `.claude/skills/` 目录，每个 skill 有独立的 `SKILL.md` 文件。

- **brainstorming**: 在任何创造性工作之前必须使用此技能——创建功能、构建组件、添加功能或修改行为。在实现之前先探索用户意图、需求和设计。
- **chinese-code-review**: 中文 review 沟通参考——话术模板、分级标注（必须修复/建议修改/仅供参考）、国内团队常见反模式应对。仅在用户显式 /chinese-code-review 时调用，不要根据上下文自动触发。
- **chinese-commit-conventions**: 中文 commit 与 changelog 配置参考——Conventional Commits 中文适配、commitlint/husky/commitizen 中文模板、conventional-changelog 中文配置。仅在用户显式 /chinese-commit-conventions 时调用，不要根据上下文自动触发。
- **chinese-documentation**: 中文文档排版参考——中英文空格、全半角标点、术语保留、链接格式、中文文案排版指北约定。仅在用户显式 /chinese-documentation 时调用，不要根据上下文自动触发。
- **chinese-git-workflow**: 国内 Git 平台配置参考——Gitee、Coding.net、极狐 GitLab、CNB 的 SSH/HTTPS/凭据/CI 接入差异与镜像同步配置。仅在用户显式 /chinese-git-workflow 时调用，不要根据上下文自动触发。
- **dispatching-parallel-agents**: 当面对 2 个以上可以独立进行、无共享状态或顺序依赖的任务时使用
- **executing-plans**: 当你有一份书面实现计划需要在单独的会话中执行，并设有审查检查点时使用
- **finishing-a-development-branch**: 当实现完成、所有测试通过、需要决定如何集成工作时使用——通过提供合并、PR 或清理等结构化选项来引导开发工作的收尾
- **mcp-builder**: MCP 服务器构建方法论 — 系统化构建生产级 MCP 工具，让 AI 助手连接外部能力
- **receiving-code-review**: 收到代码审查反馈后、实施建议之前使用，尤其当反馈不明确或技术上有疑问时——需要技术严谨性和验证，而非敷衍附和或盲目执行
- **requesting-code-review**: 完成任务、实现重要功能或合并前使用，用于验证工作成果是否符合要求
- **subagent-driven-development**: 当在当前会话中执行包含独立任务的实现计划时使用
- **systematic-debugging**: 遇到任何 bug、测试失败或异常行为时使用，在提出修复方案之前执行
- **test-driven-development**: 在实现任何功能或修复 bug 时使用，在编写实现代码之前
- **using-git-worktrees**: 当需要开始与当前工作区隔离的功能开发，或在执行实现计划之前使用——通过原生工具或 git worktree 回退机制确保隔离工作区存在
- **using-superpowers**: 在开始任何对话时使用——确立如何查找和使用技能，要求在任何响应（包括澄清性问题）之前调用 Skill 工具
- **verification-before-completion**: 在宣称工作完成、已修复或测试通过之前使用，在提交或创建 PR 之前——必须运行验证命令并确认输出后才能声称成功；始终用证据支撑断言
- **workflow-runner**: 在 Claude Code / OpenClaw / Cursor 中直接运行 agency-orchestrator YAML 工作流——无需 API key，使用当前会话的 LLM 作为执行引擎。当用户提供 .yaml 工作流文件或要求多角色协作完成任务时触发。
- **writing-plans**: 当你有规格说明或需求用于多步骤任务时使用，在动手写代码之前
- **writing-skills**: 当创建新技能、编辑现有技能或在部署前验证技能是否有效时使用

## 如何使用

当任务匹配某个 skill 时，使用 `Skill` 工具加载对应 skill 并严格遵循其流程。绝不要用 Read 工具读取 SKILL.md 文件。

如果你认为哪怕只有 1% 的可能性某个 skill 适用于你正在做的事情，你必须调用该 skill 检查。
<!-- superpowers-zh:end -->
