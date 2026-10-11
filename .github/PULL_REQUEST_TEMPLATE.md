## What

<!-- One or two sentences: what changes, and why. -->

## How a test failed first

<!-- For each new or changed test: the change to the code that made it
fail, and what it reported. Write "none" for a change with no test,
such as a page's wording. -->

## Checklist

- [ ] The title is a Conventional Commit (`feat:`, `fix:`, `docs:`, …)
- [ ] `make test` is green locally
- [ ] Tests come with code changes, and each was watched to fail
- [ ] If `src/ffi.lisp`, `src/native/`, or how the library starts
      cmark-gfm changed: `make check-native NATIVE_LISPS="ccl ecl"` and
      `make check-ecl-static` are green, or I've asked a maintainer to
      run CI's full steps on this branch
- [ ] If library discovery changed: the gates are green on a Mac too
- [ ] `docs/` is updated if users would see the change, and `make
      reference` is rerun if an export or its docstring changed
- [ ] `CHANGELOG.md` has an entry if users would see the change
