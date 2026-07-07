# Agent 行为规范

## Git 推送规则

每个项目的每一次代码更改完成后，都需要：
1. `git add -A` 暂存所有变更
2. `git commit -m "项目名: 简短描述该会话做了什么"` — commit 信息需包含项目名，明确指出对应哪个项目/会话
3. `git push` 推送到 GitHub

**commit message 格式**: `<项目>: <本轮会话做了什么>`

commit 信息需概括本轮会话的核心内容，包括用户的需求和完成的工作，做到之后看 commit 记录就能回忆起当时的对话。

示例：
- `birdreport: 修复居留型匹配、添加2025名录亚种回退；优化稀有度排序(V>Mv>罕见)`
- `birdreport: 新增四季配色模板(春#ffb6c1/夏#1e5631/秋#f77f00/冬#0077b6)、稀有度排序规则`
- `hulu-tracker: 替换奶瓶/大便/睡觉图标为Lucide版本；部署到localtunnel多设备访问`

项目对应关系：
- `~/Desktop/kilo/` → `birdreport-shanghai` (鸟类报告项目)
- 其他项目按目录名或功能命名

## 语言
全程使用中文回答。
