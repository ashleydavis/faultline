# Development

How to work with and contribute to this repo.

## Setup

Install dependencies:

```sh
mise install
```

Install kcov as well: the example suite runs every example under it. Where your distribution packages it:

```sh
sudo apt install kcov
```

Where it does not, build it from source. It needs cmake, a C++ compiler, and the development packages for elfutils (`libdw`), libcurl, zlib and OpenSSL (`cmake`, `g++`, `libdw-dev`, `libelf-dev`, `libcurl4-openssl-dev`, `zlib1g-dev` and `libssl-dev` on Debian and Ubuntu):

```sh
curl -L https://github.com/SimonKagstrom/kcov/archive/refs/tags/v43.tar.gz | tar xz
cd kcov-43
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$HOME/.local" ..
make
make install
```

That puts `kcov` in `~/.local/bin`, which has to be on your PATH.

## Commands

- `zig build` compiles the Faultline library and its tests.
- `zig build test` runs the unit tests, in the default optimisation and again in `ReleaseSafe`.
- `bash scripts/smoke.sh` runs smoke tests against all examples.
- `bash scripts/test-everything.sh` runs the suites the change affects, in parallel, stopping at the first failure. This is run by the Git pre-commit hook.

## The examples

Every directory under `examples/` is a small project of its own: it declares Faultline as a dependency and calls `addFaultTest` in its own `build.zig`, exactly as a real project does. 

`bash scripts/smoke.sh` runs `zig build flt` in each of them. 
`examples/working/` is one feature per directory and `examples/non-working/` is one failure per directory.

The examples with `kcov` in their names show coverage read from kcov: a module with no annotation and no `Log` parameter reaching every path, and the branches kcov cannot tell apart being named on the checklist.

Run tests individually:

```sh
bash scripts/smoke.sh 01-one-function
```
