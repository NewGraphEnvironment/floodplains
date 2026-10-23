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
  calls <- do.call(rbind, c(list(data.frame(id = character(0), name = character(0), path = character(0))),
    unlist(lapply(recs, function(r)
      lapply(Filter(function(x) identical(x$type, "tool_use"), r$message$content), function(x)
        data.frame(id = x$id %||% NA_character_, name = x$name, path = x$input$file_path %||% NA_character_,
                   stringsAsFactors = FALSE))),
    recursive = FALSE)))
  # each call's result, from the user turns: a call counts as done only if a result came back without error
  res <- unlist(lapply(Filter(function(r) identical(r$type, "user") && is.list(r$message$content), lapply(lines, function(l)
    tryCatch(jsonlite::fromJSON(l, simplifyVector = FALSE), error = function(e) NULL))), function(r)
    lapply(Filter(function(x) identical(x$type, "tool_result"), r$message$content), function(x) {
      img <- Filter(function(y) is.list(y) && identical(y$type, "image"), if (is.list(x$content)) x$content else list())
      list(id = x$tool_use_id %||% NA_character_, err = isTRUE(x$is_error),
           src = if (length(img)) img[[1]]$source else NULL)
    })), recursive = FALSE)
  res_id  <- vapply(res, function(x) x$id, "")
  res_err <- vapply(res, function(x) x$err, TRUE)
  calls$ok <- calls$id %in% res_id[!res_err]
  img_of   <- function(id) { k <- match(id, res_id); if (is.na(k)) NULL else res[[k]]$src }
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
  unread <- fp_acc_unread(calls[!hand, , drop = FALSE], batch_dir(b), key_md, want)
  # The key the agents read must be the pre-registered one, and each sheet must be the very image the agent
  # was shown: its bytes in the transcript against the file on disk. Names repeat across renders; bytes do not.
  if (!identical(readLines(key_md, warn = FALSE), fp_acc_labelling_key()))
    stop(key_md, " is not the labelling key in research/landcover_accuracy.md", call. = FALSE)
  rd <- calls[calls$name == "Read" & calls$ok & !is.na(calls$path) &
              dirname(normalizePath(calls$path, mustWork = FALSE)) == normalizePath(batch_dir(b)), ]
  disk  <- vapply(want, function(x) sha256(file.path(batch_dir(b), x)), "")
  saw   <- vapply(want, function(x) {
    ids <- rd$id[basename(rd$path) == x]
    any(vapply(ids, function(i) fp_acc_image_matches(img_of(i), file.path(batch_dir(b), x)), TRUE))
  }, TRUE)
  moved <- want[!saw]
  if (length(moved)) stop(length(moved), " sheet(s) of batch ", b, " on disk are not the images the agent saw (",
                          paste(utils::head(moved, 3), collapse = ", "), "): a re-render since the batch was labelled",
                          call. = FALSE)
  f_csv <- file.path(dir_raw, sprintf("batch_%02d.csv", b))
  if (file.exists(f_csv) && !identical(Sys.getenv("FORCE"), "1"))
    stop(f_csv, " is already extracted; FORCE=1 only to replace an accepted batch deliberately", call. = FALSE)
  dir.create(dir_raw, showWarnings = FALSE, recursive = TRUE)
  audit <- list(batch = b, model = models, transcript_sha256 = sha256(tr), n_rows = nrow(rows),
                n_reads = sum(calls$name == "Read" & !hand), violations = nrow(viol), unread = length(unread),
                missing = length(setdiff(want, rows$sheet)), extra = length(setdiff(rows$sheet, want)),
                key_sha256 = sha256(key_md), sheet_sha256 = as.list(disk),
                extracted_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (nrow(viol) || length(unread) || audit$missing || audit$extra || anyDuplicated(rows$sheet)) {
    rej <- file.path(dir_raw, "rejected"); dir.create(rej, showWarnings = FALSE)
    jsonlite::write_json(c(audit, list(violation_calls = viol, unread_files = unread)), file.path(rej, sprintf("batch_%02d_%s.json", b,
                         format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"))), auto_unbox = TRUE, pretty = TRUE)
    stop(sprintf("batch %d refused: %d tool call(s) outside its sheets and the key, %d file(s) never read, %d sheet(s) missing, %d extra -- label it again",
                 b, nrow(viol), length(unread), audit$missing, audit$extra), call. = FALSE)
  }
  utils::write.csv(rows, f_csv, row.names = FALSE, na = "")
  audit$csv_sha256 <- sha256(f_csv)
  jsonlite::write_json(audit, file.path(dir_raw, sprintf("batch_%02d.audit.json", b)), auto_unbox = TRUE, pretty = TRUE)
  message(sprintf("batch %d: %d rows, %d reads, model %s", b, nrow(rows), audit$n_reads, models))

} else if (mode == "import") {
  fb <- sort(list.files(dir_raw, pattern = "^batch_[0-9]{2}[.]csv$", full.names = TRUE))
  if (!length(fb)) stop("no extracted batch under ", dir_raw, call. = FALSE)
  au <- lapply(sub("[.]csv$", ".audit.json", fb), jsonlite::read_json)
  models <- unique(vapply(au, function(x) x$model, ""))
  if (length(models) != 1) stop("batches were labelled by different models: ", paste(models, collapse = ", "), call. = FALSE)
  # each batch as extracted, on the sheets now on disk, read under the key now on disk
  for (k in seq_along(fb)) {
    x <- au[[k]]
    if (is.null(x$csv_sha256) || !identical(sha256(fb[k]), x$csv_sha256))
      stop(fb[k], " is not the csv its audit recorded: extract it again", call. = FALSE)
    if (!identical(x$key_sha256, sha256(key_md))) stop("batch ", x$batch, " was read under another key.md", call. = FALSE)
    now <- vapply(names(x$sheet_sha256), function(s) sha256(file.path(batch_dir(x$batch), s)), "")
    if (!identical(unname(now), unname(unlist(x$sheet_sha256))))
      stop("batch ", x$batch, "'s sheets on disk are not the ones it labelled: the render moved under it", call. = FALSE)
  }
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
  # complete, not merely present: an export midway through labelling would unblind the rest
  fp_acc_b_complete(utils::read.csv(fb, colClasses = c(point_id = "character")),
                    fp_acc_review_key_read(file.path(cfg$dir_ref, "review_key.csv")))
  if (!file.exists(sha_file) || !file.exists(out_csv)) stop("run import first", call. = FALSE)
  # COMMITTED, not merely on disk: the hash is what the model's labels are held to, and B's labels must be
  # fixed in history before the model's are put where B could read them
  for (g in c(fb, sha_file)) {
    tracked <- system2("git", c("-C", shQuote(here::here()), "ls-files", "--error-unmatch", shQuote(g)), stdout = FALSE, stderr = FALSE) == 0
    clean   <- system2("git", c("-C", shQuote(here::here()), "diff", "--quiet", "HEAD", "--", shQuote(g)), stdout = FALSE, stderr = FALSE) == 0
    if (!tracked || !clean) stop(g, " is not committed as it stands: commit it before publishing", call. = FALSE)
  }
  # ...and the model's hash was committed BEFORE B's labels first were: its last commit is an ancestor of the
  # commit that added labels_b.csv, so a re-import or re-commit after B had seen anything is refused
  git1 <- function(...) system2("git", c("-C", shQuote(here::here()), ...), stdout = TRUE)
  c_hash <- git1("log", "-1", "--format=%H", "--", shQuote(sha_file))
  c_b    <- utils::tail(git1("log", "--diff-filter=A", "--format=%H", "--", shQuote(fb)), 1)
  before <- length(c_hash) == 1 && length(c_b) == 1 && c_hash != c_b &&
    system2("git", c("-C", shQuote(here::here()), "merge-base", "--is-ancestor", c_hash, c_b), stdout = FALSE, stderr = FALSE) == 0
  if (!before) stop(basename(sha_file), "'s last commit does not precede the commit that added labels_b.csv", call. = FALSE)
  want <- strsplit(readLines(sha_file, n = 1), "  ", fixed = TRUE)[[1]][1]
  if (!identical(sha256(out_csv), want)) stop(out_csv, " does not match the committed hash ", want, call. = FALSE)
  f <- file.path(cfg$dir_ref, "labels.csv")
  if (file.exists(f) && !identical(sha256(f), want)) stop(f, " exists and differs from the model's labels", call. = FALSE)
  if (!isTRUE(file.copy(out_csv, f, overwrite = TRUE)) || !identical(sha256(f), want))
    stop("copying the model's labels to ", f, " failed", call. = FALSE)
  # B is frozen from here: the gate in accuracy_estimate.R refuses a labels_b.csv that differs from this,
  # and a second publish refuses rather than re-freezing an edited B
  fp_acc_freeze(file.path(cfg$dir_ref, "labels_b.sha256"), sha256(fb), "labels_b.csv")
  message(f, ": the model's labels, matching ", basename(sha_file), "; labels_b.csv frozen in labels_b.sha256")
}
