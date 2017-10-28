{
type token =
  | Name of string
  | Udp_tracker of string * int
  | Http_tracker of string * int * string
  | Peer of string * int
  | EOF
}

let num = ['0' - '9']+

rule prefix = parse
  "magnet:?xt=urn:btih:" ([^ '&']* as hash) { hash }

and read = parse
  | "&dn=" ([^ '&']* as name) { Name name }
  | "&tr=udp://" ([^ ':']* as addr) ':' (num as port)
    { Udp_tracker (addr, int_of_string port)}
  | "&tr=udp%3A%2F%2F" ([^ '%']* as addr) "%3A" (num as port)
    { Udp_tracker (addr, int_of_string port)}
  | "&tr=http://" ([^ ':']* as addr) ':' (num as port) ([^ '&']* as path)
    { Http_tracker (addr, int_of_string port, path)}
  | "&tr=http%3A%2F%2F" ([^ '%']* as addr) "%3A" (num as port) ([^ '&']* as path)
    { Http_tracker (addr, int_of_string port, path)}
  | "&x.pe=" ([^ ':']* as addr) ':' (num as port) { Peer (addr, int_of_string port)}
  | eof { EOF }
