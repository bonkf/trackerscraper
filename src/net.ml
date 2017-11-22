open Core
open Lwt
open Lwt_unix
open Printf

type connection = {
  hash : string;
  socket : Lwt_unix.file_descr;
  mutable cid : [`Active of string | `Inactive | `Closed]; (* connection_id *)
  local_port : int;
  peer_id : string; (* the peer_id we used *)
  address : string (* human readable address for logging (IPv4:Port) *)
}

type scrape_result = {
  leechers : int;
  seeders : int;
  peers : (Unix.Inet_addr.t * int) list
}

type action =
  | Connect
  | Announce
  | Scrape
  | Err

exception Tracker_error of string

exception Invalid_response of string *
  [ `Too_short
  | `Wrong_tid
  | `Invalid_action of int
  | `Unexpected_action of action]

exception Internal_error of string

let get_address { address } = address

let timeout = ref 15.

let set_timeout f = timeout := f

let action_to_string a =
  match a with
  | Connect -> "connect"
  | Announce -> "announce"
  | Scrape -> "scrape"
  | Err -> "error"

let action_of_int i =
  match i with
  | 0 -> Connect
  | 1 -> Announce
  | 2 -> Scrape
  | 3 -> Err
  | _ -> raise @@ Invalid_argument "unknown action"

let log_exn ~log address exn =
  let log_msg =
    match exn with
    | Tracker_error msg ->
      sprintf "tracker error: \"%s\" from %s" msg address
    | Invalid_response (response, reason) ->
      let reason =
        match reason with
        | `Too_short -> "response too short"
        | `Wrong_tid -> "transaction_id not matching"
        | `Invalid_action i -> sprintf "invalid action %d" i
        | `Unexpected_action a -> sprintf "unexpected action %s" (action_to_string a) in
      sprintf "invalid response (%s) from %s\n" reason address
    | Timeout ->
      sprintf "received no response within %fs from %s" !timeout address
    | Internal_error msg ->
      sprintf "internal error (%s)" msg
    | exn ->
      sprintf "other exception (%s)" (Exn.to_string exn) in
  log log_msg

let handle_tracker_error response len tid =
  match String.sub response ~pos:0 ~len:4 with
  | "\x00\x00\x00\x03" ->
    if String.sub response ~pos:4 ~len:4 <> tid then
      fail @@ Invalid_response (response, `Wrong_tid)
    else
      fail @@ Tracker_error (String.sub response ~pos:8 ~len:(len - 8))
  | "\x00\x00\x00\x00"
  | "\x00\x00\x00\x01"
  | "\x00\x00\x00\x02" as a ->
    let action = action_of_int (Util.int_of_4bytes a ~pos:0) in
    fail @@ Invalid_response (response, `Unexpected_action action)
  | _ ->
    fail @@ Invalid_response (response, `Invalid_action (Util.int_of_4bytes response ~pos:0))

let prepare_connect tid =
  (* magic number, action = connect, random transaction_id*)
  "\x00\x00\x04\x17\x27\x10\x19\x80\x00\x00\x00\x00" ^ tid

let verify_connect response len tid =
  if len < 16 then
    fail @@ Invalid_response (response, `Too_short)
  else if String.sub response ~pos:0 ~len:4 <> "\x00\x00\x00\x00" then
    handle_tracker_error response len tid
  else if String.sub response ~pos:4 ~len:4 <> tid then
    fail @@ Invalid_response (response, `Wrong_tid)
  else
    return @@ String.sub response ~pos:8 ~len:8 (* return the connection_id the tracker provided *)

let connect ~log ~hash ~addr ~port =
  let readable_address = sprintf "%s:%d" (Unix.Inet_addr.to_string addr) port in
  try%lwt
    let socket = socket PF_INET SOCK_DGRAM 0 in
    connect socket (ADDR_INET (addr, port)) >>= fun () ->

    let local_port =
      match getsockname socket with (* TODO this is not caught by the try%lwt *)
      | ADDR_UNIX _ -> raise @@ Internal_error "invalid socket"
      | ADDR_INET (_, port) -> port in

    let tid = Util.random_string 4 in
    let msg = prepare_connect tid in
    let%lwt send_len = write socket msg 0 (String.length msg) in
    log @@ sprintf "sent connect (%d bytes, tid: %s) to %s"
      send_len
      (Util.to_hex tid)
      readable_address;

    let recv_buf = String.create 10_000 in
    let%lwt recv_len =
      with_timeout !timeout (fun () -> read socket recv_buf 0 (String.length recv_buf)) in
    let%lwt cid = verify_connect recv_buf recv_len tid in
    log @@ sprintf "received connect (%d bytes, connection_id: %s) from %s"
      recv_len
      (Util.to_hex cid)
      readable_address;

    let connection = {
      hash;
      socket;
      cid = `Active cid;
      local_port;
      peer_id = Util.peer_id ();
      address = readable_address
    } in
    (* apparently we do not need to keep a pointer to the invalidating thread *)
    ignore (sleep 60. >|= fun () -> connection.cid <- `Inactive);
    return connection
  with
  | e ->
    log_exn ~log readable_address e;
    fail e

let reconnect ~log ({ socket; address; _ } as connection) =
  try%lwt
    let tid = Util.random_string 4 in
    let msg = prepare_connect tid in
    let%lwt send_len = write socket msg 0 (String.length msg) in
    log @@ sprintf "sent reconnect (%d bytes, tid: %s) to %s"
      send_len
      (Util.to_hex tid)
      address;

    let recv_buf = String.create 10_000 in
    let%lwt recv_len =
      with_timeout !timeout (fun () -> read socket recv_buf 0 (String.length recv_buf)) in
    let%lwt cid = verify_connect recv_buf recv_len tid in
    log @@ sprintf "received reconnect (%d bytes, connection_id: %s) from %s"
      recv_len
      (Util.to_hex cid)
      address;

    connection.cid <- `Active cid;

    ignore (sleep 60. >|= fun () -> connection.cid <- `Inactive);
    return_unit
  with
  | e ->
    log_exn ~log address e;
    fail e

let prepare_announce cid tid info_hash peer_id local_port num_want event =
  let event =
    match event with
    | `None -> '\x00'
    | `Completed -> '\x01'
    | `Started -> '\x02'
    | `Stopped -> '\x03' in

  (* constants are action = announce, downloaded, left, uploaded, IP address = 0 *)
  sprintf
    "%s\
     \x00\x00\x00\x01\
     %s\
     %s\
     %s\
     \x00\x00\x00\x00\x00\x00\x00\x00\
     \xff\xff\xff\xff\xff\xff\xff\xff\
     \x00\x00\x00\x00\x00\x00\x00\x00\
     \x00\x00\x00%c\
     \x00\x00\x00\x00\
     %s\
     \x00\x00\x00%c\
     %c%c"
    cid (* connection_id *)
    tid (* transaction_id *)
    (Util.from_hex info_hash)
    peer_id
    event
    (Util.random_string 4) (* we'll just generate 4 random bytes for the key *)
    (num_want land 0xff |> Char.of_int_exn)
    ((local_port lsr 8) land 0xff |> Char.of_int_exn) (* upper and lower byte of the port *)
    (local_port land 0xff |> Char.of_int_exn)

let verify_announce response len tid =
  if len < 20 then
    fail @@ Invalid_response (response, `Too_short)
  else if String.sub response ~pos:0 ~len:4 <> "\x00\x00\x00\x01" then
    handle_tracker_error response len tid
  else if String.sub response ~pos:4 ~len:4 <> tid then
    fail @@ Invalid_response (response, `Wrong_tid)
  else
    let leechers = Util.int_of_4bytes response ~pos:12 in
    let seeders = Util.int_of_4bytes response ~pos:16 in

    let num_peers = (len - 20) / 6 in
    let rec loop acc n =
      if n >= 0 then
        let offset = (20 + (6 * n)) in
        let addr = (* Inet_addr.t is represented as a string internally, this is very unsafe *)
          (Obj.magic (String.sub response ~pos:offset ~len:4) : Unix.Inet_addr.t) in
        let port =
          (Char.to_int response.[offset + 4] lsl 8) + (Char.to_int response.[offset + 5]) in
        loop ((addr, port) :: acc) (n - 1)
      else acc in

    return { leechers; seeders; peers = loop [] (num_peers - 1) }

let rec announce ~log ({ hash; socket; cid; local_port; peer_id; address } as c) ~num_want event =
  match cid with
  | `Closed ->
    log @@ sprintf "connection already closed (%s)" address;
    fail @@ Internal_error "connection already closed"
  | `Inactive ->
    log @@ sprintf "connection timed out, reconnecting (%s)" address;
    reconnect ~log c >>= fun () ->
    announce ~log c ~num_want event
  | `Active cid ->
    try%lwt
      let tid = Util.random_string 4 in
      let msg = prepare_announce cid tid hash peer_id local_port num_want event in
      let%lwt send_len = write socket msg 0 (String.length msg) in
      log @@ sprintf "sent announce %s (%d bytes, cid: %s, tid: %s, num_want %d) to %s"
        (match event with `Started -> "started" | `None -> "none")
        send_len
        (Util.to_hex cid)
        (Util.to_hex tid)
        num_want
        address;

      let recv_buf = String.create 10_000 in
      let%lwt recv_len =
        with_timeout !timeout (fun () -> read socket recv_buf 0 (String.length recv_buf)) in
      let%lwt { leechers; seeders; peers } as result = verify_announce recv_buf recv_len tid in
      log @@ sprintf
        "received announce response (%d bytes, cid: %s, %d leechers, %d seeders, %d peers) from %s"
        recv_len
        (Util.to_hex cid)
        leechers
        seeders
        (List.length peers)
        address;

      return result
    with
    | e ->
      log_exn ~log address e;
      fail e

let close ~log ({ hash; socket; cid; local_port; peer_id; address } as c) =
  match cid with
  | `Closed ->
    log @@ sprintf "connection already closed (%s)" address;
    return_unit
  | `Inactive ->
    log @@ sprintf "connection already inactive (%s)" address;
    c.cid <- `Closed;
    close socket
  | `Active cid ->
    let tid = Util.random_string 4 in
    let msg = prepare_announce cid tid hash peer_id local_port 0 `Stopped in
    let%lwt send_len = write socket msg 0 (String.length msg) in
    log @@ sprintf "sent announce stopped (%d bytes, tid %s) to %s"
      send_len
      (Util.to_hex tid)
      address;
    c.cid <- `Closed;
    close socket
