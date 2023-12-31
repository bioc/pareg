#' @title Parallelize function calls on LSF cluster.
#'
#' @description Run function for each row of input dataframe
#'  in LSF job.
#'
#' @export
#' @param df_iter Dataframe over whose rows to iterate.
#' @param func Function to apply to each dataframe row.
#'  Its arguments must be all dataframe columns.
#' @param .bsub_params Parameters to pass to `bsub` during job submission.
#' @param .tempdir Location to store auxiliary files in.
#' @param .packages Packages to import in each job.
#' @param ... Extra arguments for function.
#'
#' @return Dataframe created by concatenating results of each function call.
#'
#' @examples
#' \dontrun{
#' foo <- 42
#' cluster_apply(
#'   data.frame(i = seq_len(3), group = c("A", "B", "C")),
#'   function(i, group) {
#'     log_debug("hello")
#'     data.frame(group = group, i = i, foo = foo, result = foo + 2 * i)
#'   },
#'   .packages = c(logger)
#' )
#' }
#' @importFrom logger log_trace log_debug log_warn log_error
#' @importFrom tibble tibble add_row
#' @importFrom dplyr bind_rows
#' @importFrom glue glue
#' @importFrom stringr str_match
#' @importFrom progress progress_bar
cluster_apply <- function(
  df_iter,
  func,
  .bsub_params = c("-n", "2", "-W", "24:00", "-R", "rusage[mem=10000]"),
  .tempdir = ".",
  .packages = c(),
  ...
) {
  # create infrastructure
  image_dir <- file.path(.tempdir, "images")
  script_dir <- file.path(.tempdir, "scripts")
  result_dir <- file.path(.tempdir, "results")
  log_dir <- file.path(.tempdir, "logs")

  lapply(
    c(image_dir, script_dir, result_dir, log_dir),
    function(x) {
      dir.create(x, showWarnings = FALSE, recursive = TRUE)
    }
  )

  # submit jobs
  df_jobs <- tibble(
    index = numeric(),
    job_id = character(),
    result_path = character()
  )
  for (index in seq_len(nrow(df_iter))) {
    # save environment needed to execute function
    image_path <- file.path(image_dir, glue("image_{index}.RData"))
    log_trace("[index={index}] Saving image to {image_path}")

    current_df_row <- df_iter[index, , drop = FALSE]
    extra_func_arguments <- list(...)
    function_arguments <- c(current_df_row, extra_func_arguments)

    with(
      c(
        as.list(environment()), # current env for function and argument
        as.list(parent.frame()) # env of function to deal with globals
      ), {
        save(
          list = ls(),
          file = image_path
        )
      }
    )

    # create script
    script_path <- file.path(script_dir, glue("script_{index}.R"))
    result_path <- file.path(result_dir, glue("result_{index}.rds"))

    header <- ""
    if (length(.packages) > 0) {
      for (pkg in .packages) {
        header <- glue("
          {header}
          library({pkg})
        ")
      }
    }

    code <- glue("
      {header}
      load('{image_path}')
      result <- do.call(func, function_arguments)
      saveRDS(result, '{result_path}')
    ")
    log_trace("[index={index}] Writing script to {script_path}")
    writeLines(code, script_path)

    # assemble bsub parameters
    bsub_params <- c(
      .bsub_params,
      "-o", file.path(log_dir, "job_%J.stdout"),
      "-e", file.path(log_dir, "job_%J.stderr"),
      "Rscript", script_path
    )

    # submit script
    bsub_param_str <- paste(bsub_params, sep = "", collapse = " ")
    log_trace("[index={index}] Executing 'bsub {bsub_param_str}'")
    stdout <- system2("bsub", bsub_params, stdout = TRUE, stderr = FALSE)

    job_id <- str_match(stdout, "Job <(.*?)>")[1, 2]
    log_debug("[index={index}] Submitted job {job_id}")

    # finalize
    df_jobs <- add_row(
      df_jobs,
      index = index,
      job_id = job_id,
      result_path = result_path
    )
  }

  # check job status and retrieve results
  successful_job_list <- c()
  result_list <- list()

  pb <- progress_bar$new(total = index)
  pb$tick(0)

  while (length(successful_job_list) < nrow(df_jobs)) {
    for (i in seq_len(nrow(df_jobs))) {
      row <- df_jobs[i, ]

      # skip processed jobs
      if (row$job_id %in% successful_job_list) {
        next
      }

      # check job
      status <- character(0)
      while (length(status) == 0) {
        status <- system2(
          "bjobs",
          c("-o", "stat", "-noheader", row$job_id),
          stdout = TRUE
        )

        if (length(status) == 0) {
          log_warn(
            "Couldn't get status for job {row$job_id}. ",
            "Retrying..."
          )
          Sys.sleep(1)
        }
      }
      # log_trace("Job {row$job_id} has status {status}")

      if (status == "DONE") {
        log_debug("Job {row$job_id} at index {row$index} is done")
        successful_job_list <- c(successful_job_list, row$job_id)

        result <- readRDS(row$result_path)
        result_list[[row$index]] <- result

        pb$tick()
      } else if (status == "EXIT") {
        log_error("Job {row$job_id} crashed, killing all other jobs")

        log_file <- file.path(log_dir, glue("job_{row$job_id}.stdout"))
        log_error("Log: {log_file}")

        for (i in seq_len(nrow(df_jobs))) {
          system2("bkill", df_jobs[i, ]$job_id)
        }

        stop(glue("Cluster job {row$job_id} crashed"))
      }

      Sys.sleep(0.1)
    }

    Sys.sleep(10)
  }

  # finalize
  return(bind_rows(result_list))
}
