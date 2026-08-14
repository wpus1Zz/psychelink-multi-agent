# PsycheLink Multi-Agent

PsycheLink 是一个面向校园心理支持场景的多智能体平台，围绕意图路由、风险识别、知识检索、运行时编排和高风险后处理闭环做工程化落地。

当前主线运行时采用事件驱动的多 Agent 协作模型：外层由 `PsycheLinkAgentHarness` 统一处理输入脱敏、会话解析、消息持久化、风险报告、工具计划和运行 trace；内层由 `EventDrivenAgentRuntimeService + CollaborationBlackboard + EventDrivenCoordinator` 驱动多 Agent 按 task claim 和 artifact publish 机制协作完成一次对话。

## Core Highlights

### Agent Runtime Harness

- 统一收口一轮对话的工程侧逻辑：输入脱敏、session 解析、消息落库、心理报告、trace、工具派发
- 关键实现：
  - [app/agents/harness.py](./app/agents/harness.py)

### 事件驱动多 Agent 协作

- 基于 `CollaborationBlackboard` 保存任务、产物、消息和事件
- `EventDrivenCoordinator` 根据缺失 artifact 动态派生任务，而不是写死固定链路
- 关键实现：
  - [app/agents/event_driven_runtime.py](./app/agents/event_driven_runtime.py)
  - [app/agents/coordinator.py](./app/agents/coordinator.py)
  - [app/agents/events.py](./app/agents/events.py)
  - [app/agents/autonomous.py](./app/agents/autonomous.py)

### 上下文管理与压缩

- 短期上下文优先从 Redis 读取，缺失时从 MySQL 最近消息回填
- 支持历史窗口裁剪、规则摘要压缩和 LLM 记忆摘要
- 关键实现：
  - [app/services/memory.py](./app/services/memory.py)
  - [app/agents/autonomous.py](./app/agents/autonomous.py)

### Skill + RAG 回复增强

- `PsycheLinkSkillRegistry` 动态加载 `skills/*/SKILL.md`
- 支持心理支持技能选择、query rewrite、Chroma + BM25 hybrid retrieval、本地 rerank
- 关键实现：
  - [app/services/skills.py](./app/services/skills.py)
  - [app/services/knowledge.py](./app/services/knowledge.py)
  - [app/services/vector_store.py](./app/services/vector_store.py)

### 风险识别与高风险闭环

- `SafetyAgent` 同时负责风险评估与候选回复安全审查
- 高风险场景可触发心理报告、Excel 台账、个案创建和预警发送
- 关键实现：
  - [app/services/assessment.py](./app/services/assessment.py)
  - [app/services/tools.py](./app/services/tools.py)
  - [app/services/tool_queue.py](./app/services/tool_queue.py)

### Engineering Harness

- 提供可重复的一键验证 harness，覆盖 Risk Safety、Agent Routing、RAG、API、Tool Queue 等核心链路
- 关键实现：
  - [app/harness/runner.py](./app/harness/runner.py)
  - [app/harness/routing_eval.py](./app/harness/routing_eval.py)
  - [app/rag_eval/runner.py](./app/rag_eval/runner.py)

## Tech Stack

```text
Python, FastAPI, SQLAlchemy, MySQL, Redis
RAG, Chroma, BM25, OpenAI Embeddings
MCP, Docker, Basic Auth
Event-Driven Multi-Agent Runtime
Harness Engineering, Skill Registry, Tool Queue
```

## Default Runtime Flow

当前默认主线是 `event_driven_multi_agent`。

一次用户请求的主链路如下：

1. `POST /api/chat/stream` 进入 FastAPI 路由
2. `ChatService.stream_chat()` 调用 `PsycheLinkAgentHarness.run()`
3. Harness 完成输入脱敏、session 解析、runtime 选择、风险报告与 trace 规划
4. `EventDrivenAgentRuntimeService.run()` 创建黑板 `CollaborationBlackboard`
5. `EventDrivenCoordinator.run()` 进入 bounded loop
6. Coordinator 根据黑板缺失的 artifact 动态派生任务：
   - `intent`
   - `risk`
   - `context`
   - `response_proposal`
   - `safety_review`
7. 各 Agent 根据 `decide(task, board)` claim 任务并执行 `act(task, board)`
8. `board.apply_turn_result(...)` 将消息、artifact、follow-up task、event 写回黑板
9. 一旦 `response_proposal` 通过安全审查，Coordinator `accept_final(...)`
10. runtime 将黑板结果收口为 `AgentRunResult`
11. 外层 `AiClient.stream(...)` 基于 `response_messages` 流式输出最终文本
12. 回复完成后，Harness 异步投递工具队列或 MCP 工具调用

对应关键文件：

- [app/api/routes.py](./app/api/routes.py)
- [app/services/chat.py](./app/services/chat.py)
- [app/agents/harness.py](./app/agents/harness.py)
- [app/agents/event_driven_runtime.py](./app/agents/event_driven_runtime.py)
- [app/agents/coordinator.py](./app/agents/coordinator.py)
- [app/agents/events.py](./app/agents/events.py)
- [app/agents/autonomous.py](./app/agents/autonomous.py)

## Runtime Roles

- `CoordinatorAgent`
  - 维护任务板、预算、安全门槛和最终采纳

- `UnderstandingAgent`
  - 判断当前输入属于 `CHAT / CONSULT / RISK`

- `SafetyAgent`
  - 独立风险评估
  - 候选回复安全审查

- `ContextAgent`
  - 读取历史记忆
  - 进行压缩摘要
  - 触发 RAG 检索
  - 注入 Skill context

- `ResponseAgent`
  - 基于意图、风险、记忆、RAG 和 Skill 生成候选回复方案 `response_proposal`

## Project Structure

```text
app/
├── agents/         # runtime、黑板、协调器、多 Agent 实现
├── api/            # FastAPI 路由
├── core/           # 配置、数据库、安全、启动初始化
├── harness/        # engineering harness 与路由评测
├── knowledge/      # 内置心理知识库
├── mcp_tools/      # MCP 工具服务
├── models/         # SQLAlchemy 实体
├── rag_eval/       # RAG 评测集与 runner
├── schemas/        # DTO / Pydantic 模型
├── services/       # AI、记忆、知识库、报告、工具、trace
└── static/         # 前端页面

models/psychelink-qwen2.5-7b-ft/
scripts/
skills/
tests/
```

## Quick Start

### 1. Install

```bash
pip install -r requirements.txt
```

### 2. Configure MySQL and Redis

创建数据库：

```sql
CREATE DATABASE psychelink DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'psychelink'@'%' IDENTIFIED BY 'psychelink';
GRANT ALL PRIVILEGES ON psychelink.* TO 'psychelink'@'%';
FLUSH PRIVILEGES;
```

`.env` 示例：

```env
DATABASE_URL=mysql+pymysql://psychelink:psychelink@127.0.0.1:3306/psychelink?charset=utf8mb4
REDIS_URL=redis://127.0.0.1:6379/0
AGENT_FRAMEWORK=event_driven_multi_agent
AI_PROVIDER=ollama
OLLAMA_MODEL=psychelink-qwen2.5-7b-ft:latest
TOOL_QUEUE_ENABLED=true
```

### 3. Run locally

```bash
uvicorn app.main:app --host 127.0.0.1 --port 8080
```

或者使用启动脚本：

```bash
start-psychelink.ps1
```

### 4. Docker Compose

```bash
docker compose up -d --build
```

## Authentication

项目使用 `Basic Auth` 做基础登录鉴权。

- 学生接口需要 `current_user`
- 管理员接口需要 `require_admin`

默认种子用户可参考：

- [app/core/bootstrap.py](./app/core/bootstrap.py)

## RAG

知识检索默认走 hybrid retrieval：

- 向量召回：Chroma + `text-embedding-3-small`
- 关键词召回：BM25
- 融合排序：hybrid score
- rerank：本地 reranker

相关接口：

- `GET /api/admin/knowledge/status`
- `POST /api/admin/knowledge`
- `POST /api/admin/knowledge/rebuild-vector`
- `POST /api/admin/knowledge/backup`

## Tool Queue and MCP

高风险报告生成后，后处理默认不阻塞学生侧回复，而是进入异步工具队列：

- `EXCEL_REPORT`
- `CASE_CREATE`
- `ALERT_SEND`

如果关闭工具队列，则退回到 MCP client 直接调用：

- `psychelink_excel_report`
- `psychelink_case_create`
- `psychelink_alert_send`
- `psychelink_alert_ack`
- `psychelink_case_note_add`
- `psychelink_alert_notify`

对应实现：

- [app/services/tool_queue.py](./app/services/tool_queue.py)
- [app/services/mcp_client.py](./app/services/mcp_client.py)
- [app/mcp_tools/server.py](./app/mcp_tools/server.py)

## Engineering Harness

运行完整工程验证：

```bash
python -m app.harness.runner
```

只运行路由评测：

```bash
python -m app.harness.runner --suite routing-eval
```

运行 RAG 评测：

```bash
python -m app.rag_eval.runner
```

## Tests

```bash
python -m unittest discover -s tests
```

## Notes

- 当前仓库主学习与展示重点是默认 runtime：`event_driven_multi_agent`
- `custom` 和 `langgraph` 仍保留为对照实现，但不是当前主线
- 对外展示时，建议保持项目名、README、类名、前端文案、脚本和模型资源命名一致
