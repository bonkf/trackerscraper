open Core
open Lwt

type magnet_info = {
  info_hash : string;
  name : string option;
  udp_trackers : (string option * Unix.Inet_addr.t * int) list;
  http_trackers : (string option * Unix.Inet_addr.t * int * string) list;
  peers : (string option * Unix.Inet_addr.t * int) list
}

exception Broken_link of [`No_info_hash | `Other]

let parse_magnet_link ~log link =
  let open Magnet_lex in
  let lexbuf = Lexing.from_string link in
  let%lwt info_hash =
    try%lwt return @@ prefix lexbuf with
    | Failure _ ->
      log @@ sprintf "no info_hash found in magnet link \"%s\" (possibly non-standard position)"
        link;
      fail @@ Broken_link `No_info_hash in

  let empty_info = {
    info_hash;
    name = None;
    udp_trackers = [];
    http_trackers = [];
    peers = []
  } in

  let rec loop info =
    let addr_of_str addr =
      let open Unix.Inet_addr in
      try None, Some (of_string addr) with
      | _ ->
        try Some addr, Some (of_string_or_getbyname addr) with
        | _ -> None, None in

    try%lwt match read lexbuf with
    | Name name -> loop { info with name = Some name }
    | Udp_tracker (addr, port) ->
      let new_info =
        match addr_of_str addr with
        | _, None -> info
        | None, Some addr ->
          { info with udp_trackers = (None, addr, port) :: info.udp_trackers }
        | Some hostname, Some addr ->
          { info with udp_trackers = (Some hostname, addr, port) :: info.udp_trackers } in
      loop new_info
    | Http_tracker (addr, port, path) ->
      let new_info =
        match addr_of_str addr with
        | _, None -> info
        | None, Some addr ->
          { info with http_trackers = (None, addr, port, path) :: info.http_trackers }
        | Some hostname, Some addr ->
          { info with http_trackers = (Some hostname, addr, port, path) :: info.http_trackers } in
      loop new_info
    | Peer (addr, port) ->
      let new_info =
        match addr_of_str addr with
        | _, None -> info
        | None, Some addr ->
          { info with peers = (None, addr, port) :: info.peers }
        | Some hostname, Some addr ->
          { info with peers = (Some hostname, addr, port) :: info.peers } in
      loop new_info
    | EOF -> return info
    with
    | Failure _ as exn ->
      log @@ sprintf "lexer failure: %s" (Exn.to_string exn);
      fail @@ Broken_link `Other in

  let%lwt result = loop empty_info in
  let summarise_udp_trackers_and_peers (host, ip, port) =
    sprintf "  %s%s:%d\n"
      (match host with Some name -> name ^ "/" | None -> "")
      (Unix.Inet_addr.to_string ip)
      port
  and summarise_http_trackers (host, ip, port, path) =
    sprintf "  %s%s:%d%s\n"
      (match host with Some name -> name ^ "/" | None -> "")
      (Unix.Inet_addr.to_string ip)
      port
      path in
  log @@ sprintf
    "parsed magnet link \"%s\" with result:\ninfo_hash: %s\nname: %s\n\
     udp trackers:\n%shttp trackers:\n%speers:\n%s"
    link
    result.info_hash
    (match result.name with Some str -> str | None -> "")
    (List.fold
      result.udp_trackers
      ~init:""
      ~f:(fun acc tracker -> acc ^ summarise_udp_trackers_and_peers tracker))
    (List.fold
      result.http_trackers
      ~init:""
      ~f:(fun acc tracker -> acc ^ summarise_http_trackers tracker))
    (List.fold
      result.peers
      ~init:""
      ~f:(fun acc peer -> acc ^ summarise_udp_trackers_and_peers peer));

  return @@ result
