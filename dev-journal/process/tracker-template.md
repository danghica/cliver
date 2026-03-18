# tracker.md 模板

> 复制到 `dev-journal/features/YYYY-MM-DD-<name>/tracker.md`
> 在 Phase 0.1 创建，随开发过程持续更新，Phase 4 填完所有行。

---

```markdown
---
feature: <name>
date_started: YYYY-MM-DD
date_verified:
---

# Feature Tracker: <name>

## Phase Completion

| Phase | 状态 | 日期 | 备注 |
|-------|------|------|------|
| Phase 0: Design | [ ] 未开始 | — | — |
| Phase 1: Implementation | [ ] 未开始 | — | — |
| Phase 2: Verification | [ ] 未开始 | — | — |
| Phase 3: Independent Testing | [ ] 未开始 | — | — |
| Phase 4: Wrap-up | [ ] 未开始 | — | — |

状态取值：`[ ] 未开始` / `⚠ 部分完成` / `✓ 完成` / `✗ 跳过（原因）`

## Checkpoint Records

| Checkpoint | 是否执行 | 执行方式 | 隔离级别 | 输出 |
|-----------|---------|---------|---------|------|
| Doc Reviewer A（格式） | ✗ 未执行 | — | — | — |
| Doc Reviewer B（内容） | ✗ 未执行 | — | — | — |
| Test Agent A（写测试） | ✗ 未执行 | — | — | — |
| Test Agent B（gap review） | ✗ 未执行 | — | — | — |
| Mutation verification | ✗ 未执行 | — | — | — |

隔离级别取值：`硬隔离（spec 嵌入 prompt）` / `软隔离（prompt 约束）` / `—`

## Test Results

| 测试套件 | 数量 | 结果 | 日期 |
|---------|------|------|------|
| 单元测试（cjpm test） | — | — | — |
| 集成测试（sample_cangjie_package） | — | — | — |
| 独立协议测试（cliver-tests） | — | — | — |
| Mutation verification | — | — | — |

## Gap Report 决策（来自 Agent B）

| Gap | 优先级 | 决策 |
|-----|--------|------|
| — | — | — |
```
