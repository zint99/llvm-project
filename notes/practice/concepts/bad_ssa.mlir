func.func @main() -> i32 {
  %c = arith.addi %a, %b : i32   // %a、%b 还没定义！
  return %c : i32
}
