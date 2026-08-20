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
