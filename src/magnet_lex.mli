type token =
  | Name of string
  | Udp_tracker of string * int
  | Http_tracker of string * int * string
  | Peer of string * int
  | EOF

val prefix : Lexing.lexbuf -> string

val read : Lexing.lexbuf -> token