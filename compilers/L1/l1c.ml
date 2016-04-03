open SExpr;;
open Str;;

(*
type aop = Add | Sub | Mul | Antype sop = Lshift | Rshift
type cmp = Less | Lesseq | Equal
type u = W of w | Lable of lable
*)

type l1 = Mem of l1 * l1
        | Mov of l1 * l1
        | Add of l1 * l1
        | Sub of l1 * l1
        | Mul of l1 * l1
        | And of l1 * l1
        | Lshift of l1 * l1
        | Rshift of l1 * l1
        | Cmp of l1 * l1 * string * l1
        | Goto of l1
        | Cjmp of l1 * string * l1 * l1 * l1
        | Call of l1 * l1
        | Tail_call of l1 * l1 * int * int (* callee function args and spillls *)
        | Return of int
        | Print
        | Allocate
        | ArrayError
        | Reg of string
        | Label of string
        | Number of int

(* string -> string *)
let eightbit_reg_map = function
    "r10" -> "r10b"
  | "r11" -> "r11b"
  | "r12" -> "r12b"
  | "r13" -> "r13b"
  | "r14" -> "r14b"
  | "r15" -> "r15b"
  | "r8"  -> "r8b"
  | "r9" -> "r9b"
  | "rax" -> "al"
  | "rbx" -> "bl"
  | "rcx" -> "cl"
  | "rdx" -> "dl"
  | "rdi" -> "dil"
  | "rsi" -> "sil"
  | "rbp" -> "bpl"
  | _ as s -> failwith (Printf.sprintf "l1c error: %s not a valid register name" s)

let adjset_map = function
  | "<=" -> "setge"
  | "<" -> "setg"
  | "=" -> "sete"
  | _ as s -> failwith (Printf.sprintf "l1c error: %s not a valid compare op" s)

let set_map = function
  | "<=" -> "setle"
  | "<" -> "setl"
  | "=" -> "sete"
  | _ as s -> failwith (Printf.sprintf "l1c error: %s not a valid compare op" s)

let adjcondjmp_map = function
  | "<=" -> "jge"
  | "<" -> "jg"
  | "=" -> "je"
  | _ as s -> failwith (Printf.sprintf "l1c error: %s not a valid opeartor" s)

let condjmp_map = function
  | "<=" -> "jle"
  | "<" -> "jl"
  | "=" -> "je"
  | _ as s -> failwith (Printf.sprintf "l1c error: %s not a valid operator" s)

let is_integer s =
  try ignore(int_of_string s); true with Failure _ -> false;;

let is_aop = function
    "=+=" | "-=" | "*=" | "&=" -> true
  | _ -> false

let is_sop = function
    "<<=" | ">>=" -> true
  | _ -> false

let is_cmp = function
    "<" | "<=" |"=" -> true
  | _ -> false

let is_sx s =
  s = "rcx"

let is_a = function
    "rdi" | "rsi" | "rdx" | "r8" | "r9" -> true
  | _ as s -> is_sx s

let is_label s =
  let r = Str.regexp "^:[a-zA-Z_][a-zA-Z_0-9]*$" in
  Str.string_match r s 0

let is_w = function
    "rax" | "rbx" | "rbp" | "r10" | "r11" | "r12" | "r13" | "r14" | "r15" -> true
  | _ as s -> is_a s

let is_x s = is_w s || s = "rsp";;
let is_u s = is_w s || is_label s;;
let is_t s = is_x s || is_integer s;;
let is_s s = is_x s || is_integer s || is_label s;;

(* compile your file here *)
let compile f =
  ()

(* to get list of l1 *)
let parse_func_sexpr = function
  | Expr sexps ->
    begin match sexps with
      | (Atom labl) :: (Atom args) :: (Atom spills) :: rest
        when ((is_integer args) && (is_integer spills)) ->
        let args, spills = int_of_string args, int_of_string spills in

        let rec parse_inst_sexpr = function
          | Atom lb when is_label lb -> Label lb
          | Atom n when is_integer n -> Number (int_of_string n)
          | Atom r when is_x r -> Reg r
          | Expr (Atom "return" :: []) -> Return spills
          | Expr (Atom "mem" :: reg :: off :: []) -> Mem (parse_inst_sexpr reg, parse_inst_sexpr off)
          | Expr (dst :: Atom "<-" :: src :: []) ->
            Mov (parse_inst_sexpr src, parse_inst_sexpr dst)
          | Expr (w :: Atom aop :: t ::[]) when is_aop aop ->
            begin match aop with
              | "+=" -> Add (parse_inst_sexpr t, parse_inst_sexpr w)
              | "-=" -> Sub (parse_inst_sexpr t, parse_inst_sexpr w)
              | "*=" -> Mul (parse_inst_sexpr t, parse_inst_sexpr w)
              | "&=" -> And (parse_inst_sexpr t, parse_inst_sexpr w)
              | _ -> failwith "l1c error: internal error: compiler should never get here"
            end
          | Expr (w :: Atom sop :: t :: []) when is_sop sop ->
            (* assumee w and t are all syntacticly valid for convience *)
            begin match sop with
              | "<<=" -> Lshift (parse_inst_sexpr w, parse_inst_sexpr t)
              | ">>=" -> Rshift (parse_inst_sexpr w, parse_inst_sexpr t)
              | _ -> failwith "l1c error: internal error: compiler should never get here"
            end
          | Expr (w :: Atom "<-" :: t0 :: Atom cmp :: t1 :: []) when is_cmp cmp ->
            Cmp (parse_inst_sexpr w, parse_inst_sexpr t0, cmp, parse_inst_sexpr t1)
          | Expr (Atom "goto" :: lb :: []) -> Goto (parse_inst_sexpr lb)
          | Expr (Atom "cjump" :: t0 :: Atom cmp :: t1 :: lb0 :: lb1 ::[]) when is_cmp cmp ->
            Cjmp (parse_inst_sexpr t0, cmp, parse_inst_sexpr t1,
                  parse_inst_sexpr lb0, parse_inst_sexpr lb1)
          | Expr (Atom "call" :: Atom "print" :: Atom "1" :: []) -> Print
          | Expr (Atom "call" :: Atom "allocate" :: Atom "2" :: []) -> Allocate
          | Expr (Atom "call" :: (Atom ustr as u) :: (Atom nstr as n) :: [])
            when ((is_u ustr) && (is_integer nstr)) -> Call (parse_inst_sexpr u, parse_inst_sexpr n)
          | Expr (Atom "tail-call" :: (Atom ustr as u) :: (Atom nstr as n) :: [])
            when ((is_u ustr) && (is_integer nstr)) ->
            Tail_call (parse_inst_sexpr u, parse_inst_sexpr n, args, spills)
          | _ -> failwith (Printf.sprintf "l1c error: s-expr syntax error\n %s" (string_of_sexpr_indent sexps))
        in
        (Label labl) :: (Number args) ::
        (Number spills) :: List.map parse_inst_sexpr rest
      (* accept only valid function*)
      | _ -> failwith "l1c error: not a valid function"
    end
  | _ -> failwith "l1c error: not a valid function"

(*
let compile_prog =
  | Expr sexp -> ()
  | _ -> failwith "l1c error: not a valid program"
*)

(* l1 instruciton -> x64 string *)
let rec compile_l1 = function 
  | Label s -> "_" ^ String.sub s 1 ((String.length s) - 1)
  | Reg reg -> "%" ^ reg
  | Number num -> "$" ^ string_of_int num
  | Mem (reg, Number off) -> string_of_int off ^ "(" ^ compile_l1 reg ^ ")"
  | Mov (src, dest) -> "movq " ^ compile_l1 src ^ ", " ^ compile_l1 dest
  | Add (lhs, rhs) -> "addq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs
  | Sub (lhs, rhs) -> "subq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs
  | Mul (lhs, rhs) -> "imulq " ^ compile_l1 lhs ^ "," ^ compile_l1 rhs
  | And (lhs, rhs) -> "andq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs
  | Lshift (Reg reg, rhs) -> "sqlq " ^ "%" ^ eightbit_reg_map reg ^ ", " ^ compile_l1 rhs
  | Lshift (lhs, rhs) -> "sqlq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs
  | Rshift (Reg reg, rhs) -> "sqrq " ^ "%" ^ eightbit_reg_map reg ^ ", " ^ compile_l1 rhs
  | Rshift (lhs, rhs) -> "sqrq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs
  | Cmp (dst, lhs, op, rhs) ->
    begin match lhs, rhs with
      | (Number l), (Number r) ->
        begin match op with
          | "<=" -> (if l <= r then "movq " ^ "$1" else "movq " ^ "$0") ^ ", " ^ compile_l1 dst
          | "<" -> (if l < r then "movq " ^ "$1" else "movq " ^ "$0") ^ ", " ^ compile_l1 dst
          | "=" -> (if l = r then "movq " ^ "$1" else "movq " ^ "$0") ^ ", " ^ compile_l1 dst
          | _ -> failwith (Printf.sprintf "l1c error: unvalid cmp op string %s" op)
        end
      | _ ->
        begin match dst with
          | Reg reg ->
            let eightbit_reg = eightbit_reg_map reg in
            let set_inst_map, inst1 = match lhs with
              | Number l -> adjset_map, "cmpq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs ^ "\n"
              | _ -> set_map, "cmpq " ^ compile_l1 rhs ^ ", " ^ compile_l1 lhs ^ "\n"
            in
            let inst2 = set_inst_map op ^ " %" ^ eightbit_reg ^ "\n" in
            let inst3 = "movzbq " ^ " %" ^ eightbit_reg ^ " %" ^ reg in
            inst1 ^ inst2 ^ inst3
          | _ -> failwith "l1c error: cmp dst are supposed to be a resgister"
        end
    end
  | Cjmp (lhs, op, rhs, labl0, labl1) ->
    begin match lhs, rhs with
      | (Number l), (Number r) ->
        let cmpare = match op with
          | "<=" -> (<=)
          | "<" -> (<)
          | "=" -> (=)
          | _ -> failwith (Printf.sprintf "l1c error: cjump invalid opeartor %s" op)
        in
        "jmp " ^ if cmpare l r then compile_l1 labl0 else compile_l1 labl0
      | _ ->
        let condjmp_inst_map, inst1 = match lhs with
          | Number l -> adjcondjmp_map, "cmpq " ^ compile_l1 lhs ^ ", " ^ compile_l1 rhs ^ "\n"
          | _ -> condjmp_map, "cmpq " ^ compile_l1 rhs ^ ", " ^ compile_l1 lhs ^ "\n"
        in
        let condjmp = condjmp_inst_map op in
        let inst2 = condjmp ^ " " ^ compile_l1 labl0 ^ "\n" in
        let inst3 = "jmp " ^ compile_l1 labl1 in
        inst1 ^ inst2 ^ inst3
    end
  | Goto lb -> "jmp " ^ compile_l1 lb
  | Call (labl, Number n) ->
    "subq $" ^ string_of_int (((if n - 6 < 0 then 0 else n - 6) + 1) * 8) ^ ", %rsp\n"
    ^ "jmp " ^ compile_l1 labl
      (* do argument space allocate and pass val only when call via move rsp*)
  | Tail_call (labl, my_args, callee_args, spills) ->
    "addq $" ^ string_of_int (((if callee_args > 6 then callee_args - 6 else 0) + spills) * 8) ^ ", %rsp\n"
    ^ "jmp " ^ compile_l1 labl
      (* "function can only be called at tail position when they have 6 or fewer args so not args in stack "*)
  | Print -> "call print"
  | Allocate -> "call allocate"
  | ArrayError -> "call array_error"
  | Return spills -> "addq $" ^ string_of_int (spills * 8) ^ ", %rsp\n" ^ "ret"
  | _ -> failwith "l1c error: failed to matching instruction"

(* function in l1 -> list of instructions in x64*)
let compile_func = function
  | (Label lb as l1labl) :: Number args :: Number spills :: rest ->
    let inst0 = compile_l1 l1labl ^ ":\n" in
    let inst1 = "subq $" ^ string_of_int (spills * 8) ^ ", %rsp" in
    (* allocate spill when function are defined *)
    (inst0 ^ inst1) :: List.map compile_l1 rest
  | _ -> failwith "l1c error: not a valid function"

(*
let () =
  let len = Array.length Sys.argv in
  match len with
  | 2 -> compile (parse_file Sys.argv.(1))
  | _ -> failwith "l1c error: no input files"
*)

let test_case1 () =
  let inst0 = Mov ((Mem ((Reg "rsp"), (Number (-8)))), (Reg "r10b"))
  and inst1 = Goto (Label":next")
  and inst2 = Mov ((Number 10), (Reg "r10"))
  and inst3 = Mem ((Reg "r8"), (Number (-8)))
  and inst4 = Label ":go"
  and inst5 = Label ":main"
  and inst6 = Print
  and inst7 = Allocate
  and inst8 = ArrayError
  and inst9 = Return 24
  and inst10 = Add ((Reg "r11"), (Reg "rbp"))
  and inst11 = Sub ((Reg "r11"), (Reg "r15"))
  and inst12 = Mul ((Reg "r9"), (Number 10))
  and inst13 = Lshift ((Reg "rcx"), (Reg "rdi"))
  and inst14 = Lshift ((Number 1), (Reg "r9"))
  and inst15 = Rshift ((Reg "rax"), (Reg "rsi"))
  and inst16 = Rshift ((Number 3), (Reg "r8"))
  and inst17 = Cmp ((Reg "rdi"), (Number 10), "<=", (Reg "rax"))
  and inst18 = Cmp ((Reg "rsi"), (Number 10), "<=", (Number 20))
  and inst19 = Cmp ((Reg "rax"), (Number 12), "<=", (Number 11))
  and inst20 = Cmp ((Reg "rbx"), (Reg "rax"), "<=", (Number 20))
  and inst21 = Cjmp ((Reg "rax"), "<=", (Reg "rdi"), (Label ":yes"), (Label ":no"))
  and inst22 = Cjmp ((Number (-2)), "<=", (Reg "rdi"), (Label ":yes"), (Label ":no"))
  in
  print_newline (print_string (compile_l1 inst1));
  print_newline (print_string (compile_l1 inst2));
  print_newline (print_string (compile_l1 inst3));
  print_newline (print_string (compile_l1 inst4));
  print_newline (print_string (compile_l1 inst5));
  print_newline (print_string (compile_l1 inst6));
  print_newline (print_string (compile_l1 inst7));
  print_newline (print_string (compile_l1 inst8));
  print_newline (print_string (compile_l1 inst9));
  print_newline (print_string (compile_l1 inst0));
  print_newline (print_string (compile_l1 inst10));
  print_newline (print_string (compile_l1 inst11));
  print_newline (print_string (compile_l1 inst12));
  print_newline (print_string (compile_l1 inst13));
  print_newline (print_string (compile_l1 inst14));
  print_newline (print_string (compile_l1 inst15));
  print_newline (print_string (compile_l1 inst16));
  print_newline (print_string (compile_l1 inst17));
  print_newline (print_string (compile_l1 inst18));
  print_newline (print_string (compile_l1 inst19));
  print_newline (print_string (compile_l1 inst20));
  print_newline (print_string (compile_l1 inst21));
  print_newline (print_string (compile_l1 inst22));
;;

let test_case2 () =
  let inst0 = Return 3
  and inst1 = Call (Label ":anthortherfunction", Number 11)
  and inst2 = Call (Label ":hello_world1", Number 6)
  and inst3 = Call (Label ":hello_world2", Number 0)
  and inst4 = Call (Label ":hello_world3", Number 20)
  and inst5 = Tail_call (Label ":tailfunction", Number 3, 0, 0)
  and inst6 = Tail_call (Label "tailfunction2", Number 0, 0, 2)
  and inst7 = Tail_call (Label "tailfunction3", Number 6, 7, 2)
  and inst8 = Tail_call (Label "tailfunction4", Number 5, 11, 3)
  in
  print_newline (print_string (compile_l1 inst0));
  print_newline (print_string (compile_l1 inst1));
  print_newline (print_string (compile_l1 inst2));
  print_newline (print_string (compile_l1 inst3));
  print_newline (print_string (compile_l1 inst4));
  print_newline (print_string (compile_l1 inst5));
  print_newline (print_string (compile_l1 inst6));
  print_newline (print_string (compile_l1 inst7));
  print_newline (print_string (compile_l1 inst8));
;;


let test3 str =
  let f se = print_newline (print_string (String.concat "\n" (compile_func (parse_func_sexpr se)))) in
  List.iter f (parse_string str)

(* compiler function *)
let test_cases3 () =
  let func0 = "(:go 0 0 (rdi <- 5) (call print 1) (return))\
               (:go 0 0 (rdi <- 5) (rsi <- 7) (call allocate 2) (rdi <- rax) (call print 1))\
              "
  in
  test3 func0

let () =
  test_cases3 ()