[@@@alert "-unstable"]
[@@@warning "-32"]

module Clock = struct
  type _ Effect.t += Get : Eio.Time.clock Effect.t

  let get () = Effect.perform Get
  let sleep flt = Eio.Time.sleep (get ()) flt
  let now () = Eio.Time.now (get ())

  let run (clock : Eio.Time.clock) f =
    let effc (type a) (eff : a Effect.t) : ((a, 'r) Effect.Deep.continuation -> 'r) option
      =
      match eff with
      | Get -> Some (fun k -> Effect.Deep.continue k clock)
      | _ -> None
    in
    Effect.Deep.try_with f () { effc }
  ;;
end

module Chan_async = struct
  module C = Domainslib.Chan

  exception Recv_closed

  type 'a t =
    { chan : 'a C.t
    ; closed : bool Atomic.t
    }

  let make () = { chan = C.make_unbounded (); closed = Atomic.make false }

  let rec recv t =
    match C.recv_poll t.chan with
    | Some v -> v
    | None ->
      if Atomic.get t.closed then raise Recv_closed else Eio.Fiber.yield ();
      recv t
  ;;

  let rec send t v =
    if C.send_poll t.chan v
    then ()
    else (
      if Atomic.get t.closed then () else Eio.Fiber.yield ();
      send t v)
  ;;

  let drain t = ignore @@ recv t
  let close t = Atomic.set t.closed true

  module Syntax = struct
    let ( <~ ) chan v = send chan v
    let ( ~> ) chan = recv chan
    let ( ~>! ) chan = drain chan
  end

  let rec recv_forever t f =
    try
      let v = recv t in
      ignore @@ f v;
      recv_forever t f
    with
    | Recv_closed -> ()
  ;;
end

open Chan_async.Syntax

let rec fib n = if n < 3 then n else fib (n - 1) + fib (n - 2)
let run_in_fiber sw f = Eio.Fiber.fork ~sw f

let worker ~clock ~stdout id jobs results =
  Chan_async.recv_forever jobs
  @@ fun j ->
  Clock.run clock
  @@ fun () ->
  Eio.Flow.copy_string (Printf.sprintf "worker %d started job %d\n" id j) stdout;
  (* let res = fib j in *)
  Clock.sleep 1.;
  Eio.Flow.copy_string (Printf.sprintf "worker %d finished job %d\n" id j) stdout;
  results <~ j * 2
;;

(* results <~ res *)

let main sw ~clock ~stdout =
  let jobs = Chan_async.make () in
  let results = Chan_async.make () in
  let num_jobs = 3 in
  let num_data = 5 in
  let start = Eio.Time.now clock in
  for w = 1 to num_jobs do
    run_in_fiber sw @@ fun () -> worker ~clock ~stdout w jobs results
  done;
  for j = 1 to num_data do
    jobs <~ 40 + j
  done;
  Chan_async.close jobs;
  for _ = 1 to num_data do
    ~>!results
  done;
  let end' = Eio.Time.now clock in
  Eio.Flow.copy_string (Printf.sprintf "%f sec\n" (end' -. start)) stdout
;;

let () =
  Eio_main.run @@ fun env -> Eio.Switch.run @@ main ~clock:env#clock ~stdout:env#stdout
;;
