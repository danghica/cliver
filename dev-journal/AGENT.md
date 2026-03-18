# Cliver — Agent Entry Point

**读这个文件作为开始每次开发的第一步。**

---

## 当前状态（2026-03-17）

| 项 | 状态 |
|----|------|
| 最近落地的 feature | `upload-download`：WebSocket upload/download 协议 |
| 单元测试 | ✓ 通过 |
| 集成测试 | ✓ backend tests 全过（含 3 个 upload/download 用例） |
| 独立测试（cliver-tests/） | ✓ 42/42 通过（spec 1.2；Doc Reviewer A/B + Agent A/B × 2 轮均已执行） |
| 已知环境问题 | `cjpm run -- --pkg` 在本机不工作，用 `PKG_SRC=... ./target/release/bin/main` |

---

## 怎么找到你需要的东西

```
dev-journal/
├── AGENT.md                        ← 你在这里（入口）
├── process/
│   ├── feature-workflow.md         ← 开发新 feature 的完整流程
│   ├── tracker-template.md         ← tracker.md 的初始模板
│   ├── testing-setup.md            ← 测试仓搭建 + Agent A/B 硬隔离运行方式
│   ├── testing-strategy.md         ← 测试策略背景
│   └── design-doc-standard.md     ← design.md 格式规范 + Doc Reviewer 模板
└── features/
    └── 2026-03-17-upload-download/ ← 每个 feature 一个目录
        ├── design.md               ← 规格（稳定，标 final 后不动）
        ├── impl.md                 ← 实现笔记（决策、bug fix）
        └── tracker.md              ← 执行追踪（checkpoint、测试数字、gap 决策）
```

- **开发新 feature** → 先读 `process/feature-workflow.md`
- **写 design.md** → 先读 `process/design-doc-standard.md`（格式规范 + 完成清单）
- **查 feature 执行状态** → 读对应 `features/<date-name>/tracker.md`（checkpoint 执行情况、测试数字）
- **查 feature 实现细节** → 读对应 `features/<date-name>/impl.md`（bug fix、实现决策）
- **测试策略和置信度** → 读 `process/testing-strategy.md`
- **搭建/使用独立测试仓** → 读 `process/testing-setup.md`（含仓库位置、Agent A/B 硬隔离运行方式）
- **查看历史规格** → 找对应 `features/<date-name>/design.md`
- **查代码约束和架构** → 读 repo 根目录的 `CLAUDE.md`

---

## 开始新 feature 的清单

完整流程有四个 review checkpoint，详见 `process/feature-workflow.md`。

```
Design
[ ] 1. 读 CLAUDE.md + process/feature-workflow.md
[ ] 2. 读 process/design-doc-standard.md（格式规范）
[ ] 3. 写 design.md draft + impl.md（In Progress）
[ ] 4. Doc Reviewer A（独立 subagent）：格式/可读性 → 修复  ← 完成后在 tracker.md Checkpoint Records 更新
[ ] 5. Doc Reviewer B（独立 subagent）：内容/可测试性 → 修复  ← 同上
[ ] 6. design.md 标记 status: final，更新 README.md 索引

Implementation
[ ] 7. 实现（parser → codegen → main → tests）

Verification（实现仓）
[ ] 8. cjpm build + cjpm test + 集成测试 + backend 测试

Independent Testing（测试仓 /home/gloria/tianyue/cliver-tests/）
[ ] 9.  sync-specs.sh（同步 design.md，更新 MANIFEST）
[ ] 10. Test Agent A（独立 session）：写测试（只读 specs/）
[ ] 11. Test Agent B（独立 session）：gap report（只读 spec + name 列表）
[ ] 12. 人工决策 gap，补 P1/P2，run_tests.sh
[ ] 13. Mutation verification（关键逻辑）

Wrap-up
[ ] 14. impl.md Verified ✓ + known gaps 记录
[ ] 15. 更新本文件"当前状态"表格
```

---

## 关键环境命令

```bash
# 激活 Cangjie 工具链（每次 session 必须）
source /home/gloria/cangjie/envsetup.sh

# 构建 Clive
cjpm build

# 重新生成样例包（注意：cjpm run -- 在本机不工作，用 binary）
PKG_SRC=sample_cangjie_package ./target/release/bin/main

# 单元测试
cjpm test

# 全量验证（含集成 + backend）
cd sample_cangjie_package && cjpm build && node test_backend.js
```
