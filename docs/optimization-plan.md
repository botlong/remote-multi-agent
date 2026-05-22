# App 优化需求

日期: 2026-05-22

## 一、多 Profile 配置系统

类似 CC-Switch，支持多套 API key 配置，可随时切换。

### 数据模型

```json
{
  "profiles": [
    {
      "id": "uuid",
      "name": "公司代理",
      "isCurrent": true,
      "keys": {
        "anthropic": { "key": "sk-ant-...", "baseUrl": "https://proxy.example.com" },
        "openai": { "key": "sk-...", "baseUrl": null }
      },
      "defaultModel": {
        "claude-code": "claude-sonnet-4-20250514",
        "codex": "gpt-5.5",
        "opencode": "anthropic/claude-sonnet-4-20250514"
      },
      "createdAt": 1779177600000
    }
  ]
}
```

### 网关接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/settings/profiles` | 列出所有 profile（key 脱敏显示） |
| POST | `/settings/profiles` | 创建 profile |
| PATCH | `/settings/profiles/:id` | 修改 profile |
| DELETE | `/settings/profiles/:id` | 删除 profile |
| POST | `/settings/profiles/:id/activate` | 切换激活 profile |
| GET | `/settings/active-profile` | 获取当前激活 profile |

### 网关持久化

- 文件: `~/.gateway/profiles.json`
- 新建 `gateway/src/config.js` 负责读写
- Adapter 读 key 优先级: `env 变量 → active profile → CC-Switch DB → ~/.claude/settings.json → fallback`
- 运行 agent CLI 时将 active profile 的 key 注入子进程环境变量

### App 侧

- 设置页新增 "Profiles" 管理区域（增删改 profile，配置各 provider 的 key 和 baseUrl）
- App 本地不存储 key，只存 gateway URL 和 bearer token
- 聊天页某处显示当前 profile 名称，支持快速切换
- 切换 profile 后刷新模型列表

---

## 二、每个 Profile 可设置默认模型

- 每个 profile 内按 agent 存储默认 model ID
- 新建 session 时自动使用对应 agent 的默认 model，无需每次手动选
- 设置页 profile 编辑界面中可为每个 agent 选择默认 model
- 如果 profile 没设默认 model，新建 session 时仍弹 model picker

---

## 三、聊天内命令全面优化

### 问题

当前所有 `/command` 都直接发给网关，网关转发给 agent CLI。CLI 返回纯文本，在手机上不可读、不可交互。所有命令都应该有对应的原生 UI 体验。

### 设计原则

每个命令按交互类型分为四类：
- **picker 类** — 需要从列表中选择（弹 bottom sheet）
- **confirm 类** — 需要确认才执行（弹对话框）
- **action 类** — 直接执行，结果用 toast/snackbar 展示（不需要 CLI 文本输出）
- **passthrough 类** — 无法在 app 侧处理，发给网关但结果格式化展示

### 全部命令拦截表

#### 通用命令（所有 agent 共享）

| 命令 | 类型 | App 行为 |
|------|------|----------|
| `/model` `/models` | picker | 弹 model picker，选择后发 `/model <id>` 给网关 |
| `/fast` | action | 从 agent metadata 取 fast model，直接切换，toast 提示 |
| `/compact` `/summarize` | confirm | "压缩上下文将减少历史细节，继续？" → 发给网关 |
| `/clear` | confirm | "清空当前对话？" → 发给网关 |
| `/new` | confirm | "创建新对话？" → 创建 session 并跳转 |
| `/status` | action | App 本地组装状态信息（session/agent/model/token usage），显示为卡片 |
| `/help` | action | 显示当前 agent 的命令列表（已有数据），用 bottom sheet 展示 |
| `/diff` `/copy` | action | 调用已有的 diff 页面 / 复制到剪贴板 |
| `/export` | picker | 弹选择 "Markdown / JSON"，然后复制或分享 |
| `/undo` | confirm | "撤销上次更改？" → 发给网关 |
| `/redo` | confirm | "重做？" → 发给网关 |
| `/exit` `/quit` `/q` | confirm | "结束当前会话？" → 关闭 session，返回列表 |

#### Claude Code 专属

| 命令 | 类型 | App 行为 |
|------|------|----------|
| `/permissions` | picker | 显示权限模式列表（plan/acceptEdits/bypassPermissions），选择后发给网关 |
| `/memory` | passthrough | 发给网关，结果格式化为 markdown 卡片展示 |
| `/cost` | action | 从 session.usage 本地展示 token 用量和费用估算 |
| `/review` | confirm | "对当前更改进行 code review？" → 发给网关 |
| `/mcp` | passthrough | 发给网关，结果格式化展示 |
| `/config` | passthrough | 发给网关，结果格式化展示 |
| `/doctor` | passthrough | 发给网关，结果格式化展示 |
| `/pr_comments` | action | 发给网关，toast 提示 "Loading PR comments..." |
| `/add-dir` | picker | 弹目录选择器（已有 directory_picker），选择后发给网关 |
| `/agents` | passthrough | 发给网关，结果格式化展示 |
| `/init` | confirm | "初始化项目配置？" → 发给网关 |
| `/login` `/logout` | passthrough | 发给网关（需要 CLI 交互，结果展示） |
| `/bug` | passthrough | 发给网关 |
| `/terminal-setup` `/vim` | action | 不适用于移动端，toast 提示 "Not available on mobile" |

#### Codex 专属

| 命令 | 类型 | App 行为 |
|------|------|----------|
| `/permissions` | picker | 显示 sandbox 模式列表（full-auto/workspace-write/read/locked） |
| `/sandbox-add-read-dir` | picker | 弹目录选择器 |
| `/plan` `/goal` | passthrough | 发给网关（需要后续文本输入） |
| `/fork` `/side` | confirm | "创建分支/侧对话？" → 发给网关 |
| `/approve` | action | 发给网关，toast 提示 |
| `/memories` `/skills` | passthrough | 发给网关，结果格式化展示 |
| `/personality` | passthrough | 发给网关（需要后续文本输入） |
| `/feedback` `/review` | passthrough | 发给网关 |
| `/ps` | action | 发给网关，结果用列表卡片展示 |
| `/stop` | action | 调用 abort 接口 |
| `/mcp` `/hooks` `/plugins` `/apps` `/agent` | passthrough | 发给网关，结果格式化展示 |
| `/ide` `/keymap` `/vim` | action | 不适用于移动端，toast 提示 |
| `/init` | confirm | "初始化项目配置？" → 发给网关 |
| `/experimental` | passthrough | 发给网关 |
| `/debug-config` | passthrough | 发给网关，结果格式化展示 |
| `/raw` | passthrough | 发给网关（后面跟的是 prompt 内容） |
| `/mention` | picker | 弹文件选择器，选择后插入到输入框 |
| `$` | passthrough | shell 命令，直接发给网关 |

#### OpenCode 专属

| 命令 | 类型 | App 行为 |
|------|------|----------|
| `/sessions` `/resume` `/continue` | picker | 从网关拉 session 列表，弹选择器，选择后跳转 |
| `/share` | action | 发给网关，toast 提示分享链接 |
| `/unshare` | confirm | "取消分享？" → 发给网关 |
| `/details` | action | 本地组装 session 详情卡片展示 |
| `/editor` | action | 不适用于移动端，toast 提示 |
| `/themes` | action | 不适用于移动端（app 有自己的主题设置） |
| `/init` | confirm | "初始化项目配置？" → 发给网关 |

#### `$` Shell 命令

| 命令 | 类型 | App 行为 |
|------|------|----------|
| `$<command>` | passthrough | 直接发给网关执行，结果在终端视图展示 |

### passthrough 命令的优化

即使是 passthrough 类命令，也不应该直接显示 CLI 原始文本。网关应该：
- 尽量解析 CLI 输出为结构化数据
- 返回 `{ type: "command.result", format: "markdown" | "json" | "list", data: ... }`
- App 根据 format 用对应的渲染组件展示（markdown 卡片、JSON 树、列表）

### 实现方式

1. 在 `gateway_chat_page.dart` 的 `_send()` 中，建立命令路由表
2. 每个命令对应一个处理函数（`_handleModelCommand`、`_handleClearCommand` 等）
3. 处理函数负责弹 UI → 收集用户选择 → 发最终指令给网关
4. passthrough 命令仍走 `sendSlashCommand`，但 UI 侧对返回的 `command.result` 事件做格式化渲染

---

## 四、交互优化

### 4.1 新建对话简化

- 记住上次选择的 agent + model（存 SharedPreferences）
- 新建对话时默认选中上次的 agent/model
- 如果只有一个 project，跳过项目列表直接进入 project detail

### 4.2 启动恢复

- 记住上次打开的 session ID（SharedPreferences）
- 启动时如果有活跃 session，直接进入聊天页

### 4.3 底部导航精简（可选）

- 考虑将 Git/Files 降级为聊天页内入口（已在 AppBar 有入口）
- 底部 nav 简化为: Projects / Settings，或完全去掉改用抽屉

---

## 五、涉及文件

### 网关

| 文件 | 改动 |
|------|------|
| 新建 `gateway/src/config.js` | Profile 读写、key 管理 |
| `gateway/src/server.js` | 新增 `/settings/*` 路由 |
| `gateway/src/agents.js` | Adapter 读 key 时接入 config；CLI 启动时注入环境变量 |

### App

| 文件 | 改动 |
|------|------|
| `lib/api/gateway_client.dart` | 新增 profile CRUD 方法 |
| `lib/state/settings_store.dart` | 新增 lastAgentId/lastModelId/lastSessionId；profile 状态 |
| `lib/ui/pages/settings_page.dart` | 新增 Profiles 管理 UI |
| `lib/ui/pages/gateway_chat_page.dart` | `_send()` 中加入命令拦截逻辑；profile 切换入口 |
| `lib/ui/pages/agent_group_page.dart` | 默认选中上次 agent/model |
| `lib/ui/pages/project_list_page.dart` | 单 project 时自动跳转 |
| `lib/main.dart` | 启动时恢复上次 session |

---

## 六、实现顺序

1. **网关 `config.js` + `/settings` 路由** — profile 基础设施
2. **网关 Adapter 接入 profile key** — 让模型列表和 agent 运行能用 profile 的 key
3. **App 设置页 Profile 管理 UI** — 创建/编辑/切换 profile
4. **App 命令全面拦截** — 所有命令都有原生 UI（picker/confirm/action/passthrough 格式化）
5. **App 交互优化** — 记住选择、启动恢复、流程简化
