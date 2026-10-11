---
name: Feature request
about: Propose an addition to the library
labels: enhancement
---

**The problem**

What can't you do today?

**What you'd like to write**

The function, variable or option you'd add, and a call that uses it.

**Does cmark-gfm already do this?**

If it would call cmark-gfm, name the `cmark_*` function. The library
supports cmark-gfm 0.29.0.gfm.13 alone, so it must be there.

**Safety and the pure core**

The library is safe by default. Its AST, its HTML tree, and the native
layer's decisions in `src/native-core/` never load CFFI. Would this
change a default, or need native code in one of those? Either needs a
design conversation first.
