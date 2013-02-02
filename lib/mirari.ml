(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

let lines_of_file file =
  let ic = open_in file in
  let lines = ref [] in
  let rec aux () =
    let line =
      try Some (input_line ic)
      with _ -> None in
    match line with
    | None   -> ()
    | Some l ->
      lines := l :: !lines;
      aux () in
  aux ();
  close_in ic;
  List.rev !lines

let strip str =
  let p = ref 0 in
  let l = String.length str in
  let fn = function
    | ' ' | '\t' | '\r' | '\n' -> true
    | _ -> false in
  while !p < l && fn (String.unsafe_get str !p) do
    incr p;
  done;
  let p = !p in
  let l = ref (l - 1) in
  while !l >= p && fn (String.unsafe_get str !l) do
    decr l;
  done;
  String.sub str p (!l - p + 1)

let cut_at s sep =
  try
    let i = String.index s sep in
    let name = String.sub s 0 i in
    let version = String.sub s (i+1) (String.length s - i - 1) in
    Some (name, version)
  with _ ->
    None

let split s sep =
  let rec aux acc r =
    match cut_at r sep with
    | None       -> List.rev (r :: acc)
    | Some (h,t) -> aux (strip h :: acc) t in
  aux [] s

let key_value line =
  match cut_at line ':' with
  | None       -> None
  | Some (k,v) -> Some (k, strip v)

let filter_map f l =
  let rec loop accu = function
    | []     -> List.rev accu
    | h :: t ->
        match f h with
        | None   -> loop accu t
        | Some x -> loop (x::accu) t in
  loop [] l

let subcommand ~prefix (command, value) =
  let p1 = String.uncapitalize prefix in
  match cut_at command '-' with
  | None      -> None
  | Some(p,n) ->
    let p2 = String.uncapitalize p in
    if p1 = p2 then
      Some (n, value)
    else
      None

let remove file =
  if Sys.file_exists file then
    Sys.remove file

let append oc fmt =
  Printf.kprintf (fun str ->
    Printf.fprintf oc "%s\n" str
  ) fmt

let newline oc =
  append oc ""

let error fmt =
  Printf.kprintf (fun str ->
    Printf.eprintf "ERROR: %s\n%!" str;
    exit 1;
  ) fmt

let info fmt =
  Printf.kprintf (Printf.printf "%s\n%!") fmt

let command fmt =
  Printf.kprintf (fun str ->
    info "+ Executing: %s" str;
    match Sys.command str with
    | 0 -> ()
    | i -> error "The command %S exited with code %d." str i
  ) fmt

let in_dir dir f =
  let pwd = Sys.getcwd () in
  let reset () =
    if pwd <> dir then Sys.chdir pwd in
  if pwd <> dir then Sys.chdir dir;
  try let r = f () in reset (); r
  with e -> reset (); raise e

(* Headers *)
module Headers = struct

  let output oc =
    append oc "(* Generated by mirari *)";
    newline oc

end

(* Filesystem *)
module FS = struct

  type fs = {
    name: string;
    path: string;
  }

  type t = {
    dir: string;
    fs : fs list;
  }

  let create ~dir kvs =
    let kvs = filter_map (subcommand ~prefix:"fs") kvs in
    let aux (name, path) = { name; path } in
    { dir; fs = List.map aux kvs }

  let call t =
    List.iter (fun { name; path} ->
      let path = Printf.sprintf "%s/%s" t.dir path in
      let file = Printf.sprintf "%s/filesystem_%s.ml" t.dir name in
      if Sys.file_exists path then (
        info "Creating %s." file;
        command "mir-crunch -name %S %s > %s" name path file
      ) else
      error "The directory %s does not exist." path
    ) t.fs

  let output oc t =
    List.iter (fun { name; _ } ->
      append oc "open Filesystem_%s" name
    ) t.fs;
    newline oc

end

(* IP *)
module IP = struct

  type ipv4 = {
    address: string;
    netmask: string;
    gateway: string;
  }

  type t =
    | DHCP
    | IPv4 of ipv4

  let create kvs =
    let kvs = filter_map (subcommand ~prefix:"ip") kvs in
    let use_dhcp =
      try List.assoc "use-dhcp" kvs = "true"
      with _ -> false in
    if use_dhcp then
      DHCP
    else
      let address =
        try List.assoc "address" kvs
        with _ -> "10.0.0.2" in
      let netmask =
        try List.assoc "netmask" kvs
        with _ -> "255.255.255.0" in
      let gateway =
        try List.assoc "gateway" kvs
        with _ -> "10.0.0.1" in
      IPv4 { address; netmask; gateway }

    let output oc = function
      | DHCP   -> append oc "let ip = `DHCP"
      | IPv4 i ->
        append oc "let get = function Some x -> x | None -> failwith \"Bad IP!\"";
        append oc "let ip = `IPv4 (";
        append oc "  get (Net.Nettypes.ipv4_addr_of_string %S)," i.address;
        append oc "  get (Net.Nettypes.ipv4_addr_of_string %S)," i.netmask;
        append oc "  [get (Net.Nettypes.ipv4_addr_of_string %S)]" i.gateway;
        append oc ")";
        newline oc

end

(* HTTP listening parameters *)
module HTTP = struct

  type http = {
    port   : int;
    address: string option;
  }

  type t = http option

  let create kvs =
    let kvs = filter_map (subcommand ~prefix:"http") kvs in
    if List.mem_assoc "port" kvs &&
       List.mem_assoc "address" kvs then
      let port = List.assoc "port" kvs in
      let address = List.assoc "address" kvs in
      let port =
        try int_of_string port
        with _ -> error "%S s not a valid port number." port in
      let address = match address with
        | "*" -> None
        | a   -> Some a in
      Some { port; address }
    else
      None

  let output oc = function
    | None   -> ()
    | Some t ->
      append oc "let listen_port = %d" t.port;
      begin
        match t.address with
        | None   -> append oc "let listen_address = None"
        | Some a -> append oc "let listen_address = Net.Nettypes.ipv4_addr_of_string %S" a;
      end;
      newline oc

end

(* Main function *)
module Main = struct

  type t =
    | IP of string
    | HTTP of string

  let create kvs =
    let kvs = filter_map (subcommand ~prefix:"main") kvs in
    let is_http = List.mem_assoc "http" kvs in
    let is_ip = List.mem_assoc "ip" kvs in
    match is_http, is_ip with
    | false, false -> error "No main function is specified. You need to add 'main-ip: <NAME>' or 'main-http: <NAME>'."
    | true , false -> HTTP (List.assoc "http" kvs)
    | false, true  -> IP (List.assoc "ip" kvs)
    | true , true  -> error "Too many main functions."

  let output_http oc main =
    append oc "let main () =";
    append oc "  let spec = Cohttp_lwt_mirage.Server.({";
    append oc "    callback    = %s;" main;
    append oc "    conn_closed = (fun _ () -> ());";
    append oc "  }) in";
    append oc "  Net.Manager.create (fun mgr interface id ->";
    append oc "    Printf.eprintf \"listening to HTTP on port %%d\\\\n\" listen_port;";
    append oc "    Net.Manager.configure interface ip >>";
    append oc "    Cohttp_lwt_mirage.listen mgr (listen_address, listen_port) spec";
    append oc "  )"

  let output_ip oc main =
    append oc "let main () =";
    append oc "  Net.Manager.create (fun mgr interface id ->";
    append oc "    Net.Manager.configure interface ip >>";
    append oc "    %s mgr interface id" main;
    append oc "  )"

  let output oc t =
    begin
      match t with
      | IP main   -> output_ip oc main
      | HTTP main -> output_http oc main
    end;
    newline oc;
    append oc "let () = OS.Main.run (main ())";

end

(* .obuild & opam file *)
module Build = struct

  type t = {
    name   : string;
    dir    : string;
    depends: string list;
    packages: string list;
  }

  let get name kvs =
    let kvs = List.filter (fun (k,_) -> k = name) kvs in
    List.fold_left (fun accu (_,v) ->
      split v ',' @ accu
    ) [] kvs

  let create ~dir ~name kvs =
    let depends = get "depends" kvs in
    let packages = get "packages" kvs in
    { name; dir; depends; packages }

  let output oc t =
    let file = Printf.sprintf "%s/main.obuild" t.dir in
    let deps = match t.depends with
      | [] -> ""
      | ds -> ", " ^ String.concat ", " ds in
    let oc = open_out file in
    append oc "obuild-ver: 1";
    append oc "name: %s" t.name;
    append oc "version: 0.0.0";
    newline oc;
    append oc "executable %s" t.name;
    append oc "  main: main.ml";
    append oc "  buildDepends: mirage%s" deps;
    append oc "  pp: camlp4o";
    close_out oc

  let check t =
    let exists s = (Sys.command ("which " ^ s ^ " > /dev/null") = 0) in
    if t.packages <> [] && not (exists "opam") then
      error "OPAM is not installed.";
    if not (exists "obuild") then
      error "obuild is not installed."

  let prepare t =
    check t;
    match t.packages with
    | [] -> ()
    | ps -> command "opam install --yes %s" (String.concat " " ps)

end

type t = {
  file   : string;
  xen    : bool;
  name   : string;
  dir    : string;
  main_ml: string;
  fs     : FS.t;
  ip     : IP.t;
  http   : HTTP.t;
  main   : Main.t;
  build  : Build.t;
}

let create ~xen ~file =
  let dir = Filename.dirname file in
  let name = Filename.chop_extension (Filename.basename file) in
  let lines = lines_of_file file in
  let kvs = filter_map key_value lines in
  let main_ml = Printf.sprintf "%s/main.ml" dir in
  let fs = FS.create ~dir kvs in
  let ip = IP.create kvs in
  let http = HTTP.create kvs in
  let main = Main.create kvs in
  let build = Build.create ~name ~dir kvs in
  { file; xen; name; dir; main_ml; fs; ip; http; main; build }

let output_main t =
  let oc = open_out t.main_ml in
  Headers.output oc;
  FS.output oc t.fs;
  IP.output oc t.ip;
  HTTP.output oc t.http;
  Main.output oc t.main;
  Build.output oc t.build;
  close_out oc

let call_crunch_scripts t =
  FS.call t.fs

let call_configure_scripts t =
  in_dir t.dir (fun () ->
    Build.prepare t.build;
    command "obuild configure %s" (if t.xen then "--executable-as-obj" else "");
  )

let call_build_scripts t =
  let setup = Printf.sprintf "%s/dist/setup" t.dir in
  if Sys.file_exists setup then (
    in_dir t.dir (fun () ->
      let exec = Printf.sprintf "mir-%s" t.name in
      command "rm -f %s" exec;
      command "obuild build";
      command "ln -s %s/dist/build/%s/%s %s" t.dir t.name t.name exec
    )
  ) else
    error "You should run 'mirari configure %s' first." t.file

let call_xen_scripts t =
  let obj = Printf.sprintf "dist/build/%s/%s.native.obj" t.name t.name in
  let target = Printf.sprintf "dist/build/%s/%s.xen" t.name t.name in
  if Sys.file_exists obj then
    command "mir-build -b xen-native -o %s %s" target obj

let configure ~xen ~file =
  let t = create ~xen ~file in
  (* main.ml *)
  info "Generating %s." t.main_ml;
  output_main t;
  (* crunch *)
  call_crunch_scripts t;
  (* obuild configure *)
  call_configure_scripts t

let build ~xen ~file =
  let t = create ~xen ~file in
  (* build *)
  call_build_scripts t;
  (* gen_xen.sh *)
  if xen then
    call_xen_scripts t