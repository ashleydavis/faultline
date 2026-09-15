# Fault testing a repository with Faultline (the quick version)

What a repository has to do to start using the tool, in the order it is done.

## 1. Add the dependency

```sh
zig fetch --save=faultline git+https://github.com/ashleydavis/faultline
```

## 2. Add the build step

One line in your `build.zig`. It adds a step named `flt`, attaches the `annotate` module to yours, and walks your tree for what to drive.

```zig
@import("faultline").addFaultTest(b, .{ .imports = your_imports });
```

`.imports` is what your own code imports, so the run compiles against the same modules your project does. Three more are there when you want them: `.source` names the directories to fault test, `.exclude` names directory names to leave out, and `.options_module` names the module your code already reads its build options from.

Use `.exclude` for your benchmarks and your test harnesses. They are code, so the walk takes them for source and asks you to cover their paths too.

Build options: `-Dfile=<path>` and `-Dfunction=<name>` narrow a run to one file or one function, `-Dreport=<path>` moves the full checklist, and `-Dreplay="<plan>"` reproduces one failure a run already reported.

Everything a run generates goes in your build's own cache, so there is no gitignore entry to add.

## 3. Run it

```sh
zig build flt
```

Faultline finds your Zig files, compiles them, calls every function it can and exercises every code path it can reach. It exits 1 on anything under 100% coverage and 0 at 100%.

## 4. Read the report

One line per function, one group per file, then what is left to do, then one number:

```
  sizing.zig
    MISS isLarge                            2/3 paths, 120 calls

  FAIL 1 code path that nothing reached:
      sizing.zig:9 "if:9:false" in isLarge: this branch carries no annotation.

  One thing to do:
    Add an annotation to sizing.zig:9, on the false side of the if in isLarge.

  Coverage: 2 of 3 paths, 66%.
```

A function is done when its line reads `ok` and the two numbers match. `unobservable`, where it appears, is the `and`, `or` and `try` branches, which are not yours to fix.

Work the checklist from the top. Each line carries the file, the line and the one thing to do there.

The report file named on the `Full detail` line lists every branch, ticked or not, with its file and line.

## 5. Annotate every branch

Add a `Log` parameter to every function, import the `annotate` module, and mark each branch with one line:

```zig
const faultline = @import("log");
const Log = faultline.Log;
const an = faultline.an;
const annotate = faultline.annotate;

pub fn isLarge(log: Log, value: u32) bool {
    if (value > 1000) {
        if (an) annotate(log, "isLarge-large", "", .{});
        return true;
    }
    return false;
}
```

`if (an)` compiles the call out of a release build, so annotations cost production code nothing.

Where each annotation goes:

- The first statement of every `if` body. The `else` side needs none, whether or not it has a body: Faultline counts how often it called the function against how often the `if` fired.
- The first statement of every `switch` arm.
- The first statement of every loop body.
- Every nested block, however deep: an `if` inside a loop, a loop inside a `switch` arm.

`and`, `or` and `try` have nowhere to put a line. Leave them: Faultline counts them separately and never asks for them.

Name a branch after what happened: `"cache-miss"`, `"format-file-size-zero"`. The name is what appears in the report.

## 6. Write a test input factory for a type Faultline cannot build

Faultline builds every ordinary value from its type, and everything standard as well: the allocator, `std.Io`, the clock, `std.Random`, a writer, the log. Take those as parameters and write no factory.

It cannot build your own types. A test input factory is a public function returning your type, and the return type is how Faultline finds it:

```zig
pub fn imageLoader() ImageLoader {
    return .{ .source = my_test_bytes() };
}
```

Write as many as you like for one type and Faultline uses all of them. Write one per fault to drive the error handling paths in the code that uses it:

```zig
pub fn missingFileLoader() ImageLoader {
    return .{ .source = my_missing_file() };
}

pub fn truncatedFileLoader() ImageLoader {
    return .{ .source = my_truncated_bytes() };
}
```

To hand back a different value on each call, put the factory on a struct as a method:

```zig
pub const MyLoaders = struct {

    //
    // Whatever state variables you want.
    //

    pub fn loader(self: *MyLoaders) ImageLoader {
        //
        // Returns the next loader in whatever sequence you want.
        //
    }
};
```

## 7. Write scenarios for hard to reach paths

Faultline makes up argument values from their types, so it will not reach a branch that runs only for one particular value, or one that needs several arguments to line up at once.

```zig
const sim = @import("sim");
const Log = @import("log").Log;
const Subject = sim.Subject(Log);
const image = @import("image.zig");

pub fn runPngHeaderScenario(self: *Subject, injector: *sim.Injector, checklist: *sim.Checklist) anyerror!void {
    _ = checklist;
    _ = injector;

    if (image.formatOf("PNG", self.log) != .png) {
        return error.WrongFormat;
    }
}
```

Copy those three parameters exactly and make the function `pub`: Faultline finds a scenario by its parameter types, never by its name. `simulation` is the one name you cannot use.

Pass `self.log` to the code you drive, or its annotations go unseen. Return any error when the answer is wrong, and Faultline stops and prints the command that reproduces it.

## Sim files

Test input factories and scenarios both go in a sim file: `image.zig` gets `image.sim.zig` beside it. You create the file, and Faultline finds it by its name.
