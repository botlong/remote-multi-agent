# 开发工作流

## 项目结构

```text
lib/                  Flutter 移动端应用
  api/                Gateway REST、SSE、Git 客户端
  models/             Project、Session、Message、Part、Agent 等模型
  state/              Riverpod 状态管理
  ui/                 页面和组件
gateway/              Node.js 本地网关
  src/                HTTP 服务、存储、事件总线、文件和 Git 路由
  src/agents/         Codex、Claude Code、OpenCode 适配器和共享工具
  test/               Gateway 单元测试
docs/                 产品、需求和开发文档
test/                 Flutter 单元测试
```

V1 只支持移动端和 iOS。Flutter Web 不是支持目标，应用依赖移动端能力来处理
流式输出和附件。

## Gateway 本地运行

默认只监听本机，适合开发和测试：

```powershell
cd gateway
npm install
npm start
```

需要让手机访问电脑上的 gateway 时，只在可信局域网或 Tailscale 网络中开放：

```powershell
cd gateway
$env:GATEWAY_HOST='0.0.0.0'
$env:GATEWAY_PORT='4096'
npm start
```

V1 gateway 不实现认证，也不校验访问令牌。不要把它直接暴露到公网；保持
`127.0.0.1` 用于本机测试，只在手机必须访问电脑时才使用 `0.0.0.0`。

## Flutter 测试和分析

本机安装 Flutter 3.27 或更新版本时：

```powershell
flutter pub get
flutter analyze
flutter test
```

如果本机没有 Flutter SDK，可以用 Docker 运行同样的检查：

```powershell
docker run --rm `
  -v "D:\Code\WorkSpace\remote-multi-agent:/app" `
  -w /app `
  ghcr.io/cirruslabs/flutter:3.27.1 `
  bash -c "flutter pub get && flutter analyze && flutter test"
```

## iOS IPA 工作流

iOS 打包由 GitHub Actions 处理。给 agent 的标准流程如下：

1. 确认本地分支已经推送，或 PR 已合并到 `main`。
2. 查看最近的 workflow run：

```powershell
gh run list --limit 10
```

3. 找到最新的 `main` / `push` run，确认这些 workflow 成功：
   - `CI`
   - `iOS unsigned IPA`
   - `Build IPA`

4. 查看目标 run 的 artifact。优先使用 `iOS unsigned IPA` workflow 的 run id：

```powershell
gh api repos/botlong/remote-multi-agent/actions/runs/<run-id>/artifacts `
  --jq '.artifacts[] | {name, expired, size_in_bytes, archive_download_url}'
```

5. 确认存在未过期的 `ios-ipa` artifact 后，下载到本地固定目录：

```powershell
New-Item -ItemType Directory -Force -Path "build\artifacts\ios-ipa" | Out-Null
gh run download <run-id> --name ios-ipa --dir "build\artifacts\ios-ipa"
Get-ChildItem -Path "build\artifacts\ios-ipa" -Force
```

如果只存在 `Build IPA` workflow 的 `ipa` artifact，下载到单独目录，避免和
`ios-ipa` 混在一起：

```powershell
New-Item -ItemType Directory -Force -Path "build\artifacts\ipa" | Out-Null
gh run download <run-id> --name ipa --dir "build\artifacts\ipa"
Get-ChildItem -Path "build\artifacts\ipa" -Force
```

6. 最后向用户报告本地目录、IPA 文件名、run id 和 artifact 名称。不要提交 IPA；
   `.gitignore` 已忽略 `/build/` 和 `*.ipa`。

## 常用命令

```powershell
# 查看工作区状态
git status --short

# 运行 gateway 测试
npm test --prefix gateway

# 运行 Flutter 测试
flutter test

# 运行 Flutter 静态分析
flutter analyze
```
