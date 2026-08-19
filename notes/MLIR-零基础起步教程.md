# MLIR 零基础起步保姆级教程

> 本文是《MLIR 学习规划》阶段 0 的展开版。
> 目标：让一个**从没碰过编译原理**的人，在**半天到一天内**把 MLIR 编译出来、跑通第一个程序、看懂第一段 IR。
> 假设环境：Windows 上的 WSL2 + Ubuntu（也适用于纯 Linux；macOS 略有差异会标注）。

---

## 第 1 步：确认你手上有什么（10 分钟）

打开终端，逐条敲下面的命令，缺什么补什么。

```bash
git --version        # 需要 >= 2.x
cmake --version      # 需要 >= 3.20（越高越好）
ninja --version      # 没有就装，比 make 快很多
g++ --version        # 需要能支持 C++17，建议 gcc 11+
```

**缺了怎么办（Ubuntu/Debian 一行搞定）：**

```bash
sudo apt update
sudo apt install -y build-essential cmake ninja-build git python3
```

> **macOS**：`brew install cmake ninja`，编译器用 Xcode 自带的 clang。
> **纯 Windows（无 WSL）**：不建议。MLIR 在 Windows 上能编译，但踩坑多、教程少，强烈建议先装 WSL2。

**检查 g++ 版本是否够新**（C++17 是最低线，但新版 LLVM 可能要求更高）：

```bash
g++ --version
# 如果输出里是 gcc 9.x 这种老版本，去装更新的：
sudo apt install -y g++-12
```

---

## 第 2 步：下载源码（5 分钟 + 下载时间）

MLIR 的代码在 LLVM 的仓库里（叫 "llvm-project"），整个仓库很大（几个 GB），只下最新一次提交即可：

```bash
cd ~                          # 回到主目录
git clone --depth 1 https://github.com/llvm/llvm-project.git
```

- `--depth 1`：只拉最近一次提交，**别省略**，否则下载量翻几十倍。
- 国内网络慢的话，可以换镜像：`https://gitee.com/mirrors/llvm-project.git` 或 `https://mirrors.tuna.tsinghua.edu.cn/git/llvm-project.git`。

---

## 第 3 步：配置并编译（编译要等很久，先了解清楚再动手）

```bash
cd llvm-project
mkdir build && cd build

cmake -G Ninja ../llvm \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=mlir \
  -DLLVM_TARGETS_TO_BUILD="Native" \
  -DLLVM_ENABLE_ASSERTIONS=ON

ninja -j$(nproc)
```

**逐条解释这几个参数（理解它们能帮你少走很多弯路）：**

| 参数 | 作用 | 为什么 |
|---|---|---|
| `-G Ninja` | 用 Ninja 构建系统 | 比默认的 Make 并行度高、增量编译快 |
| `-DCMAKE_BUILD_TYPE=Release` | 优化构建 | 编译出的工具跑得快；学习阶段别用 Debug（慢且占内存） |
| `-DLLVM_ENABLE_PROJECTS=mlir` | 只编译 MLIR | 不编译 clang/lld 等，能省掉一大半时间 |
| `-DLLVM_TARGETS_TO_BUILD="Native"` | 只支持本机 CPU 架构 | 默认要编译 x86/ARM/RISC-V… 所有后端，非常慢 |
| `-DLLVM_ENABLE_ASSERTIONS=ON` | 开启断言 | MLIR 靠断言做大量校验，学习时开着能帮你早点发现错误 |

**编译要多久？** 取决于机器，一般 8 核电脑约 20–40 分钟，首次编译最久。之后增量编译（改一个文件）只要几秒到几分钟。

> **内存不足的坑**：如果 8GB 内存，`-j$(nproc)` 可能把内存吃满。改成 `ninja -j4` 限制并行度。

---

## 第 4 步：验证成功——mlir-opt 是你的第一个成果

编译完成后，验证一下：

```bash
ls build/bin/mlir-opt      # 存在就说明成功了
build/bin/mlir-opt --version
```

**`mlir-opt` 是什么？** 它是 MLIR 自带的命令行工具，功能是：
1. 读入一个 `.mlir` 文本文件
2. 按你指定的顺序运行各种"优化/变换"（pass）
3. 把结果打印出来

它是你学习 MLIR 的**沙盘**——以后你写任何 pass，都能用它先手动跑一遍看效果，不用自己写 main 函数。

> 强烈建议把它加进 PATH，后面用起来方便：
> ```bash
> echo 'export PATH=$HOME/llvm-project/build/bin:$PATH' >> ~/.bashrc
> source ~/.bashrc
> ```

---

## 第 5 步：写你的第一个 MLIR 程序（10 分钟）

MLIR 文件就是纯文本，扩展名 `.mlir`。用任意编辑器新建一个文件 `hello.mlir`，内容如下：

```mlir
func.func @main() -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %c = arith.addi %a, %b : i32
  return %c : i32
}
```

别急着理解每一行，先把它跑起来：

```bash
mlir-opt hello.mlir
```

如果一切正常，屏幕会原样打印出这段代码（因为没加任何 pass，它只是"读进来再吐出去"，顺便帮你验证了语法是否正确）。

**如果报错了**，通常是这两个原因：
- 写了中文标点或空格格式不对（MLIR 语法对空格敏感）
- 文件名路径没对

---

## 第 6 步：逐行读懂这段代码（这是理解 MLIR 的第一块基石）

现在一句句拆开，**每个符号都搞懂**：

```mlir
func.func @main() -> i32 {
```

- `func.func` —— 一个"函数定义"的操作（Op）。点号前面的 `func` 是**方言名**，后面的 `func` 是具体的 Op 名。
- `@main` —— 函数的名字。`@` 开头表示"符号"（symbol）。
- `() -> i32` —— 无参数，返回一个 32 位整数（`i32` = integer 32）。
- `{` —— 函数体开始。这花括号里的东西叫 **Region（区域）**。

```mlir
  %a = arith.constant 1 : i32
```

- `arith.constant` —— `arith` 方言里的"常量"Op，表示一个常数。
- `1` —— 这个常数的**值**（叫 Attribute，属性）。
- `: i32` —— 类型标注，说这个常量是 32 位整数。
- `%a` —— 给这个结果起个名字，方便后面引用。`%` 开头表示"值"。

```mlir
  %c = arith.addi %a, %b : i32
```

- `arith.addi` —— `arith` 方言的"整数加法"Op（add + integer）。
- `%a, %b` —— 两个操作数。
- `%c` —— 加法的结果。

```mlir
  return %c : i32
}
```

- `return` —— 返回语句，把 `%c` 作为函数返回值。

**两个你必须立刻记住的规则：**

1. **SSA（单静态赋值）**：`%a` 一旦定义就永远不变。你不能再写一句 `%a = ...` 去改它。这会让编译器分析起来轻松很多。
2. **一切皆 Op**：连"函数定义""返回语句"都是 Op，只是有的 Op 里面还装着代码（Region）。

---

## 第 7 步：动手改一改（形成肌肉记忆）

别看完就走，做这三个练习，每个都很短：

**练习 1：加一个减法**
在上面基础上，把 `%c` 再减去 1。提示：`arith.subi` 是整数减法。

<details>
<summary>参考答案</summary>

```mlir
func.func @main() -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %c = arith.addi %a, %b : i32
  %one = arith.constant 1 : i32
  %d = arith.subi %c, %one : i32
  return %d : i32
}
```
</details>

**练习 2：故意写错，看报错长什么样**
把 `arith.addi %a, %b` 的两个操作数改成不同类型（比如 `%a` 是 `i32`，另一个写成 `f32`），跑 `mlir-opt`，读一读报错信息。**学会读报错，是独立学习的关键**。

**练习 3：换个浮点数**
把整段改成浮点运算：常量用 `1.5`，类型用 `f32`，加法用 `arith.addf`（add float）。体会一下"同样的结构，换个类型和 Op 名"。

---

## 第 8 步：第一次看"优化"——跑一个 pass（15 分钟）

MLIR 最酷的地方是 pass。我们跑一个最简单的 pass：**常量折叠**（把 `1 + 2` 直接算成 `3`）。

把 `hello.mlir` 保持为最初那个 `1 + 2` 的版本，然后：

```bash
mlir-opt hello.mlir --canonicalize
```

对比一下输出和输入，你会发现：

```mlir
// 输入
%a = arith.constant 1 : i32
%b = arith.constant 2 : i32
%c = arith.addi %a, %b : i32

// 输出（--canonicalize 之后）
%c = arith.constant 3 : i32
```

**发生了什么？** `canonicalize` 这个 pass 里内置了"看到 `常数 + 常数` 就折叠成新常数"的规则，它在编译期就把加法算好了。

> 这就是 MLIR 的玩法：**你定义 Op，然后写 pass 去"看懂并改写"这些 Op**。整个 MLIR 的学习，本质就是学这两件事。

再试一个更有画面感的 pass——`--cse`（公共子表达式消除）和 `--mlir-print-op-generic`（把 IR 打印成最原始、最啰嗦的形式，让你看到 Op 的"内部结构"）：

```bash
mlir-opt hello.mlir --mlir-print-op-generic
```

输出会变成类似 `"arith.addi"(%a, %b) : (i32, i32) -> i32` 这样的通用格式——这是 MLIR 内部真正存储的样子，前面那种 `%c = arith.addi ...` 只是它的"甜头写法"。

---

## 第 9 步：逛一逛官方样例（10 分钟）

仓库里已经给你准备好了几百个 `.mlir` 示例文件，它们是最好的免费教材：

```bash
cd ~/llvm-project
ls mlir/test/                 # 全是测试用的 .mlir 文件
```

随便挑几个打开看看，比如：
- `mlir/test/Dialect/Arith/` —— 各种算术运算的例子
- `mlir/test/Dialect/Func/` —— 函数相关
- `mlir/test/Dialect/Affine/` —— 循环（先别深究，感受一下即可）

这些文件里每个都是一小段自包含的 MLIR，配上文件名注释说明了它在测什么。**阶段 1 学概念时，可以随时来这里找例子对照**。

---

## 第 10 步：遇到问题怎么办

| 问题 | 排查方法 |
|---|---|
| cmake 报错找不到编译器 | 确认 `g++ --version` 能跑，重跑 cmake 前先删掉 `build/CMakeCache.txt` |
| 编译中途 OOM / 卡死 | 减少并行度：`ninja -j4`，或加内存 |
| 编译到一半改了参数想重来 | 直接删掉 `build` 目录重新 cmake，最干净 |
| mlir-opt 报 `unknown dialect` | 说明某个方言没被链接进这个工具，多数常见方言默认都有，罕见方言要用对应工具或自己编译 |
| 语法报错看不懂 | 先检查：是不是用了中文标点、`:` 和 `%` 和空格是否规范 |

**去社区问**：[MLIR Discourse](https://discourse.llvm.org/c/mlir/31)，搜索时用英文关键词（`mlir addi error ...`）更容易命中。

---

## 你现在的进度

完成到这里，你已经：

- ✅ 从源码编译出了 MLIR 的 `mlir-opt` 工具
- ✅ 写出了第一段 MLIR 代码并逐行读懂
- ✅ 亲手跑了一个优化 pass，看到 `1+2` 被折叠成 `3`
- ✅ 知道了"Op / 方言 / SSA / Region"这几个词大概指什么

**下一步**：带着这些体感，回到《MLIR 学习规划》的阶段 1，系统学习核心概念。你已经不是"从零开始"了——你见过真实的东西了。

---

## 附录：一次性备忘（可打印贴墙）

```bash
# 编译
cmake -G Ninja ../llvm -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS=mlir -DLLVM_TARGETS_TO_BUILD="Native" \
  -DLLVM_ENABLE_ASSERTIONS=ON
ninja -j$(nproc)

# 跑一个 .mlir 文件（原样输出 = 语法检查）
mlir-opt file.mlir

# 常量折叠
mlir-opt file.mlir --canonicalize

# 看 Op 的底层通用表示
mlir-opt file.mlir --mlir-print-op-generic

# 列出所有可用 pass
mlir-opt --help | grep -i canonicalize
```
