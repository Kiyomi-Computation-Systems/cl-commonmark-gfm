# ADR-0017: The public API, and how it runs

- **Status:** Accepted; amended by ADR-0019 (2026-10-01): a new condition,
  `unsupported-input`, and the input guard, which each entry point applies
  with the limits, before any native call; amended 2026-10-01, after M2b's
  review (spec §5.2, §5.3, findings 15 and 18): startup turns errors from
  the loaded libraries into project conditions; closing refuses while a
  call holds the state; and retrying a failed startup carries finding 15's
  caveat; amended 2026-10-01, after M2b's second review (spec §5.3, §5.4,
  §11, finding 21): interrupts are deferred during each cmark call, so
  timeouts are coarse; and a restore hook clears any published state when
  an image starts
- **Date:** 2026-09-30
- **Scope:** `parse`, `markdown->html`, `markdown->plaintext` and
  `markdown->html-tree`; their options and conditions; the
  `cl-commonmark-gfm` package; startup, saved images, native lifetimes,
  threads and interrupts
- **Spec:** [M2 design](../2026-09-30-m2-native-layer-design.md) §2 (D3, D7,
  D11 to D14, D16, findings 12, 14, 15, 18 and 21), §3, §5.2 to §5.4, §7,
  §11
- **Related:** ADR-0006 (`:gfm` enables footnotes), ADR-0008 (lifetimes and
  counters), ADR-0009 (discovery), ADR-0012 (the tree options), ADR-0014
  (options as `&rest`), ADR-0016 (the limits)
- **Prior art:** chez-cmark-gfm ADR-0006 (a liveness flag), ADR-0008 and
  ADR-0009 (source positions by entry point)

## Context

M2b puts cmark-gfm behind the pure core. What callers see, and how the
native layer runs, have to meet these facts:
- **The plan's sketch** gave `parse` and the renderers `&key` arguments,
  validated as "option objects". ADR-0014 had already given
  `ast->html-tree` `&rest` options, checked by hand, so that an unknown key
  signals.
- **cmark has options the HTML tree can't follow.** Three change only
  cmark's HTML: GitHub `pre` languages, table style attributes and full
  info strings (`src/html.c`, `extensions/table.c`).
- **The libraries are found and loaded at run time,** once per process,
  before the first parse (ADR-0009).
- **A saved image keeps its loaded libraries,** and its pointers into
  them. UIOP's image hooks run only inside `uiop:dump-image` and
  `uiop:restore-image`. SBCL's `sb-ext:*save-hooks*` and CCL's
  `ccl:*save-exit-functions*` run on every save, including one made by
  `uiop:dump-image` (finding 12).
- **SBCL runs save hooks before it refuses a save** (finding 18, from
  M2b's review). It refuses a save while other threads run, but only once
  `*save-hooks*` have run. A hook that closed cmark there closed it under
  other threads' parses: a probe saw memory faults.
- **A native document is freed when its scope ends** (ADR-0008), but the
  Lisp object can outlive the scope.
- **Concurrent parses corrupt each other** (finding 14).
  `cmark_parser_finish`, the only call that parses inlines, adds the
  attached extensions' special characters to two global tables
  (`src/inlines.c`), and removes them when it's done. Two throwaway C
  probes, in the Guix container:
  - eight threads rendering one 140 KB GFM document gave the wrong HTML
    246 times out of 320, losing strikethroughs and autolinks;
  - four CommonMark threads, beside four GFM threads, rendered `a~_b_~c`
    without its `<em>` 123 times out of 160;
  - with a lock around `cmark_parser_finish`, both gave 0 wrong results
    out of the same counts.
- **An interrupt that unwinds out of a cmark call can deadlock**
  (finding 21, from M2b's second review). A worker rendering in a loop,
  interrupted 30,000 times with a `throw` as `sb-ext:with-timeout` would
  do, stopped for good on the lock of a glibc malloc arena. A `throw` out
  of cmark's `malloc` or `free` leaves that lock held, so the thread's
  next allocation waits on itself, and the C heap can be left
  inconsistent.

## Decision

### Four entry points, their options checked first

`parse`, `markdown->html`, `markdown->plaintext` and `markdown->html-tree`
take a string and a `&rest` list of options (spec §7.1), checked by hand
as ADR-0014 checks `ast->html-tree`'s. Each checks all its options, then
applies the limits (ADR-0016), before any native call. A bad option or an
oversized input fails before startup, and creates no parser.

### A small option set (D3), with defaults per function (D14)

Version 1 takes the options of spec §7.2. More can be added later without
breaking callers.
- **The profile only supplies defaults,** so a caller can choose the
  extensions and footnotes under either profile (ADR-0006).
- **`:sourcepos` is on for `parse` and off for `markdown->html`.** An AST is
  worth more with positions, and HTML reads better without
  `data-sourcepos` (chez ADR-0008, ADR-0009). `markdown->html-tree` parses
  without them, since the tree has none.

### New conditions, and one package (D16)

- `invalid-option` and `native-error` are new parents (spec §7.4), so one
  handler covers every option error, or every native failure.
  `invalid-parse-option` and `resource-limit-exceeded` are new conditions.
- `cl-commonmark-gfm` re-exports the public symbols of the conditions, the
  AST and the HTML tree, and four variables: the three limits and
  `*cmark-gfm-libraries*` (spec §3). A caller needs one package.

### Startup on first use, once, under a lock (D11)

The first call that needs cmark runs startup (spec §5.2), under a
bordeaux-threads lock (D7). A failed attempt closes what it loaded and
publishes nothing, and the next call starts again.
- Loading the Lisp system doesn't load cmark.
- A caller can set `*cmark-gfm-libraries*` after loading, and can retry a
  failed startup without restarting the process. That's unsafe while
  something else in the process keeps libcmark-gfm loaded (finding 15).
- Errors from the loaded libraries, such as a missing function when an
  override names some other library, become project conditions that name
  the original (spec §5.2). So a handler for `native-error` catches every
  failed startup, and no raw FFI error escapes.
- The smoke parse runs before the state is published, so no call uses a
  state that failed it.

### A finish lock (finding 14)

One lock for the process is held around `cmark_parser_finish` (spec §5.4).
It's the only call that writes cmark's global tables once the extensions
have registered, and they register under the startup lock. So encoding,
feeding, copying and rendering stay parallel (spec §7.5). Spec §5.2 gives
the lock order.

### The Lisps' own save hooks (D12)

Before an image is saved, a function on `sb-ext:*save-hooks*` and
`ccl:*save-exit-functions*` closes both libraries and clears the published
state (spec §5.3). The image starts up again on its first call, wherever
it runs. It never asks the loader to reopen cmark at a path from the
machine that built it, and holds no stale pointer.

### No closing under a parse (finding 18)

A call holds the published state until its document is released, and
closing refuses while any call holds it (spec §5.3). So a save hook can't
unload cmark under another thread's parse. The save fails instead, before
anything is unloaded, and the state stays published.

### A restore hook as well

A save can still go ahead with the state published, for instance when a
user skips the save hook from the debugger. The image's state would then
hold pointers from the process that saved it. So a function on
`sb-ext:*init-hooks*` and `ccl:*restore-lisp-functions*` clears the
published state and the holds when an image starts, before any call
(spec §5.3).

### Interrupts wait for each cmark call (finding 21)

Every call into cmark runs with interrupts deferred, and so does the
bookkeeping of holds and counters (spec §5.4). An interrupt, a timeout for
instance, lands when the call returns, never inside cmark's allocator.

### An alive flag (D13)

Every native accessor checks its document's alive flag, and the flag is
cleared before anything is freed (spec §5.4). A document used after its
scope signals an internal condition instead of touching freed memory, and
nothing is freed twice (chez ADR-0006).

### Rejected

- **Every cmark option.** The HTML tree has nothing like the three
  HTML-only ones (D3), so `markdown->html` and `markdown->html-tree` would
  no longer agree under every option. Spec §11 lists the options left out.
- **UIOP's image hooks.** A direct `save-lisp-and-die` skips them
  (finding 12). The Lisps' own hooks run on every save, however it's made.
- **Parallel parses without a lock.** Finding 14's probes gave wrong
  results in 246 of 320 renders, and in 123 of 160. With the lock, none.
- **Letting an interrupt unwind out of a cmark call,** and documenting a
  leak, as this ADR first did. Finding 21 shows the thread can deadlock,
  and the C heap can be left inconsistent.

## Consequences

- The plan's `&key` sketch and its option objects give way to spec §7.
- A caller who wants positions in HTML passes `:sourcepos t`.
- **Inline parsing is serialized across the process.** Threads still parse
  in parallel, but take turns inside `cmark_parser_finish` (spec §7.5).
- **Another cmark-gfm user in the same process,** such as a second
  binding, doesn't take the finish lock, and can still race with this
  library (spec §7.5).
- **Timeouts are coarse.** An interrupt, such as a timeout, waits for the
  current cmark call to return, so it can't cut one long call short
  (spec §5.4, §11). The limits keep calls short: a 1 MiB parse takes
  about 70 ms. In exchange, no interrupt leaves cmark's allocator locked,
  or stops `cmark_parser_finish` halfway, with its extensions' characters
  still in cmark's tables. A failed startup's condition is signalled after
  the startup lock is released, so a caller's handler, or the debugger,
  runs with interrupts as the caller had them and blocks no other thread.
- A save made while another thread is in a call fails, with an error that
  says so, and leaves cmark loaded (spec §5.3).
- The save and restore hooks, and deferring interrupts, need reader
  conditionals. With ECL's `:dffi` check, they are the library's only
  ones, all in `/native` (spec §3).
- CCL's hooks and its deferred interrupts are first exercised in M4, with
  the native suite on CCL (spec §11). ECL doesn't save images.
- The native systems depend on CFFI and bordeaux-threads (D7). The pure
  systems still depend on nothing outside the project (spec §3).
