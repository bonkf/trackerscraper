open Core

let () = Random.self_init ()

type log = string -> unit

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
    Char.to_int c - offset c in

  String.init
    (String.length str / 2)
    ~f:(fun i -> Char.of_int_exn ((hex_to_int str.[2 * i] lsl 4) + (hex_to_int str.[(2 * i) + 1])))

let to_hex ?(upper = false) str =
  let f i =
    let c = Char.to_int str.[i / 2] in
    let nibble = if i mod 2 = 0 then c lsr 4 else c land 0xf in
    let offset =
      match nibble with
      | n when n >= 0x0 && n < 0xa -> 48
      | n when n >= 0xa && n <= 0xf -> if upper then 55 else 87
      | _ -> raise @@ Invalid_argument "invalid nibble" (* this should never happen *) in
    Char.of_int_exn (nibble + offset) in

  String.init (String.length str * 2) ~f

let random_string len =
  String.init len ~f:(fun _ -> Random.int 256 |> Char.of_int_exn)

let peer_id () = (* faking a Transmission 2.92 peer id *)
  let pool = "0123456789abcdefghijklmnopqrstuvwxyz" in
  let pool_len = String.length pool in
  "-TR2920-" ^ (String.init 12 ~f:(fun _ -> pool.[Random.int pool_len]))

let int_of_4bytes str ~pos =
  let i = Char.to_int in
  (i str.[pos] lsl 24)
  + (i str.[pos + 1] lsl 16)
  + (i str.[pos + 2] lsl 8)
  + (i str.[pos + 3])

let unescape str =
  let len = String.length str in
  let out = Buffer.create len in (* out is <= str, so we won't have to reallocate *)
  let rec loop in_index =
    if in_index < len then
      if str.[in_index] = '%' then
        let first = str.[in_index + 1] in
        let second = str.[in_index + 2] in
        begin try
          ((Char.to_int first - offset first) lsl 4) + (Char.to_int second - offset second)
        with
        | Invalid_argument _ (* index out of bounds *) ->
          raise @@ Invalid_argument "% too close to end of string"
        end
        |> Char.of_int_exn
        |> Buffer.add_char out
      else
        Buffer.add_char out str.[in_index] in
  loop 0;
  Buffer.to_bytes out
