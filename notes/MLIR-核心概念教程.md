# MLIR 核心概念保姆级教程

> 本文是《MLIR 学习规划》**阶段 1** 的展开版。
> 前置：已完成阶段 0（《MLIR-零基础起步教程.md》），`mlir-opt` 能跑起来。
> 目标：把 MLIR 里最核心的几个概念——**Op / Dialect / SSA / Region / Block / Type / Attribute / Symbol**——在脑子里建成一张能互相勾连的图。
> 方法：**每个概念都配一段能跑、能改的 `.mlir` 代码**。这一阶段不写 pass，只"读"和"跑"，用 `mlir-opt` 当显微镜。

***

## 第 0 步：本阶段学什么、怎么学（先看地图再走路）

阶段 1 是整个学习里**最重要的一环**，但它的任务很纯粹：**看懂 IR，而不是动手写变换代码**。

后面阶段 2 学 TableGen、写 Pass，阶段 3 做 Toy Tutorial——那些都是在"操作"这些概念。如果概念没建立好，后面会一直"似懂非懂"。所以这一阶段慢一点、深一点，是完全值得的。

**本阶段要回答的 8 个问题：**

1. Op 长什么样？它由哪几部分组成？
2. Dialect 是什么？为什么 IR 里到处都是 `arith.`、`func.` 这种前缀？
3. SSA 是什么规则？为什么它让编译器更好写？
4. Region 和 Block 是什么？它们和 Op 是什么关系？
5. Type 和 Attribute 有什么区别？
6. Symbol（符号）是什么？`@` 开头代表什么？
7. 控制流（`if`/`for`）在 MLIR 里怎么表示？它如何和 SSA 配合？
8. 给我一段完整代码，我能不能数出几个方言、几个 Op、SSA 体现在哪？

先建一个实验台，后面每一步都在这里敲命令：

```bash
mkdir -p ~/mlir-playground/concepts
cd ~/mlir-playground/concepts
```

> 提醒：如果 `mlir-opt` 还没加进 PATH，先 `export PATH=$HOME/llvm-project/build/bin:$PATH`（阶段 0 讲过）。

***

## 第 1 步：一切皆 Operation（Op）——MLIR 的原子单位

### 1.1 一个 Op 的解剖

MLIR 里最基本的单位**不是"语句"，而是 Operation（运算）**。看这个老朋友：

```mlir
%result = arith.addi %a, %b : i32
```

把它拆成五块：

| 部分 | 例子 | 含义 |
|---|---|---|
| **Op 名** | `arith.addi` | 这个 Op 叫什么（点号前 `arith` 是方言，点号后 `addi` 是具体 Op） |
| **操作数** | `%a, %b` | 输入的值（operands） |
| **结果** | `%result` | 输出，给这个结果起的名字 |
| **类型** | `: i32` | 结果（以及操作数）的类型 |
| **（可选）属性** | 后面会讲 | 附在 Op 上的编译期常量 |

**关键认知**：MLIR 最大的自由度在于——**Op 长什么样、叫什么名字、有什么语义，全都可以由你自定义**。传统 IR（比如 LLVM IR）是"固定菜单"，只有有限的几条指令；MLIR 是"自助厨房"，你自己发明菜。这也是它区别于所有传统 IR 的核心。

### 1.2 甜头写法 vs 通用写法（重要，先记住）

上面 `%result = arith.addi %a, %b : i32` 这种写法，其实是**"定制语法糖"（custom syntax / pretty form）**——每个方言可以自己决定"我这个 Op 用什么样的漂亮写法"。

但 MLIR 内部真正存储的是一个**统一的、啰嗦的通用格式**。跑一下：

```bash
cat > add.mlir <<'EOF'
func.func @main() -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %c = arith.addi %a, %b : i32
  return %c : i32
}
EOF

mlir-opt add.mlir --mlir-print-op-generic
```

输出大致长这样（不同版本细节略有差异，但骨架一致）：

```mlir
"builtin.module"() ({
  "func.func"() <{sym_name = "main", function_type = () -> i32}> ({
  ^bb0:
    %0 = "arith.constant"() <{value = 1 : i32}> : () -> i32
    %1 = "arith.constant"() <{value = 2 : i32}> : () -> i32
    %2 = "arith.addi"(%0, %1) : (i32, i32) -> i32
    "func.return"(%2) : (i32) -> ()
  }) : () -> ()
}) : () -> ()
```

**从这段通用格式里，你能看出 Op 的"真实内部结构"：**

- `"arith.addi"(...)` —— Op 名是用**字符串**存的
- `<{value = 1 : i32}>` —— 这是**属性（Attribute）**，用尖括号包着
- `: (i32, i32) -> i32` —— 操作数类型 `(i32, i32)`，结果类型 `i32`
- `^bb0:` —— 这是**块（Block）**的名字，后面详讲
- 最外层 `builtin.module` 包着 `func.func`——**连"整个文件"都是一个 Op（module），它内部再套别的 Op**

一个 Op 内部完整的组成是这 5 样东西（现在先记住名字，后面逐个展开）：

```
Operation
 ├─ 结果值（results）
 ├─ 操作数（operands）
 ├─ 属性（attributes）        ← 第 6 步讲
 ├─ 后继块（successors）      ← 第 8 步控制流时讲
 └─ 区域（regions）           ← 第 5 步讲
```

> **把这一刻焊进脑子**：`mlir-opt --mlir-print-op-generic` 是你以后拆解任何 IR 的"X 光机"。遇到看不懂的 Op，先跑这个命令看它的通用格式，什么都能看清。

### 1.3 亲手验证

```bash
# 试试这两个命令，对比"漂亮写法"和"通用写法"
mlir-opt add.mlir                         # 漂亮写法（默认）
mlir-opt add.mlir --mlir-print-op-generic # 通用写法（内部真相）
```

***

## 第 2 步：方言（Dialect）——Op 的"家族"

### 2.1 为什么要有方言

上一节看到 Op 名是 `arith.addi`、`func.func`，中间都有个点。这个点号前面的 `arith`、`func` 就是**方言（Dialect）**。

**Dialect = 一组相关的 Op、类型、属性的集合**，它把 IR 按"抽象层次"和"领域"分门别类。为什么要分？因为 MLIR 想同时容纳"高高在上的机器学习算子"和"贴地的机器指令"，如果不分类，所有 Op 挤在一个命名空间里会乱成一锅粥。方言给它们划了"家族"。

### 2.2 一条"抽象层次的楼梯"

不同方言的抽象层次高低不同。编译的本质，就是让代码**沿着这架楼梯一级一级往下走（lowering，降级）**，每下一级丢掉一些高层信息，换取离机器更近。

| 方言 | 抽象层次 | 干什么的 | 你会见到的典型 Op |
|---|---|---|---|
| `tosa` | 很高 | 机器学习算子（卷积、矩阵乘…） | `tosa.conv2d`、`tosa.matmul` |
| `linalg` | 高 | 线性代数运算 + 循环的通用表示 | `linalg.matmul`、`linalg.generic` |
| `affine` | 中 | 带约束的循环嵌套（多面体优化） | `affine.for`、`affine.load` |
| `scf` | 中 | 结构化控制流（`for`/`if`/`while`） | `scf.for`、`scf.if` |
| `arith` | 低 | 整数/浮点算术 | `arith.addi`、`arith.constant` |
| `func` | 低 | 函数定义/调用 | `func.func`、`func.call` |
| `memref` | 低 | 内存缓冲区的抽象 | `memref.alloc`、`memref.load` |
| `cf` | 很低 | 底层控制流（分支、跳转） | `cf.br`、`cf.cond_br` |
| `llvm` | 最低 | 直接对应 LLVM IR，交接给后端 | `llvm.add`、`llvm.func` |

**关键直觉**：同一段计算，可以用不同方言"说"。比如"两个数相加"，既可以是 `arith.addi`（低层、直接），未来也会被 lower 成 `llvm.add`（贴机器）。方言就是"语言的层次"。

### 2.3 怎么认一个 Op 属于哪个方言

看第一个词点号前面的部分：

```mlir
arith.addi   → 方言 arith，Op addi
func.func    → 方言 func，Op func
scf.for      → 方言 scf，Op for
```

没点号的？`return` 其实是 `func.return` 的简写（`func` 方言给了它一个不用写全名的便利写法）。`builtin.module` 属于内置方言 `builtin`。

> 你在阶段 0 遇到的报错 `unknown dialect`，意思就是"这个方言没被链接进当前工具"。MLIR 的方言是可以**按需编译进来**的——这是它模块化设计的体现：你只需要你用到的那几个方言。

***

## 第 3 步：SSA（单静态赋值）——为什么每个值只能用一次名字

### 3.1 规则

**每个值只能被赋值一次，一旦定义就不可变。**

```mlir
%0 = arith.constant 1 : i32      // %0 永远是 1
%1 = arith.addi %0, %0 : i32     // %1 永远是 2
```

你**不能**写：

```mlir
%x = arith.constant 1 : i32
%x = arith.constant 2 : i32   // ❌ 非法！%x 已经被定义过了
```

要"改"一个值，只能**新建一个名字**：

```mlir
%x = arith.constant 1 : i32
%x2 = arith.addi %x, %x : i32   // ✅ 新值 %x2，%x 保持 1
```

### 3.2 为什么这么"反人类"？

因为**不可变 → 好分析**。一旦 `%0` 定义为 1，编译器可以放心地：

- 把它移动到任何地方（它的值不会变）
- 复制它、删除它（不会影响别处）
- 复用它的计算结果（不会有"中途被改过"的担心）

如果变量可以随便改（像 C 那样），编译器做任何优化都得先费劲地证明"这个值在这里没被改过"。SSA 把这个负担直接消掉了。**SSA 是现代编译器 IR（LLVM IR、MLIR 都是）的通用基石。**

### 3.3 一个隐含规则：先定义，后使用

SSA 还有一个附带规则：**一个值必须在使用之前定义**（术语叫"支配关系 dominance"）。反过来讲，这也意味着你**无法引用"未来"的值**。所以循环里的"累加"没法用普通变量表达——这引出下一节的重要角色：**块参数（block argument）**。

先跑个反例感受报错：

```bash
cat > bad_ssa.mlir <<'EOF'
func.func @main() -> i32 {
  %c = arith.addi %a, %b : i32   // %a、%b 还没定义！
  return %c : i32
}
EOF

mlir-opt bad_ssa.mlir
# 报错大致是：use of undeclared SSA value name '%a'
```

**学会读这类报错**，是独立学习的关键能力。

***

## 第 4 步：Region 与 Block——Op 里还能套代码

### 4.1 递归的嵌套结构

MLIR 最优雅的设计之一：**一个 Op 可以包含代码，这些代码组织成 Region（区域）→ Block（块）→ Op（运算）的递归结构。**

```
Op（外层，比如 func.func）
 └─ Region（区域，一个 Op 可以有多个 Region）
     ├─ Block（入口块）
     │    ├─ Op
     │    └─ Op
     └─ Block（另一个块）
          └─ Op
```

我们熟悉的函数就是活例子：

```mlir
func.func @main() -> i32 {      // 这个 { ... } 里就是一个 Region
  %0 = arith.constant 0 : i32
  return                        // 每个 Block 结尾必须有个"终结 Op"
}
```

- `func.func` 这个 Op 里套着一个 Region
- 这个 Region 里有一个 Block
- Block 里有两个 Op：`arith.constant` 和 `return`

**为什么说这很优雅？** 因为"函数体""循环体""条件分支"这些看似不同的东西，全都统一成了同一个递归概念——"Op 里套 Region"。理解了这一点，你看任何 MLIR 都不会慌：它无非就是"Op 套 Op，有的 Op 肚子里有 Region，Region 里又有 Block，Block 里又有 Op"。

### 4.2 Block 的两件重要的事

1. **每个 Block 的最后一个 Op 必须是"终结符"（Terminator）**——它决定"接下来跳去哪"或"把什么值传出去"。函数体的 `return` 就是终结符（它是 `func.return`）。

2. **Block 可以有参数（block argument）**——这是理解 SSA 和控制流的关键。函数参数本质就是"入口块的块参数"：

```mlir
func.func @add_two(%arg0: i32) -> i32 {   // %arg0 就是入口块的块参数
  %c2 = arith.constant 2 : i32
  %sum = arith.addi %arg0, %c2 : i32
  return %sum : i32
}
```

`%arg0` 不是"凭空冒出来的变量"，它是**函数入口块的一个参数**——调用者调用这个函数时，把实参"塞进"这个块参数里。这样既保持了 SSA（`%arg0` 只被赋值这一次），又能把值传进来。

***

## 第 5 步：Type 与 Attribute——"是什么"和"关于它的常量"

这两个词经常一起出现，但职责完全不同，一定要分清。

### 5.1 Type（类型）：描述值"是什么"

Type 描述**一个值的类型**。常见的有：

| 写法 | 含义 |
|---|---|
| `i32` | 32 位整数 |
| `i1` | 1 位整数（就是布尔） |
| `f32` | 32 位浮点 |
| `index` | 机器相关的整数（常用作循环下标、索引） |
| `memref<4xf32>` | 一块内存：4 个 f32 的缓冲区 |
| `tensor<4xf32>` | 4 个 f32 的张量（不可变、适合优化） |

### 5.2 Attribute（属性）：附在 Op 上的"编译期常量"

Attribute 描述**关于这个 Op 的固定参数**——它是编译期就确定的常量信息，不是运行时的值。

最典型的例子是常量 Op 里的那个数：

```mlir
%a = arith.constant 42 : i32
```

- `42` 是**属性**（一个 IntegerAttr），它是"这个常量 Op 到底是多少"的固定信息
- `i32` 是**类型**（Type），它是"这个结果是什么类型"

再比如函数名也是一个属性：

```mlir
func.func @main() -> i32 { ... }
```

`@main` 这个符号名，在内部就是存成 Op 的一个 `sym_name` 属性（回顾第 1 步通用格式里的 `<{sym_name = "main"}>`）。

### 5.3 一句话记法

> **Type 回答"这个值是什么"；Attribute 回答"关于这个 Op 的某个固定事实"。**

***

## 第 6 步：Symbol（符号）——`@` 开头的名字

MLIR 里，`@` 开头的名字是**符号（Symbol）**，代表一个"有名字的、可被引用的实体"——最常见的就是函数名：

```mlir
func.func @main() -> i32 { ... }      // 定义了一个叫 main 的符号
```

```mlir
func.func @caller() {
  func.call @main() : () -> i32       // 引用 main 这个符号
  return
}
```

几个要点：

- `%` 开头的是**值（value）**，`@` 开头的是**符号（symbol）**——两者不要混。
- 符号是"全局"的、有名字的；值是"局部"的、匿名的（或者被 `%名字` 临时命名）。
- 某些 Op 天然是**符号表（Symbol Table）**：`builtin.module` 和 `func.func` 都能"容纳"符号定义。比如 `func.func` 内部可以定义嵌套的私有函数符号。
- 符号让"函数、全局变量、模块"这些"跨作用域、按名字引用"的东西成为可能，是 MLIR 支持"多函数、多模块"的基础设施。

> 阶段 1 你只需要知道：**`@` = 符号 = 有名字、可被引用**。符号表、符号引用的深入机制留到真正写多函数程序时再细看。

***

## 第 7 步：控制流——Region / Block / SSA 的汇合点（本阶段最难也最精彩）

前面几个概念是分开讲的，现在用**控制流**把它们串起来，你会瞬间明白它们为什么这么设计。

### 7.1 用 `scf.if` 看"块参数 + SSA"

写一个绝对值函数，跑起来：

```bash
cat > abs.mlir <<'EOF'
func.func @abs(%x: i32) -> i32 {
  %c0 = arith.constant 0 : i32
  %is_neg = arith.cmpi slt, %x, %c0 : i32     // slt = 有符号小于，结果是 i1（布尔）
  %r = scf.if %is_neg -> (i32) {
    %neg = arith.subi %c0, %x : i32
    scf.yield %neg : i32                      // 把结果"交出去"
  } else {
    scf.yield %x : i32
  }
  return %r : i32
}
EOF

mlir-opt abs.mlir
```

逐块读：

- `%is_neg = arith.cmpi slt, %x, %c0 : i32` —— 比较 `%x < 0`，结果是 `i1`（真/假）。
- `scf.if %is_neg -> (i32) { ... } else { ... }` —— 一个 `scf` 方言的 if 运算，**它带着两个 Region**（then 分支和 else 分支）。
- `scf.yield %neg : i32` —— 分支的终结符，把本分支的结果"产出"给外面。
- 最终 `%r = scf.if ...` —— `scf.if` 本身是一个**有结果的 Op**，`%r` 接收它产出的值。

**这里 SSA 和块参数配合得极妙**：两个分支各自在**自己的 Region/Block 里**算出一个值，谁都不会"改"别人的值（各自独立、互不干扰），最后由 `scf.if` 统一选出该返回哪个。**没有赋值，只有"每个块各自产出结果，再由父 Op 选择"**——这就是 SSA 精神在控制流里的体现。

### 7.2 用 `scf.for` 看"循环里怎么累加"

循环里"累加"怎么在 SSA 下做？答案还是**块参数**：

```bash
cat > loop.mlir <<'EOF'
func.func @sum(%n: index) -> index {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %sum = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %c0) -> (index) {
    %acc_next = arith.addi %acc, %i : index
    scf.yield %acc_next : index
  }
  return %sum : index
}
EOF

mlir-opt loop.mlir
```

关注这一行：

```mlir
scf.for %i = %c0 to %n step %c1 iter_args(%acc = %c0) -> (index)
```

> **为什么这里全用 `index` 而不是 `i32`？** 因为 `scf.for` 的循环变量 `%i` **天生就是 `index` 类型**——它是"机器相关的整数"，专门用来做循环下标、数组索引这类事，和具体宽度（32/64 位）解耦。循环的上下界、步长、累加器都得和它同类型才能相加。如果你确实需要一个 `i32`，可以在循环里用 `arith.index_cast` 转换，但入门阶段记住"循环用 `index`"就够。

- `%i` —— 循环变量，**它其实也是一个块参数**，每次迭代由循环"塞进"新的值。
- `iter_args(%acc = %c0)` —— 循环携带的变量，初始值 `%c0`（也就是 0）。
- 循环体里 `%acc_next = arith.addi %acc, %i`，然后 `scf.yield %acc_next` —— **把新值交回给循环**，成为下一轮的 `%acc`。
- 循环结束后，`%sum` 拿到最后一轮的 `%acc`。

**看懂了吗？** 累加不是"改 `%acc` 的值"，而是"每一轮产出新的 `%acc_next`，交回去，下一轮它成了新的块参数 `%acc`"。**SSA 里没有"修改"，只有"传递新值"。**

> 这就是块参数存在的意义：**在保持 SSA（每个值只定义一次）的前提下，实现"循环携带值"和"条件分支传值"**。如果你能跟人讲清楚 `scf.for` 里 `iter_args` 是怎么借块参数实现累加的，SSA 和 Block 这两个概念你就真正吃透了。

### 7.3 一眼看懂嵌套结构

用 `--mlir-print-op-generic` 再看一次 `abs.mlir`，你会亲眼看到 `scf.if` 内部有两个 Region（两个 `^bb`）：

```bash
mlir-opt abs.mlir --mlir-print-op-generic
```

输出里 `"scf.if"(%is_neg) ({ ... }) ({ ... })` 这样的结构——**两个圆括号里各装着一个 Region**，每个 Region 里一个 Block。这就是第 4 步那个递归图在真实 IR 里的样子。

***

## 第 8 步：完整验收——能不能数出"几个方言、几个 Op、SSA 在哪"

用《学习规划》里的完整例子收尾：

```mlir
func.func @add_two(%arg0: i32) -> i32 {
  %c2 = arith.constant 2 : i32
  %sum = arith.addi %arg0, %c2 : i32
  return %sum : i32
}
```

**逐项标注（对着读一遍）：**

- `func.func` —— `func` 方言的 Op，带一个 Region（函数体）
- `@add_two` —— **符号名（Symbol）**
- `%arg0` —— **块参数（block argument）**，函数入口块的参数
- `-> i32` —— 返回类型（Type）
- `arith.constant`、`arith.addi` —— `arith` 方言的 Op
- `2` —— **属性（Attribute）**；`i32` —— **类型（Type）**
- `%c2`、`%sum` —— 每个值只定义一次，**SSA** 的体现
- 整个文件最外层还有个看不见的 `builtin.module` Op 包着它

**验收三个问题（不看上面，自己回答）：**

1. 这段代码里有**几个方言**？—— 两个：`func` 和 `arith`（外加最外层隐含的 `builtin`）。
2. 有**几个 Op**？—— `func.func`、`arith.constant`、`arith.addi`、`return`（= `func.return`）共 4 个（算上隐含的 `module` 是 5 个）。
3. **SSA 体现在哪**？—— `%arg0`、`%c2`、`%sum` 每个都只被定义一次，从不重复赋值。

> 能不看笔记答出这三个问题，**阶段 1 就通关了**，可以进入阶段 2 学 TableGen / Pass 了。

***

## 本阶段完成清单

对照打勾：

- [ ] 能说出一个 Op 由哪几部分组成（结果 / 操作数 / 属性 / 后继 / 区域）
- [x] 会用 `mlir-opt --mlir-print-op-generic` 看 IR 的"通用格式"
- [x] 知道 `arith.` `func.` 这些前缀是方言，能按抽象层次给常见方言排个序
- [x] 能解释 SSA 规则，以及它为什么让编译器更好写
- [ ] 能画出 `Op → Region → Block → Op` 的递归结构
- [x] 能分清 Type（"是什么"）和 Attribute（"关于它的常量"）
- [x] 知道 `@` 是符号（Symbol）、`%` 是值（value）
- [ ] 能讲清楚 `scf.for` 的 `iter_args` 如何借"块参数"实现循环累加
- [x] 不看注释读懂 `@add_two` 那整段，并答出"几个方言 / 几个 Op / SSA 在哪"

***

## 附录：一次性备忘（贴墙）

```bash
# 看漂亮写法（默认）
mlir-opt file.mlir

# 看通用格式（Op 的内部真相，X 光机）
mlir-opt file.mlir --mlir-print-op-generic
```

```mlir
# 概念速查
%result = arith.addi %a, %b : i32     # Op = 名 + 操作数 + 结果 + 类型(+属性)
arith.addi  → 方言 arith、Op addi      # 点号前是方言
%a / %b / %result                      # % = 值，SSA：只定义一次
@main / @add_two                       # @ = 符号，有名字、可引用
: i32   → 类型 Type（"是什么"）
42     → 属性 Attribute（"关于它的常量"）
func.func @f() { ... }                 # { } 里是 Region，Region 里是 Block
scf.for ... iter_args(%acc = %c0) ...  # 循环累加 = 借块参数传递新值
```

```text
层级速记：
Op → Region → Block → Op  （递归套娃，一切皆 Op）
```

---

> **下一步**：回到《MLIR 学习规划》阶段 2，学 TableGen/ODS、Pass、Pattern Rewriting——开始"动手改代码"。你已经不是零基础了，你手里有一套能拆解任何 IR 的显微镜。
