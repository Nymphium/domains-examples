open Eio
module Chan = Domainslib.Chan

type 'a t = 'a Chan.t

let create_empty () = Chan.make_bounded 1

let create v =
  let t = create_empty () in
  Chan.send t v;
  t
;;

let rec take t =
  match Chan.recv_poll t with
  | None ->
    Fiber.yield ();
    take t
  | Some v -> v
;;

let take_opt = Chan.recv_poll

let rec put t v =
  if Chan.send_poll t v
  then ()
  else (
    Fiber.yield ();
    put t v)
;;

let try_put = Chan.send_poll

let compare t v' =
  let v = take t in
  put t v;
  v = v'
;;

let is_empty t =
  match take_opt t with
  | Some v ->
    put t v;
    true
  | None -> false
;;

let rec swap t v' =
  match Chan.recv_poll t with
  | None ->
    Fiber.yield ();
    swap t v'
  | Some v ->
    put t v';
    v
;;

let rec modify t f =
  match Chan.recv_poll t with
  | None ->
    Fiber.yield ();
    modify t f
  | Some v -> put t (f v)
;;
