# Remote Multi-Agent — Feature Roadmap

## P0: 核心体验提升

### 1. Session 自动标题
- 用第一条用户消息前 30 字符自动命名 session
- Agent 返回的 title（如 Codex 的 thread title）自动同步更新
- 涉及：`server.js` startTurn 逻辑 + `store.js` updateSession

### 2. 消息长按菜单
- 长按消息弹出菜单：复制文本、复制 Markdown、删除消息
- 删除需要 gateway API：`DELETE /sessions/:id/messages/:messageId`
- 涉及：`gateway_chat_page.dart` MessageBubble + `server.js` 新端点 + `store.js` deleteMessage

### 3. 深色/浅色主题 + 前端全面优化
- 设置页加主题切换开关（跟随系统 / 浅色 / 深色），持久化到 SharedPreferences
- 全面优化 UI 细节，做成一个真正精致的 app：
  - 统一色彩体系、间距、圆角
  - 消息气泡区分用户/助手样式，代码块语法高亮
  - 工具调用折叠/展开卡片，状态图标动画
  - 空状态插图、加载骨架屏
  - 输入栏动效（打字中、发送中、引导中）
  - 页面转场动画
  - 响应式布局（平板/桌面宽屏适配）
- 涉及：`main.dart` ThemeData + `settings_page.dart` + 全局 widget 优化

### 4. 通知推送
- Agent 长任务完成后发送系统通知（app 在后台也能收到）
- 使用 `flutter_local_notifications` 插件
- SSE 监听 session.completed 事件触发通知
- 涉及：新增 notification service + `gateway_chat_store.dart` 事件监听

---

## P1: 信息与效率

### 5. Context 用量条
- 显示当前 session 的 context window 使用率（token 数 / 上限）
- 从 agent JSON 事件中提取 usage 数据（Codex: `usage`, Claude: `usage`, OpenCode: token count）
- 接近上限时在输入栏上方显示警告并建议使用 `/compact`
- 涉及：`agents.js` 提取 usage → SSE 事件 `session.usage` + 新 Flutter widget

### 6. Diff 查看器
- Agent 修改文件后在 app 内查看 git diff
- Gateway 已有 git 相关端点，需要确认/扩展
- App 新增 diff 查看页，支持文件级 diff 展示（增/删/改高亮）
- 可从聊天页工具调用卡片跳转到 diff 页
- 涉及：gateway git API + 新 `diff_page.dart`

### 7. Session 搜索
- 跨 session 全文搜索历史对话
- Gateway 新增 `GET /search?q=...&projectId=...` 端点，搜索所有 session 的消息文本
- App 新增搜索页，搜索结果可跳转到对应 session 和消息
- 涉及：`store.js` 搜索逻辑 + `server.js` 新端点 + 新 `search_page.dart`

### 8. 消息导出
- 导出整个 session 为 Markdown 或 JSON 文件
- Gateway 新增 `GET /sessions/:id/export?format=md|json` 端点
- App 使用 share 插件分享导出文件
- 涉及：`server.js` 导出端点 + Flutter `share_plus` 插件 + 导出按钮（session 菜单或聊天页 AppBar）

---

## 实现状态

| # | 功能 | 状态 |
|---|------|------|
| 1 | Session 自动标题 | ✅ 已完成 |
| 2 | 消息长按菜单 | ✅ 已完成 |
| 3 | 深色/浅色主题 + UI 优化 | ✅ 已完成 |
| 4 | 通知推送 | ✅ 已完成 |
| 5 | Context 用量条 | ✅ 已完成 |
| 6 | Diff 查看器 | ✅ 已完成 |
| 7 | Session 搜索 | ✅ 已完成 |
| 8 | 消息导出 | ✅ 已完成 |
