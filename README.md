# EECS-322
a Lisp dialogue Compiler Construction in OCaml 

Procedure
* L1 -> x86-64
* L2 -> L1
 * spill vars
 * liveness anaysis
 * graph coloring (using ocamlgraph library for graph construction)
* L3 -> L2 (linearization)
  * accept partially nested programme 
* L4 -> L3 (a-normalization)
 * cps  
* L5 -> l4
