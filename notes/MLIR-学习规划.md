# MLIR 学习规划（面向零基础）

> 目标读者：没有任何编译器背景、但会用 C++ 的人。
> 总周期：约 3–4 个月（全职节奏），从零到能独立使用 MLIR 做项目。

---

## 0. 先说清楚：MLIR 是什么，为什么学它

**一句话**：MLIR 是一个"编译器基础设施框架"，你可以把它理解成一套**搭编译器的乐高积木**，它把编译器里最琐碎、最重复的部分（定义中间表示、管理优化流程、做代码变换）标准化了，让你专注于自己的领域逻辑。

**几个关键认知，先种下：**

- **MLIR 不是一种编程语言**，而是一个"元框架"——它不规定你的编译器长什么样，而是给你一套工具去*自定义*你的编译器。
- 它诞生于 Google（Chris Lattner 团队，后来进 LLVM 官方项目），最初动机是解决**机器学习编译器**里 IR 种类爆炸的问题：各种框架（TensorFlow、PyTorch）、各种硬件（GPU、TPU、NPU）之间的转换需要写 O(N×M) 个桥接，MLIR 想把它降成 O(N+M)。
- 你不需要先精通编译原理才能开始，但需要**会用 C++**（这是硬门槛，见阶段 0）。

**你最终会得到什么能力**：能读懂 MLIR 代码、能自己定义一个"方言"（Dialect）、能写优化 Pass、能把自定义语言降级到 LLVM 生成机器码。

---

## 阶段 0：前置知识准备（1–2 周，视基础而定）

### 0.1 C++（必修，最重要）

MLIR 本体是 C++17 写的，所有 API 都是 C++。**C++ 不行，后面寸步难行。**

最低要求：
- 类、继承、虚函数、模板、智能指针（`unique_ptr`/`shared_ptr`）
- `std::vector`、`std::map`、`std::function`
- 移动语义（MLIR 里大量使用，`std::move` 到处都是）
- CMake 基础（会用 `cmake -G Ninja` 和看懂 `target_link_libraries`）

不需要 C++ 专家，但**模板和虚函数一定要过一遍**。

### 0.2 编译原理最小知识（不需要整本龙书）

只需要理解这几个概念，MLIR 就能读下去：

| 概念 | 大白话 |
|---|---|
| **编译器** | 把一种语言翻译成另一种语言（通常是机器能跑的）的程序 |
| **中间表示（IR）** | 编译过程中"半加工"的代码形式，介于源码和机器码之间 |
| **前端 / 后端** | 前端负责"读懂源码变成 IR"，后端负责"IR 变成机器码" |
| **优化（Pass）** | 对 IR 做的等价变换，让它更快更小 |
| **SSA** | 每个变量只能被赋值一次，是现代 IR 的基石（后面详讲） |

**推荐**：《Crafting Interpreters》（前几章讲词法/语法分析的直觉，免费在线）或任何一本编译原理的"IR + 优化"章节，不用啃语法分析细节。

### 0.3 把环境搭起来（第一天就做）

```bash
git clone https://github.com/llvm/llvm-project.git
mkdir llvm-project/build && cd llvm-project/build
cmake -G Ninja ../llvm \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD="Native"
ninja -j$(nproc)
```

> 提示：MLIR 只需要 `mlir` 这一个 project，不用编译整个 LLVM。`-DLLVM_TARGETS_TO_BUILD="Native"` 能大幅减少编译时间。熟悉后用 `ninja check-mlir` 跑测试。

**产出物**：`build/bin/mlir-opt`（MLIR 的瑞士军刀，能解析、运行 pass、输出 IR）能跑起来。

> 更详细的逐步教程见《MLIR-零基础起步教程.md》。

---

## 阶段 1：MLIR 核心概念（2–3 周）

这一阶段是**整个学习的重中之重**。不要急着写代码，先把这些概念在脑子里建立成一张图。

### 1.1 一切皆 Operation（Op）

MLIR 里最基本的单位不是"语句"，而是 **Operation（运算）**。一个 Op 有：

```mlir
%result = arith.addi %a, %b : i32
```

拆开看：
- `arith.addi` —— Op 的名字（`addi` = add integer，属于 `arith` 方言）
- `%a, %b` —— 操作数（operands）
- `%result` —— 结果（result）
- `i32` —— 类型（type）

**MLIR 最大的自由度**：你可以自定义 Op 长得什么样、叫什么名字、有什么语义。这是它区别于传统 IR（如 LLVM IR）的核心——LLVM IR 是"固定菜单"，MLIR 是"自助厨房"。

### 1.2 方言（Dialect）

**Dialect = 一组相关 Op、类型、属性的集合**。它把 IR 按"抽象层次"和"领域"分门别类。

常见方言，从"高级"到"低级"排个序，你会在学习路上反复遇到：

| 方言 | 抽象层次 | 干什么的 |
|---|---|---|
| `tosa` | 很高 | 机器学习算子（卷积、矩阵乘…） |
| `linalg` | 高 | 线性代数运算 + 循环的通用表示 |
| `affine` | 中 | 带约束的循环嵌套（多面体优化） |
| `scf` | 中 | 结构化控制流（`for`/`if`/`while`） |
| `arith` | 低 | 整数/浮点算术 |
| `func` | 低 | 函数定义/调用 |
| `memref` | 低 | 内存缓冲区的抽象 |
| `cf` | 很低 | 底层控制流（分支、跳转） |
| `llvm` | 最低 | 直接对应 LLVM IR，交接给后端 |

**关键直觉**：编译 = 把代码从"高抽象方言"一路"降级"（lowering）到"低抽象方言"的过程。每一级丢失一些高层信息，换取离机器更近。

### 1.3 SSA（单静态赋值）

**规则**：每个值只能被赋值一次，一旦定义就不可变。

```mlir
%0 = arith.constant 1 : i32      // %0 永远是 1
%1 = arith.addi %0, %0 : i32     // %1 永远是 2
```

为什么这么设计？因为**不变量好优化、好分析**——编译器可以放心地复用、移动、删除一个值，不用担心它后来被改过。这是现代编译器 IR 的通用设计，LLVM IR 和 MLIR 都基于它。

### 1.4 Region 与 Block

一个 Op 可以**包含代码**，这些代码组织成 Region（区域），Region 里是 Block（基本块），Block 里是 Op。

```
Op（外层）
 └─ Region
     ├─ Block（入口块）
     │    ├─ Op
     │    └─ Op
     └─ Block
          └─ Op
```

最常见的例子是函数：

```mlir
func.func @main() {
  // 这里 {} 里的就是一个 Region，包含一个 Block
  %0 = arith.constant 0 : i32
  return
}
```

**这是 MLIR 最优雅的设计之一**：连"函数体""循环体""条件分支"都是"Op 里套 Region"，所有结构都统一成一个递归概念。理解了这点，你看任何 MLIR 代码都不会慌。

### 1.5 Type 与 Attribute

- **Type**：值的类型（`i32`、`f32`、`memref<4xf32>`）
- **Attribute**：Op 上附带的**编译期常量信息**（比如 `arith.constant 5` 里的 `5`，或循环步长）

直觉：Type 描述"这是什么"，Attribute 描述"关于这个 Op 的固定参数"。

### 1.6 一个完整的例子，串起所有概念

```mlir
func.func @add_two(%arg0: i32) -> i32 {
  %c2 = arith.constant 2 : i32
  %sum = arith.addi %arg0, %c2 : i32
  return %sum : i32
}
```

- `func.func` 是 `func` 方言的 Op，带一个 Region（函数体）
- `@add_two` 是符号名（symbol）
- `%arg0` 是 Block 参数（block argument），`-> i32` 是返回类型
- `arith.constant`、`arith.addi` 是 `arith` 方言的 Op
- `2` 是 Attribute，`i32` 是 Type

**这一阶段完成标志**：不看注释能读懂上面这段，并能回答"这里面有几个方言、几个 Op、SSA 体现在哪"。

---

## 阶段 2：MLIR 基础设施——"写 Pass 的工具"（3–4 周）

懂了概念之后，开始学"怎么动手改代码"。这阶段会大量查官方文档（见资源清单）。

### 2.1 TableGen 与 ODS（Op 定义）

MLIR 用 **TableGen**（一种声明式 DSL）来定义 Op，这叫 **ODS（Op Definition Specification）**。

你写一个 `.td` 文件描述"我的 Op 叫什么、有哪些操作数、结果、约束"，然后构建系统自动生成 C++ 样板代码。**这是 MLIR 工程效率的核心**：定义 Op 基本不用手写冗长的 C++。

先学会"读"已有的 `.td` 文件（比如 `arith` 方言的），再尝试自己定义一个简单 Op。

### 2.2 Pass 与 PassManager

**Pass = 对 IR 的一次变换/优化**。PassManager 负责按顺序、按嵌套结构调度这些 Pass。

要分清几种 Pass 的作用范围：
- 作用在**一个 Op 上**（最常见的，比如把某个 Op 替换成另一个）
- 作用在**整个 Module** 上（全局分析）
- **转换 Pass（Conversion Pass）**：方言之间的降级，会改变 IR 的"抽象层次"

学会用 `mlir-opt` 命令行手动跑 pass、观察 IR 变化，是最快的反馈循环：

```bash
mlir-opt input.mlir -pass-pipeline='builtin.module(func.func(canonicalize))'
```

### 2.3 Pattern Rewriting（模式重写）与 DRR

写 pass 最常见的做法是 **pattern rewriting**：定义"如果看到形如 X 的代码，就替换成形如 Y 的代码"。

- 手写 C++ 的 `RewritePattern`
- 或者用 **DRR（Declarative Rewrite Rules）**，同样写在 `.td` 里，声明式地写"模式 → 替换"

例如一个很经典的优化——**折叠常量**：

```mlir
// 匹配: %r = arith.addi 1, 2
// 替换: %r = arith.constant 3
```

### 2.4 Trait、Interface、Verifier

- **Trait**：给 Op 贴的"能力标签"（如 `Commutative` 可交换、`NoSideEffect` 无副作用），Pass 靠这些标签决定能不能安全地做优化
- **Interface**：跨方言的通用接口（如 `CallOpInterface`），让 pass 不关心具体是哪个方言
- **Verifier**：校验 Op 是否合法（操作数类型对不对、约束满不满足），出错时给出友好报错

### 2.5 读懂 MLIR 源码的结构

开始逛 llvm-project 源码，重点看 `mlir/include/mlir/`：
- `mlir/IR/` —— Operation、Value、Type、Attribute 的核心定义
- `mlir/Dialect/Arith/`、`mlir/Dialect/Func/` —— 简单方言的好例子
- `mlir/Transforms/` —— 通用 pass

**这一阶段完成标志**：能独立定义一个只有一个 Op 的方言，写一个 pass 把它 lower 成 `arith`，并用 `mlir-opt` 跑通。

---

## 阶段 3：官方 Toy Tutorial（2–3 周，全程动手）

这是 MLIR 官方为新手设计的**旗舰教程**：用 MLIR 从零实现一个叫 "Toy" 的小语言（类似简化版 TensorFlow），一共 7 章，每章讲一层概念。

**务必一行一行跟着敲，不要只看。**

| Chapter | 讲什么 | 你会学到 |
|---|---|---|
| Ch1 | 词法/语法分析，构建 AST | 前端基础 |
| Ch2 | 发射 MLIR，定义第一个方言 `toy` | ODS、定义 Op |
| Ch3 | 用 ODS 定义 Operation | TableGen 语法 |
| Ch4 | 形状推导 | Op 上做分析、Interface |
| Ch5 | 降级：把部分 `toy` 换成 `affine` | Conversion Pass、Pattern Rewriting |
| Ch6 | 进一步降到 `llvm` 方言，生成机器码 | 多层 lowering、代码生成 |
| Ch7 | 组合优化、扩展方言 | 完整的端到端流程 |

**学完 Toy，你就走完了"源码 → 多种方言 → LLVM 机器码"的全流程**，这是 MLIR 学习的分水岭。

---

## 阶段 4：实战项目（4–6 周）

教程是"照葫芦画瓢"，实战才是"真的会了"。按难度递进选一两个：

### 4.1 入门：给现有方言写优化 Pass
- 给 `arith`/`affine` 写一个常量折叠、死代码消除之类的 pass
- 目标：用 pattern rewriting 完整实现 + 写测试

### 4.2 进阶：定义一个自己的方言
- 做一个你自己感兴趣的领域语言：一个栈式机、一个正则引擎、一个表达式语言……
- 完整走一遍：ODS 定义 → verifier → lowering → 跑起来

### 4.3 贴近真实世界：接触 MLIR 的"杀手级应用"
MLIR 目前最大的应用场景是**机器学习编译器**和**硬件设计**，选一个方向深入：

- **AI 方向**：学习 `linalg`、`tensor`、`tosa` 方言，理解 `mlir-hlo` / IREE / Torch-MLIR 这些项目（把 PyTorch 编译到各种硬件）
- **硬件方向**：学习 Calyx、CIRCT（芯片设计）、Handshake（异步电路）等

### 4.4 参与社区（可选但推荐）
- 读 `mlir/docs/` 下的设计文档（很多写得很清楚）
- 上 [MLIR Discourse](https://discourse.llvm.org/c/mlir/31) 潜水、提问
- 从给文档挑错、修小 bug 开始提 PR

---

## 阶段 5：深入方向（长期，按兴趣）

到这里你已经不是零基础了，可以按兴趣深入：

- **代码生成 / 后端**：如何从 MLIR 生成 LLVM IR，理解 ABI、调用约定
- **多面体优化**：`affine` 方言背后的数学，性能优化的深水区
- **Type/量化系统**：MLIR 的量化（quantization）机制
- **自定义 Pass 基础设施**：Pass 之间如何通信、分析结果如何缓存复用

---

## 学习路线总览（一图流）

```
阶段0 前置知识      →  C++ / 编译最小知识 / 搭环境        (1-2周)
阶段1 核心概念      →  Op / Dialect / SSA / Region / Type (2-3周)  ← 最关键
阶段2 基础设施      →  ODS / Pass / Rewriting / Trait     (3-4周)
阶段3 Toy Tutorial  →  端到端实现一个小语言                (2-3周)  ← 分水岭
阶段4 实战项目      →  写 pass / 自定义方言 / 真实项目      (4-6周)
阶段5 深入方向      →  代码生成 / 多面体 / 量化...          (长期)
```

总计约 **3–4 个月**从零到能独立使用 MLIR 做项目（全职学习节奏）。

---

## 资源清单

**官方（最权威，务必优先）**
- [MLIR 官方文档](https://mlir.llvm.org/) —— 尤其是《MLIR Language Reference》和 `Dialects` 索引
- [Toy Tutorial](https://mlir.llvm.org/docs/Tutorials/Toy/) —— 阶段 3 的主线
- [MLIR 设计文档](https://mlir.llvm.org/docs/Rationale/) —— 讲"为什么这么设计"，培养品味
- 源码里的 `mlir/docs/` 和 `mlir/test/`（**test 是最好的学习材料**，全是小而精的例子）

**入门讲解（帮助建立直觉）**
- Chris Lattner 的演讲《MLIR: A Compiler Infrastructure for the End of Moore's Law》—— 讲动机和愿景，很有感染力
- 博客/知乎上搜"MLIR 入门"系列，很多中文教程质量不错（如"MLIR 学习笔记"系列）
- 《Getting Started with MLIR》类博客（如 Tavi Twary / Johnny's Software Lab 的文章）

**需要时再查**
- 《Engineering a Compiler》（比龙书更现代、更工程化，查"IR 设计""优化"章节用）
- TableGen 官方文档（写 ODS 时反复翻）

---

## 给零基础者的几条实战建议

1. **先把环境跑起来，再谈概念**。`mlir-opt` 能跑起来，你就有了一块"试错的沙盘"，边学边敲命令验证，比纯看书快十倍。
2. **`mlir-opt` + `-mlir-print-ir-*` 是你的显微镜**。学习任何 pass，先手动跑一遍、看 IR 前后变化，形成直觉。
3. **读 test 文件**。`mlir/test/` 里有海量 `.mlir` 文件，每个都是"输入 → 期望输出"，是零成本的范例库。
4. **不要一上来就啃 LLVM IR 后端**。先在高抽象方言（`arith`/`affine`/`scf`）里打转，抽象层次越高越容易看懂。
5. **先模仿，再创造**。定义自己的方言时，从 copy 一个简单官方方言（`arith` 或 Toy）改起，别从零写。
6. **卡住时去 Discourse 搜**。MLIR 社区活跃且友好，你踩的坑大概率有人问过。
