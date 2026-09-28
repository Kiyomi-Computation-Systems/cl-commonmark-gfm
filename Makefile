# cl-commonmark-gfm
#
# On a Guix host, run targets through the container (ADR-0004):
#   scripts/guix-env make <target>

SBCL ?= sbcl

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

# The oracle fixtures (design §7.3): one manifest, one Markdown input and one
# committed HTML file per case. FIXTURES_FLAGS is cmark's GFM set, minus
# --sourcepos, applied before each case's own extra flags.
FIXTURES_DIR   := tests/fixtures/html
FIXTURES_CASES := $(FIXTURES_DIR)/cases
FIXTURES_FLAGS := -e footnotes -e table -e strikethrough -e autolink \
                  -e tagfilter -e tasklist

# MUST stay on one physical line: check-help reads it with awk, one line only.
.PHONY: help check-help info deps ocicl check-vocabulary check-pins check-notice check-purity check-fixtures fixtures-html test check-guix check-guix-inside clean

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
	@echo "ccl       : $$(ccl --eval '(progn (princ (lisp-implementation-version)) (ccl:quit))' 2>/dev/null || echo missing)"
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
	@ocicl install </dev/null

# The AST vocabulary table in the plan was read off this output. If a pin
# bump changes it, the table (and ADR-0005) must be revisited.
check-vocabulary: ## Diff the pinned cmark-gfm's XML for the vocabulary fixture against the record
	@cmark-gfm $(VOCAB_FLAGS) -t xml $(VOCAB_MD) | diff -u $(VOCAB_XML) - \
	  && echo "check-vocabulary: cmark-gfm output matches $(VOCAB_XML)"

check-fixtures: ## Diff the pinned cmark-gfm's HTML for every oracle case against its committed .html
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

# The Lisps check-purity runs the pure suite on. CL_SOURCE_REGISTRY below
# lists the repository root, non-recursively (one trailing slash), so ASDF
# finds cl-commonmark-gfm.asd but never walks into vendor/ or .guix-env/;
# then ocicl// recursively, so it finds every dependency ocicl installed.
# There is no empty entry, so no inherited configuration (e.g. a home
# directory source-registry.conf) leaks in (design §7.1, §7.2).
LISPS ?= sbcl ccl ecl

check-purity: ## Run the pure test suite (tests/run.lisp) on each Lisp in $(LISPS)
	@failed=""; \
	for lisp in $(LISPS); do \
	  case "$$lisp" in \
	    sbcl) cmd="$(SBCL) --non-interactive --no-sysinit --no-userinit --load tests/run.lisp" ;; \
	    ccl)  cmd="ccl -n -b -l tests/run.lisp" ;; \
	    ecl)  cmd="ecl -norc -load tests/run.lisp" ;; \
	    *) echo "check-purity: unknown Lisp '$$lisp'" >&2; cmd=""; failed="$$failed $$lisp" ;; \
	  esac; \
	  if [ -n "$$cmd" ]; then \
	    if CL_SOURCE_REGISTRY="$(CURDIR)/:$(CURDIR)/ocicl//" $$cmd </dev/null; then \
	      echo "check-purity: $$lisp passed"; \
	    else \
	      echo "check-purity: $$lisp failed" >&2; \
	      failed="$$failed $$lisp"; \
	    fi; \
	  fi; \
	done; \
	if [ -n "$$failed" ]; then \
	  echo "check-purity: failed on:$$failed" >&2; \
	  exit 1; \
	fi; \
	echo "check-purity: passed on all of: $(LISPS)"

test: check-purity check-fixtures ## Run the full test suite

check-guix: ## Test scripts/guix-env on the host, then run the checks inside the container
	@sh tests/guix-env-launcher.sh
	@scripts/guix-env make check-guix-inside

check-guix-inside: ## (inside the container) Assert the pinned toolchain and isolation
	@CMARK_GFM_VERSION=$(CMARK_GFM_VERSION) OCICL_TAG=$(OCICL_TAG) sh scripts/guix-env-selftest

clean: ## Remove build outputs (keeps .guix-env/)
	rm -rf build
