# cl-commonmark-gfm
#
# On a Guix host, run targets through the container (ADR-0004):
#   scripts/guix-env make <target>

SBCL ?= sbcl
CCL  ?= ccl

# The make target to name in a missing-tool hint (scripts/require-tools):
# what the user typed, $(MAKECMDGOALS), stripped -- so `make test` hints
# `scripts/guix-env make test`, never an inner prerequisite's own name
# such as check-purity -- or, when MAKECMDGOALS is empty, the recipe's own
# target, $@. Recursively expanded (=, not :=), so each reference picks up
# whichever recipe is running it.
GOAL = $(strip $(if $(MAKECMDGOALS),$(MAKECMDGOALS),$@))

# The container's ocicl, pinned by tag AND commit (ADR-0003, ADR-0004).
# `make ocicl` refuses a tag that has moved. Outside Guix, use your own ocicl:
# nothing else in this Makefile names .guix-env/.
OCICL_TAG    := v2.9.0
OCICL_COMMIT := f5faca8070c5ef04c6eac9b324c060519c5379d0
OCICL_URL    := https://github.com/ocicl/ocicl
STATE_DIR    := .guix-env
OCICL_SRC    := $(STATE_DIR)/src/ocicl-$(OCICL_TAG)

# The cmark-gfm release every native build and test is pinned to (ADR-0002).
CMARK_GFM_VERSION := 0.29.0.gfm.13

# The vendor/cmark-gfm submodule's commit for that release (ADR-0002, ADR-0011).
CMARK_GFM_COMMIT := 587a12bb54d95ac37241377e6ddc93ea0e45439b

# The ADR that must record CMARK_GFM_COMMIT in full; check-pins fails if it
# doesn't. Overridable so a mutation can point it elsewhere (see the check).
PIN_ADR := .plans/decisions/0002-pin-cmark-gfm-0.29.0.gfm.13.md

# Every syntax extension, plus footnotes (an option, not an extension, in
# the library; the CLI spells it as one). Used by check-vocabulary (ADR-0005).
VOCAB_FLAGS := --sourcepos -e footnotes -e table -e strikethrough -e autolink \
               -e tagfilter -e tasklist
VOCAB_MD    := tests/fixtures/vocabulary.md
VOCAB_XML   := tests/fixtures/vocabulary.xml

# The oracle fixtures (M1 design §7.3): one manifest, one Markdown input and one
# committed HTML file per case. FIXTURES_FLAGS is cmark's GFM set, minus
# --sourcepos, applied before each case's own extra flags.
FIXTURES_DIR   := tests/fixtures/html
FIXTURES_CASES := $(FIXTURES_DIR)/cases
FIXTURES_FLAGS := -e footnotes -e table -e strikethrough -e autolink \
                  -e tagfilter -e tasklist

# MUST stay on one physical line: check-help reads it with awk, one line only.
.PHONY: help check-help info deps ocicl check-vocabulary check-pins check-notice check-purity check-native check-fixtures fixtures-html check-watchdog check-preflight test fuzz check-guix check-guix-inside check-ecl-static check-ecl-nodffi check-ecl-nodffi-inside clean

# The name column is as wide as the longest target's name.
help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { n++; name[n] = $$1; text[n] = $$2; if (length($$1) > width) width = length($$1) } \
	  END { format = "  \033[36m%-" width "s\033[0m %s\n"; \
	        for (i = 1; i <= n; i++) printf format, name[i], text[i] }' $(MAKEFILE_LIST)

check-help: ## Fail if any .PHONY target is undocumented in `make help`
	@missing=0; \
	targets=$$(awk '/^\.PHONY:/ { $$1 = ""; print }' Makefile); \
	for t in $$targets; do \
	  grep -qE "^$$t:.*## " Makefile || { \
	    echo "check-help: target '$$t' has no '## ' description on its own line" >&2; \
	    missing=1; \
	  }; \
	done; \
	exit $$missing

info: ## Print the toolchain and cmark-gfm versions in use
	@echo "arch      : $$(uname -m)"
	@echo "sbcl      : $$($(SBCL) --version 2>/dev/null || echo missing)"
	@echo "ecl       : $$(ecl --version 2>/dev/null || echo missing)"
	@ccl_out=$$(scripts/lisp-start-watchdog "$(CCL_START_WINDOW)" "$(CCL_START_TRIES)" "$(LISP_START_MARKER)" \
	  $(CCL) -n -b --eval '(progn (format t "~&~A~%" "$(LISP_START_MARKER)") (finish-output) (princ (lisp-implementation-version)) (terpri) (ccl:quit))' 2>/dev/null); \
	if [ $$? -eq 0 ]; then \
	  echo "ccl       : $$(printf '%s\n' "$$ccl_out" | tail -n 1)"; \
	else \
	  echo "ccl       : missing"; \
	fi
	@echo "cmark-gfm : $$(if command -v cmark-gfm >/dev/null; then cmark-gfm --version | sed -n 's/^cmark-gfm \([^ ]*\).*/\1/p'; else echo missing; fi) (CLI; pinned $(CMARK_GFM_VERSION))"
	@echo "ocicl     : $$(if command -v ocicl >/dev/null; then ocicl version </dev/null 2>/dev/null | head -1; else echo missing; fi)"

ocicl: ## Build the pinned ocicl from source into .guix-env/bin
	@set -eu; \
	if [ ! -d "$(OCICL_SRC)/.git" ]; then \
	  git clone --quiet --depth 1 --branch $(OCICL_TAG) $(OCICL_URL) "$(OCICL_SRC)"; \
	fi; \
	got=$$(git -C "$(OCICL_SRC)" rev-parse HEAD); \
	if [ "$$got" != "$(OCICL_COMMIT)" ]; then \
	  echo "ocicl: $(OCICL_TAG) is $$got, pinned $(OCICL_COMMIT). Refusing to build." >&2; \
	  exit 1; \
	fi; \
	cd "$(OCICL_SRC)" && SBCL=$(SBCL) $(SBCL) --non-interactive --no-userinit --load setup.lisp

deps: ## Install the Lisp dependencies pinned in ocicl.csv
	@scripts/require-tools "$(GOAL)" ocicl
	@ocicl install </dev/null

# The AST vocabulary table in the plan was read off this output. If a pin
# bump changes it, the table (and ADR-0005) must be revisited.
check-vocabulary: ## Diff the pinned cmark-gfm's XML for the vocabulary fixture against the record
	@scripts/require-tools "$(GOAL)" cmark-gfm
	@cmark-gfm $(VOCAB_FLAGS) -t xml $(VOCAB_MD) | diff -u $(VOCAB_XML) - \
	  && echo "check-vocabulary: cmark-gfm output matches $(VOCAB_XML)"

check-fixtures: ## Diff the pinned cmark-gfm's HTML for every oracle case against its committed .html
	@scripts/require-tools "$(GOAL)" cmark-gfm
	@if [ ! -f $(FIXTURES_CASES) ]; then \
	  echo "check-fixtures: $(FIXTURES_CASES) is missing" >&2; \
	  exit 1; \
	fi; \
	failed=""; \
	while read -r name file rest; do \
	  case "$$name" in ""|\#*) continue ;; esac; \
	  input="$(FIXTURES_DIR)/$$file"; \
	  if [ ! -f "$$input" ]; then \
	    echo "check-fixtures: $$name: missing $$input" >&2; \
	    failed="$$failed $$name"; \
	    continue; \
	  fi; \
	  expected="$(FIXTURES_DIR)/$$name.html"; \
	  if [ ! -f "$$expected" ]; then \
	    echo "check-fixtures: $$name: missing $$expected" >&2; \
	    failed="$$failed $$name"; \
	    continue; \
	  fi; \
	  if ! cmark-gfm $(FIXTURES_FLAGS) $$rest "$$input" | diff -u "$$expected" -; then \
	    echo "check-fixtures: $$name: differs from $$expected" >&2; \
	    failed="$$failed $$name"; \
	  fi; \
	done < $(FIXTURES_CASES); \
	if [ -n "$$failed" ]; then \
	  echo "check-fixtures: failed on:$$failed" >&2; \
	  exit 1; \
	fi; \
	echo "check-fixtures: every case matches cmark-gfm's output"

fixtures-html: ## Write missing tests/fixtures/html/*.html files from cmark-gfm; never overwrites
	@scripts/require-tools "$(GOAL)" cmark-gfm
	@failed=""; \
	while read -r name file rest; do \
	  case "$$name" in ""|\#*) continue ;; esac; \
	  out="$(FIXTURES_DIR)/$$name.html"; \
	  if [ -f "$$out" ]; then \
	    echo "fixtures-html: $$name: $$out already exists, skipping"; \
	    continue; \
	  fi; \
	  input="$(FIXTURES_DIR)/$$file"; \
	  if [ ! -f "$$input" ]; then \
	    echo "fixtures-html: $$name: missing $$input" >&2; \
	    failed="$$failed $$name"; \
	    continue; \
	  fi; \
	  if cmark-gfm $(FIXTURES_FLAGS) $$rest "$$input" > "$$out.tmp"; then \
	    mv "$$out.tmp" "$$out"; \
	    echo "fixtures-html: $$name: wrote $$out"; \
	  else \
	    echo "fixtures-html: $$name: cmark-gfm failed on $$input" >&2; \
	    rm -f "$$out.tmp"; \
	    failed="$$failed $$name"; \
	  fi; \
	done < $(FIXTURES_CASES); \
	if [ -n "$$failed" ]; then \
	  echo "fixtures-html: failed on:$$failed" >&2; \
	  exit 1; \
	fi; \
	echo "fixtures-html: every missing case was written"

check-pins: ## Verify the gitlink, PIN_ADR, and vendor/cmark-gfm's checkout all agree on CMARK_GFM_COMMIT
	@got=$$(git ls-files -s vendor/cmark-gfm | awk '{print $$2}'); \
	if [ -z "$$got" ] || [ "$$got" != "$(CMARK_GFM_COMMIT)" ]; then \
	  echo "check-pins: vendor/cmark-gfm gitlink is '$${got:-empty}', pinned $(CMARK_GFM_COMMIT)" >&2; \
	  exit 1; \
	fi; \
	if ! grep -qF -- "$(CMARK_GFM_COMMIT)" "$(PIN_ADR)" 2>/dev/null; then \
	  echo "check-pins: $(PIN_ADR) does not record commit $(CMARK_GFM_COMMIT)" >&2; \
	  exit 1; \
	fi; \
	if [ -e vendor/cmark-gfm/.git ]; then \
	  head=$$(git -C vendor/cmark-gfm rev-parse HEAD); \
	  if [ "$$head" != "$$got" ]; then \
	    echo "check-pins: vendor/cmark-gfm is checked out at $$head, gitlink is $$got; run 'git submodule update vendor/cmark-gfm'" >&2; \
	    exit 1; \
	  fi; \
	fi; \
	echo "check-pins: gitlink, $(PIN_ADR), and the checkout all agree on $$got"

check-notice: ## Diff NOTICE's COPYING section against vendor/cmark-gfm/COPYING
	@if [ ! -f vendor/cmark-gfm/COPYING ]; then \
	  echo "check-notice: vendor/cmark-gfm/COPYING is missing; run 'git submodule update --init vendor/cmark-gfm'" >&2; \
	  exit 1; \
	fi; \
	heading=$$(grep -nFx -- "cmark-gfm $(CMARK_GFM_VERSION) -- COPYING" NOTICE | head -1 | cut -d: -f1); \
	if [ -z "$$heading" ]; then \
	  echo "check-notice: could not find the 'cmark-gfm ... -- COPYING' heading in NOTICE" >&2; \
	  exit 1; \
	fi; \
	start=$$((heading + 3)); \
	tail -n +$$start NOTICE | diff -u vendor/cmark-gfm/COPYING - \
	  && echo "check-notice: NOTICE reproduces vendor/cmark-gfm/COPYING"

# The Lisps each test suite runs on. check-purity runs the pure suite on
# all three; check-native runs the native suite on NATIVE_LISPS, sbcl by
# default, so `make test` is what a pull request runs. main's CI adds `make
# check-native NATIVE_LISPS="ccl ecl"` (M4 design §5.6; ADR-0013).
LISPS ?= sbcl ccl ecl
NATIVE_LISPS ?= sbcl

# Both suites find their systems through this CL_SOURCE_REGISTRY. It lists
# the repository root, non-recursively (one trailing slash), so ASDF finds
# cl-commonmark-gfm.asd but never walks into vendor/ or .guix-env/; then
# ocicl// recursively, so it finds every dependency ocicl installed. There
# is no empty entry, so no inherited configuration (e.g. a home directory
# source-registry.conf) leaks in (M1 design §7.1, §7.2).
TEST_SOURCE_REGISTRY := $(CURDIR)/:$(CURDIR)/ocicl//

# CCL 1.13's release binary sometimes hangs inside its own startup, before
# any Lisp code runs, and is deaf to SIGTERM (finding 20, M2 design §8.5;
# ADR-0013). run-suite below runs CCL only through
# scripts/lisp-start-watchdog, which waits CCL_START_WINDOW seconds for
# LISP_START_MARKER -- tests/run.lisp and tests/run-native.lisp's first,
# flushed line of output -- before killing the run and starting it again,
# up to CCL_START_TRIES times. `make check-watchdog` tests the script
# itself, against a fake.
CCL_START_WINDOW ?= 30
CCL_START_TRIES  ?= 3
LISP_START_MARKER := ;; lisp started

# $(call run-suite,TARGET,LISPS,RUNNER,ENV) runs RUNNER (tests/run.lisp,
# tests/run-native.lisp or one of the fuzz runners below) on each Lisp in
# LISPS, with ENV's environment assignments, if any, set for that run only;
# reports each Lisp under TARGET's name; and fails when any Lisp fails or is
# unknown.
#
# SBCL gets a 2 GB heap wherever it runs. Debian's SBCL, which CI uses
# (ADR-0013), defaults to 1 GB and Guix's to 3 GB. The deep tests need more
# than 768 MB at their peak, and under 1 GB CI's run ran out of heap while
# the container's passed.
#
# An empty or blank LISPS/NATIVE_LISPS makes the `for` loop below run zero
# times, leaving $$failed empty: nothing would run, yet TARGET would report
# a pass. $(strip ...) catches that first: both "" and " " strip to "".
define run-suite
if [ -z "$(strip $(2))" ]; then \
  echo "$(1): no Lisps given" >&2; \
  exit 1; \
fi; \
needed=""; \
for lisp in $(2); do \
  case "$$lisp" in \
    sbcl) needed="$$needed $(firstword $(SBCL))" ;; \
    ccl)  needed="$$needed $(CCL)" ;; \
    ecl)  needed="$$needed ecl" ;; \
    *) ;; \
  esac; \
done; \
[ -z "$$needed" ] || scripts/require-tools "$(GOAL)" $$needed || exit 2; \
failed=""; \
for lisp in $(2); do \
  if [ "$$lisp" = ccl ]; then \
    if $(4) CL_SOURCE_REGISTRY="$(TEST_SOURCE_REGISTRY)" scripts/lisp-start-watchdog \
         "$(CCL_START_WINDOW)" "$(CCL_START_TRIES)" "$(LISP_START_MARKER)" \
         $(CCL) -n -b -l $(3) </dev/null; then \
      echo "$(1): $$lisp passed"; \
    else \
      echo "$(1): $$lisp failed" >&2; \
      failed="$$failed $$lisp"; \
    fi; \
    continue; \
  fi; \
  case "$$lisp" in \
    sbcl) cmd="$(SBCL) --dynamic-space-size 2048 --non-interactive --no-sysinit --no-userinit --load $(3)" ;; \
    ecl)  cmd="ecl -norc -load $(3)" ;; \
    *) echo "$(1): unknown Lisp '$$lisp'" >&2; cmd=""; failed="$$failed $$lisp" ;; \
  esac; \
  if [ -n "$$cmd" ]; then \
    if $(4) CL_SOURCE_REGISTRY="$(TEST_SOURCE_REGISTRY)" $$cmd </dev/null; then \
      echo "$(1): $$lisp passed"; \
    else \
      echo "$(1): $$lisp failed" >&2; \
      failed="$$failed $$lisp"; \
    fi; \
  fi; \
done; \
if [ -n "$$failed" ]; then \
  echo "$(1): failed on:$$failed" >&2; \
  exit 1; \
fi; \
echo "$(1): passed on all of: $(2)"
endef

# PROPERTY_SEED and PROPERTY_CASES (ADR-0020) replay a property run: given,
# check-purity and check-native, and so `make test`, pass them to the Lisp
# runs as CL_COMMONMARK_GFM_SEED and CL_COMMONMARK_GFM_CASES. Unset (the
# default), nothing is passed and the harness's own defaults hold (seed 1,
# the CI counts). scripts/guix-env preserves only TERM, COLORTERM, LANG and
# GUIX_ENV_MANIFEST into the container, so these must be make variables,
# never an inherited environment variable: `scripts/guix-env make
# check-native PROPERTY_SEED=42` replays seed 42.
PROPERTY_SEED  ?=
PROPERTY_CASES ?=
PROPERTY_ENV := $(strip $(if $(PROPERTY_SEED),CL_COMMONMARK_GFM_SEED=$(PROPERTY_SEED)) \
                        $(if $(PROPERTY_CASES),CL_COMMONMARK_GFM_CASES=$(PROPERTY_CASES)))

check-purity: ## Run the pure suite on $(LISPS); replay with PROPERTY_SEED/PROPERTY_CASES
	@$(call run-suite,check-purity,$(LISPS),tests/run.lisp,$(PROPERTY_ENV))

check-native: ## Run the native suite on $(NATIVE_LISPS) (default sbcl; main's CI adds ccl and ecl); replay with PROPERTY_SEED/PROPERTY_CASES
	@$(call run-suite,check-native,$(NATIVE_LISPS),tests/run-native.lisp,$(PROPERTY_ENV))

check-watchdog: ## Test scripts/lisp-start-watchdog against a fake command
	@sh tests/lisp-start-watchdog.sh

check-preflight: ## Test that make fails fast, with a hint, when its tools are missing
	@sh tests/make-preflight.sh

test: check-watchdog check-preflight check-purity check-fixtures check-native ## Run the test suite a pull request runs (native suite on NATIVE_LISPS)

# The property tests' own CI case counts (ADR-0020) give `make test` about
# 30 s in the container. `make fuzz` replaces every property's own count
# with the flat FUZZ_CASES, from FUZZ_SEED (random by default): a few
# minutes, not hours, at the default. FUZZ_SEED=N FUZZ_CASES=M replays a
# fuzz failure. Empty is refused, not silently treated as unset.
FUZZ_CASES ?= 150000
FUZZ_SEED  ?= random

fuzz: ## Run the property tests, more cases (FUZZ_CASES); replay with FUZZ_SEED (random)
	@if [ -z "$(strip $(FUZZ_SEED))" ]; then \
	  echo "fuzz: FUZZ_SEED is empty" >&2; \
	  exit 1; \
	fi; \
	if [ -z "$(strip $(FUZZ_CASES))" ]; then \
	  echo "fuzz: FUZZ_CASES is empty" >&2; \
	  exit 1; \
	fi; \
	pure=0; native=0; \
	( $(call run-suite,fuzz-purity,$(LISPS),tests/run-fuzz.lisp,CL_COMMONMARK_GFM_SEED=$(FUZZ_SEED) CL_COMMONMARK_GFM_CASES=$(FUZZ_CASES)) ); pure=$$?; \
	if [ $$pure -eq 2 ]; then exit 2; fi; \
	( $(call run-suite,fuzz-native,$(NATIVE_LISPS),tests/run-native-fuzz.lisp,CL_COMMONMARK_GFM_SEED=$(FUZZ_SEED) CL_COMMONMARK_GFM_CASES=$(FUZZ_CASES)) ); native=$$?; \
	if [ $$native -eq 2 ]; then exit 2; fi; \
	if [ $$pure -ne 0 ] || [ $$native -ne 0 ]; then \
	  echo "fuzz: failed" >&2; \
	  exit 1; \
	fi

check-guix: ## Test scripts/guix-env on the host, then run the checks inside the container
	@sh tests/guix-env-launcher.sh
	@scripts/guix-env make check-guix-inside

check-guix-inside: ## (inside the container) Assert the pinned toolchain and isolation
	@CMARK_GFM_VERSION=$(CMARK_GFM_VERSION) OCICL_TAG=$(OCICL_TAG) sh scripts/guix-env-selftest

# check-ecl-static builds the smoke program, tests/static/, as an ECL
# program with cmark-gfm linked in, and runs it (M4 design §6.3). Its
# fasls, compiled under CFFI's :c/c++ method, go into ECL_STATIC_DIR with
# the program, and nowhere else: no other ECL may share them (finding 9).
# tests/static/build.lisp sets ASDF's output translations itself, so no
# inherited translation can send them elsewhere, and the recipe empties
# ECL_STATIC_DIR before each build. The program runs with
# CL_COMMONMARK_GFM_LIBS naming two files there that don't exist, so a
# startup that looks for files fails.
#
# The program's exit status alone doesn't show that it ran its checks. An
# ECL program that fails as it starts, before its epilogue, stops in ECL's
# debugger, which quits with status 0 at the end of its stdin (finding 26;
# the top level's :eof command, ECL 24.5.10's src/lsp/top.lsp). On
# Debian's ECL, a program built without the build's prologue does just
# that (finding 7). So the recipe also requires the program's summary line,
# with at least one check and 0 failed.
ECL_STATIC_DIR        := build/ecl-static
ECL_STATIC_PATH       := $(CURDIR)/$(ECL_STATIC_DIR)
ECL_STATIC_CORE       := $(ECL_STATIC_PATH)/missing-libcmark-gfm.so
ECL_STATIC_EXTENSIONS := $(ECL_STATIC_PATH)/missing-libcmark-gfm-extensions.so

# As TEST_SOURCE_REGISTRY, plus tests/static/, non-recursively, for the
# smoke system and for the condition test's, which check-ecl-nodffi-inside
# loads.
STATIC_SOURCE_REGISTRY := $(CURDIR)/:$(CURDIR)/tests/static/:$(CURDIR)/ocicl//

# The directory holding cmark-gfm's static archives, libcmark-gfm.a and
# libcmark-gfm-extensions.a, which Debian ships in libcmark-gfm-dev and
# libcmark-gfm-extensions-dev. Left empty, it is the directory of the first
# path in CL_COMMONMARK_GFM_LIBS, which the containers set (ADR-0004);
# otherwise the first of discovery's Linux directories, multiarch first,
# that holds both pinned shared libraries (ADR-0009;
# src/native-core/discovery.lisp), as Debian's /usr/lib/x86_64-linux-gnu
# does. That search is Linux's alone: elsewhere, such as on macOS,
# CMARK_GFM_ARCHIVE_DIR must name the directory (M4 design §6.3).
CMARK_GFM_ARCHIVE_DIR ?=

check-ecl-static: ## Build and run an ECL program with cmark-gfm linked in
	@scripts/require-tools "$(GOAL)" ecl
	@dir='$(subst ','\'',$(CMARK_GFM_ARCHIVE_DIR))'; \
	if [ -z "$$dir" ] && [ -n "$${CL_COMMONMARK_GFM_LIBS:-}" ]; then \
	  core=$${CL_COMMONMARK_GFM_LIBS%%:*}; \
	  dir=$${core%/*}; \
	elif [ -z "$$dir" ]; then \
	  case $$(uname -m) in \
	    x86_64) multiarch=/usr/lib/x86_64-linux-gnu ;; \
	    aarch64) multiarch=/usr/lib/aarch64-linux-gnu ;; \
	    *) multiarch= ;; \
	  esac; \
	  searched="$${multiarch:+$$multiarch }/usr/lib64 /usr/lib /usr/local/lib"; \
	  for candidate in $$searched; do \
	    if [ -f "$$candidate/libcmark-gfm.so.$(CMARK_GFM_VERSION)" ] \
	       && [ -f "$$candidate/libcmark-gfm-extensions.so.$(CMARK_GFM_VERSION)" ]; then \
	      dir=$$candidate; \
	      break; \
	    fi; \
	  done; \
	  if [ -z "$$dir" ]; then \
	    echo "make $(GOAL): no directory holds both pinned cmark-gfm libraries." >&2; \
	    echo "Searched discovery's Linux directories: $$searched." >&2; \
	    echo "Set CMARK_GFM_ARCHIVE_DIR to the directory holding libcmark-gfm.a and" \
	      "libcmark-gfm-extensions.a. Elsewhere than Linux, such as on macOS, it must be set." >&2; \
	    exit 2; \
	  fi; \
	fi; \
	missing=0; \
	for archive in libcmark-gfm-extensions.a libcmark-gfm.a; do \
	  if [ ! -f "$$dir/$$archive" ]; then \
	    echo "make $(GOAL): $$dir/$$archive not found." >&2; \
	    missing=1; \
	  fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then \
	  echo "On Debian, libcmark-gfm-dev and libcmark-gfm-extensions-dev ship them;" \
	    "or set CMARK_GFM_ARCHIVE_DIR to the directory holding both." >&2; \
	  exit 2; \
	fi; \
	rm -rf $(ECL_STATIC_DIR) && mkdir -p $(ECL_STATIC_DIR) || exit 1; \
	CL_SOURCE_REGISTRY="$(STATIC_SOURCE_REGISTRY)" CMARK_GFM_ARCHIVE_DIR="$$dir" \
	  ecl -norc -load tests/static/build.lisp </dev/null || exit 1; \
	CL_COMMONMARK_GFM_LIBS="$(ECL_STATIC_CORE):$(ECL_STATIC_EXTENSIONS)" \
	  $(ECL_STATIC_DIR)/cl-commonmark-gfm-static-smoke $(FIXTURES_DIR)/ \
	  </dev/null >$(ECL_STATIC_DIR)/smoke.log 2>&1; \
	status=$$?; \
	cat $(ECL_STATIC_DIR)/smoke.log; \
	[ "$$status" -eq 0 ] || exit 1; \
	grep -q '^check-ecl-static: [1-9][0-9]* checks, 0 failed$$' $(ECL_STATIC_DIR)/smoke.log || { \
	  echo "make $(GOAL): the program exited 0, but printed no" \
	    "'check-ecl-static: <n> checks, 0 failed', n above 0" >&2; \
	  exit 1; \
	}

check-ecl-nodffi: ## Run the ECL-without-dynamic-FFI container's checks
	@GUIX_ENV_MANIFEST=manifest-ecl-nodffi.scm scripts/guix-env make check-ecl-nodffi-inside

# Run on a Guix host outside any Guix environment, this target first
# points at `make check-ecl-nodffi`, which runs it in the container whose
# ECL has no dynamic FFI: scripts/require-tools would point at the
# ordinary one.
#
# *FEATURES* is a plain Lisp list, set once as ECL starts; reading it
# calls no foreign function, so an uncompiled -eval form sees exactly what
# a compiled one would. Unlike a real native probe, this guard exercises
# no FFI or interrupt path, so it needs no compiling. It prints what it
# found, and exits 3 for an ECL with :dffi, so an ECL that fails to run,
# with any other status or without that line, is reported as such, with
# its output.
#
# The condition test, tests/static/nodffi.lisp, does probe the FFI, so ASDF
# compiles it first, with cl-commonmark-gfm, into this container's own fasl
# cache (finding 9); then a process of its own loads them and runs it (M4
# design §6.4). It runs with CL_COMMONMARK_GFM_LIBS malformed, so a
# startup that ran discovery before step 1 would signal
# native-library-not-found there, and the test would fail. ECL reads each
# -eval form as it runs it (ECL 24.5.10's src/lsp/cmdline.lsp), so the last
# can name the package the load made. Like the smoke program, it must print
# its summary line, with at least one check and 0 failed: an ECL process
# can exit 0 from its debugger (finding 26).
check-ecl-nodffi-inside: ## (inside that container) The dynamic-FFI guard, dynamic-ffi-unavailable's condition test, then check-ecl-static
	@if command -v guix >/dev/null 2>&1 && [ -z "$${GUIX_ENVIRONMENT:-}" ]; then \
	  echo "make $(GOAL): this target runs inside the container whose ECL has no" \
	    "dynamic FFI. On this Guix host, run 'make check-ecl-nodffi', which starts it." >&2; \
	  exit 2; \
	fi
	@scripts/require-tools "$(GOAL)" ecl
	@out=$$(ecl -norc -eval '(let ((dffi (member :dffi *features*))) (format t "~&features: ~:[no :dffi~;:dffi~]~%" dffi) (finish-output) (si:quit (if dffi 3 0)))' </dev/null 2>&1); \
	status=$$?; \
	case "$$out" in *'features: no :dffi'*) found=yes ;; *) found=no ;; esac; \
	if [ "$$status" -eq 0 ] && [ "$$found" = yes ]; then \
	  echo "check-ecl-nodffi-inside: ok, this ECL has no :dffi"; \
	elif [ "$$status" -eq 3 ]; then \
	  echo "check-ecl-nodffi-inside: this ECL has :dffi; it is for the container without dynamic FFI, run 'make check-ecl-nodffi' instead" >&2; \
	  exit 1; \
	else \
	  printf '%s\n' "$$out" >&2; \
	  echo "check-ecl-nodffi-inside: ecl failed to run (exit $$status), so whether it has :dffi is unknown" >&2; \
	  exit 1; \
	fi
	@CL_SOURCE_REGISTRY="$(STATIC_SOURCE_REGISTRY)" ecl -norc -eval '(require :asdf)' \
	  -eval '(asdf:load-system "cl-commonmark-gfm-static-nodffi")' -eval '(si:quit 0)' </dev/null
	@log=build/ecl-nodffi/condition.log; \
	mkdir -p build/ecl-nodffi || exit 1; \
	CL_SOURCE_REGISTRY="$(STATIC_SOURCE_REGISTRY)" CL_COMMONMARK_GFM_LIBS=not-a-pair \
	  ecl -norc -eval '(require :asdf)' \
	  -eval '(asdf:load-system "cl-commonmark-gfm-static-nodffi")' \
	  -eval '(si:quit (if (cl-commonmark-gfm.static-nodffi:main) 0 1))' \
	  </dev/null >"$$log" 2>&1; \
	status=$$?; \
	cat "$$log"; \
	[ "$$status" -eq 0 ] || exit 1; \
	grep -q '^check-ecl-nodffi: [1-9][0-9]* checks, 0 failed$$' "$$log" || { \
	  echo "make $(GOAL): the condition test exited 0, but printed no" \
	    "'check-ecl-nodffi: <n> checks, 0 failed', n above 0" >&2; \
	  exit 1; \
	}
	@$(MAKE) --no-print-directory check-ecl-static

clean: ## Remove build outputs (keeps .guix-env/)
	rm -rf build
