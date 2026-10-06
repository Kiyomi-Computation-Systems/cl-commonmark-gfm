# Installing

The library needs cmark-gfm 0.29.0.gfm.13: its two shared libraries,
libcmark-gfm and libcmark-gfm-extensions. Install them first, then the
library itself, through ocicl. The library has no C code of its own: you
need a C compiler only to build cmark-gfm yourself, or for ECL, which
compiles Lisp through one.

It must be exactly that version. The library calls cmark-gfm directly,
and relies on details of that one release. So it checks the version as
cmark-gfm starts, and refuses any other.

## Debian and Ubuntu

On Debian 13 or Ubuntu 26.04 LTS, install cmark-gfm's two libraries:

```sh
sudo apt install libcmark-gfm0.29.0.gfm.13 libcmark-gfm-extensions0.29.0.gfm.13
```

The library needs only these two, not the `-dev` packages. Debian 12,
Ubuntu 24.04 LTS and older releases ship an older cmark-gfm, which the
library won't use: see
[Building cmark-gfm from source](#building-cmark-gfm-from-source).

## Building cmark-gfm from source

On an older Debian or Ubuntu, install the tools, then fetch version
0.29.0.gfm.13, build it, and install it:

```sh
sudo apt install build-essential cmake git
git clone --depth 1 --branch 0.29.0.gfm.13 https://github.com/github/cmark-gfm
cmake -S cmark-gfm -B cmark-gfm/build \
  -DCMARK_TESTS=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build cmark-gfm/build
sudo cmake --install cmark-gfm/build
```

This puts both libraries in `/usr/local/lib`, where the library looks.
`-DCMARK_TESTS=OFF` skips cmark-gfm's own tests.
`-DCMAKE_POLICY_VERSION_MINIMUM=3.5` lets CMake 4 build cmark-gfm, whose
build files it would refuse as too old. An older CMake warns that it
didn't use it, which is harmless.

## macOS

On macOS, install cmark-gfm with Homebrew:

```sh
brew install cmark-gfm
```

Homebrew puts it in `/opt/homebrew/lib` on Apple silicon, and in
`/usr/local/lib` on Intel. The library looks in both.

### CCL on Apple silicon

CCL runs there under Rosetta, as an Intel program, so it needs an Intel
cmark-gfm, such as the one a Homebrew for Intel installs into
`/usr/local/lib`. Name that pair in the shell you start CCL from:

```sh
core=/usr/local/lib/libcmark-gfm.0.29.0.gfm.13.dylib
extensions=/usr/local/lib/libcmark-gfm-extensions.0.29.0.gfm.13.dylib
export CL_COMMONMARK_GFM_LIBS=$core:$extensions
```

Otherwise, when `/opt/homebrew/lib` holds cmark-gfm too, the library
finds that pair first, which CCL can't load, and the call signals
[`native-library-not-found`](reference.md#native-library-not-found). Set
the variable only for CCL: an SBCL or ECL built for Apple silicon needs
the other pair. These steps haven't been tried yet.

## Guix

On Guix, install cmark-gfm, then name its two files in the shell you
start Lisp from, since the library doesn't look in your profile:

```sh
guix install cmark-gfm
core=$HOME/.guix-profile/lib/libcmark-gfm.so.0.29.0.gfm.13
extensions=$HOME/.guix-profile/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13
export CL_COMMONMARK_GFM_LIBS=$core:$extensions
```

## The library, through ocicl

Install SBCL from your system's packages, and ocicl as
[ocicl's README](https://github.com/ocicl/ocicl#installation) says. Then
add ocicl's setup to SBCL's startup file:

```sh
ocicl setup >> ~/.sbclrc
```

For CCL, add it to `~/ccl-init.lisp` instead, or to `~/.ccl-init.lisp`
if you already have that one. For ECL, see
[Loading the library](ecl.md#loading-the-library). Next, install the
library in your project's directory:

```sh
mkdir -p my-app && cd my-app
ocicl install cl-commonmark-gfm
```

ocicl puts the library in `ocicl/` there, and records it in `ocicl.csv`,
unless a directory above already holds an `ocicl.csv`, which ocicl then
uses instead. Start SBCL in that directory, where ocicl finds it, then
load the library and call it:

```lisp
(asdf:load-system "cl-commonmark-gfm")

(cl-commonmark-gfm:markdown->html "Hello, *world*!")
;; => "<p>Hello, <em>world</em>!</p>\n"
```

The first load takes longer: ocicl fetches anything still missing, and
SBCL compiles it all. If the call signals `native-library-not-found`, see
[When cmark-gfm can't start](#when-cmark-gfm-cant-start).
[Usage](usage.md) shows what to do next. Its examples leave off the
`cl-commonmark-gfm:` prefix: see [The package](usage.md#the-package).

## Where the library looks

The library loads cmark-gfm at the first call that needs it. Unless you
name the files yourself, it searches these directories, in order, for
both libraries under their full names:

| | Linux | macOS |
|---|---|---|
| Directories | `/usr/lib/x86_64-linux-gnu` or `/usr/lib/aarch64-linux-gnu`, `/usr/lib64`, `/usr/lib`, `/usr/local/lib` | `/opt/homebrew/lib`, `/usr/local/lib` |
| Core library | `libcmark-gfm.so.0.29.0.gfm.13` | `libcmark-gfm.0.29.0.gfm.13.dylib` |
| Extensions library | `libcmark-gfm-extensions.so.0.29.0.gfm.13` | `libcmark-gfm-extensions.0.29.0.gfm.13.dylib` |

It takes the first directory that holds both, skipping any that holds
only one. The extensions library depends on the core library, so taking
the two from different places could load two copies of the core, and
nothing would warn you. The version in each name means another version
is never picked up by mistake. The system's own search, such as
`LD_LIBRARY_PATH`, isn't used.

When no directory holds both, the call signals `native-library-not-found`,
listing the directories. A pair that won't load, such as one built for
another architecture, signals it too, naming the file: the search
doesn't go on to the next directory.

## Choosing the libraries yourself

Name the two files yourself, by their absolute paths, the core library
first. In Lisp, bind
[`*cmark-gfm-libraries*`](reference.md#cmark-gfm-libraries) to a list of
the two, around your first call:

```lisp no-run
(let ((*cmark-gfm-libraries*
        '("/opt/cmark-gfm/lib/libcmark-gfm.so.0.29.0.gfm.13"
          "/opt/cmark-gfm/lib/libcmark-gfm-extensions.so.0.29.0.gfm.13")))
  (markdown->html "Hello, *world*!"))
;; => "<p>Hello, <em>world</em>!</p>\n"
```

Or, before Lisp starts, set `CL_COMMONMARK_GFM_LIBS` to the two paths,
separated by a colon: see [Guix](#guix). When both are set, the Lisp
variable wins.

Either is used just as given: the library doesn't search, or fall back
to the other. One that isn't two absolute paths, or names something that
isn't a file, makes the call signal `native-library-not-found`, naming
that override. Both are read as cmark-gfm starts, at the first call that
needs it. Once it has started, changing them does nothing.

## When cmark-gfm can't start

If cmark-gfm can't start, the call that needed it signals one of four
conditions, each a [`native-error`](reference.md#native-error). Fix the
cause, and call again: each call tries again until cmark-gfm starts.

- `native-library-not-found`: no pair was found, an override is wrong,
  or a file wouldn't load. When no directory holds both libraries, its
  message says "no searched directory holds both pinned libraries".
  Install cmark-gfm 0.29.0.gfm.13 as above, or fix the override.
- [`native-abi-mismatch`](reference.md#native-abi-mismatch): the files
  loaded aren't version 0.29.0.gfm.13. Name that version's files.
- [`native-initialization-error`](reference.md#native-initialization-error):
  the files loaded, but cmark-gfm didn't start, such as when an
  extension is missing. Name the two libraries of one install.
- [`dynamic-ffi-unavailable`](reference.md#dynamic-ffi-unavailable): this
  ECL was built without dynamic FFI, so it can't load a library. Link
  cmark-gfm into your program instead: see [A program with cmark-gfm
  linked in](ecl.md#a-program-with-cmark-gfm-linked-in).

On CCL, to load another pair, start a new CCL: see
[Libraries on CCL](safety.md#libraries-on-ccl). [Errors](errors.md)
explains the other conditions.

## Other code that loads cmark-gfm

Load cmark-gfm only through this library. Loading its files yourself in
the same process, such as through your own CFFI definitions, isn't
supported. The library closes its files at times, such as when a start
fails, or before SBCL saves an image. On SBCL and ECL, that unloads them
from under your code too. Another binding of cmark-gfm can also race with
this one: see [Threads and timeouts](safety.md#threads-and-timeouts).
