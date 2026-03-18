# Cliver Feature 开发流程

> Feature 是最小开发单元。每个 feature 经过四个独立 review checkpoint 才算完成：
> Doc Reviewer A/B（设计阶段）→ Test Agent A/B（验证阶段）。
> 所有 reviewer 都是独立 session，不共享彼此的 context。

---

## 环境准备（每次 session 开始前）

```bash
source /home/gloria/cangjie/envsetup.sh
```

---

## 完整流程总览

```
Phase 0: Design
  ├─ 0.1 写 design.md draft
  ├─ 0.2 Doc Reviewer A：格式/可读性检查
  ├─ 0.3 修复格式问题
  ├─ 0.4 Doc Reviewer B：内容/可测试性检查
  ├─ 0.5 修复内容问题
  └─ 0.6 标记 status: final，创建 impl.md

Phase 1: Implementation
  └─ 按 parser → codegen → main → tests 顺序实现

Phase 2: Verification（实现仓）
  ├─ 2.1 cjpm build
  ├─ 2.2 cjpm test（单元测试）
  ├─ 2.3 重新生成样例包
  ├─ 2.4 构建样例包
  ├─ 2.5 集成测试
  └─ 2.6 实现仓 backend 测试

Phase 3: Independent Testing（测试仓）
  ├─ 3.1 sync-specs.sh（同步 design.md 到 cliver-tests/）
  ├─ 3.2 Test Agent A：独立写测试（只读 specs/）
  ├─ 3.3 Test Agent B：gap report（只读 spec + test name 列表）
  ├─ 3.4 人工决策：哪些 gap 必须补
  ├─ 3.5 run_tests.sh（含新鲜度检查）
  └─ 3.6 Mutation verification（关键安全/核心逻辑）

Phase 4: Wrap-up
  └─ 更新 impl.md、AGENT.md、CLAUDE.md
```

---

## Phase 0 — Design

### 0.1 写 design.md draft

在 `dev-journal/features/YYYY-MM-DD-<name>/` 创建三个文件：
- `design.md`（draft，按 `process/design-doc-standard.md` 格式）
- `impl.md`（初始 status: In Progress，记录实现决策和 bug fix）
- `tracker.md`（执行追踪，记录每个 checkpoint 的实际执行情况和测试数字）

同步更新 `dev-journal/README.md` 的 Feature 索引。

`tracker.md` 初始状态：所有 Phase 标记为 `[ ] 未开始`，Checkpoint 全部标记为 `✗ 未执行`。每个 Phase 结束时更新对应行。

### 0.2 Doc Reviewer A：格式/可读性检查

**独立 session。只给 Reviewer A：**
- `process/design-doc-standard.md`（格式规范）
- 草稿 `design.md`

**不给：** 任何实现代码、impl.md、其他 feature 的文档。

使用 `design-doc-standard.md` 中的 **Doc Reviewer A Prompt 模板**。

**输出：** 格式问题列表（逐条，指向 standard 的具体要求）。

### 0.3 修复格式问题

按 Reviewer A 的输出逐条修复，不需要重新过 Reviewer A（格式问题通常是机械的）。

### 0.4 Doc Reviewer B：内容/可测试性检查

**独立 session。只给 Reviewer B：**
- 格式修复后的 `design.md`

**不给：** `design-doc-standard.md`（避免 Reviewer B 被格式锚定而忽略内容问题）、实现代码、impl.md。

使用 `design-doc-standard.md` 中的 **Doc Reviewer B Prompt 模板**。

**输出：** 内容问题列表（不一致、不可测试、缺失边界等）。

### 0.5 修复内容问题

按 Reviewer B 的输出修复。如果修复涉及重大结构变化，重新过 Reviewer A。

### 0.6 标记 final

design.md frontmatter 改为 `status: final`，过 `design-doc-standard.md` 完成清单。

---

## Phase 1 — Implementation

工作顺序（严格遵循 Cliver 架构）：

```
parser.cj  →  codegen.cj  →  main.cj  →  实现仓内 test files
```

约束（来自 `CLAUDE.md`）：
- 只改动与 feature 直接相关的代码，不做顺手重构
- 不添加超出当前需求的错误处理、fallback、注释
- 不创建新文件，除非 feature 明确需要

每次改动记录到 `impl.md`：diff 摘要 + 遇到的问题。

---

## Phase 2 — Verification（实现仓）

> 策略见 `testing-strategy.md`。

每步绿灯才继续：

```bash
# Step 2.1：编译
cjpm build

# Step 2.2：单元测试
cjpm test                     # 期望 FAILED: 0

# Step 2.3：重新生成样例包
# 注意：cjpm run -- 在本机不工作，用 binary
PKG_SRC=sample_cangjie_package ./target/release/bin/main

# Step 2.4：构建样例包
cd sample_cangjie_package && cjpm build

# Step 2.5：集成测试
cjpm test
./test_ref_output.sh
./test_cli_usage.sh
./test_nested_package.sh

# Step 2.6：实现仓 backend 测试
node test_backend.js          # 期望 All backend tests passed.
```

一键全量（repo root）：
```bash
./scripts/build_and_test.sh
```

---

## Phase 3 — Independent Testing（测试仓）

> 测试仓位置：`/home/gloria/tianyue/cliver-tests/`
> 落地细节见 `testing-setup.md`。

### 3.1 同步 spec

```bash
cd /home/gloria/tianyue/cliver-tests
CLIVER_REPO=/home/gloria/tianyue/cliver ./sync-specs.sh
# 输出：MANIFEST.json 更新，源文件 sha256 记录
```

### 3.2 Test Agent A：独立写测试

**独立 session，在 `cliver-tests/` 目录下启动。只给 Agent A：**
- `cliver-tests/specs/`（同步来的 design.md）
- `cliver-tests/` 下已有的测试基础设施

**不给：** `cliver/src/`、impl.md、任何实现文件。

Agent A 按 spec 写测试，test name 格式：`[feature][type] 行为描述`

type 取值：`spec`、`invariant`、`security`、`error`、`boundary`

### 3.3 Test Agent B：gap report

**独立 session。只给 Agent B：**
- `cliver-tests/specs/` 中对应 feature 的 spec
- 当前测试的 name 列表（命令见 `testing-setup.md`）

**不给：** 测试代码、实现代码。

使用 `testing-setup.md` 中的 **Agent B 固定 Prompt 模板**。

**输出：** gap report → 保存到 `cliver-tests/gap-reports/YYYY-MM-DD-<feature>.md`

### 3.4 人工决策

看 gap report，决定：
- P1/P2 gap：必须补（补完后重新过 3.5）
- P3 gap：可接受，记录为 known gap

### 3.5 运行测试仓全量测试

> ⚠️ 如果在 Phase 3 期间修改了 `src/main.cj`（例如修 bug），必须先重新执行 Phase 2.1–2.3（重新 build + 重新生成 `cli_ws_server.js`），再回到 3.1 重新同步 spec，然后才能运行 3.5。不能跳过这步——测试仓测的是实际运行的 `cli_ws_server.js`，不是 `src/main.cj` 源码。

```bash
cd /home/gloria/tianyue/cliver-tests
./run_tests.sh
# 启动时自动检查 spec 新鲜度（MANIFEST hash 对比）
# 期望：All tests passed.
# 如果 spec 过期：先 ./sync-specs.sh，再重新运行 Agent A，再运行 run_tests.sh
```

### 3.6 Mutation Verification

对关键安全/核心逻辑手动做 mutation，验证对应测试会失败。
结果记录到 `cliver-tests/mutation-log.md`。详见 `testing-setup.md`。

---

## Phase 4 — Wrap-up

```
[ ] impl.md status 改为 Verified ✓
[ ] impl.md 记录 known gaps（明确的，不是遗忘的空白）
[ ] tracker.md 所有行填完（Phase 状态、Checkpoint 执行情况、测试数字、gap 决策）
[ ] AGENT.md 的"当前状态"表格更新
[ ] CLAUDE.md 更新（如有新约束、命令、架构变化）
[ ] Commit（仅在用户要求时）
```

tracker.md 是三个 feature 文件里唯一"应该在开发过程中持续更新"的文件：
- `design.md`：开发前写好，标 final 后不动（除非 spec 升版）
- `impl.md`：记录实现决策和 bug，开发完成后基本稳定
- `tracker.md`：每个 phase/checkpoint 完成时更新一行，是开发过程的执行记录

---

## 关键文件速查

### 实现仓（`/home/gloria/tianyue/cliver/`）

| 文件 | 职责 |
|------|------|
| `src/parser.cj` | `.cj` 文件解析 → `Manifest` |
| `src/codegen.cj` | `Manifest` → `cli_driver.cj` 源码 |
| `src/main.cj` | 入口 + `_backendScriptTemplate()` |
| `src/dir.cj` | 路径规范化、文件收集 |
| `src/*_test.cj` | 单元测试（`cjpm test`） |
| `test/fixtures/` | 单元测试用 fixture |
| `sample_cangjie_package/test_backend.js` | 实现仓 backend 集成测试 |
| `scripts/build_and_test.sh` | 全量验证入口 |
| `dev-journal/features/*/design.md` | Feature spec（同步到测试仓） |

### 测试仓（`/home/gloria/tianyue/cliver-tests/`）

| 文件 | 职责 |
|------|------|
| `specs/` | 从实现仓同步来的 design.md |
| `specs/MANIFEST.json` | spec 版本 + sha256 记录（新鲜度校验） |
| `backend/test_protocol.js` | 独立协议测试（Agent A 写） |
| `gap-reports/` | Agent B 的 gap report 归档 |
| `mutation-log.md` | Mutation verification 记录 |
| `sync-specs.sh` | spec 单向同步 + MANIFEST 更新 |
| `run_tests.sh` | 统一测试入口（含新鲜度检查） |

---

## 测试框架约定

### 实现仓单元测试（`src/*_test.cj`）
- fixture 在 `test/fixtures/<name>/src/` 下，必须有 `src/` 子目录
- `parsePackage` 对无 `.cj` 文件的路径返回 `Some(空 Manifest)`，不报错

### 实现仓 Backend 测试（`test_backend.js`）
- `t.line`：发 `{ line: "..." }` 命令
- `t.sendMsg`：发任意静态消息对象
- `t.getMsg()`：延迟求值（用于状态依赖场景）
- `t.check(stdout, stderr, j)`：`j` 是原始 JSON 响应

### 测试仓协议测试（`test_protocol.js`）
- name 格式：`[feature][type] 行为描述`
- Type B 不变量测试直接用 `fs` 验证磁盘副作用，不只信任返回值

---

## 协议扩展约定（WebSocket 新消息类型）

1. 在 `_backendScriptTemplate()` 的 `ws.on('message', ...)` 最顶部加 `if (msg.type === '...') { handle...(ws, msg); return; }`
2. handler 函数放在 `unescapeLine` 和 `const server` 之间（全局可见）
3. 原有 `{ line: "..." }` 路径不受影响（向后兼容）
4. 在实现仓 `test_backend.js` 和测试仓 `test_protocol.js` 都加对应测试

---

## 不做的事（CLAUDE.md 约束摘要）

- 不改 Cangjie 函数签名（v1 限制：parser 只处理 public top-level 函数和构造器）
- 不支持泛型函数（`isGenericFuncDecl` 过滤掉）
- 不做 `index.html` UI 改动（Phase 2）
- object store 仅内存，不做持久化
- 生成的 driver 假设与 target 在同一 Cangjie package（不跨包 import）
