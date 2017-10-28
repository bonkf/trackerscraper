open Core
open Yojson.Safe
open Printf

type ok_result = {
  info_hash : string;
  name : string option;
  peers : (string option * Unix.Inet_addr.t * int) list;
  udp_trackers : (string option * Unix.Inet_addr.t * int * (Net.scrape_result, exn) result) list
}

let ip_str = Unix.Inet_addr.to_string

let default d = function
  | None -> d
  | Some v -> v

let handle_peers =
  List.map
    ~f:(fun (host, ip, port) -> `Assoc [
        ("hostname", match host with None -> `Null | Some name -> `String name);
        ("ip", `String (ip_str ip));
        ("port", `Int port)
      ])

let handle_trackers =
  List.map
    ~f:(fun (host, ip, port, result) ->
      let open Net in
      let error, errormsg =
        match result with
        | Error (Tracker_error msg) ->
          `Int 1, `String ("tracker error: " ^ msg)
        | Error (Invalid_response (_, `Too_short)) ->
          `Int 2, `String "tracker response too short"
        | Error (Invalid_response (_, `Wrong_tid)) ->
          `Int 3, `String "tracker response has wrong tid"
        | Error (Invalid_response (_, `Invalid_action a)) ->
          `Int 4, `String (sprintf "tracker response has invalid action code %d" a)
        | Error (Invalid_response (_, `Unexpected_action a)) ->
          `Int 5, `String (sprintf "tracker response has unexpected action %s" (action_to_string a))
        | Error (Internal_error msg) ->
          `Int 6, `String ("internal error: " ^ msg)
        | Error (Lwt_unix.Timeout) ->
          `Int 7, `String "request timed out"
        | Error exn ->
          `Int 0, `String ("unknown error: " ^ Exn.to_string exn)
        | Ok _ ->
          `Null, `Null in

      let default_fields = [
        ("error", error);
        ("errormsg", errormsg);
        ("hostname", match host with None -> `Null | Some name -> `String name);
        ("ip", `String (ip_str ip));
        ("port", `Int port)
      ] in

      match result with
      | Error _ ->
        `Assoc default_fields
      | Ok { leechers; seeders; peers } ->
        let peers =
          List.map
            peers
            ~f:(fun (addr, port) ->
              `Assoc [
                ("ip", `String (ip_str addr));
                ("port", `Int port)
              ]) in
        `Assoc (("leechers", `Int leechers)
        :: ("seeders", `Int seeders)
        :: ("peers", `List peers)
        :: ("numberPeers", `Int (List.length peers))
        :: default_fields))

let to_json result =
  match result with
  | Error (Magnet.Broken_link `No_info_hash) ->
    `Assoc [
      ("error", `Int 1);
      ("errormsg", `String "broken link: no info hash in magnet link")
    ]
  | Error (Magnet.Broken_link `Other) ->
    `Assoc [
      ("error", `Int 2);
      ("errormsg", `String "broken link: other lexer failure")
    ]
  | Error exn ->
    `Assoc [
      ("error", `Int 0);
      ("errormsg", `String ("unkown error: " ^ Exn.to_string exn))
    ]
  | Ok { info_hash; name; peers; udp_trackers } ->
    `Assoc [
      ("error", `Null);
      ("errormsg", `Null);
      ("hash", `String info_hash);
      ("name", match name with None -> `Null | Some n -> `String n);
      ("peers", `List (handle_peers peers));
      ("numberTrackers", `Int (List.length udp_trackers));
      ("trackers", `List (handle_trackers udp_trackers))
    ]
