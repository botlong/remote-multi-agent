# 开发工作流

## 项目结构

```text
lib/                  Flutter 移动端应用
  api/                Gateway REST、SSE、Git 客户端
  models/             Project、Session、Message、Part、Agent 等模型
  state/              Riverpod 状态管理
  ui/                 页面和组件
gateway/              Node.js 本地网关
  src/agents/         Codex、Claude Code、OpenCode 适配器
docs/                 产品、需求和开发文档
test/                 Flutter 单元测试
```

V1 只支持移动端/iOS。Flutter Web 不是支持目标。

## Node Gateway 本地运行

默认只监听本机：

```powershell
cd gateway
npm install
npm start
```

需要让手机访问电脑上的网关时，可以在可信局域网或 Tailscale 网络中暴露：

```powershell
$env:GATEWAY_HOST='0.0.0.0'
$env:GATEWAY_PORT='4096'
npm start
```

V1 gateway 无认证，不校验 bearer token。只应在可信局域网或 Tailscale 中暴露，
不要直接暴露到公网。

## Flutter 测试和分析

本机 Flutter 可用时：

```powershell
flutter pub get
flutter analyze
flutter test
```

如果本机没有 Flutter SDK，可以使用 Docker：

```powershell
docker run --rm `
  -v "D:\Code\WorkSpace\remote-multi-agent:/app" `
  -w /app `
  ghcr.io/cirruslabs/flutter:3.27.1 `
  bash -c "flutter pub get && flutter analyze && flutter test"
```

## iOS CI 打包

iOS 打包由 GitHub Actions 处理，workflow 位于 `.github/workflows/ios.yml`。

```powershell
git push
gh run list --limit 3
gh run watch <run-id>
gh run download <run-id> --name ios-ipa
```

下载后的 unsigned IPA 可通过 Sideloadly 或 AltStore 安装到 iPhone。

## 常用命令

```powershell
# 查看工作区状态
git status --short

# 运行 gateway 测试
npm test --prefix gateway

# 运行 Flutter 测试
flutter test
```
