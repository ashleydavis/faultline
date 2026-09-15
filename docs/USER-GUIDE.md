# Fault testing a repository with Faultline (full guide)

Faultline exercises every code path in every function in your repository. This is a guide to help you get up and running with Faultline.

## Step 1: Add Faultline to your project

Faultline is an ordinary Zig library. Fetch it:

```sh
zig fetch --save=faultline git+https://github.com/ashleydavis/faultline
```

Then add one line to your `build.zig`:

```zig
@import("faultline").addFaultTest(b, .{ .imports = your_imports });
```

That gives you a build step named `flt`. 

Your `build.zig` already lists the modules your code imports. They are the `.imports` on the module you declare for your own code:

```zig
const your_module = b.addModule("yourproject", .{
    .root_source_file = b.path("src/root.zig"),
    .imports = your_imports,
});
```

Give Faultline that same `your_imports`. It builds your code into a test program of its own, and that will not compile unless it has the modules your code imports. If one is missing, Faultline tells you which.

### Install kcov

Faultline reads which lines of your code ran from [kcov](https://github.com/SimonKagstrom/kcov), a program that watches a binary from outside through its debug information. That is how it knows a branch ran without you writing anything into it.

Install it from your distribution where it has a package:

```sh
sudo apt install kcov
```

Where it has none, build it from source. It needs cmake, a C++ compiler, and the development packages for elfutils (`libdw`), libcurl, zlib and OpenSSL. On Debian and Ubuntu those are `cmake`, `g++`, `libdw-dev`, `libelf-dev`, `libcurl4-openssl-dev`, `zlib1g-dev` and `libssl-dev`.

```sh
curl -L https://github.com/SimonKagstrom/kcov/archive/refs/tags/v43.tar.gz | tar xz
cd kcov-43
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX="$HOME/.local" ..
make
make install
```

That puts `kcov` in `~/.local/bin`. Faultline finds it on the PATH, or you name it with `-Dkcov=<path>`.

kcov is optional. A run without it says so in one line and reads coverage from annotations alone. With it, a path is ticked by its line running or by its annotation, whichever comes back, so annotations and kcov mix however you like.

## Step 2: Run it

```sh
zig build flt
```

Faultline finds your Zig files, compiles them, calls every function it can and exercises every code path it can reach.

It prints a checklist of the things you must do to reach 100% code coverage.

It exits 1 on anything under 100% and 0 at 100%. This is by design to use it you need to get the 100% coverage and stay there (don't worry, Claude will help you get there quickly).

## Step 3: Read the report

At the end Faultline prints a block per file and a line per function:

```
  packages/example/src/format.zig
    ok   formatFileSize                     9/9 paths, 120 calls

  packages/example/src/wrapped_error.zig
    ok   formatErrorChain                   5/5 paths, 307 calls
```

Your function is done when its line reads `ok` and the two numbers match. 

When a code path can't be reached, Faultline tells you want to do to fix it:

```
  FAIL 1 code path that nothing reached:
      sizing.zig:9 "if:9:false" in isLarge: this branch carries no annotation.

  One thing to do:
    Add an annotation to sizing.zig:9, on the false side of the if in isLarge.
```

The output of Faultline is a checklist you can work through to achieve 100% test coverage of your code.

## Step 4: Annotate every branch

Faultline needs to know what branches in your code are being exercised. So you must `annotate` each branch like this:

```zig
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

pub fn isLarge(log: Log, value: u32) bool {
    if (value > 1000) {
        // Annotates this code branch. 
        if (an) annotate(log, "isLarge-large", "", .{}); 
        return true;
    }
    return false;
}
```

Calls to `annotate` are only for Faultline testing builds and are compiled out for release builds, so they have no impact on production code.

`log` is a `Log` parameter your function takes so that it can annotated its code paths and log important events.

Where each annotation goes:

- **The first statement of every side of every `if` that has code in it.** An `else` with a body gets its own annotation, the same as the `if` side.
- **An `if` with no `else` needs no annotation for the missing side.** Faultline counts how often it called the function against how often the branch said it was taken, and a function called more often than the branch fired is one that did not take it.
- **The first statement of every `switch` arm.**
- **The first statement of every loop body.** One annotation, the same as any other branch.

```zig
for (items) |item| {
    if (an) annotate(log, "my-loop-body", "", .{});
    try handleOne(item, log);
}
```

Put annotations in every nested code block: an `if` inside a loop, a loop inside a `switch` arm, an `if` inside an `else`, however deep it goes. 

Name a branch after what happened: `"cache-miss"`, `"format-file-size-zero"`. The name is what you read in Faultline's output.

## Step 5: Create test input factories for your types

Faultline automatically instantiates parameters where possible.

It can handle ordinary primitive values like integers, floats, booleans, enums, optionals, errors, slices, arrays, plain structs, tagged unions and pointers to any of those. 

It can handle various standard types: the allocator, `std.Io`, the network, the clock, `std.Random`, a writer, the log, etc.

It inject failures: the allocator it hands you fails every few calls, the writer it hands you sometimes has almost no room, and the network it hands you resolves no name and refuses connections.

Faultline cannot instantiate your custom types. So you must provide one or more "test input factory" for each of your own types.

### A plain test input factory function

A test input factory is an ordinary public function returning an instance of your type:

```zig

// Draws from this run's own seeded source.
pub fn randomGenerator() RandomGenerator {
    return .{ .random = my_random_number() };
}
```

Faultline finds a test input factory function by its return type.

Put the test input factory in a sim file, which you create next to the file being tested. For example if you are testing functions in `image.zig`, create a file `image.sim.zig`. Faultline automatically finds your sim files to find your test input factories.

A test input factory may take parameters and Faultline provides them automatically.

### One factory, many different values

A plain test input factory function hands provides one value. To hand back a different value each time, put the function on a struct instead:

```zig
pub const MyValueCreator = struct {

    //
    // Whatever state variables you want.
    //

    pub fn generator(self: *MyValueCreator) RandomGenerator {
        //
        // Returns the next value in whatever 
        // sequence you want.
        //        
    }
};
```

Faultline finds it the same way as a plain function, by the type the function returns.

### As many test input factories as you want

You can write many test input factories for a type and Faultline uses all of them to instantiate values to pass as parameters to your functions.

```zig
// One that always gives the same value.
pub fn fixedGenerator() RandomGenerator {
    return .{ .random = 7 };
}

// One that gives a different value every time.
pub fn changingGenerator() RandomGenerator {
    return .{ .random = my_random_number() };
}

// One that walks a sequence of your own.
pub const MyValueCreator = struct {

    //
    // Whatever state you want.
    //

    pub fn generator(self: *MyValueCreator) RandomGenerator {
        //
        // Returns the next value in whatever
        // sequence you want.
        //
    }
};
```

Each of your functions taking a `RandomGenerator` parameter is called with each of them.

### Fault injection

Your code has branches that only run when something goes wrong: a connection refused, a response that will not parse, a value at the end of its range. An ordinary call never reaches them, so they stay unticked.

Write a test input factory per fault. Faultline uses every one of them, so your code is called against a working value and against each broken one in turn.

```zig
// A loader that works.
pub fn workingLoader() ImageLoader {
    return .{ .source = my_test_bytes() };
}

// One whose file is not there.
pub fn missingFileLoader() ImageLoader {
    return .{ .source = my_missing_file() };
}

// One whose file stops halfway.
pub fn truncatedFileLoader() ImageLoader {
    return .{ .source = my_truncated_bytes() };
}

// One whose file is not an image at all.
pub fn notAnImageLoader() ImageLoader {
    return .{ .source = my_text_bytes() };
}
```

## Step 6: Write scenarios for hard to reach paths

Faultline makes up argument values from their types, so it will not reach a branch that only runs for one particular value, like the text `"PNG"` below. 

The answer: write a scenario, a function that calls yours with that value (Claude can do this for you).

```zig
const sim = @import("sim");
const Log = @import("log").Log;
const Subject = sim.Subject(Log);
const image = @import("image.zig");

//
// Faultline finds a scenario by its three parameters.
// Faultline doesn't care about the function name, just choose a name that's meaningful to you.
//
pub fn runPngHeaderScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {

    //
    // Faultline hands these to every scenario. Most scenarios use neither:
    // the injector is what makes effects fail, and the checklist is what
    // Faultline ticks from your annotations. Discard them and call your code.
    //
    _ = checklist;
    _ = injector;

    //
    // Runs the code under test directly passing in "PNG" as an input.
    //
    if (image.formatOf("PNG", self.log) != .png) {
        //
        // Returning an error here fails the Faultline test run.
        // You can return any error you like.
        //
        return error.WrongFormat;
    }
}
```
Scenarios go in the `<module>.sim.zig` file next to the module being tested.

Return an error of your own to fail the scenario and have it reported by Faultline.

## Sim files

A `<module>.sim.zig` sim file (e.g. `image.sim.zig` for `image.zig`) is where you put your test input factories and scenarios.

```zig
const std = @import("std");
const sim = @import("sim");
const Log = @import("log").Log;
const Subject = sim.Subject(Log);

//
// A test input factory: It returns an instance of your 
// custom type to pass a parameter to your functions.
//
pub fn myValueFactory() SomeValue {
    //
    // Return a value to passed as a parameter to your functions.
    //
}

//
// A test input factory as a struct: May have state and return 
// a sequence of values to pass as parameters to your functions.
//
pub const MyLoaders = struct {

    //
    // Whatever state variables you want.
    //

    pub fn loader(self: *MyLoaders) ImageLoader {
        //
        // Returns the next loader in whatever
        // sequence you want.
        //
    }
};

//
// A scenario: calls your functions with specific values to 
// exercise code paths that Faultline can't find automatically.
//
pub fn myScenario1(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;

    //
    // Call your function with specific inputs.
    //
    // If anything goes wsrong, return an error to
    // make Faultline fail the test run and 
    // report the problem.
    //
}
```

## When Faultline finds a failure

Faultline prints what failed and the command that runs it again:

```
Seed 17 failed in packages/example/src with ParsedWrong.
Reproduce it with: zig build flt -Dreplay="seed=17"
```

To replicate the failure, copy that command and run it:

```sh
zig build flt -Dreplay="seed=17"
```
