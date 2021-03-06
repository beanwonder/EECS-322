open SExpr
open Str
open Int64
open Utils_l2

(* f : sexpr list, var : string, prefix : string *)
let spill func_sexpr var prefix =
  begin match func_sexpr with
  | Expr (l :: ag :: Atom spills :: rest) ->
    let spills = int_of_string spills in
    let spills_n8 = string_of_int (spills * 8) in
    let is_var_to_spill s = (s = var) in
    let counter = ref 0 in
    let spill_inst = function
      | Expr [Atom w; Atom "<-"; Atom s] as inst ->
        (* w <- s *)
        if (is_var_to_spill w && is_var_to_spill s) then
          []
        else if is_var_to_spill w then
          Expr [Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]; Atom "<-"; Atom s] :: []
        else if is_var_to_spill s then
          Expr [Atom w; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] :: []
        else
          [inst]
      | Expr [Atom w; Atom "<-"; Expr [Atom "stack-arg"; _] as stack_acc] when is_var_to_spill w ->
        (* w <- (stack-arg n8) *)
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix
        in
        incr counter;
        Expr [Atom var_after_spill; Atom "<-"; stack_acc] ::
        Expr [Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]; Atom "<-"; Atom var_after_spill] :: []
      | Expr [Atom w; Atom "<-"; Expr [Atom "mem"; Atom x; Atom n8] as mem]
        when (is_var_to_spill w || is_var_to_spill x) ->
        (* w <- (mem x n8)*)
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix in
        let mread = Expr [Atom var_after_spill; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] in
        let assign_inst =
          Expr [if is_var_to_spill w then Atom var_after_spill else Atom w;
                Atom "<-";
                if is_var_to_spill x then Expr [Atom "mem"; Atom var_after_spill; Atom n8] else mem] in
        let mwrite = Expr [Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]; Atom "<-"; Atom var_after_spill]
        in
        incr counter;
        if is_var_to_spill w && is_var_to_spill x then
          mread :: assign_inst :: mwrite :: []
        else if is_var_to_spill w then
          assign_inst :: mwrite :: []
        else
          mread :: assign_inst :: []
      | Expr [Expr [Atom "mem"; Atom x; Atom n8] as mem; Atom "<-"; Atom s]
        when (is_var_to_spill x || is_var_to_spill s) ->
        (* (mem x n8) <- s *)
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix in
        let mread = Expr [Atom var_after_spill; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] in
        let assign_inst =
          Expr [if is_var_to_spill x then Expr [Atom "mem"; Atom var_after_spill; Atom n8] else mem;
                Atom "<-";
                if is_var_to_spill s then Atom var_after_spill else Atom s]
        in
        incr counter;
        mread :: assign_inst :: []
      | Expr [Atom w; Atom op; Atom t] when ((is_aop op || is_sop op) && (is_var_to_spill w || is_var_to_spill t)) ->
        (* combined with sop and aop *)
        (* assume no invalid input here *)
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix in
        let mread = Expr [Atom var_after_spill; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] in
        let op_inst = Expr [if is_var_to_spill w then Atom var_after_spill else Atom w;
                            Atom op;
                            if is_var_to_spill t then Atom var_after_spill else Atom t] in
        let mwrite = Expr [Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]; Atom "<-"; Atom var_after_spill]
        in
        incr counter;
        if is_var_to_spill w then
          mread :: op_inst :: mwrite :: []
        else
          mread :: op_inst :: []
      | Expr [Atom w; Atom "<-"; Atom t1; Atom cmp; Atom t2]
        when (is_var_to_spill w || is_var_to_spill t1 || is_var_to_spill t2) ->
        (* cmp *)
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix in
        let mread = Expr [Atom var_after_spill; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] in
        let mwrite = Expr [Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]; Atom "<-"; Atom var_after_spill] in
        let cmp_inst = Expr [if is_var_to_spill w then Atom var_after_spill else Atom w;
                             Atom "<-";
                             if is_var_to_spill t1 then Atom var_after_spill else Atom t1;
                             Atom cmp;
                             if is_var_to_spill t2 then Atom var_after_spill else Atom t2]
        in
        incr counter;
        if is_var_to_spill w then
          if is_var_to_spill t1 || is_var_to_spill t2 then
            mread :: cmp_inst :: mwrite :: []
          else
            cmp_inst :: mwrite :: []
        else
          mread :: cmp_inst :: []
      | Expr [Atom "cjump"; Atom t1; Atom cmp; Atom t2; label1; label2]
        when (is_var_to_spill t1 || is_var_to_spill t2) ->
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix in
        let mread = Expr [Atom var_after_spill; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] in
        let cjump_inst = Expr [Atom "cjump";
                               if is_var_to_spill t1 then Atom var_after_spill else Atom t1;
                               Atom cmp;
                               if is_var_to_spill t2 then Atom var_after_spill else Atom t2;
                               label1;
                               label2]
        in
        incr counter;
        mread :: cjump_inst :: []
      | Expr [Atom c as call; Atom u; Atom nat]
        when ((c = "call" || c = "tail-call") && is_var_to_spill u) ->
        let suffix = string_of_int !counter in
        let var_after_spill = prefix ^ suffix in
        begin
          incr counter;
          Expr [Atom var_after_spill; Atom "<-"; Expr [Atom "mem"; Atom "rsp"; Atom spills_n8]] ::
          Expr [call; Atom var_after_spill; Atom nat] :: []
        end
      | _ as inst -> [inst]
      (* assume no invalid input here*)
    in
    let spill_and_acc acc inst = List.append acc (spill_inst inst) in
    Expr (l :: ag :: Atom (string_of_int (spills + 1)) :: List.fold_left spill_and_acc [] rest)
  | _ -> failwith "l2-spill: error: not a valid function"
  end


(* 
let test0 () =
  let func0 = "(:f 
  8 0
  (x <- rdi)
  (y <- (stack-arg 0))
  (z <- (stack-arg 8))
  (a <- 3)
  (a += x)
  (a += y)
  (a += z))"
  in
  match (List.hd (parse_string func0)) with
  | Expr fl -> print_sexpr (spill_in_function fl "a" "s")
  | _ -> failwith "test0: invalid input"

let run_tests () =
  test0 ()

let () =
      let func = read_line () in
      let var = read_line () in
      let prefix = read_line () in
      match parse_string func with
      | [func_lst] -> print_sexpr [spill func_lst var prefix]
      | _ -> failwith "spill_reader: error: not a valid "
*)
