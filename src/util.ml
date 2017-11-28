open Core

let () = Random.self_init ()

type log = string -> unit

let ci = Char.to_int
let ic = Char.of_int_exn

let offset c =
  match c with
  | '0' .. '9' -> 48
  | 'a' .. 'f' -> 87
  | 'A' .. 'F' -> 55
  | _ -> raise @@ Invalid_argument "invalid hex digit"

let from_hex str =
  let str = (* if str is not of even length we pad with a '0' *)
    if String.length str mod 2 <> 0 then "0" ^ str else str in

  let hex_to_int c =
    ci c - offset c in

  String.init
    (String.length str / 2)
    ~f:(fun i -> ic ((hex_to_int str.[2 * i] lsl 4) + (hex_to_int str.[(2 * i) + 1])))

let to_hex ?(upper = false) str =
  let f i =
    let c = ci str.[i / 2] in
    let nibble = if i mod 2 = 0 then c lsr 4 else c land 0xf in
    let offset =
      if nibble < 0xa then 48 (* 0x0 <= nibble <= 0xf *)
      else if upper then 55 else 87 in
    ic (nibble + offset) in

  String.init (String.length str * 2) ~f

let random_string len =
  String.init len ~f:(fun _ -> Random.int 256 |> ic)

let peer_id () = (* faking a Transmission 2.92 peer id *)
  let pool = "0123456789abcdefghijklmnopqrstuvwxyz" in
  let pool_len = String.length pool in
  "-TR2920-" ^ (String.init 12 ~f:(fun _ -> pool.[Random.int pool_len]))

let int_of_4bytes str ~pos =
  (ci str.[pos] lsl 24)
  + (ci str.[pos + 1] lsl 16)
  + (ci str.[pos + 2] lsl 8)
  + (ci str.[pos + 3])

let unescape str =
  let len = String.length str in
  let out = Buffer.create len in (* out is <= str, so we won't have to reallocate *)
  let rec loop in_index =
    if in_index < len then
      if str.[in_index] = '%' then begin
        let new_char =
          try
            let first = str.[in_index + 1] in
            let second = str.[in_index + 2] in
            ((ci first - offset first) lsl 4) + (ci second - offset second)
          with
          | Invalid_argument _ (* index out of bounds *) ->
            raise @@ Invalid_argument "% too close to end of string" in
        ic new_char
        |> Buffer.add_char out;
        loop (in_index + 3)
      end else begin
        Buffer.add_char out str.[in_index];
        loop (in_index + 1)
      end in
  loop 0;
  Buffer.to_bytes out
 