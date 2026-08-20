func.func @main() -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %c = arith.addi %a, %b : i32
  return %c : i32
}
