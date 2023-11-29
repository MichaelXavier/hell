# hell

Welcome to Hell :smiling_imp:

<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
**Table of Contents**

- [hell](#hell)
    - [Description](#description)
        - [Informal description](#informal-description)
        - [More formal description](#more-formal-description)
        - [Design philosophy](#design-philosophy)
    - [Instructions](#instructions)
        - [Running](#running)
        - [Building](#building)

<!-- markdown-toc end -->

## Description

Hell is an interpreted, statically-typed, shell scripting language
based on Haskell.

### Informal description

See `examples/` for a list of example scripts.

Example program:

```haskell
main = do
  Text.putStrLn "Please enter your name and hit ENTER:"
  name :: Text <- Text.getLine
  Text.putStrLn "Thanks, your name is: "
  Text.putStrLn name
```

### More formal description

The language is a simply-typed lambda calculus, plus some syntactic
sugar and some primitives that can be polymorphic (but require
immediately applied type applications). Recursion is not supported.

Its syntax is a subset of Haskell.

Polymorphic primitives such as `id` require passing the type of the
argument as `id @Int 123`. You cannot define polymorphic lambdas of
your own. It's not full System-F.

It will support type-classes (for equality, dictionaries, etc), but
the dictionaries must be explicitly supplied. You can't define
classes, or data types, of your own.

The types and functions available lean directly on the host language
(Haskell) and are either directly lifted, or a simplified layer over
the original things.

There is (presently) no type inference. All parameters of lambdas, or
do-notation let bindings, must have their type declared via a pattern
signature.

```haskell
\(x :: Int) -> x
```

Globals of any kind must be fully qualified (`Main.foo` and
`Text.putstrLn`).

### Design philosophy

Turtle, Shelly, shell-conduit and Shh are "do shell scripting in
Haskell", but lack something. GHC is a large dependency to require for
running scripts, and the Haskell ecosystem is not capable of the
stability required. Scripts written in them are brittle and clunky.

My definition of a shell scripting language:

* A small interpreted language capable of launching processes
* No abstraction or re-use capabilities from other
  files/modules/packages
* Small, portable binary
* Stable, does not change in backwards-incompatible ways

Hell satisfies these criteria.

## Instructions

### Running

Presently the `hell` binary type-checks and interprets immediately a
program in `IO`.

    $ hell examples/01-hello-world.hell
    Hello, World!

See https://github.com/chrisdone/hell/releases for a statically-linked
amd64 Linux binary.

### Building

Build statically for Linux in a musl distribution:

    stack build --ghc-options="-static -optl-static"
