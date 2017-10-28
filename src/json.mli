open Core

type ok_result = {
  info_hash : string;
  name : string option;
  peers : (string option * Unix.Inet_addr.t * int) list;
  udp_trackers : (string option * Unix.Inet_addr.t * int * (Net.scrape_result, exn) result) list
}

val to_json : (ok_result, exn) result -> Yojson.Safe.json
