open Core

type magnet_info = {
  info_hash : string;
  name : string option;
  udp_trackers : (string option * Unix.Inet_addr.t * int) list;
  http_trackers : (string option * Unix.Inet_addr.t * int * string) list;
  peers : (string option * Unix.Inet_addr.t * int) list
}

(* in case of `No_trackers we return the peers we found in the link (if there were any) *)
exception Broken_link of [`No_info_hash | `Other]

val parse_magnet_link : log:Util.log -> string -> magnet_info Lwt.t
