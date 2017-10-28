open Core

type connection

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

(* return human-readable address *)
val get_address : connection -> string

val set_timeout : float -> unit

val action_to_string : action -> string

val connect : log:Util.log -> hash:string -> addr:Unix.Inet_addr.t -> port:int -> connection Lwt.t

(* reconnect required after 60 seconds *)
val reconnect : log:Util.log -> connection -> unit Lwt.t

val announce : log:Util.log -> connection -> num_want:int -> [`Started | `None] -> scrape_result Lwt.t

(* sends announce stopped *)
val close : log:Util.log -> connection -> unit Lwt.t
