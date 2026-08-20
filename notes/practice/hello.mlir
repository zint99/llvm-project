func.func @main() -> i32 {
  %a = arith.constant 1 : i32
  %b = arith.constant 2 : i32
  %c = arith.addi %a, %b : i32
  %res = arith.subi %c, %a : i32
  return %res : i32
}

func.func @floatCalc() -> f32 {
  %a = arith.constant 1. : f32
  %b = arith.constant 2. : f32
  %c = arith.addf %a, %b : f32
  %res = arith.subf %c, %a : f32
  return %res : f32
}