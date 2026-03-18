# Cliver 测试策略

> 这份文档回答：**对于 Cliver 这个项目，什么样的测试工作流能让"测试通过"这件事是可信的？**
> 落地方案见 [`testing-setup.md`](testing-setup.md)。

---

## 1. 两个根本性问题

**问题一：Cliver 是生成器，真正运行的是生成的代码**

存在两层正确性：
- 生成器层：Clive 生成了正确的代码（codegen 单元测试验证）
- 运行时层：生成的代码在运行时行为正确（集成测试验证）

两层都必须测。字符串断言通过 ≠ 生成的 Cangjie 代码能编译；编译通过 ≠ 运行时参数解析正确。

**问题二：代码和测试由同一个 agent 在同一 context 下生成，存在相关性**

如果 agent 对某个行为有误解，代码和测试都会携带这个误解，并以互相兼容的方式表现——测试绿灯，但测的是错误的东西。这不是 agent 特有的问题（人类开发者自测也有这个偏差），但 agent 的速度很快，容易在没有外部校验的情况下积累。

---

## 2. 结构性解法：测试仓与实现仓隔离

### 核心原则

写测试的 agent 在写测试时，**不能看到实现代码**。只能看到：
- 协议/行为规格文档（`design.md`）
- 已有的接口定义（消息格式、函数签名）
- 构建产物（binary、生成的 JS 文件）——作为被测对象，不作为测试设计的参考

### 仓库结构

```
cliver/              ← 实现仓（当前仓）
  src/               ← 实现代码（测试 agent 不可见）
  dev-journal/       ← 设计文档（spec 同步到测试仓）
  ...

cliver-tests/        ← 测试仓（独立 git 仓库）
  specs/             ← 从 cliver/dev-journal/features/ 同步来的规格
  backend/           ← WebSocket 协议测试
  fixtures/          ← Parser fixture 库
  unit/              ← 可独立运行的单元级断言
  run_tests.sh       ← 统一入口，接受 env var 指定 build artifacts
  sync-specs.sh      ← 从实现仓拉取最新 design.md
```

### 信息流向

```
cliver/dev-journal/features/*/design.md
        │  sync-specs.sh（单向同步）
        ▼
cliver-tests/specs/          ← 测试 agent 的信息来源（只读规格）
        │
        │  Agent A 读规格，写测试
        ▼
cliver-tests/backend/*.js    ← 测试代码（运行时连接 build artifacts）
cliver-tests/fixtures/       ← fixture 文件

cliver/ build artifacts ──────────────────────────────────────────┐
  (binary, cli_ws_server.js)                                       │
        │  CLIVER_BUILD_DIR 等 env var                             │
        └──────────────► run_tests.sh ◄────────────────────────────┘
```

---

## 3. 两个 Agent 的角色分工

### Agent A：Test Writer（只读规格，写测试）

**信息边界**：只能看 `cliver-tests/specs/`（设计文档）和 `cliver-tests/` 下已有的测试基础设施。不能看 `cliver/src/`。

**任务**：根据 spec 把所有描述的行为转化为测试用例，覆盖正常路径、错误路径、边界情况。

**输出**：测试代码。

**关键约束**：当 Agent A 觉得某个边界情况"实现里可能没有处理"，它**不应该**去看实现来确认——它应该写这个测试，让测试来发现。

### Agent B：Adversarial Reviewer（读规格 + 测试列表，不读实现）

**信息边界**：读 spec + Agent A 写完的测试的 **name 列表**（不读测试代码细节，不读实现）。

**任务**：
1. 对着 spec，找出没有对应测试的行为
2. 对着已有测试列表，找出覆盖维度上的空白（类型错误？并发？大文件？空值？）
3. 输出 **gap report**（缺少什么测试），不直接写测试

**输出**：gap report，交由人决定哪些需要补充。

**为什么是 gap report 而不是补充测试**：Agent B 不应该直接补充测试，因为它也没有看实现，无法验证自己补充的测试是否测了正确的东西。Gap report 是给人的决策输入，不是自动填充。

---

## 4. 四类测试的功能区分

不同类型的测试解决不同的置信度问题。

### Type A：规格测试（Specification Tests）

**解决**：确认系统做了规格要求的事
**来源**：从 spec 的正常路径推导
**例子**：`upload → 返回 upload_result，path 以 /tmp/cliver/uploads/ 开头`
**限制**：只能证明"规格里写到的功能实现了"，不能发现规格没写到的边界

### Type B：不变量测试（Invariant Tests）

**解决**：验证系统维护了应该始终成立的属性，包括副作用
**来源**：从系统承诺推导（不只是"返回了什么"，还有"做了什么"）
**例子**：
```
// Type A（只验证返回值）：
upload → j.type === 'upload_result' && j.path.startsWith(...)

// Type B（验证实际副作用）：
upload → j.type === 'upload_result'
       && fs.existsSync(j.path) === true
       && fs.readFileSync(j.path) 字节等于 Buffer.from(msg.data, 'base64')
```
**这是当前测试集最缺失的一类**。

### Type C：对抗性测试（Adversarial Tests）

**解决**：系统在非预期输入下的行为
**来源**：从攻击面、边界、错误路径推导——不从正常流程推导
**例子**：缺少必填字段、错误类型、路径穿越、空值、超长字符串
**Agent A 的价值在这里最明显**：没有看过实现的 agent 会问"spec 里说字段必填，那如果不填会怎样"，而看过实现的 agent 会下意识地只测它看到代码里处理了的情况。

### Type D：元测试（Mutation Verification）

**解决**：测试本身是否有效——如果代码有 bug，测试能抓住吗？
**方法**：故意破坏实现里的关键逻辑，验证测试失败
**例子**：
```bash
# 注释掉路径安全检查，跑测试
# if (!resolved.startsWith('/tmp/cliver/')) { ... }
# → 如果 traversal 测试没有失败，说明该测试无效
```
**这不需要自动化工具**，对关键安全/核心逻辑手动做，每次对应代码变更后重复一次。

---

## 5. Cliver 各层的具体建议

### Layer 1 — Parser（`src/parser.cj`）

**当前**：一个 `minimal_package` fixture
**需要**：按语言特性分类的 fixture 库（在 `cliver-tests/fixtures/` 下）

```
fixtures/
├── minimal/            ← hello + Box（当前有）
├── generic_functions/  ← 泛型函数，验证被过滤掉
├── private_public/     ← private/public 混合，验证 private 不出现
├── nested_package/     ← 嵌套目录，验证 packagePath 正确
├── operator_overload/  ← 运算符重载，验证不被包含
└── multiline_sig/      ← 多行签名，验证解析行为（已知可能不支持，需记录）
```

每个 fixture 由 Agent A 根据 Cangjie 语法规格设计，不参考 parser 实现。

### Layer 2 — 代码生成器（`src/codegen.cj`）

**关键认知**：字符串断言（当前做法）测的是"生成了这个字符串"，不是"这个字符串是有效的 Cangjie 代码"。

**实际可行的补充**：

1. 编译验证（已有，通过 `cjpm build` 集成测试覆盖）——这是 Layer 2 置信度的主要来源，应该明确依赖它
2. 结构性断言：验证生成代码中关键函数的存在、import 的完整性，而不是完整字符串匹配
3. 反向验证：对已知应该不生成的内容做断言（e.g., 泛型函数的 dispatcher 不应该出现）

### Layer 3 — 生成的 Driver 运行时（`cli_driver.cj`）

这一层的集成测试置信度已经是四层中最高的（直接运行生成代码）。可以补充的方向：

- ref ID 单调递增的不变量
- 错误命令返回明确 exit code 的验证
- 参数类型转换失败时的错误格式

### Layer 4 — WebSocket 协议（`cli_ws_server.js`）

**当前缺失，按优先级**：

| 优先级 | 测试 | 类型 |
|--------|------|------|
| P1 | upload 后 `fs.existsSync(path)` 和内容字节匹配 | Type B（不变量） |
| P1 | download 不存在的文件 → `download_error` | Type C（对抗性） |
| P2 | upload 缺少 `data` 字段 → `upload_error` | Type C |
| P2 | upload 缺少 `filename` 字段 → `upload_error` | Type C |
| P2 | download 相对路径穿越 → `download_error` | Type C |
| P3 | upload 无效 base64（当前静默写入，需先明确期望行为） | Type C |
| P3 | upload `filename` 为空字符串 | Type C |

**Mutation Verification 清单**（每次对应逻辑变更后手动验证）：

| 代码逻辑 | 应注释掉的行 | 必须失败的测试 | 当前有测试？ |
|---------|------------|--------------|------------|
| 路径安全检查 | `if (!resolved.startsWith(...))` | traversal 测试 | ✓ |
| `path.resolve()` 规范化 | 改为直接用 `msg.path` | 相对路径穿越测试 | ✗ 缺口 |
| filename sanitize | 改为空操作 | 含 `../` filename 测试 | ✗ 缺口 |
| `path.basename()` | 改为直接用 `msg.filename` | 路径注入 filename 测试 | ✗ 缺口 |

---

## 6. 测试工作流在 Feature 开发中的位置

```
Phase 0 — Design（实现仓）
  └─ 写 design.md
  └─ 从 design.md 提取"测试维度矩阵"（每个输入空间 × 正常/错误/边界/安全）

  [sync-specs.sh 把 design.md 同步到测试仓]

Phase 1 — 实现（实现仓）
  └─ 写代码
  └─ 写 Type A 初始测试（开发者自测，允许看实现）

Phase 2 — 独立测试生成（测试仓，Agent A）
  └─ Agent A 只读 specs/，写测试
  └─ 覆盖正常路径、错误路径、所有边界

Phase 2+ — 对抗性 Review（Agent B）
  └─ Agent B 读 spec + Agent A 的测试 name 列表
  └─ 输出 gap report
  └─ 人决定哪些 gap 必须补（P1/P2），哪些可接受（P3/known gap）

Phase 3 — Mutation Verification（手动，5-10 分钟）
  └─ 对 gap report 里标注的关键逻辑做 mutation 验证
  └─ 确认对应测试确实会失败

Phase 4 — 收尾
  └─ 在 impl.md 记录：已覆盖的测试类别 + 明确的 known gaps
  └─ 更新 AGENT.md 的状态表
```

---

## 7. 合理的测试边界（不过度测试）

以下情况在当前项目范围内明确不测：

- **并发上传**：没有并发安全承诺，UUID 前缀是 best-effort
- **文件大小限制**：没有大小限制语义
- **Cangjie 语法全集**：Parser 声称不支持的语法（泛型等）记录为 known limitation，不测全集
- **symlink 攻击**：需要本地写权限，超出当前威胁模型

这些边界必须在 `impl.md` 里显式记录（known gaps），和"忘了测"的情况区分开来。
