# MLIR 方言与 Pass 开发保姆级教程

> 本文是《MLIR 学习规划》**阶段 2** 的展开版。
> 前置：已完成阶段 1（《MLIR-核心概念教程.md》），会用 `mlir-opt` 读 IR、认得出 Op/Dialect/SSA/Region。
> 目标：把"读 IR"升级成"写变换"——**用 TableGen/ODS 定义一个方言，写一个 Pass，用 `mlir-opt` 跑通**。
> 方法：跟着官方最小的 `standalone` 例子走一遍完整的"定义 → 编译 → 加载 → 跑通"闭环，再动手把它改成你自己的方言，写一个真正做 lowering 的 Pass。**这一阶段你要开始写 C++ 和 TableGen 了，但每一步都能立刻看到结果。**

***

## 第 0 步：本阶段学什么、怎么学（先看地图再走路）

阶段 1 你学会了"**读**"：看到一个 `.mlir` 文件，能数出几个方言、几个 Op、SSA 体现在哪。阶段 2 要反过来学"**写**"：定义新的 Op、写代码去改写已有的 IR。

**本阶段要回答的 5 个问题：**

1. TableGen 是什么？ODS 是什么？凭什么写一个 `.td` 文件就能自动生成几百行 C++？
2. 定义一个方言，到底要写哪几个文件、每个文件干什么？
3. Pass 是什么？PassManager 怎么把一堆 Pass 串成流水线？
4. Pattern Rewriting（模式重写）的"看到 X 就换成 Y"是怎么写出来的？
5. Trait / Interface / Verifier 三个词分别解决什么问题？

**这一阶段的完成标志**（也是验收标准）：

> 独立定义一个**只有一个 Op 的方言**，写一个 Pass 把它 **lower 成 `arith`**，并用 `mlir-opt` 跑通。

**本阶段最重要的一个认知——"显微镜"升级了：**

阶段 0/1 里，`mlir-opt` 是读 IR 的显微镜。现在你会面临一个新问题：**`mlir-opt` 是提前编译好的二进制，它不认识你自己新定义的方言和 Pass，怎么办？**

答案就是 MLIR 的**插件机制**：

```bash
# 把你的方言 / Pass 编译成一个 .so，动态加载进 mlir-opt
mlir-opt file.mlir \
  --load-dialect-plugin=./libStandalonePlugin.so \   # 加载方言
  --load-pass-plugin=./libStandalonePlugin.so         # 加载 Pass
```

这样你**不用重新编译整个 `mlir-opt`**，只需要编译你自己的小插件。这就是本阶段的"快速反馈环"：改代码 → `ninja` 编译几秒钟 → 加载插件跑一遍看效果。

> 前提：阶段 0 编译时确认了 `LLVM_ENABLE_PLUGINS=ON`（本文后面会带你验证）。

先建好本阶段的实验台：

```bash
# ⚠️ 把下面两条路径换成你自己的（阶段 0 clone llvm-project 的位置）
export LLVM_ROOT="$HOME/worksapce/ai/compiler/llvm-project"
export BUILD_DIR="$LLVM_ROOT/build"

# 本阶段的工作区（放你自己的方言项目）
mkdir -p ~/mlir-playground
```

> 校验一下环境就位（三个输出都应正常）：
> ```bash
> ls $BUILD_DIR/bin/mlir-opt
> $BUILD_DIR/bin/mlir-opt --help-hidden | grep -E "load-dialect-plugin|load-pass-plugin"
> ```

***

## 第 1 步：TableGen 与 ODS——用"声明"代替"手写"

### 1.1 问题：定义一个 Op，要写多少代码？

回忆阶段 1 里 `arith.addi` 的内部结构：一个 Op 有名字、操作数、结果、类型、属性，还要能被打印、被解析、被校验、被遍历……如果这些都手写 C++，定义一个 Op 是几百上千行的体力活，而且大量是重复的样板。

MLIR 的解法是 **TableGen**：一个 LLVM 自带的**声明式代码生成器**。你写一个 `.td` 文件，用声明式的语法"描述"你的 Op，构建系统就自动生成那一大堆 C++ 样板。**把 ODS 用在 Op 定义上，就叫 ODS（Op Definition Specification，Op 定义规范）。**

一句话对比：

| 方式 | 你要写的 | 谁生成 C++ |
|---|---|---|
| 手写 | 全部 C++（上千行） | 无 |
| ODS | 一个 `.td` 声明（几行到几十行） | TableGen 自动生成 `.inc` 文件 |

### 1.2 读一段真实的 ODS：`arith.addi` 是怎么声明的

打开 `$LLVM_ROOT/mlir/include/mlir/Dialect/Arith/IR/ArithBase.td` 和 `ArithOps.td`，你会看到 `arith.addi` 的"简历"是这样写的（下面是**简化示意**，真身在源码里）：

```tablegen
// ① 先定义方言本身
def Arith_Dialect : Dialect {
  let name = "arith";                    // 方言名字（IR 里那个前缀）
  let cppNamespace = "::mlir::arith";    // 生成的 C++ 放在哪个命名空间
  let description = [{ ... }];
}

// ② 再定义一个 Op
def Arith_AddIOp : Arith_IntBinaryOp<"addi",      // Op 名字（IR 里 addi）
    [Commutative]                                   // Trait：可交换
> {
  let summary = "integer addition operation";
  let arguments = (ins Arith_SignlessIntegerOrIndexLike:$lhs,  // 两个操作数
                        Arith_SignlessIntegerOrIndexLike:$rhs);
  let results   = (outs Arith_SignlessIntegerOrIndexLike:$result); // 一个结果
  let assemblyFormat = "$lhs `,` $rhs attr-dict `:` type($result)"; // 打印/解析格式
}
```

**逐块拆解（这几行就是 ODS 的全部精髓）：**

| 片段 | 含义 |
|---|---|
| `def Arith_AddIOp : ...` | `def` 定义一个记录；`Arith_AddIOp` 是它的名字 |
| `"addi"` | 这个 Op 在 IR 里的**助记符**（`arith.addi` 里的 `addi`） |
| `[Commutative]` | **Trait**（能力标签），声明这个 Op 满足交换律 `a+b == b+a`，Pass 靠它做优化 |
| `arguments = (ins ...)` | **输入**（操作数），`$lhs`/`$rhs` 是给它们起的字段名 |
| `results = (outs ...)` | **输出**（结果），`$result` 是字段名 |
| `assemblyFormat` | **打印/解析格式**——一段 DSL，告诉 MLIR 这个 Op 在文本 IR 里长什么样 |

**关键点**：`arguments` 里那个 `Arith_SignlessIntegerOrIndexLike` 是一个**类型约束**——它不指定具体是 `i32` 还是 `i64`，而是"某种整数类型"。所以同一个 `arith.addi` 定义，能自动支持 `i32`、`i64`、`index` 等各种整数，不用每种写一遍。

### 1.3 `.td` 编译后变出什么

构建时，`mlir-tblgen` 把 `.td` 编译成一组 `*.inc`（C++ 代码），这些 `.inc` 再被你的 `.cpp` 文件 `#include` 进去。生成的代码里，`Arith_AddIOp` 变成了一个 C++ 类 `arith::AddIOp`，自带：

- `AddIOp::build(...)` —— 一堆创建 Op 的构造器
- `getLhs()` / `getRhs()` / `getResult()` —— 访问字段的方法
- `parse()` / `print()` —— 按 `assemblyFormat` 定义的格式读写文本
- 各种 Trait 对应的模板特化

> **这一阶段的定位**：你不需要立刻精通 TableGen 语法（那是阶段 3 Toy 会练的），只需要**能读懂 `.td`、知道它和生成的 C++ 的对应关系**。先会用，再深入。

### 1.4 亲手看一眼生成物

`arith` 是内置方言，它的 `.inc` 已经躺在构建目录里了：

```bash
ls $BUILD_DIR/tools/mlir/include/mlir/Dialect/Arith/IR/
# 你会看到 ArithOps.h.inc、ArithOps.cpp.inc 等一堆 .inc 文件
grep -n "class AddIOp" $BUILD_DIR/tools/mlir/include/mlir/Dialect/Arith/IR/ArithOps.h.inc
# → class AddIOp : public ::mlir::Op<AddIOp, ...>
```

亲眼看到 `Arith_AddIOp`（.td 里的名字）变成了 `class AddIOp`（C++ 里的类），你就理解了 ODS 的"声明 → 生成"闭环。

***

## 第 2 步：一个最小方言项目的"地图"（standalone 例子）

MLIR 官方在 `mlir/examples/standalone/` 放了一个**最小、可运行的出树方言**，专门用来示范"怎么从头定义一个方言"。它是本阶段的模板——**先照葫芦画瓢，再改成自己的**。

先看它的文件清单和各自职责（这是你以后定义任何方言都要重复的结构）：

```
standalone/
├── CMakeLists.txt                    # 顶层：找到 MLIR、组织子目录
├── include/Standalone/
│   ├── StandaloneDialect.td          # ① 声明方言
│   ├── StandaloneOps.td              # ② 声明 Op
│   ├── StandaloneTypes.td            # ③ 声明自定义类型
│   ├── StandalonePasses.td           # ④ 声明 Pass
│   ├── StandaloneDialect.h           # 手写头文件（include 生成的方言 .inc）
│   ├── StandaloneOps.h               # 手写头文件（include 生成的 Op .inc）
│   ├── StandaloneTypes.h             # 手写头文件（include 生成的类型 .inc）
│   └── StandalonePasses.h            # 手写头文件（include 生成的 Pass .inc）
├── lib/Standalone/
│   ├── StandaloneDialect.cpp         # 方言的 C++ 实现（注册 Op、类型）
│   ├── StandaloneOps.cpp             # Op 的 C++ 实现（验证器等）
│   ├── StandaloneTypes.cpp           # 类型的 C++ 实现
│   └── StandalonePasses.cpp          # Pass 的 C++ 实现
├── standalone-opt/                   # 一个自带方言的独立 opt 工具（可选）
└── standalone-plugin/                # ★ 关键：编译成 .so 插件，加载进 mlir-opt
    └── standalone-plugin.cpp
```

**看懂这张图的规律**：

1. **`.td` 文件是"声明"，`.h`/`.cpp` 是"手写实现"**。声明交给 TableGen 生成样板，手写只写机器生成不了的部分（比如验证器逻辑、Pass 的变换逻辑）。
2. **几乎每个 `.td` 都对应一个 `.h.inc` 和一个 `.cpp.inc`**：`.h.inc` 是声明，`.cpp.inc` 是定义，分别被手写的 `.h` 和 `.cpp` include。
3. **`standalone-plugin` 是灵魂**：它把方言和 Pass 打包成一个 `.so`，让我们能用 `mlir-opt --load-*-plugin` 加载。

下面逐个读关键文件，边读边标注意思。

### 2.1 方言声明：`StandaloneDialect.td`

```tablegen
def Standalone_Dialect : Dialect {
    let name = "standalone";                  // IR 里的前缀：standalone.foo
    let summary = "A standalone out-of-tree MLIR dialect.";
    let cppNamespace = "::mlir::standalone";  // 生成的 C++ 放这里
    let useDefaultTypePrinterParser = 1;      // 用默认的类型打印/解析
    let extraClassDeclaration = [{
        void registerTypes();                 // 让方言自己声明一个注册类型的函数
    }];
}
```

这几乎就是定义一个方言的最小配置：**一个名字 + 一个命名空间**，剩下全是可选。

### 2.2 Op 声明：`StandaloneOps.td`

```tablegen
def Standalone_FooOp : Standalone_Op<"foo", [Pure,
                                             SameOperandsAndResultType]> {
    let arguments = (ins I32:$input);   // 一个 i32 输入
    let results   = (outs I32:$res);    // 一个 i32 输出
    let assemblyFormat = [{
        $input attr-dict `:` type($input)    // 打印成：standalone.foo %0 : i32
    }];
}
```

- `"foo"` → Op 助记符，IR 里就是 `standalone.foo`
- `[Pure, SameOperandsAndResultType]` → 两个 Trait：`Pure`（无副作用、结果只依赖输入）、`SameOperandsAndResultType`（操作数和结果同类型）
- `I32` 是内置类型约束（32 位整数）
- `assemblyFormat` 用 `$input` 引用字段名——这就是阶段 1 里 `%1 = standalone.foo %0 : i32` 那种漂亮写法的来源

> 注意 `Standalone_Op` 这个自定义基类（在 `StandaloneDialect.td` 里）：`class Standalone_Op<string mnemonic, list<Trait> traits = []> : Op<Standalone_Dialect, mnemonic, traits>;`——它把"属于哪个方言"这层固定下来，后面每个 Op 就不用重复写了。这是 ODS 里很常用的"减少重复"技巧。

### 2.3 Pass 声明：`StandalonePasses.td`

```tablegen
def StandaloneSwitchBarFoo: Pass<"standalone-switch-bar-foo", "::mlir::ModuleOp"> {
  let summary = "Switches the name of a FuncOp named `bar` to `foo` and folds.";
}
```

- 第一个参数 `"standalone-switch-bar-foo"` 是这个 Pass 的**命令行名字**（`mlir-opt --standalone-switch-bar-foo`）
- 第二个参数 `"::mlir::ModuleOp"` 是**作用范围**——这个 Pass 作用在整个 Module 上（后面详讲）

### 2.4 Pass 实现：`StandalonePasses.cpp`（重点读）

```cpp
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "Standalone/StandalonePasses.h"

namespace mlir::standalone {
#define GEN_PASS_DEF_STANDALONESWITCHBARFOO    // 生成这个 Pass 的"基类"
#include "Standalone/StandalonePasses.h.inc"

namespace {
// ① 一个"重写规则"：看到名字是 bar 的函数，改名叫 foo
class StandaloneSwitchBarFooRewriter : public OpRewritePattern<func::FuncOp> {
public:
  using OpRewritePattern<func::FuncOp>::OpRewritePattern;
  LogicalResult matchAndRewrite(func::FuncOp op,
                                PatternRewriter &rewriter) const final {
    if (op.getSymName() == "bar") {                      // 匹配条件
      rewriter.modifyOpInPlace(op, [&op]() { op.setSymName("foo"); }); // 改写
      return success();
    }
    return failure();
  }
};

// ② 真正的 Pass 类：继承 TableGen 生成的基类
class StandaloneSwitchBarFoo
    : public impl::StandaloneSwitchBarFooBase<StandaloneSwitchBarFoo> {
public:
  using impl::StandaloneSwitchBarFooBase<
      StandaloneSwitchBarFoo>::StandaloneSwitchBarFooBase;
  void runOnOperation() final {
    RewritePatternSet patterns(&getContext());          // 收集规则
    patterns.add<StandaloneSwitchBarFooRewriter>(&getContext());
    FrozenRewritePatternSet patternSet(std::move(patterns));
    if (failed(applyPatternsGreedily(getOperation(), patternSet)))  // 反复应用规则直到稳定
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::standalone
```

这个例子麻雀虽小五脏俱全，先记住它的骨架（后面第 5、6 步会展开讲）：

- **`OpRewritePattern<func::FuncOp>`** —— 声明"我要匹配 `func::FuncOp` 这种 Op"
- **`matchAndRewrite`** —— 两件事合一：先判断"匹配吗"（`failure()` 表示不匹配），匹配了就改写并 `success()`
- **`runOnOperation`** —— 每个 Pass 的入口
- **`applyPatternsGreedily`** —— 贪心地把规则反复应用到 IR 上，直到没有规则能再改写为止

### 2.5 插件：`standalone-plugin.cpp`

```cpp
// 方言插件入口：告诉 mlir-opt "有这些方言、这些 Pass"
extern "C" LLVM_ATTRIBUTE_WEAK DialectPluginLibraryInfo
mlirGetDialectPluginInfo() {
  return {MLIR_PLUGIN_API_VERSION, "Standalone", LLVM_VERSION_STRING,
          [](DialectRegistry *registry) {
            registry->insert<mlir::standalone::StandaloneDialect>();
            mlir::standalone::registerPasses();
          }};
}

// Pass 插件入口
extern "C" LLVM_ATTRIBUTE_WEAK PassPluginLibraryInfo mlirGetPassPluginInfo() {
  return {MLIR_PLUGIN_API_VERSION, "StandalonePasses", LLVM_VERSION_STRING,
          []() { mlir::standalone::registerPasses(); }};
}
```

两个 `extern "C"` 函数是 MLIR 约定的**插件入口符号**：`mlir-opt --load-*-plugin` 加载 `.so` 时，就是去调用这两个函数，把你定义的方言注册进它的 `DialectRegistry`、把你的 Pass 注册进它的 Pass 注册表。

***

## 第 3 步：编译并加载——跑通最小闭环（本阶段第一个里程碑）

现在动手把它编译出来，用插件加载进 `mlir-opt` 跑一遍。

### 3.1 把例子拷贝成"你自己的项目"

```bash
cp -r $LLVM_ROOT/mlir/examples/standalone ~/mlir-playground/standalone
```

以后你就改 `~/mlir-playground/standalone` 这个副本，不动 `llvm-project` 里的原版（保持 git 干净，也方便随时对照原版）。

### 3.2 用"外部项目"方式把项目挂进现有构建

LLVM 支持把外部项目"挂"进主构建一起编译（叫 `LLVM_EXTERNAL_PROJECTS`）。在你的 build 目录上**重新跑一次 cmake**，加上这两个参数：

```bash
cd $BUILD_DIR
cmake -G Ninja $LLVM_ROOT/llvm \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD="Native" \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_EXTERNAL_PROJECTS=standalone-dialect \
  -DLLVM_EXTERNAL_STANDALONE_DIALECT_SOURCE_DIR=$HOME/mlir-playground/standalone
```

> 解释：`LLVM_EXTERNAL_PROJECTS=standalone-dialect` 声明"我要多构建一个叫 standalone-dialect 的项目"；`LLVM_EXTERNAL_STANDALONE_DIALECT_SOURCE_DIR=...` 告诉它这个项目的源码在哪。项目名来自 standalone 的 `CMakeLists.txt` 里 `project(standalone-dialect ...)`。
> **这一步不会重新编译整个 MLIR**，只是把新项目挂进去，已有的东西都不动。

### 3.3 只编译那个插件

```bash
ninja StandalonePlugin
```

几秒钟到一两分钟，只编译 standalone 这一小块。完成后找插件：

```bash
find $BUILD_DIR -name "StandalonePlugin*.so"
# 通常会输出类似 $BUILD_DIR/tools/Standalone/lib/StandalonePlugin.so
```

把找到的路径记下来，存进一个变量：

```bash
export PLUGIN=$(find $BUILD_DIR -name "StandalonePlugin.so" | head -1)
echo $PLUGIN
```

### 3.4 加载方言，跑通第一个 `.mlir`

写一个用到 `standalone.foo` 的文件：

```bash
mkdir -p ~/mlir-playground/standalone/test
cat > ~/mlir-playground/standalone/test/dummy.mlir <<'EOF'
func.func @main() -> i32 {
  %0 = arith.constant 1 : i32
  %res = standalone.foo %0 : i32
  return %res : i32
}
EOF
```

先试试**不加插件**直接跑（应该报"未知方言"）：

```bash
$BUILD_DIR/bin/mlir-opt ~/mlir-playground/standalone/test/dummy.mlir
# → error: Dialect 'standalone' not found for custom op 'standalone.foo'
```

再**加载方言插件**跑：

```bash
$BUILD_DIR/bin/mlir-opt ~/mlir-playground/standalone/test/dummy.mlir \
  --load-dialect-plugin=$PLUGIN
# → 正常打印出原样 IR
```

**这个对比就是本阶段的核心玩法**：`mlir-opt` 本身不认识 `standalone`，但加载你的 `.so` 之后就认识了。你以后定义的每一个方言、每一个 Pass，都走这条路进来。

### 3.5 跑一个 Pass，看它改写 IR

再试试那个重命名函数的 Pass（它只通过 `--load-pass-plugin` 加载，因为它是纯 Pass、不涉及新方言）：

```bash
cat > ~/mlir-playground/standalone/test/rename.mlir <<'EOF'
module {
  func.func @bar() {
    return
  }
}
EOF

$BUILD_DIR/bin/mlir-opt ~/mlir-playground/standalone/test/rename.mlir \
  --load-pass-plugin=$PLUGIN \
  --pass-pipeline="builtin.module(standalone-switch-bar-foo)"
# → 输出里 @bar 变成了 @foo
```

到这里，你走通了"定义方言 + 定义 Pass + 编译插件 + 加载进 mlir-opt 跑通"的**完整闭环**。这是阶段 2 的里程碑，后面都是在这个骨架上加内容。

***

## 第 4 步：Pass 与 PassManager——IR 的"变换流水线"

### 4.1 Pass 是什么

**Pass = 对 IR 做的一次变换 / 分析。** 阶段 0 你已经见过了：`--canonicalize` 把 `1 + 2` 折叠成 `3`，就是一个 Pass。

注意 Pass 的**粒度**差异很大：

| Pass 类型 | 作用范围 | 例子 |
|---|---|---|
| **Module Pass** | 整个 `builtin.module`（能看到全部函数） | `standalone-switch-bar-foo` |
| **Func Pass** | 单个 `func.func`（只能看到函数内部） | 大多数优化 Pass |
| **Op Pass** | 某个具体的 Op | 泛化到任意 Op 的 Pass |

在 `StandalonePasses.td` 里，第二个参数 `"::mlir::ModuleOp"` 就声明了作用范围。定义 Pass 时想清楚"我要看的范围有多大"，选对类型。

### 4.2 PassManager：把 Pass 串成流水线

真正的编译不会只跑一个 Pass，而是**一连串 Pass 按顺序、按嵌套结构执行**。这就是 **PassManager**。它支持**嵌套**——因为 MLIR 是 `Op → Region → Block → Op` 的套娃结构，Pass 也可以"套娃式"地作用于不同层级。

`-pass-pipeline` 就是这个嵌套结构的文本表示：

```bash
# 对整个 module：先 canonicalize，再 cse（公共子表达式消除）
$BUILD_DIR/bin/mlir-opt input.mlir \
  -pass-pipeline='builtin.module(canonicalize,cse)'

# 嵌套：对 module 里的每个 func.func 都跑一遍 canonicalize
$BUILD_DIR/bin/mlir-opt input.mlir \
  -pass-pipeline='builtin.module(func.func(canonicalize))'
```

**语法规则**：`外层(子Pass,子Pass)`，括号里用逗号分隔；子 Pass 前面可以再套一层作用域 `func.func(...)`。读法：**从外往里**，外层 Pass 决定"在哪个层级跑"，内层 Pass 决定"跑什么变换"。

### 4.3 亲手跑几个官方 Pass，看流水线的效果

复用阶段 1 的 `add.mlir`（`1 + 2` 那个）：

```bash
cat > /tmp/add.mlir <<'EOF'
func.func @main() -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %c = arith.addi %a, %b : i32
  %d = arith.addi %a, %b : i32   // %c 和 %d 是"重复计算"
  %e = arith.addi %c, %d : i32
  return %e : i32
}
EOF

# 1) 只 canonicalize（折叠 1+2 → 3）
$BUILD_DIR/bin/mlir-opt /tmp/add.mlir --canonicalize

# 2) 只 cse（把重复的 1+2 算一次）
$BUILD_DIR/bin/mlir-opt /tmp/add.mlir --cse

# 3) 串起来：先 cse 再 canonicalize
$BUILD_DIR/bin/mlir-opt /tmp/add.mlir -pass-pipeline='builtin.module(cse,canonicalize)'
```

逐个对比输入输出，感受"一个 Pass 做一件事，流水线把小事串成大事"。**这是 MLIR 设计哲学的核心**：Pass 越小、越单一越好，组合出力量。

***

## 第 5 步：Pattern Rewriting——"看到 X 就换成 Y"

写 Pass 最常见的落地方式就是 **Pattern Rewriting（模式重写）**：声明"**如果 IR 里出现了形如 X 的东西，就把它替换成形如 Y 的东西**"。这正是第 2 步 `StandaloneSwitchBarFooRewriter` 在做的事（看到 `@bar` → 改成 `@foo`）。

### 5.1 核心组件

- **`RewritePattern` / `OpRewritePattern<OpTy>`** —— 一个"模式"，封装了"匹配 + 改写"。
  - `OpRewritePattern<OpTy>` 是特化版：只匹配 `OpTy` 这一种 Op。
- **`PatternRewriter`** —— 给你做改写的工具，提供 `replaceOp`、`eraseOp`、`create<...>`、`modifyOpInPlace` 等方法。
- **`RewritePatternSet`** —— 一堆模式的集合，交给驱动器。
- **`applyPatternsGreedily`** —— **贪心驱动器**：反复扫 IR，发现能匹配的模式就应用，应用完继续扫，直到没有任何模式再匹配（"不动为止"）。

### 5.2 一个模式的生命周期（读代码的套路）

回看第 2.4 节那段代码，它的逻辑是：

1. `matchAndRewrite(FuncOp op, ...)` 被调用，传入一个 `func.func`；
2. `op.getSymName() == "bar"` 判断**匹不匹配**——不匹配就 `return failure()`，驱动器跳过；
3. 匹配了，就 `rewriter.modifyOpInPlace(...)` **改**名字，`return success()`；
4. 驱动器发现"有成功应用"，于是**从头再扫一遍**，直到整轮都没成功应用为止。

> **为什么叫"贪心"？** 因为它一看到能匹配的就立刻改，不考虑"改了会不会更好"。对大多数局部优化（折叠、重命名、替换）来说，贪心足够且高效。

### 5.3 亲手改一下，形成肌肉记忆

做个小练习：把规则从"改 `bar` 为 `foo`"改成"改 `bar` 为 `hello`"。编辑 `~/mlir-playground/standalone/lib/Standalone/StandalonePasses.cpp`，把 `setSymName("foo")` 改成 `setSymName("hello")`，然后：

```bash
ninja StandalonePlugin
$BUILD_DIR/bin/mlir-opt ~/mlir-playground/standalone/test/rename.mlir \
  --load-pass-plugin=$PLUGIN \
  --pass-pipeline="builtin.module(standalone-switch-bar-foo)"
# → @bar 现在变成了 @hello
```

改一行 → 编译几秒 → 立刻看到效果。**这就是本阶段最该养成的节奏。**

***

## 第 6 步：写一个真正的 lowering Pass——把 `standalone.foo` 降成 `arith`

前面那个 Pass 只是"原地改个名字"，不改变抽象层次。真正的 lowering 是**把一个方言的 Op 换成另一个方言的 Op**——这需要用一组专门的 API：**方言转换（Dialect Conversion）框架**。

### 6.1 为什么不能用简单的 `OpRewritePattern`？

`standalone.foo %x : i32` 要变成 `arith.addi %x, %x : i32`（即 `foo(x) = x + x`，翻倍）。这其实用 `OpRewritePattern` + `replaceOp` 也能写。但**真正的 lowering 要保证一件事：转换结束后，源方言的 Op 一个都不能剩**——否则 IR 里还残留着后端不认识的 `standalone.foo`，就是"没降干净"。

`ConversionPattern` + `ConversionTarget` 就是为这个设计的：

- **`ConversionTarget`** 声明"**什么算合法、什么算非法**"（这里：`standalone.foo` 非法，`arith` 方言合法）
- **`ConversionPattern`** 负责"把一个非法的 Op 换成合法的 Op"
- **`applyPartialConversion`** 反复应用，**保证所有非法 Op 都被转换**，转换不干净就报错

### 6.2 三步改造

**第一步：在 `StandalonePasses.td` 里声明新 Pass：**

```tablegen
def StandaloneLowerFoo: Pass<"standalone-lower-foo", "::mlir::ModuleOp"> {
  let summary = "Lower standalone.foo to arith.addi";
  let dependentDialects = ["arith::ArithDialect"];   // 声明会用到 arith 方言
}
```

> `dependentDialects` 告诉 PassManager："跑我的时候，把 `arith` 方言一起加载进来"——这样 `arith.addi` 才能被创建。

**第二步：在 `StandalonePasses.cpp` 里实现它：**

```cpp
#include "mlir/Dialect/Arith/IR/Arith.h"        // 新增：要用 arith::AddIOp
#include "mlir/Transforms/DialectConversion.h"   // 新增：方言转换框架
// （其余 include 不变）

namespace mlir::standalone {
#define GEN_PASS_DEF_STANDALONELOWERFOO          // 新增：生成这个 Pass 的基类
#include "Standalone/StandalonePasses.h.inc"

namespace {

// ① 转换规则：standalone.foo(%x)  →  arith.addi(%x, %x)  即翻倍
struct FooToArith : public OpConversionPattern<FooOp> {
  using OpConversionPattern<FooOp>::OpConversionPattern;
  LogicalResult
  matchAndRewrite(FooOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    Value input = adaptor.getInput();                     // 拿到转换后的操作数
    Value doubled = rewriter.create<arith::AddIOp>(       // 造一个 arith.addi
        op.getLoc(), input, input);
    rewriter.replaceOp(op, doubled);                      // 用它替换掉 standalone.foo
    return success();
  }
};

// ② 转换 Pass：声明"谁非法、谁合法"，然后驱动转换
struct StandaloneLowerFoo
    : public impl::StandaloneLowerFooBase<StandaloneLowerFoo> {
  using impl::StandaloneLowerFooBase<
      StandaloneLowerFoo>::StandaloneLowerFooBase;

  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<FooToArith>(&getContext());

    ConversionTarget target(getContext());
    target.addIllegalOp<FooOp>();                 // standalone.foo 是"非法"的，必须被转换掉
    target.addLegalDialect<arith::ArithDialect>(); // arith 方言是"合法"的

    if (failed(applyPartialConversion(getOperation(), target,
                                      std::move(patterns))))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::standalone
```

**读这段代码的要点：**

- **`OpConversionPattern<FooOp>`** —— 注意 `FooOp` 是 ODS 从 `Standalone_FooOp` 生成的 C++ 类名（`Standalone_` 前缀被剥掉了，`FooOp` 保留）。
- **`OpAdaptor adaptor`** —— 和普通 pattern 的差别：转换框架会**先把操作数也转换掉**，`adaptor.getInput()` 拿到的是"已经转换后的"输入。这个例子里输入 `i32` 不变，所以看起来和原值一样，但机制上它是"转换过的值"。
- **`rewriter.create<arith::AddIOp>(loc, input, input)`** —— 在 IR 里**创建**一个新的 `arith.addi`。`create` 是重写器最重要的能力。
- **`rewriter.replaceOp(op, doubled)`** —— 用新值替换掉原来的 Op。

**第三步：把新 Pass 的 C++ 文件编译进去。** 新代码在 `StandalonePasses.cpp` 里，所以 `lib/Standalone/CMakeLists.txt` 里 `MLIRStandalone` 已经包含了它，不用改；只需让 Pass 链接到 `arith` 方言库。检查 `lib/Standalone/CMakeLists.txt` 的 `LINK_LIBS`：

```cmake
LINK_LIBS PUBLIC
MLIRIR
MLIRInferTypeOpInterface
MLIRFuncDialect
MLIRArithDialect        # ← 新增：因为要用 arith::AddIOp
```

### 6.3 编译并跑通

```bash
ninja StandalonePlugin
export PLUGIN=$(find $BUILD_DIR -name "StandalonePlugin.so" | head -1)

$BUILD_DIR/bin/mlir-opt ~/mlir-playground/standalone/test/dummy.mlir \
  --load-dialect-plugin=$PLUGIN \
  --load-pass-plugin=$PLUGIN \
  --pass-pipeline="builtin.module(standalone-lower-foo)"
```

输入：

```mlir
func.func @main() -> i32 {
  %0 = arith.constant 1 : i32
  %res = standalone.foo %0 : i32
  return %res : i32
}
```

输出（`standalone.foo` 已经消失，变成了 `arith.addi`）：

```mlir
func.func @main() -> i32 {
  %0 = arith.constant 1 : i32
  %res = arith.addi %0, %0 : i32
  return %res : i32
}
```

**这就是阶段 2 验收要求的那件事**：定义了一个只有 `foo` 一个 Op 的方言，写了一个 Pass 把它 lower 成了 `arith`，并用 `mlir-opt` 跑通了。

> 想看"降得干不干净"，可以再串一个 `canonicalize`：`arith.addi %0, %0` 会被进一步优化。自己试试 `-pass-pipeline="builtin.module(standalone-lower-foo,canonicalize)"`。

***

## 第 7 步：Trait、Interface、Verifier——三个高频词一次性说清

写到这里，你已经在代码里见过 `Pure`、`Commutative`、`SameOperandsAndResultType` 这些词了。它们是**Trait**。这一节把 Trait / Interface / Verifier 三个概念划清界限。

### 7.1 Trait（能力标签）：给 Op 贴"我是什么样"的标签

**Trait = 声明 Op 的一条属性，让 Pass 能据此做判断。** 它回答"这个 Op 有什么性质"：

| Trait | 含义 | 为什么有用 |
|---|---|---|
| `Pure` | 无副作用，结果只依赖操作数 | 结果可缓存、可删除、可重排 |
| `Commutative` | 可交换（`a+b == b+a`） | 规范表达式的顺序，利于合并 |
| `SameOperandsAndResultType` | 操作数与结果同类型 | 简化类型推断 |
| `NoMemoryEffect` | 不读不写内存 | 可被移动、消除 |

Trait 在 `.td` 里用 `def ... : Op<..., [Trait1, Trait2]>` 声明。**Pass 全靠 Trait 判断"能不能安全地优化"**——比如常量折叠，只有看到 `Pure` + 常量操作数的 Op 才会去折叠。

### 7.2 Interface（通用接口）：跨方言的"同一套操作"

Trait 是"标签"，Interface 是"**方法**"。如果 Trait 回答"它是什么样"，Interface 就回答"**我能对它做什么**"。

举例：`func.call` 调用函数、`llvm.call` 也调用函数，它们分属不同方言，但"调用"这个行为是共通的。MLIR 定义了 `CallOpInterface`，两个方言都实现它，于是任何 Pass 都能写"**对任意实现了 `CallOpInterface` 的 Op，拿到它的被调用者**"，不用管它具体是哪个方言。

```cpp
// 伪代码：不关心是 func.call 还是 llvm.call，只要是"调用"就统一处理
if (auto call = dyn_cast<CallOpInterface>(op)) {
  StringRef callee = call.getCallableForCallee().get<SymbolRefAttr>().getRootReference();
  // ...
}
```

> 阶段 2 你只需要知道 **Interface = 跨方言的统一方法集** 这个概念。真正动手实现 Interface 是 Toy 第 4 章和更后面的事。

### 7.3 Verifier（校验器）：给 Op 做"体检"

ODS 能自动生成**类型检查**（操作数类型对不对、数量对不对），但**业务规则**它不懂。比如 `standalone.foo` 规定"输入必须是正数"这种规则，就要手写 **Verifier**。

给 `StandaloneFooOp` 加一个校验器，两步：

**第一步：在 `.td` 里声明"我有一个自定义校验器"：**

```tablegen
def Standalone_FooOp : Standalone_Op<"foo", [Pure, SameOperandsAndResultType]> {
    let arguments = (ins I32:$input);
    let results   = (outs I32:$res);
    let assemblyFormat = [{ $input attr-dict `:` type($input) }];
    let hasVerifier = 1;          // ← 加这一行
}
```

**第二步：在 `StandaloneOps.cpp` 里实现它：**

```cpp
// 在 StandaloneOps.cpp 里，include 生成代码之后：
LogicalResult FooOp::verify() {
  // 举例子：这里校验"输入类型必须是 32 位整数"（其实 ODS 已经保证，这里演示写法）
  if (!getInput().getType().isInteger(32))
    return emitOpError("input must be a 32-bit integer");
  return success();
}
```

`emitOpError("...")` 会生成一条带 Op 位置的友好报错。`verify()` 返回 `success()` 表示合法，返回 `failure()` 表示非法（配上一句 `emitOpError` 说明原因）。

重新编译后，故意写一个不合法的输入，看报错长什么样：

```bash
ninja StandalonePlugin
# 写个 i64 的输入（如果校验器真的检查了，就会报错）
$BUILD_DIR/bin/mlir-opt ... --load-dialect-plugin=$PLUGIN
```

> **小结一句话**：Trait 是"标签"，Interface 是"方法集"，Verifier 是"体检"。Pass 靠 Trait 判断能否优化，靠 Interface 统一处理，靠 Verifier 保证 IR 合法。

***

## 第 8 步：完整验收——不看笔记，独立走一遍

**验收任务**（对应阶段 2 完成标志）：

1. 把你 `~/mlir-playground/standalone` 里的方言，改成**你自己的名字**（比如把 `standalone` 改成 `toy`，把 `foo` 改成 `double`，含义就是"翻倍"）。这需要改 `.td` 里的 `name`、`cppNamespace`、Op 助记符，以及插件注册。
2. 写一个 Pass 把你自己的 Op lower 成 `arith`（复用第 6 步的骨架）。
3. 编译插件，用 `mlir-opt --load-*-plugin` 跑通，确认输出里你的方言 Op 被 `arith` 替换了。

**自测三个问题（不看上面，自己回答）：**

1. 定义一个方言，最小需要哪两个信息？（——名字 + C++ 命名空间）
2. `standalone.foo %0 : i32` 里的漂亮写法，是由 `.td` 里哪个字段决定的？（——`assemblyFormat`）
3. 真正的 lowering 为什么用 `ConversionPattern` + `ConversionTarget`，而不是普通 `OpRewritePattern`？（——因为它**保证源方言 Op 被彻底转换掉**，转换不干净会报错）

**能独立答出这三个问题、并跑通验收任务，阶段 2 就通关了**，可以进入阶段 3 跟官方 Toy Tutorial（那时你会发现：Toy 的 Ch2/Ch3/Ch5 分别就是本节第 2/1/6 步的"加强版"，你已经会走路了）。

***

## 本阶段完成清单

对照打勾：

- [ ] 能解释 TableGen 和 ODS 是什么，以及 `.td` 如何变成 C++（`declaration → generated .inc`）
- [ ] 能说出一个方言项目由哪几类文件组成（`.td` / `.h` / `.cpp` / `CMakeLists` / 插件）
- [ ] 会用 `--load-dialect-plugin` / `--load-pass-plugin` 把自定义方言和 Pass 加载进 `mlir-opt`
- [ ] 能读懂 `-pass-pipeline='builtin.module(func.func(canonicalize))'` 这种嵌套结构
- [ ] 能写一个 `OpRewritePattern`，看懂 `matchAndRewrite` / `failure()` / `success()` / `applyPatternsGreedily`
- [ ] 能写一个 `ConversionPattern` + `ConversionTarget` + `applyPartialConversion` 做方言 lowering
- [ ] 能分清 Trait（标签）、Interface（方法集）、Verifier（体检）
- [ ] 独立走完"定义方言 → 写 lower Pass → 插件加载 → `mlir-opt` 跑通"的闭环

***

## 附录：一次性备忘（贴墙）

```bash
# —— 构建自定义方言（外部项目方式）——
export LLVM_ROOT="$HOME/worksapce/ai/compiler/llvm-project"   # 换成你的
export BUILD_DIR="$LLVM_ROOT/build"
cd $BUILD_DIR
cmake -G Ninja $LLVM_ROOT/llvm \
  -DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD="Native" \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_EXTERNAL_PROJECTS=standalone-dialect \
  -DLLVM_EXTERNAL_STANDALONE_DIALECT_SOURCE_DIR=$HOME/mlir-playground/standalone
ninja StandalonePlugin
export PLUGIN=$(find $BUILD_DIR -name "StandalonePlugin.so" | head -1)

# —— 加载方言 / Pass 跑 ——
mlir-opt in.mlir --load-dialect-plugin=$PLUGIN          # 加载方言
mlir-opt in.mlir --load-pass-plugin=$PLUGIN \
  --pass-pipeline="builtin.module(my-pass)"              # 加载并跑 Pass

# —— 官方 Pass 速查 ——
mlir-opt in.mlir --canonicalize                          # 常量折叠等
mlir-opt in.mlir --cse                                   # 公共子表达式消除
mlir-opt in.mlir -pass-pipeline='builtin.module(func.func(canonicalize))'
```

```tablegen
// ODS 速查
def X_Dialect : Dialect { let name="x"; let cppNamespace="::mlir::x"; }
def X_MyOp : Op<X_Dialect,"my",[Pure]> {         // → 生成类 MyOp
  let arguments = (ins I32:$in);
  let results   = (outs I32:$out);
  let assemblyFormat = "$in attr-dict `:` type($out)";
  let hasVerifier = 1;                           // 手写 LogicalResult MyOp::verify()
}
def MyPass : Pass<"my-pass", "::mlir::ModuleOp"> {
  let dependentDialects = ["arith::ArithDialect"];
}
```

```cpp
// C++ 骨架速查
// ① 简单重写：OpRewritePattern<OpTy>，matchAndRewrite(op, rewriter)
// ② lowering：OpConversionPattern<OpTy>，matchAndRewrite(op, adaptor, rewriter)
//    + ConversionTarget{ addIllegalOp<OpTy>(); addLegalDialect<...>(); }
//    + applyPartialConversion(getOperation(), target, std::move(patterns))
// ③ 驱动入口：class MyPass : impl::MyPassBase<MyPass> { void runOnOperation() {...} }
```

```text
概念速记：
Trait      = 标签   "它是什么样"     (Pure / Commutative / ...)
Interface  = 方法集 "能对它做什么"   (CallOpInterface / ...)
Verifier   = 体检   "它合不合法"     (hasVerifier=1 → MyOp::verify())
Pass       = 变换   "把 IR 从 A 变成 B"
PassManager= 流水线 嵌套套娃执行
Pattern    = 规则   "看到 X 就换成 Y"
```

---

> **下一步**：回到《MLIR 学习规划》阶段 3，跟官方 Toy Tutorial。你会发现 Toy 的 Ch2（定义 `toy` 方言）、Ch3（用 ODS 定义 Op）、Ch5（lower 到 `affine`）正是本教程第 2、1、6 步的"正式版"——你已经会定义方言、写 lowering Pass 了，Toy 只是把这些能力串成一条"源码 → LLVM 机器码"的完整流水线。
