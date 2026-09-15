# Faultline

Faultline automatically runs all code paths in all your Zig functions proving that all code paths run without problems.

This isn't about proving that your code does what it is supposed (that's why you should have unit tests, smoke tests, integration tests, end-to-end tests, etc). 

Instead Faultline is to test that your code can handle every combination of inputs and faults thrown at it without crashing.

## What it does

Faultline calls every single Zig function in your project and exercises every possible code path. It tries every input combination and injected fault to find every code path.

It is a library your project depends on. Two lines put it in, one to fetch it and one in your `build.zig`, and then `zig build flt` is the whole of running it.

## The work you have to do to make this possible

- Annotate every branch of your code. This will be done by automatic code coverage in the future.
- Provide factory functions for your custom types to Faultline so it can automatically build inputs to your functions (all standard types are covered automatically, this is only need for your custom types).
- Provide scenario functions that exercise code paths that Faultline can't reach by itself.

## Resources

- [Quick reference](docs/QUICK-REF.md) to add Faultline to a repository and use it.
- [User guide](docs/USER-GUIDE.md) to exhaustively test every function you write, with minimal effort.
- [Output](docs/OUTPUT.md) for what a run prints and what each line means.
- [Development](docs/DEVELOPMENT.md) to work on Faultline itself.
