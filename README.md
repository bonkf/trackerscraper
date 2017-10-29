# `trackerscraper`

`trackerscraper` is a tool for retrieving BitTorrent peer IP addresses from BitTorrent trackers.
It was quickly written by me for a university project.
As such it is very rough around the edges and most certainly not stable.
Read the disclaimer below.

## Features

Currently `trackerscraper` only supports [magnet links](http://bittorrent.org/beps/bep_0009.html)
(looks like `magnet:?xt=...`; often found on torrent index sites) and only supports
[UDP trackers](http://bittorrent.org/beps/bep_0015.html).
It features some rudimentary logging.
It outputs results and errors as JSON.
The error codes can be seen in `src/json.ml`.
It can handle escaped magnet links (`%3A` instead of `:` for example).

## Installation

### `opam` installation

Install using:
```
$ opam pin add trackerscraper git://github.com/Reperator/trackerscraper.git
```
`opam` should automatically install dependencies.

Uninstall using:
```
$ opam pin remove trackerscraper
```

### manual installation

Clone the repository and in the root directory run:
```
$ make
$ make install
```

You need to have the dependencies installed; one way to do this is:
```
$ opam install core lwt yojson jbuilder
```

Uninstall using:
```
$ make uninstall
```

## Usage

`trackerscraper` only has a command line interface.
Call it by typing `trackerscraper` into a shell, followed by a magnet link (in quotes) pointing to a torrent.
It will then attempt to fetch as many peer IP addresses as possible within the given constraints.
All optional parameters can be viewed by typing `trackerscraper -help`:

```
$ trackerscraper -help
query trackers for provided magnet link

  trackerscraper MAGNET-LINK

=== flags ===

  [--log logfile]     output logging information to logfile (-- for stdout)
  [--num-want n]      request n peers from a tracker (default: 80; < 255
                      required)
  [--output outfile]  output json result to outfile (-- for stdout)
                      (alias: -o)
  [--rescrape n]      request new peers n times (default: 0; may return the same
                      peers)
  [--timeout n]       wait for responses for n seconds
                      (alias: -t)
  [-pretty]           pretty-print json
  [-sequential]       scrape trackers sequentially instead of in parallel
  [-build-info]       print info about this build and exit
  [-version]          print the version of this build and exit
  [-help]             print this help text and exit
                      (alias: -?)
```

### Example output

This is some (censored) `trackerscraper` output. The JSON output format is not finalized and will most likely change.

```
$ trackerscraper --log logfile.txt --num-want 3 -pretty "magnet:?xt=..."
{
  "error": null,
  "errormsg": null,
  "hash": "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
  "name": "example-torrent",
  "peers": [],
  "numberTrackers": 1,
  "trackers": [
    {
      "leechers": 123,
      "seeders": 456,
      "peers": [
        { "ip": "4.3.2.1", "port": 11111 },
        { "ip": "8.7.6.5", "port": 22222 },
        { "ip": "1.2.2.1", "port": 33333 }
      ],
      "numberPeers": 3,
      "error": null,
      "errormsg": null,
      "hostname": "tracker.example.org",
      "ip": "1.2.3.4",
      "port": 1337
    }
  ]
}
$ cat logfile.txt
[2017-10-29 02:20:16.703198+02:00] parsed magnet link "magnet:?xt=..." with result:
info_hash: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
name: example-torrent
udp trackers:
  tracker.example.org/1.2.3.4:1337
http trackers:
  tracker.example.org/1.2.3.4:1337/some/path
peers:

[2017-10-29 02:20:16.706529+02:00] sent connect (16 bytes, tid: beefcace) to 1.2.3.4:1337
[2017-10-29 02:20:16.733152+02:00] received connect (16 bytes, connection_id: beefdeadbeefdead) from 1.2.3.4:1337
[2017-10-29 02:20:16.733209+02:00] sent announce started (98 bytes, cid: beefdeadbeefdead, tid: bedeadef, num_want 3) to 1.2.3.4:1337
[2017-10-29 02:20:16.758171+02:00] received announce response (80 bytes, cid: beefdeadbeefdead, 12 leechers, 809 seeders, 3 peers) from 1.2.3.4:1337
[2017-10-29 02:20:16.758190+02:00] attempting to fetch 821 peers from 1.2.3.4:1337
[2017-10-29 02:20:16.758215+02:00] sent announce stopped (98 bytes, tid feedface) to 1.2.3.4:1337
```

### Suggested parameters

- `--num-want 200`: During testing trackers returned up to 200 peers per announce request (may be due to path MTU).

- `-t 2` or `-t .5`: Non-responsive trackers prevent `trackerscraper` from finishing. Reduce timeout to below the default 15s.

- `--log --`: Enable logging to stdout to see live information.

- `--rescrape 10`: Request more peers 10 times to get massively more peers than with a single request.

## Internals

### Language

`trackerscraper` is written in OCaml.
I make use of some syntactic sugar added in OCaml 4.04.0; therefore this is the lowest supported OCaml version.
`trackerscraper` is built using [Jbuilder](https://github.com/janestreet/jbuilder).

### Dependencies

`trackerscraper` uses [core](https://github.com/janestreet/core), [Lwt](https://github.com/ocsigen/lwt) and
[Yojson](https://github.com/mjambon/yojson).

### Documentation

There is none (yet).
`trackerscraper -help` prints all command line options.
This README serves as documentation for the time being.

### Modules

#### `Net`

Client-side Implementation of the BitTorrent UDP Tracker Protocol.

#### `Magnet` and `Magnet_lex`

Magnet link parsing. `Magnet_lex` is generated by `ocamllex`.
`Magnet` may at some point be replaced by a `menhir` parser.

#### `Util`

Utility functions such as hex-encode/decode.

#### `Json`

Json backend.

#### `Trackerscraper`

Main module; contains command line interface and setup code.

### Behavior

`trackerscraper` tries to mask as a [Transmission](https://transmissionbt.com/) 2.92 client to prevent detection by trackers.
Its default values are similar and it generates its `peer_id` the same way Transmission does.
After it is done fetching addresses it disconnects from the tracker to prevent its host's IP address
from being listed as a peer; this does not work reliably (on the tracker's side).

`trackerscraper` uses Lwt to contact multiple trackers in parallel (this behavior can be turned off with `-sequential`).

`trackerscraper` is fairly performant; during testing I was able to fetch around 4000 IP addresses from two trackers
within one second with a round-trip time of ~40ms.

### Testing

There are no tests (yet).

## Future development

### Planned

- Lots of refactoring; currently the code is somewhat chaotic

- Support for http trackers

- Support for bencoded .torrent files

- Revamping the command line interface to allow for more flexibility

- Revamping the JSON backend


### Uncertain

- Support for [DHT](http://bittorrent.org/beps/bep_0005.html)

- Support for [PEX](http://bittorrent.org/beps/bep_0011.html)

- Backends other than JSON

## License

`trackerscraper` is licensed under the LGPL 3.0. See `LICENSE`.

## Disclaimer

I have no idea about the legal aspects of using this tool.

Using it most likely violates the TOS of many torrent sites.

Contacting trackers may add your IP address to the pool of peers.

Other peers may see your IP address and attempt to connect.

IP addresses can be located (assuming no precautions were taken).

Use at your own risk.
