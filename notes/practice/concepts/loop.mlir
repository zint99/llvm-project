func.func @sum(%n: index) -> index {
  %c0 = arith.constant 0 : index
  %c1 = arith.constant 1 : index
  %sum = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %c0) -> (index) {
    %acc_next = arith.addi %acc, %i : index
    scf.yield %acc_next : index
  }
  return %sum : index
}
