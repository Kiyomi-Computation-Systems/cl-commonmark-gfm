# M0 close — implementation plan

- **Spec:** [2026-09-27-m0-close-design.md](2026-09-27-m0-close-design.md)
  (approved 2026-09-27)
- **Branch:** `m0-close`
- **Scope:** decision records, plan corrections, the corpus submodule and its
  checks, the Guix override variable, and the Linux CI workflow. **No library
  code**: that starts in M1.

Every check added here is seen to fail under a targeted mutation before it
counts (AGENTS.md). Builds and tests run through `scripts/guix-env`.

## Task 1: Correct ADR-0001, ADR-0004 and ADR-0005

**Files:** `.plans/decisions/0001-…`, `0004-…`, `0005-…`

1. **ADR-0001:** CCL is amd64-only. CCL 1.13's releases are `darwinx86`,
   `linuxx86` and 32-bit `linuxarm`. Its cells become Linux amd64 (CI) and
   macOS amd64 (Intel or Rosetta, by hand, with an x86_64 cmark-gfm). Remove
   "CCL on arm64 is verified on macOS". Add an "Amended 2026-09-27" line to the
   status.
2. **ADR-0004:** `guix-env-enter` also sets `CL_COMMONMARK_GFM_LIBS` (Task 5).
   `LD_LIBRARY_PATH` remains for ocicl's `libcrypto` only. Mark it amended.
3. **ADR-0005:** mark the `cl_cmark_node_kind` decision "Superseded by
   ADR-0008 (classification in Lisp, spec §3.4)". The findings and vocabulary
   stand.

**Verify:** `grep -n 'arm64' .plans/decisions/0001-*` shows no CCL-on-arm64
claim.

## Task 2: Write ADR-0008 … ADR-0013

**Files:** `.plans/decisions/0008-…` through `0013-…`

Same format as 0001–0007 (Status, Date, Scope, Context, Decision,
Consequences), concise, each citing its spec section:

| ADR | Title | Spec |
|-----|-------|------|
| 0008 | Bind libcmark-gfm directly; no shim for now | §3.1, §3.3, §3.4, §3.5 (both ABI beliefs and what their tests cannot catch) |
| 0009 | Discover the pinned pair by absolute path | §3.2 (override rules, directory table, double-load hazard, verify steps) |
| 0010 | An LHTML-shaped HTML tree, not SXML; public `html-tree->string` | §4.1, §4.2, §4.5 (survey evidence, validation rules) |
| 0011 | cmark's HTML is the tree's oracle; `vendor/cmark-gfm` submodule | §4.3, §4.6, §4.7 |
| 0012 | Raw-HTML, softbreak and link policies | §4.4 |
| 0013 | Linux CI in a Debian trixie container | §5 |

**Verify:** each ADR names only facts the spec or this session verified. Run
`ls .plans/decisions | wc -l` → 13.

## Task 3: Amend the plan and the progress ledger

**Files:** `.plans/cl-commonmark-gfm.org`, `.plans/progress.md`,
`AGENTS.md`

Plan edits, per spec §6:
- **Shim:** delete "A narrow C shim", the suggested C ABI block, the
  shim-specific ownership bullets and risk rows. Replace them with a short
  "Direct binding" section pointing to ADR-0008.
- **Library resolution:** replace "Initialization and loading" with spec
  §3.2, pointing to ADR-0009.
- **Renames:** SXML becomes "HTML tree" throughout:
  - systems table: `cl-commonmark-gfm/html-tree`;
  - API sketch: `ast->html-tree`, `markdown->html-tree`, `html-tree->string`;
  - rendering policy: the raw-HTML `:omit`/`:text` policies;
  - SXML contract section: rewritten per spec §4.2–4.5;
  - M1 wording and the risk register.
- **Tests section:** the oracle (§4.6), the counters (§3.3), and no
  sanitizer gate (§5.4).
- **Support matrix:** CCL amd64 only.
- **Conditions:** `native-abi-mismatch` = runtime ≠ pin; add
  `invalid-html-tree`.
- **Decision log:** entries 14–19 (ADR-0008…0013).

`progress.md`:
- tick shim header (replaced by ADR-0008), tree shapes and CI;
- add constraints: no C compiled by the project; the HTML tree is LHTML-shaped
  and oracle-tested; CI is one trixie job;
- add the M0 close-out.

`AGENTS.md`: add one line on `CL_COMMONMARK_GFM_LIBS` under "Guix development
container".

**Verify:** `grep -n -i 'sxml\|cl_cmark_\|shim' .plans/cl-commonmark-gfm.org`.
Only historical mentions remain, in the decision log and in ADR references.

## Task 4: The corpus submodule, `check-pins` and `check-notice`

**Files:** `.gitmodules`, `vendor/cmark-gfm` (gitlink), `Makefile`

1. `git submodule add https://github.com/github/cmark-gfm vendor/cmark-gfm`,
   then check out `587a12bb54d95ac37241377e6ddc93ea0e45439b`.
2. Makefile: `CMARK_GFM_COMMIT := 587a12bb…`.
   - `check-pins`: the submodule's recorded gitlink (`git ls-files -s
     vendor/cmark-gfm`) must equal `CMARK_GFM_COMMIT`. It reads the recorded
     gitlink, so it works without a checkout.
   - `check-notice`: `NOTICE`'s COPYING section must equal
     `vendor/cmark-gfm/COPYING` byte for byte. A missing checkout **fails**
     with a message naming `git submodule update --init`; it never skips.
   - Both go on `.PHONY` with `## ` descriptions.
3. Add both to `scripts/guix-env-selftest`'s make-target loop.

**Mutations, each seen to fail, then reverted:**
- `CMARK_GFM_COMMIT` altered → `check-pins` fails;
- one byte of `NOTICE`'s COPYING section changed → `check-notice` fails;
- submodule deinitialised → `check-notice` fails with the init hint.

## Task 5: The Guix container sets `CL_COMMONMARK_GFM_LIBS`

**Files:** `scripts/guix-env-enter`, `scripts/guix-env-selftest`,
`tests/guix-env-launcher.sh` (only if its expectations change)

1. `guix-env-enter`: glob `$GUIX_ENVIRONMENT/lib/libcmark-gfm.so.[0-9]*` and
   `…/libcmark-gfm-extensions.so.[0-9]*`.
   - Each glob must match exactly one file, else exit 2 naming the problem.
   - Export `CL_COMMONMARK_GFM_LIBS="core:ext"`.
2. `guix-env-selftest`: add assertion `cmark-override`:
   - the variable holds two absolute paths;
   - both exist;
   - both end in `.so.$CMARK_GFM_VERSION`;
   - both resolve under `/gnu/store`.

**Mutations:** `unset CL_COMMONMARK_GFM_LIBS` before the self-test, and swap
in a wrong version. The assertion fails under each.

## Task 6: Linux CI workflow

**Files:** `.github/workflows/ci.yml`, `ci/checksums.sha256`,
`ci/install-toolchain.sh`, `README.org` (badge)

1. `ci/checksums.sha256` records the SHA-256 of
   `ccl-1.13-linuxx86.tar.gz` and `ocicl_2.9.0-1_amd64.deb`, computed from a
   download here and cross-checked by downloading twice.
2. `ci/install-toolchain.sh`:
   - apt-installs `sbcl ecl cmark-gfm libcmark-gfm0.29.0.gfm.13
     libcmark-gfm-extensions0.29.0.gfm.13 make git ca-certificates curl`,
     with **no `-dev` packages**;
   - downloads both artifacts and runs `sha256sum -c`;
   - unpacks CCL to `/opt/ccl` and puts a `ccl` wrapper script on `PATH`,
     since the binary inside the tarball is named `lx86cl64`;
   - installs the ocicl `.deb`.
3. `ci.yml`:
   - one job on `ubuntu-latest`, `container: debian:trixie`;
   - triggers: `pull_request`, and `push` to `main`;
   - `concurrency` cancels superseded runs on the same ref;
   - `timeout-minutes: 20`;
   - checkout with submodules, then `ci/install-toolchain.sh`;
   - steps: `make info`, `make check-help`, `sh tests/guix-env-launcher.sh`,
     `make check-vocabulary`, `make check-pins`, `make check-notice`.
4. README: replace `[CI bage goes here]` with the workflow's badge.

**Verify:** push and open the PR; the run is green and `make info` in its log
shows SBCL 2.5.2, ECL 24.5.10, CCL 1.13, cmark-gfm 0.29.0.gfm.13 and ocicl
2.9.0. Seen to fail: push one throwaway commit that flips a byte of
`tests/fixtures/vocabulary.xml`. The job must go red at `check-vocabulary`.
Then drop that commit (force-push the branch, which is ours alone).

## Task 7: Close out

1. On the host, `make check-help`; then `make check-guix`, which runs the
   host launcher tests and the in-container self-test, including the new
   assertion and targets.
2. Record a close-out in `progress.md`, then commit and open the PR.

## Order

Tasks 1–3 are documents and independent. Tasks 4 and 5 touch the Makefile
and self-test, so run them in sequence. Task 6 depends on Task 4, since CI runs
`check-pins` and `check-notice`. Task 7 comes last.
