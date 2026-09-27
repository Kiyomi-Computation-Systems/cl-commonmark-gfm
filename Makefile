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

# Every syntax extension, plus footnotes (an option, not an extension, in
# the library; the CLI spells it as one). Used by check-vocabulary (ADR-0005).
VOCAB_FLAGS := --sourcepos -e footnotes -e table -e strikethrough -e autolink \
               -e tagfilter -e tasklist
VOCAB_MD    := tests/fixtures/vocabulary.md
VOCAB_XML   := tests/fixtures/vocabulary.xml

# MUST stay on one physical line: check-help reads it with awk, one line only.
.PHONY: help check-help info ocicl check-vocabulary check-guix check-guix-inside clean

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
	@echo "sbcl      : $$($(SBCL) --version 2>/dev/null || echo missing)"
	@echo "ecl       : $$(ecl --version 2>/dev/null || echo missing)"
	@echo "ccl       : $$(ccl --eval '(progn (princ (lisp-implementation-version)) (ccl:quit))' 2>/dev/null || echo missing)"
	@echo "cmark-gfm : $$(pkg-config --modversion libcmark-gfm 2>/dev/null || echo missing) (pinned $(CMARK_GFM_VERSION))"
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

# The AST vocabulary table in the plan was read off this output. If a pin
# bump changes it, the table (and ADR-0005) must be revisited.
check-vocabulary: ## Diff the pinned cmark-gfm's XML for the vocabulary fixture against the record
	@cmark-gfm $(VOCAB_FLAGS) -t xml $(VOCAB_MD) | diff -u $(VOCAB_XML) - \
	  && echo "check-vocabulary: cmark-gfm output matches $(VOCAB_XML)"

check-guix: ## Test scripts/guix-env on the host, then run the checks inside the container
	@sh tests/guix-env-launcher.sh
	@scripts/guix-env make check-guix-inside

check-guix-inside: ## (inside the container) Assert the pinned toolchain and isolation
	@CMARK_GFM_VERSION=$(CMARK_GFM_VERSION) OCICL_TAG=$(OCICL_TAG) sh scripts/guix-env-selftest

clean: ## Remove build outputs (keeps .guix-env/)
	rm -rf build
