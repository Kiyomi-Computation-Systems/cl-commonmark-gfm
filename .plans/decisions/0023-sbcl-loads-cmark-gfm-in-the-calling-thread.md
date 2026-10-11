# ADR-0023: SBCL loads cmark-gfm in the calling thread

- **Status:** Accepted
- **Date:** 2026-10-10
- **Scope:** startup's step 3 on SBCL: `load-library`,
  `load-shared-library`
- **Amends:** ADR-0009 (loading by absolute path, through CFFI)
- **Related:** ADR-0017 (how calls run: the startup lock, interrupts
  deferred)

## Context

The first manual macOS run for 0.1.0 (Apple silicon, SBCL 2.6.5,
Homebrew's cmark-gfm) hung in the native suite, at
`closing-while-a-worker-renders-never-harms-it`, with no CPU used and
Ctrl-C ignored. A watchdog thread showed:
- the worker held `*startup-lock*`, restarting cmark-gfm after a reset,
  and waited on no mutex;
- the initial thread waited for `*startup-lock*`, with interrupts
  deferred, as every wait for that lock does (ADR-0017).

Tracing put the worker inside `cffi:load-foreign-library`, before SBCL's
`load-shared-object`. On macOS, CFFI's SBCL backend runs every load in
the initial thread: `%load-foreign-library`, declared inline, calls
`call-within-initial-thread`, which interrupts the initial thread and
waits on a semaphore for the load (CFFI's `src/cffi-sbcl.lisp`). The
initial thread, deferring interrupts while it waited for the lock, could
never run the load. CFFI does this because loading Apple's frameworks,
such as CoreFoundation, from another thread crashed on Mac OS X 10.6.6.
Linux takes no such path, so CI never saw it.

The hang isn't only the test's. On macOS with SBCL, any startup in a
thread other than the initial one, whether a first call or one after a
reset, waits until the initial thread takes an interrupt. It waits for
good if the initial thread is waiting for the startup lock, as when it
calls the library at the same moment, or is in any other section that
defers interrupts, or is in a foreign call that never returns to Lisp,
such as a GUI's event loop. That breaks the promise that the library
can be called from any number of threads.

## Decision

On SBCL, startup loads each library with `sb-alien:load-shared-object`,
in the calling thread (`load-shared-library`). It then records the
result in a `cffi:foreign-library` object exactly as CFFI's own loader
does: registered under a new name, with the handle SBCL returned, the
pathname, and load state `:external`. Closing, listing and the tests'
reads of those objects go through CFFI unchanged.

Every SBCL loads this way, not only macOS, so CI on Linux runs the code
macOS runs. CCL and ECL still load through `cffi:load-foreign-library`:
CFFI's backends for them load in the calling thread already.

A test pins it: `a-startup-in-another-thread-needs-nothing-from-the-initial-thread`.
The initial thread waits for a worker's first call, with interrupts
deferred and a 30-second timeout, so a load that needs the initial
thread fails the test rather than hanging the run.
- **On Linux,** it fails when `load-library` hands its load to the
  initial thread as CFFI does, and passes otherwise.
- **On macOS,** it fails before this change and passes after it.

## Rejected

- **Not deferring interrupts while waiting for the startup lock.** The
  initial thread could still be in another deferred section, or in a
  long foreign call, and a startup in another thread would still wait
  for it.
- **Binding SBCL's initial thread, or redefining CFFI's loader.** CFFI
  compares against `sb-thread::*initial-thread*`, a global, and its
  `%load-foreign-library` is inlined into its callers, so neither change
  reaches the call. Both would also change every other CFFI load in the
  process.
- **Starting cmark-gfm only in the initial thread.** The library would
  then depend on what the initial thread is doing, which is the problem.

## Consequences

- The library depends on two of CFFI's internals: the `foreign-library`
  class's `pathname` slot, which has no initarg, and
  `cffi::get-foreign-library`'s setter. CCL's path already reads
  `cffi::foreign-library-handle`. A CFFI update must keep them, or the
  native suite fails at its first startup.
- SBCL's own load error now reaches `native-library-not-found`'s reason
  without CFFI's "Unable to load foreign library" wrapper. It still
  names the file and carries the loader's message.
