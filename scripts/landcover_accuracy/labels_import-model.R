# labels_import-model.R — the model labeller's batches in, as labels the estimate can read (#145).
#
# research/landcover_accuracy.md, "Model labeller", pre-registered before any label: a blind agent labels
# every point from the contact sheets review_render-sheets.R writes under data/<area>/accuracy/model/.
# Four steps, each its own subcommand so no step is done by hand:
#
#   prompt  <area> <batch>               print the batch prompt: model_labeller-prompt.md, filled in.
#                                        Nothing else is sent to the agent.
#   extract <area> <batch> <transcript>  the agent's transcript (JSONL) -> model/raw/batch_<NN>.csv plus an
#                                        audit. Its reply is read BY SCRIPT, never retyped. Its tool calls
#                                        are audited: anything but a Read of its own sheets and key.md
#                                        refuses the batch (it is labelled again from the same sheets).
#                                        The model id is taken from the transcript, never typed.
#   import  <area>                       every raw batch + the frozen sheet_map.csv -> model/labels_model.csv
#                                        (labels.csv's shape, through fp_acc_unblind/fp_acc_labels_frame), and
#                                        its SHA-256 to reference/<area>/labels_model.sha256. The labels stay
#                                        out of the repository until the person's labels_b.csv is committed,
#                                        so labeller B is blind to the model.
#   publish <area>                       once labels_b.csv is committed: copy labels_model.csv to
#                                        reference/<area>/labels.csv after checking it against the committed
#                                        hash. Refuses while labels_b.csv is absent.
#
# usage: Rscript scripts/landcover_accuracy/labels_import-model.R <prompt|extract|import|publish> <area> [...]

source(here::here("scripts", "landcover_accuracy", "fp_accuracy.R"))

a    <- commandArgs(trailingOnly = TRUE)
mode <- a[1]
if (is.na(mode) || !mode %in% c("prompt", "extract", "import", "publish"))
  stop("usage: labels_import-model.R <prompt|extract|import|publish> <area> [...]", call. = FALSE)
area <- if (!is.na(a[2])) a[2] else "necr"
cfg  <- fp_acc_area(area)
dir_model <- file.path(cfg$dir_acc, "model")
dir_raw   <- file.path(dir_model, "raw")
key_md    <- file.path(dir_model, "key.md")
map_csv   <- file.path(dir_model, "sheet_map.csv")
out_csv   <- file.path(dir_model, "labels_model.csv")
sha_file  <- file.path(cfg$dir_ref, "labels_model.sha256")
batch_dir <- function(b) file.path(dir_model, sprintf("batch_%02d", as.integer(b)))
sha256    <- function(f) digest::digest(file = f, algo = "sha256")

if (!file.exists(map_csv)) stop("no ", map_csv, " -- run review_render-sheets.R ", area, call. = FALSE)
sheet_map <- utils::read.csv(map_csv, stringsAsFactors = FALSE)

# The batch prompt: model_labeller-prompt.md below its `---`, filled in. One definition, used to print it
# and to check that what the agent was actually sent is exactly this.
batch_prompt <- function(b) {
  d <- batch_dir(b)
  if (is.na(b) || !dir.exists(d)) stop("no batch ", b, " under ", dir_model, call. = FALSE)
  fp_acc_sheet_dir_check(dir_model)
  sheets <- sort(list.files(d, pattern = FP_ACC_SHEET_RE))
  if (!setequal(sheets, sheet_map$sheet[sheet_map$batch == b]))
    stop(d, " does not hold exactly the sheets sheet_map.csv gives batch ", b, call. = FALSE)
  tpl <- readLines(here::here("scripts", "landcover_accuracy", "model_labeller-prompt.md"), warn = FALSE)
  tpl <- tpl[(which(tpl == "---")[1] + 1L):length(tpl)]
  txt <- paste(tpl, collapse = "\n")
  txt <- gsub("{batch_dir}", normalizePath(d), txt, fixed = TRUE)
  txt <- gsub("{key_path}", normalizePath(key_md), txt, fixed = TRUE)
  txt <- gsub("{n}", length(sheets), txt, fixed = TRUE)
  txt <- gsub("{sheets}", paste(sheets, collapse = ", "), txt, fixed = TRUE)
  if (grepl("\\{[a-z_]+\\}", txt)) stop("an unfilled placeholder is left in the prompt", call. = FALSE)
  trimws(txt)
}

if (mode == "prompt") {
  cat(batch_prompt(as.integer(a[3])), "\n", sep = "")

} else if (mode == "extract") {
  b <- as.integer(a[3]); tr <- a[4]
  if (is.na(b) || is.na(tr) || !file.exists(tr)) stop("extract needs <batch> and an existing <transcript>", call. = FALSE)
  lines <- readLines(tr, warn = FALSE)
  recs  <- lapply(lines, function(l) tryCatch(jsonlite::fromJSON(l, simplifyVector = FALSE), error = function(e) NULL))
  # What the agent was sent: its first user turn, which must be the batch prompt exactly
  first <- Filter(function(r) identical(r$type, "user"), recs)[[1]]$message$content
  sent  <- if (is.character(first)) first else
    paste(vapply(Filter(function(x) identical(x$type, "text"), first), function(x) x$text, ""), collapse = "\n")
  if (!identical(trimws(sent), batch_prompt(b)))
    stop("the agent for batch ", b, " was not sent the pre-registered prompt exactly", call. = FALSE)
  recs  <- Filter(function(r) identical(r$type, "assistant") && is.list(r$message$content), recs)
  if (!length(recs)) stop(tr, " holds no assistant turn", call. = FALSE)
  models <- unique(vapply(recs, function(r) r$message$model %||% NA_character_, ""))
  models <- models[!is.na(models)]
  if (length(models) != 1) stop("the transcript names ", length(models), " models (", paste(models, collapse = ", "),
                                "); a batch is labelled by one", call. = FALSE)
  calls <- do.call(rbind, c(list(data.frame(name = character(0), path = character(0))), unlist(lapply(recs, function(r)
    lapply(Filter(function(x) identical(x$type, "tool_use"), r$message$content), function(x)
      data.frame(name = x$name, path = x$input$file_path %||% NA_character_, stringsAsFactors = FALSE))),
    recursive = FALSE)))
  # The reply: the handback message when the agent ends through one, else its last text block. The
  # handback itself is how the reply is delivered, not a tool the agent used on the files.
  hand  <- calls$name == "SubagentHandback"
  texts <- unlist(lapply(recs, function(r) {
    c(vapply(Filter(function(x) identical(x$type, "text"), r$message$content), function(x) x$text, ""),
      vapply(Filter(function(x) identical(x$type, "tool_use") && identical(x$name, "SubagentHandback"),
                    r$message$content), function(x) x$input$message %||% "", ""))
  }))
  reply <- utils::tail(texts[grepl("```csv", texts, fixed = TRUE)], 1)
  if (!length(reply)) stop("no reply with a ```csv block in ", tr, call. = FALSE)
  viol <- fp_acc_transcript_audit(calls[!hand, , drop = FALSE], batch_dir(b), key_md)
  rows <- fp_acc_model_csv(reply)
  want <- sheet_map$sheet[sheet_map$batch == b]
  dir.create(dir_raw, showWarnings = FALSE, recursive = TRUE)
  audit <- list(batch = b, model = models, transcript_sha256 = sha256(tr), n_rows = nrow(rows),
                n_reads = sum(calls$name == "Read" & !hand), violations = nrow(viol),
                missing = length(setdiff(want, rows$sheet)), extra = length(setdiff(rows$sheet, want)),
                extracted_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (nrow(viol) || audit$missing || audit$extra || anyDuplicated(rows$sheet)) {
    rej <- file.path(dir_raw, "rejected"); dir.create(rej, showWarnings = FALSE)
    jsonlite::write_json(c(audit, list(violation_calls = viol)), file.path(rej, sprintf("batch_%02d_%s.json", b,
                         format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"))), auto_unbox = TRUE, pretty = TRUE)
    stop(sprintf("batch %d refused: %d tool call(s) outside its sheets and the key, %d sheet(s) missing, %d extra -- label it again",
                 b, nrow(viol), audit$missing, audit$extra), call. = FALSE)
  }
  utils::write.csv(rows, file.path(dir_raw, sprintf("batch_%02d.csv", b)), row.names = FALSE, na = "")
  jsonlite::write_json(audit, file.path(dir_raw, sprintf("batch_%02d.audit.json", b)), auto_unbox = TRUE, pretty = TRUE)
  message(sprintf("batch %d: %d rows, %d reads, model %s", b, nrow(rows), audit$n_reads, models))

} else if (mode == "import") {
  fb <- sort(list.files(dir_raw, pattern = "^batch_[0-9]{2}[.]csv$", full.names = TRUE))
  if (!length(fb)) stop("no extracted batch under ", dir_raw, call. = FALSE)
  au <- lapply(sub("[.]csv$", ".audit.json", fb), jsonlite::read_json)
  models <- unique(vapply(au, function(x) x$model, ""))
  if (length(models) != 1) stop("batches were labelled by different models: ", paste(models, collapse = ", "), call. = FALSE)
  rows <- do.call(rbind, lapply(fb, utils::read.csv, colClasses = "character", na.strings = ""))
  day  <- max(as.Date(substr(vapply(au, function(x) x$extracted_utc, ""), 1, 10)))
  wc   <- fp_acc_model_wc(rows, sheet_map, paste0(FP_ACC_MODEL_PREFIX, models), format(day))
  key  <- fp_acc_review_key_read(file.path(cfg$dir_ref, "review_key.csv"))
  if (fp_acc_working_copy_role(wc$review_id, key) != "a")
    stop("the model labelled a subset; it is labeller A and labels every keyed point", call. = FALSE)
  smp <- sf::st_drop_geometry(sf::st_read(file.path(cfg$dir_ref, "sample.gpkg"), layer = "sample", quiet = TRUE))
  out <- fp_acc_labels_frame(fp_acc_unblind(wc, key), smp)
  if (file.exists(sha_file) && !identical(Sys.getenv("FORCE"), "1"))
    stop(sha_file, " is already committed: the model's labels are fixed. FORCE=1 only to replace them deliberately",
         call. = FALSE)
  utils::write.csv(out, out_csv, row.names = FALSE, na = "")
  writeLines(sprintf("%s  labels_model.csv", sha256(out_csv)), sha_file)
  message(sprintf("%s: %d labelled, %d cannot label, model %s; hash -> %s", out_csv,
                  sum(out$label_status == "labelled"), sum(out$label_status == "cannot_label"), models, sha_file))

} else {
  fb <- file.path(cfg$dir_ref, "labels_b.csv")
  if (!file.exists(fb)) stop("no ", fb, ": the model's labels stay out of the repository until the person's ",
                             "labels are committed", call. = FALSE)
  if (!file.exists(sha_file) || !file.exists(out_csv)) stop("run import first", call. = FALSE)
  want <- strsplit(readLines(sha_file, n = 1), "  ", fixed = TRUE)[[1]][1]
  if (!identical(sha256(out_csv), want)) stop(out_csv, " does not match the committed hash ", want, call. = FALSE)
  f <- file.path(cfg$dir_ref, "labels.csv")
  if (file.exists(f) && !identical(sha256(f), want)) stop(f, " exists and differs from the model's labels", call. = FALSE)
  file.copy(out_csv, f, overwrite = TRUE)
  message(f, ": the model's labels, matching ", basename(sha_file))
}
