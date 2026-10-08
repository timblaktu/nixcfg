---
name: gnu-parallel
description: Master GNU parallel for shell fan-out - run a command over many inputs concurrently with correct quoting, ordered/tagged output, bounded concurrency, error-halting, and joblog/resume. Use when a loop over files/hosts/IDs/lines should run in parallel, when deciding between parallel vs xargs -P vs background jobs, when a fan-out needs retries or resumability, or when debugging parallel quoting/output-interleaving.
---

# GNU parallel mastery

GNU `parallel` runs a command for each input item, up to N items at once, and (by default)
serializes each job's output so lines never interleave. It subsumes most `xargs -P` and
`for … & wait` patterns and adds ordered output, per-job logging, resume, retries, and clean
quoting.

## Mental model

```
parallel [options] COMMAND {} ::: a b c        # COMMAND runs 3x: with a, b, c
echo -e "a\nb\nc" | parallel [options] COMMAND  # same, items from stdin (one per line)
```
Each input item substitutes into `{}` (or an explicit replacement string). Jobs run
concurrently (default: one per CPU core); output is grouped per job and printed as each job
*finishes*, in input order by default only with `-k`.

## Input sources

| Form | Meaning |
|---|---|
| `::: a b c` | items given inline as arguments |
| `::: *.txt` | shell glob expands to items (one job per file) |
| `:::: file` | read items from `file` (one per line) |
| stdin (no `:::`) | read items from stdin, one per line |
| `-0` / `--null` | items are NUL-separated (pair with `find … -print0`) |
| `--colsep '\t'` | split each input line into columns -> `{1} {2} …` |
| `-a f1 -a f2` / `::: a b ::: x y` | multiple sources = **cartesian product** (all combinations) |
| `:::+` / `::::+` | **link** sources pairwise instead of cross-product |

```bash
# cross product: 6 jobs (a-x a-y b-x b-y c-x c-y)
parallel echo {1} {2} ::: a b c ::: x y
# linked: 3 jobs (a-x b-y c-z)
parallel echo {1} {2} ::: a b c :::+ x y z
# from find, NUL-safe (handles spaces/newlines in names)
find . -name '*.log' -print0 | parallel -0 gzip {}
```

## Replacement strings (operate on each item)

| String | Result for `/a/b/file.tar.gz` |
|---|---|
| `{}` | `/a/b/file.tar.gz` (whole item) |
| `{.}` | `/a/b/file.tar` (remove **last** extension) |
| `{/}` | `file.tar.gz` (basename) |
| `{//}` | `/a/b` (dirname) |
| `{/.}` | `file.tar` (basename, last ext removed) |
| `{#}` | job sequence number (1,2,3,…) |
| `{%}` | job slot number (1..N, reused as slots free) |
| `{1} {2} …` | the Nth input source / Nth `--colsep` column |

```bash
parallel convert {} {.}.png ::: *.jpg          # foo.jpg -> foo.png
parallel 'mkdir -p out/{//}; cp {} out/{}' ::: **/*.conf
```

## Concurrency control (`-j`)

- `-j N` — exactly N at a time. `-j 1` — sequential (useful for debugging).
- `-j 0` — as many as possible (one per input, no throttle). Use with care.
- `-j 50%` — half the cores; `-j +1` — cores+1; `-j -1` — cores-1.
- Default (no `-j`) — one job per physical core.
- `--memfree 2G` — don't start a job unless 2G RAM is free (backpressure).

## Output control

- **Default** = `--group`: each job's stdout/stderr buffered and printed atomically on
  completion, so lines never interleave (but you wait for the job to finish).
- `-k` / `--keep-order` — print in **input order** regardless of finish order.
- `--line-buffer` — stream lines live as they are produced (may interleave across jobs);
  pair with `--tag` to label each line with its input item.
- `--tag` — prefix every output line with the job's input item (great for fan-out logs).
- `--files` — write each job's output to a temp file, print the filenames instead.

```bash
# live, labeled, interleaved — ideal for watching N remote/async operations
parallel --tag --line-buffer 'ssh {} uptime' ::: host1 host2 host3
```

## Error handling and exit status

- parallel's **exit code** = number of failed jobs (1-100; 101 = more than 100 failed; 255 =
  other error). So `if parallel …; then` means "all jobs succeeded".
- `--halt now,fail=1` — abort immediately (kill running jobs) on the first failure.
- `--halt soon,fail=10%` — stop launching new jobs once 10% have failed; let running finish.
- `--retries 3` — retry a failing job up to 3 times before counting it failed.
- `|| true` on the whole invocation if partial failure is acceptable.

## Logging and resume (long / interruptible runs)

- `--joblog FILE` — append a TSV row per job (seq, host, start, runtime, exit, command).
- `--resume --joblog FILE` — skip jobs already recorded done; **resume an interrupted run**.
- `--resume-failed --joblog FILE` — re-run only jobs that failed last time.
- `--retry-failed --joblog FILE` — re-run the failed jobs from a completed joblog.

```bash
parallel --joblog jl --resume -j4 ./process {} :::: worklist.txt   # safe to Ctrl-C + rerun
```

## Quoting and shell functions (the #1 source of bugs)

- parallel quotes each `{}` for you — do **not** add your own quotes around `{}` in simple
  cases: `parallel gzip {}` handles spaces correctly; `parallel gzip "{}"` can double-quote.
- For anything with pipes/redirs/`&&`, wrap the command in single quotes so parallel runs it
  via a shell: `parallel 'grep foo {} | wc -l' ::: *.txt`.
- To call a **bash function**, export it first and use `env_parallel`, or export + invoke bash:
  ```bash
  work() { echo "[$1] $(wc -l < "$1")"; }
  export -f work
  parallel work ::: *.txt            # parallel finds exported funcs when SHELL=bash
  # portable form (no env_parallel): run an explicit bash that re-sees the exported func
  printf '%s\n' *.txt | parallel bash -c 'work "$@"' _ {}
  ```
  **zsh/bash gotcha (verified):** `export -f` is a **bash builtin** - it does NOT exist in
  zsh (zsh errors `export: invalid option(s)` and the function is never exported, so jobs
  fail `command not found`). If your interactive shell is zsh, run the fan-out from an
  explicit bash: `bash -c 'work(){ …; }; export -f work; printf "%s\n" … | parallel work {}'`,
  or sidestep functions entirely with `xargs -P`/`parallel bash -c '…' _ {}`. In CI the job
  shell is bash, so `export -f` + `parallel func` is fine there; it's only interactive zsh
  that bites.
- `--env VAR` (with `env_parallel`) ships a specific variable to each job; `env_parallel`
  ships functions/vars/aliases from the current shell.
- `--dry-run` — print the exact commands parallel *would* run without running them. Always
  sanity-check complex substitutions with `--dry-run` first.

## parallel vs `xargs -P` vs `& wait`

| Need | Use |
|---|---|
| Portable, no GNU-parallel dependency, simple fan-out | `xargs -P N -I{} cmd {}` (or `-0` from find) |
| Ordered output, per-job grouping, retries, joblog/resume, remote, `{.}`/`{//}` | `parallel` |
| A handful of known, heterogeneous commands | `cmd1 & cmd2 & wait` |

`xargs -P` is fine and dependency-free for bounded fan-out, but it interleaves output and has
no retry/resume/ordering. Reach for `parallel` when output hygiene, resumability, or the
replacement strings earn their keep. In CI steps that must run on a minimal image, prefer
`xargs -P` unless `parallel` is guaranteed installed.

## Common recipes

```bash
# compress every log, 4 at a time, NUL-safe, abort on first failure
find /var/log -name '*.log' -print0 | parallel -0 -j4 --halt now,fail=1 gzip {}

# run a test matrix: every suite x every arch, labeled live output
parallel --tag --line-buffer ./run-test {1} {2} ::: unit integ e2e ::: x86_64 aarch64

# resumable batch over a worklist with a joblog
parallel --joblog .jl --resume -j8 ./ingest {} :::: items.txt

# fan out an SSH op across hosts, keep output in host order
parallel -k --tag ssh {} 'systemctl is-active myservice' ::: web1 web2 web3

# transform filenames with replacement strings
parallel ffmpeg -i {} -c:a libmp3lame {.}.mp3 ::: *.wav
```

## Pitfalls

- **`parallel` prints a citation notice once.** Run `parallel --citation` once (writes
  `~/.parallel/will-cite`) on any box/image where it runs non-interactively, or the notice
  pollutes stderr. In baked images, add `will-cite` to `~/.parallel/`.
- **stdin is consumed by parallel**, not by the jobs. A job that needs stdin must get it from
  a file/redirect; `ssh` inside parallel wants `ssh -n` to avoid eating the item stream.
- **`-j 0` can fork-bomb** against ulimits for large inputs — bound it.
- **GNU parallel != the `moreutils` `parallel`.** Check `parallel --version` says "GNU
  parallel". The two have incompatible syntax.
- **Output order**: default grouping is by *completion*; add `-k` when you need input order.

## Reference

`man parallel`, `man parallel_tutorial`, and `parallel --help`. For one-off exploration,
`--dry-run` is your fastest feedback loop.
