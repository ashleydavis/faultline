# Development

How to work with and contribute to this repo.

## Setup

Install dependencies:

```sh
mise install
```

## Commands

- `zig build` compiles the Faultline library and its tests.
- `zig build test` runs the unit tests, in the default optimisation and again in `ReleaseSafe`.
- `bash scripts/smoke.sh` runs smoke tests against all examples.
- `bash scripts/test-everything.sh` runs the suites the change affects, in parallel, stopping at the first failure. This is run by the Git pre-commit hook.

## The examples

Every directory under `examples/` is a small project of its own: it declares Faultline as a dependency and calls `addFaultTest` in its own `build.zig`, exactly as a real project does. 

`bash scripts/smoke.sh` runs `zig build flt` in each of them. 
`examples/working/` is one feature per directory and `examples/non-working/` is one failure per directory.

Run tests individually:

```sh
bash scripts/smoke.sh 01-one-function
```
