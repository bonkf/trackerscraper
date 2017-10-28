open Core

type log = string -> unit

val from_hex : string -> string

(* to_hex ~upper:true "\xab" = "AB" *)
val to_hex : ?upper:bool -> string -> string

val random_string : int -> string

val peer_id : unit -> string

val int_of_4bytes : string -> pos:int -> int

(* replaces every '%YZ' substring with the character 0xYZ represents *)
val unescape : string -> string
