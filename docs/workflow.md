# 开发工作流程

## 项目结构概览

```
lib/
├── api/              # 网络层：REST 客户端、SSE 流、Git 客户端
├── models/           # 数据模型：消息、Part、会话、项目
├── state/            # 状态管理（Riverpod）：聊天、会话、项目、设置
├── ui/
│   ├── pages/        # 页面：聊天、项目列表、Git、文件浏览、设置
│   └── widgets/      # 组件：消息气泡、工具卡片、状态栏等
└── theme.dart        # Material 3 主题

gateway/src/          # Node.js 网关服务端
docs/                 # 文档
test/                 # 单元测试
```

## 功能模块对应文件

| 功能 | 关键文件 |
|------|----------|
| 聊天流式输出 | `lib/state/gateway_chat_store.dart`, `lib/ui/pages/gateway_chat_page.dart` |
| 消息渲染 | `lib/ui/widgets/message_bubble.dart` |
| 工具调用显示 | `lib/ui/widgets/parts/tool_part_view.dart` |
| 文本/Markdown 渲染 | `lib/ui/widgets/parts/text_part_view.dart` |
| 推理/思考显示 | `lib/ui/widgets/parts/reasoning_part_view.dart` |
| Agent 活动状态栏 | `lib/ui/widgets/agent_activity_bar.dart` |
| SSE 事件流 | `lib/api/sse_stream.dart` |
| REST API 客户端 | `lib/api/gateway_client.dart` |
| Git 操作 | `lib/ui/pages/git_page.dart`, `lib/api/git_client.dart` |
| 文件浏览 | `lib/ui/pages/files_page.dart` |
| 项目管理 | `lib/state/project_store.dart`, `lib/ui/pages/project_list_page.dart` |
| 会话管理 | `lib/state/gateway_session_store.dart` |
| 设置 | `lib/state/settings_store.dart`, `lib/ui/pages/settings_page.dart` |
| 主题 | `lib/theme.dart` |
| 网关服务 | `gateway/src/server.js`, `gateway/src/agents.js` |

## 本地开发环境

- Flutter SDK 不在本机 PATH，通过 Docker 运行
- Node.js 网关直接本地运行
- GitHub CI 负责 iOS IPA 打包

## 运行 Flutter Analyze

修改代码后，使用 Docker 运行静态分析：

```bash
cd D:\Code\WorkSpace\remote-multi-agent

# 仅分析
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "D:\Code\WorkSpace\remote-multi-agent:/app" \
  -w /app \
  ghcr.io/cirruslabs/flutter:3.27.1 \
  bash -c "flutter pub get && flutter analyze"

# 运行测试
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "D:\Code\WorkSpace\remote-multi-agent:/app" \
  -w /app \
  ghcr.io/cirruslabs/flutter:3.27.1 \
  bash -c "flutter pub get && flutter test"
```

## 打包 IPA（通过 GitHub CI）

### 触发构建

推送到 main 分支即自动触发：

```bash
git add <files>
git commit -m "feat: ..."
git push
```

CI workflow 文件：`.github/workflows/ios.yml`

### 监控构建

```bash
# 查看最近的 workflow 运行
gh run list --limit 3

# 监控指定 run（找 "iOS unsigned IPA" 那个）
gh run watch <run-id>

# 或查看状态
gh run view <run-id> --json status,conclusion
```

### 下载 IPA

构建成功后：

```bash
gh run download <run-id> --name ios-ipa
```

IPA 下载到当前目录：

```
D:\Code\WorkSpace\remote-multi-agent\opencode_mobile-<commit-hash>.ipa
```

### 安装到 iPhone

使用 Sideloadly 或 AltStore 侧载安装 unsigned IPA。

## 启动网关

```bash
cd gateway
npm install
GATEWAY_HOST=0.0.0.0 node src/index.js
# 监听 http://0.0.0.0:4096
```

## Git 提交规范

参考已有 commit 风格：

```
feat: 新功能描述
fix: 修复描述
ci: CI 相关改动
```

## 常用命令速查

```bash
# 静态分析
MSYS_NO_PATHCONV=1 docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter pub get && flutter analyze"

# 推送触发 CI
git push

# 查看 CI 状态
gh run list --limit 3

# 下载最新 IPA
gh run download $(gh run list --workflow=ios.yml --limit=1 --json databaseId -q '.[0].databaseId') --name ios-ipa
```
