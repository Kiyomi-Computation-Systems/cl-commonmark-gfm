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
.PHONY: help check-help info deps ocicl check-vocabulary check-pins check-notice check-purity check-native check-fixtures fixtures-html check-watchdog check-preflight test fuzz check-guix check-guix-inside clean

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / \
	  { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

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
# all three; check-native runs the native suite on SBCL alone until M4 adds
# CCL and ECL (M2 design §8.5).
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
# the CI counts). scripts/guix-env preserves only TERM, COLORTERM and LANG
# into the container, so these must be make variables, never an inherited
# environment variable: `scripts/guix-env make check-native
# PROPERTY_SEED=42` replays seed 42.
PROPERTY_SEED  ?=
PROPERTY_CASES ?=
PROPERTY_ENV := $(strip $(if $(PROPERTY_SEED),CL_COMMONMARK_GFM_SEED=$(PROPERTY_SEED)) \
                        $(if $(PROPERTY_CASES),CL_COMMONMARK_GFM_CASES=$(PROPERTY_CASES)))

check-purity: ## Run the pure suite on $(LISPS); replay with PROPERTY_SEED/PROPERTY_CASES
	@$(call run-suite,check-purity,$(LISPS),tests/run.lisp,$(PROPERTY_ENV))

check-native: ## Run the native suite on $(NATIVE_LISPS); replay with PROPERTY_SEED/PROPERTY_CASES
	@$(call run-suite,check-native,$(NATIVE_LISPS),tests/run-native.lisp,$(PROPERTY_ENV))

check-watchdog: ## Test scripts/lisp-start-watchdog against a fake command
	@sh tests/lisp-start-watchdog.sh

check-preflight: ## Test that make fails fast, with a hint, when its tools are missing
	@sh tests/make-preflight.sh

test: check-watchdog check-preflight check-purity check-fixtures check-native ## Run the full test suite

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

clean: ## Remove build outputs (keeps .guix-env/)
	rm -rf build
