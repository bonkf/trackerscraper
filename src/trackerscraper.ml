open Core
open Lwt
open Printf
open Out_channel
open Command

let trackerscraper_version = "0.3.2"

let summary = "query trackers for provided magnet link"

let run magnet log out pretty num_want rescrape seq timeout =
  let log =
    match log with
    | None -> ignore
    | Some file ->
      let log_fun oc str =
        fprintf oc "[%s] %s\n" Time.(to_string (now ())) str;
        flush oc in
      let oc =
        if file = "--" then stdout
        else
          try create file with
          | Sys_error _ (* permisson denied or invalid path *) ->
            log_fun stdout (sprintf "could not create log file %s, falling back to stdout\n" file);
            stdout in
      log_fun oc in

  let oc =
    match out with
    | None | Some "--" -> stdout
    | Some file ->
      try create file with
      | Sys_error _ (* permisson denied or invalid path *) ->
        log (sprintf "could not create output file %s, falling back to stdout\n" file);
        stdout in

  let output_json =
    if pretty then
      Yojson.Safe.pretty_to_channel oc
    else
      Yojson.Safe.to_channel oc in

  begin match timeout with
  | Some time -> Net.set_timeout time
  | None -> ()
  end;

  try%lwt
    let%lwt Magnet.{ info_hash; name; udp_trackers; peers; http_trackers } =
      Magnet.parse_magnet_link ~log magnet in

    let scrape_tracker (host, addr, port) =
      try%lwt
        let%lwt connection = Net.connect ~log ~hash:info_hash ~addr ~port in

        let announce = Net.announce ~log connection in

        let%lwt Net.{ leechers; seeders; peers } as first_scrape = announce ~num_want `Started in

        let required = leechers + seeders in
        log @@ sprintf "attempting to fetch %d peers from %s" required (Net.get_address connection);
        let rescrapes = ref rescrape in
        let peer_set =
          Hash_set.Poly.of_list first_scrape.Net.peers in

        while%lwt Hash_set.length peer_set < required && !rescrapes > 0 do
          let%lwt Net.{ peers; _ } =
            announce ~num_want:(Int.min num_want (required - Hash_set.length peer_set)) `None in
          List.iter peers ~f:(Hash_set.add peer_set);
          decr rescrapes;
          return_unit
        done >>= fun () ->
        Net.close ~log connection >>= fun () ->
        let scrape_result = Net.{ first_scrape with peers = Hash_set.to_list peer_set } in
        return (host, addr, port, Ok scrape_result)
      with
      | exn -> return (host, addr, port, Error exn) in

    let%lwt scrape_results =
      Lwt_list.(if seq then map_s else map_p) scrape_tracker udp_trackers in
    let json =
      Json.to_json @@ Ok Json.{ info_hash; name; peers; udp_trackers = scrape_results } in
    output_json json;
    return_unit
  with
  | exn ->
    let json = Json.to_json @@ Error exn in
    output_json json;
    return_unit

let command =
  basic_spec ~summary ?readme:None
    Spec.(
      empty
      +> anon ("magnet-link" %: string)
      +> flag "--log" (optional string)
        ~doc:"logfile output logging information to logfile (-- for stdout)"
      +> flag "--output" (optional string) ~aliases:["-o"]
        ~doc:"outfile output json result to outfile (-- for stdout)"
      +> flag "-pretty" no_arg
        ~doc:" pretty-print json"
      +> flag "--num-want" (optional_with_default 80 int)
        ~doc:"n request n peers from a tracker (default: 80; < 255 required)"
      +> flag "--rescrape" (optional_with_default 0 int)
        ~doc:"n request new peers n times (default: 0; may return the same peers)"
      +> flag "-sequential" no_arg
        ~doc:" scrape trackers sequentially instead of in parallel"
      +> flag "--timeout" (optional float) ~aliases:["-t"]
        ~doc:"n wait for responses for n seconds"
    ) (fun magnet log out pretty num_want rescrape seq timeout () ->
        Lwt_main.run (run magnet log out pretty num_want rescrape seq timeout))

let () =
  let build_info =
    sprintf
      "trackerscraper version: %s\n\
       OCaml version: %s\n\
       Execution mode: %s\n\
       OS type: %s\n\
       Executable: %s"
      trackerscraper_version
      Sys.ocaml_version
      (match Sys.execution_mode () with `Native -> "native" | `Bytecode -> "bytecode")
      Sys.os_type
      Sys.executable_name in
  Command.run ~version:trackerscraper_version ~build_info command
