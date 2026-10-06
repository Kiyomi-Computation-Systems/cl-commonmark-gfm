# ECL

ECL runs the library as SBCL does, when it has dynamic FFI. Without it,
ECL can't load cmark-gfm as a program runs: link cmark-gfm into your
program instead. For the package the examples run in, see
[The package](usage.md#the-package).

On ECL, don't interrupt a thread, or time it out, during a call: see
[Threads and timeouts](safety.md#threads-and-timeouts).

## Loading the library

Put ocicl's setup in ECL's startup file, `~/.eclrc`:

```sh
ocicl setup >> ~/.eclrc
```

Then install the library, starting ECL where the steps start SBCL: see
[The library, through ocicl](installing.md#the-library-through-ocicl).

## With dynamic FFI

Check that your ECL has dynamic FFI:

```lisp no-run
(find :dffi *features*)
;; => :dffi
```

Debian's ECL has it, and so does Guix's. There the library loads
cmark-gfm at run time: see [Installing](installing.md).

## Without dynamic FFI

On an ECL built without dynamic FFI, the first call signals
[`dynamic-ffi-unavailable`](reference.md#dynamic-ffi-unavailable):

```lisp no-run
(markdown->html "Hello, *world*!")
;; signals dynamic-ffi-unavailable
```

Its message says how to link cmark-gfm into your program instead: see
[A program with cmark-gfm linked in](#a-program-with-cmark-gfm-linked-in).

## A program with cmark-gfm linked in

Link cmark-gfm into your program when your ECL has no dynamic FFI, or
when the machine it runs on has no cmark-gfm. Each call to cmark-gfm is
then a direct C call, and the program loads no cmark-gfm library.

First, install ECL and cmark-gfm's two static archives,
`libcmark-gfm.a` and `libcmark-gfm-extensions.a`. On Debian 13:

```sh
sudo apt install ecl libcmark-gfm-dev libcmark-gfm-extensions-dev
```

The archives go into `/usr/lib/x86_64-linux-gnu`, or
`/usr/lib/aarch64-linux-gnu` on arm64. With Guix, install `ecl`,
`gcc-toolchain` and `cmark-gfm`: the archives are in your profile's
`lib` directory. For macOS, see [macOS](#macos).

Next, install the library in your project's directory: see
[Loading the library](#loading-the-library).

Then, in that directory, write your program as a system that depends
on the library. Here, `hello.asd`:

```lisp no-run
(asdf:defsystem "hello"
  :depends-on ("cl-commonmark-gfm")
  :components ((:file "hello")))
```

And `hello.lisp`, whose `main` the program runs:

```lisp no-run
(defpackage #:hello
  (:use #:cl)
  (:import-from #:cl-commonmark-gfm #:markdown->html)
  (:export #:main))

(in-package #:hello)

(defun main ()
  (write-string (markdown->html "Hello, *world*!"))
  (finish-output))
```

Write `build.lisp`, with `*archives*` naming the archives' directory as
an absolute path, with no spaces:

```lisp no-run
(require :asdf)
(require :cmp)

;;; The directory holding libcmark-gfm.a and libcmark-gfm-extensions.a.
(defparameter *archives* "/usr/lib/x86_64-linux-gnu")
(defparameter *build* (merge-pathnames "build/" (uiop:getcwd)))

;;; Compile every file into build/, and nowhere else.
(asdf:initialize-output-translations
 `(:output-translations
   (t (,(merge-pathnames "cache/" *build*) :implementation))
   :ignore-inherited-configuration))

;;; Before the library compiles: compile its calls to cmark-gfm as C
;;; calls, and link both archives, the extensions first.
(asdf:load-system "cffi")
(setf cffi-sys:*cffi-ecl-method* :c/c++)
(setf c::*ld-libs*
      (format nil "~A/libcmark-gfm-extensions.a ~A/libcmark-gfm.a ~A"
              *archives* *archives* c::*ld-libs*))

;;; Compile everything, then link the program, build/hello.
(asdf:load-system "hello" :force :all)
(apply #'asdf:make-build "hello"
       :type :program
       :monolithic t
       :move-here *build*
       ;; Run main; on an error, print it and exit with status 1.
       :epilogue-code '(handler-case (hello:main)
                         (error (condition)
                           (format *error-output* "~A~%" condition)
                           (ext:exit 1)))
       ;; With no ASDF to link in, load ECL's own as the program starts.
       (unless (probe-file (translate-logical-pathname "SYS:libasdf.a"))
         '(:prologue-code (let ((*load-verbose* nil)) (require :asdf)))))
(ext:quit 0)
```

Build the program in an empty `build/`, so no ECL loads another
build's files, and run it:

```sh
rm -rf build
ecl --load build.lisp
./build/hello
```

It prints `<p>Hello, <em>world</em>!</p>`. If ASDF warns that
`make-build` is deprecated, that's expected: the build still works.

The program needs ECL where it runs, but no cmark-gfm. It ignores
[`*cmark-gfm-libraries*`](reference.md#cmark-gfm-libraries) and
`CL_COMMONMARK_GFM_LIBS`. Debian's ECL has no ASDF to link in, so there
the program loads ECL's own ASDF as it starts.

## macOS

Set `*archives*` to the directory where Homebrew put cmark-gfm, which
holds both archives: see [macOS](installing.md#macos). This recipe
hasn't been tried on macOS.
