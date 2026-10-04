# 项目 Agent 约束

## 编码规则

- 本项目编码（包括前端代码的创建、修改、调试、重构和审查）无需调用 `frontend-safe-development` skill；本条取代原有必须调用该 skill 的要求。
- 写代码（创建、修改、调试、重构、审查）必须遵守以下 skill，开工前先加载：
  - [karpathy-guidelines](/Users/fun/.agents/skills/karpathy-guidelines/SKILL.md)：先思考再编码、最简实现、外科手术式改动。
  - [write-swift](/Users/fun/.agents/skills/write-swift/SKILL.md)：本项目为纯 Swift 项目，Swift 代码一律按其现代写法、并发模型与 API 设计规范来写。
  - [Ponytail](plugin://ponytail@ponytail)（`ponytail:ponytail`），默认 `full` 模式：YAGNI 阶梯，最短可行实现。
- 项目根目录存在 `.codegraph/` 时，扫描/检索项目代码之前必须先执行 `codegraph sync`（索引有变动时加 `index` 重建），再使用 codegraph 查询；禁止对着过期索引下结论。
- 其余已适用的 CodeGraph 与 Git 约束保持有效；任务完成不代表获得 Git 写操作授权。
