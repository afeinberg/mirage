(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2013 Anil Madhavapeddy <anil@recoil.org>
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

(** Configuration library. *)
open Functoria_sigs

module Dsl :
  CORE with module Key = Functoria_key

(** Various generic devices. *)
module Devices : sig
  open Dsl

  (** {2 Argv device} *)

  type argv
  val argv : argv typ

  val sys_argv : argv impl
  (** The simplest argv device. Returns {!Sys.argv}. *)

  (** {2 Key device} *)

  val keys : argv impl -> job impl
  (** This device takes an [argv] device, calls cmdliner and sets up keys. *)

end

(** Various helpful functions. *)
module Misc = Functoria_misc

(** A specialized DSL build for specific purposes. *)
module type SPECIALIZED = sig
  open Dsl

  val prelude : string
  (** Prelude printed at the beginning of [main.ml].
      It should put in scope:
      - a [run] function of type ['a t -> 'a]
      - a [return] function of type ['a -> 'a t]
      - a [>>=] operator of type ['a t -> ('a -> 'b t) -> 'b t]

      for [type 'a t = [ `Ok of | `Error of string ] Lwt.t]
  *)

  val name : string
  (** Name of the specialized dsl. *)

  val version : string
  (** Version of the specialized dsl. *)

  val driver_error : string -> string
  (** [driver_error s] is the message given to the user when the
      the configurable [s] doesn't initialize correctly. *)

  val argv : Devices.argv impl
  (** The device used to access [argv]. *)

  val config : job impl
  (** The device implementing specific configuration for this
      specialized dsl. *)

end

module type S = Functoria_sigs.S
  with module Key := Dsl.Key
   and module Info := Dsl.Info
   and type 'a impl = 'a Dsl.impl
   and type 'a typ = 'a Dsl.typ
   and type any_impl = Dsl.any_impl
   and type job = Dsl.job
   and type 'a configurable = 'a Dsl.configurable

module type KEY = Functoria_sigs.KEY
  with type 'a key = 'a Dsl.Key.key
   and type 'a value = 'a Dsl.Key.value
   and type t = Dsl.Key.t
   and type Set.t = Dsl.Key.Set.t

(** Create a configuration engine for a specialized dsl. *)
module Make (P : SPECIALIZED) : sig

  include S

  val launch : unit -> unit
  (** Launch the cmdliner application.
      Should only be used by the host specialized DSL.
  *)

end
