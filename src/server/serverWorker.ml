(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Base

module ServerWorkerState = struct
  type t = {
    init_id: string;
    logger_level: Hh_logger.Level.t;
    log_filename: string option;
  }

  let save ~init_id : t =
    {
      init_id;
      logger_level = Hh_logger.Level.min_level ();
      log_filename = Hh_logger.get_log_name ();
    }

  let restore { init_id; logger_level; log_filename } ~(worker_id : int) =
    Hh_logger.set_id (Printf.sprintf "flow serverWorker %d" worker_id);
    Hh_logger.Level.set_min_level logger_level;

    let init_id = init_id ^ "." ^ Random_id.short_string () in
    FlowEventLogger.init_worker ~init_id (Unix.gettimeofday ());

    match log_filename with
    | None -> ()
    | Some file ->
      let log_fd = Unix.openfile file [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_APPEND] 0o666 in
      Hh_logger.set_log file (Unix.out_channel_of_descr log_fd)
end

(* As for [Daemon.register_entry_point], this should stay
   at toplevel, in order to be executed before
   [Daemon.check_entry_point]. *)
let entry = WorkerController.register_entry_point ~restore:ServerWorkerState.restore

let make ~n ~channel_mode ~gc_control ~init_id heap_handle =
  MultiWorkerLwt.make
    ~channel_mode
    ~call_wrapper:None
    ~saved_state:(ServerWorkerState.save ~init_id)
    ~entry
    ~nbr_procs:n
    ~gc_control
    ~heap_handle
