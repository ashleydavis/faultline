# The output of a run

Every run below is a real capture, with the command that produced it and the exit code it returned. `zig build flt` is the step `addFaultTest` adds to a project's own build. The lines that differ between runs are taken out: the progress counts, the elapsed time, and the per-function call counts and timings.

The first is from the repository the framework was extracted from. The rest are from the examples, which `bash scripts/smoke.sh` runs and compares against these same captures.

Every run ends with one number: the percentage of code paths that ran. The exit code is zero only when that reads 100%.

`<work directory>` stands for the directory inside your build's cache that the run generated everything in. A run prints its real path. Nothing under it is yours to keep.

Past the first few, the paths nothing reached and the things to do are counted rather than listed, and the count names the file holding every one of them. A first run against a repository with no annotations has thousands of each, and the number and the file are the useful part.

## A run with nothing left to do

Captured from the repository this framework was extracted from, which is the largest run there is a capture of. Every path ran, so the last line reads 100% and the run exits zero.

```sh
$ zig build flt
```

```
Deterministic simulation of 1 package. The report comes at the end.
  Read 25 source files, with 73 functions to drive.
  packages/utils/src: scenarios first, then every function from its own types.
  Reading what those calls reached.
  packages/utils/src: sweeping 32 seeds.

Deterministic simulation

  packages/utils/src/batch_generator.zig
    ok   next                               8/8 paths, 5 unobservable

  packages/utils/src/format.zig
    ok   formatFileSize                     9/9 paths

  packages/utils/src/image.zig
    ok   getImageTransformation             18/18 paths
    ok   getVideoTransformation             15/15 paths, 6 unobservable
    ok   parseFloatLenient                  6/6 paths

  packages/utils/src/log.zig
    ok   info                               1/1 paths
    ok   verbose                            1/1 paths
    ok   err                                1/1 paths
    ok   exception                          1/1 paths
    ok   warn                               1/1 paths
    ok   debug                              1/1 paths
    ok   tool                               5/5 paths
    ok   event                              1/1 paths
    ok   getLogDetails                      1/1 paths
    ok   dropAnnotation                     0/0 paths, never called
    ok   annotate                           2/2 paths
    ok   dispatch                           1/1 paths
    ok   doWrite                            12/12 paths, 2 unobservable
    ok   log                                1/1 paths
    ok   deinit                             7/7 paths
    ok   dispatch                           2/2 paths
    ok   record                             7/7 paths, 5 unobservable
    ok   log                                1/1 paths

  packages/utils/src/log_exceptions.zig
    ok   logExceptions                      6/6 paths

  packages/utils/src/random_generator.zig
    ok   random                             1/1 paths
    ok   randomInt                          1/1 paths
    ok   randomString                       1/1 paths
    ok   digitsFromFraction                 4/4 paths, 2 unobservable
    ok   base36Digit                        3/3 paths
    ok   fill                               4/4 paths
    ok   random                             1/1 paths

  packages/utils/src/random_uuid_generator.zig
    ok   generate                           1/1 paths
    ok   dispatch                           1/1 paths
    ok   asUuidGenerator                    1/1 paths

  packages/utils/src/retry.zig
    ok   rejectAfter                        1/1 paths, 1 unobservable
    ok   retryOnce                          1/1 paths
    ok   retry                              10/10 paths, 2 unobservable

  packages/utils/src/retry_or_log.zig
    ok   retryOrLog                         8/8 paths, 1 unobservable

  packages/utils/src/reverse_geocode.zig
    ok   convertNumber                      4/4 paths
    ok   convertToDegrees                   1/1 paths
    ok   isLocationInRange                  1/1 paths, 6 unobservable
    ok   convertExifCoordinates             5/5 paths
    ok   formatBadCoordinateValue           5/5 paths
    ok   checkCoordinateOk                  10/10 paths, 2 unobservable
    ok   getFirstResultOfType               9/9 paths
    ok   containsType                       6/6 paths
    ok   parseReverseGeocodeResult          23/23 paths, 6 unobservable
    ok   chooseBestResult                   5/5 paths, 3 unobservable
    ok   parseGeocodeApiResponse            4/4 paths
    ok   realGet                            1/1 paths, 2 unobservable
    ok   get                                3/3 paths
    ok   reverseGeocode                     8/8 paths, 6 unobservable

  packages/utils/src/sleep.zig
    ok   sleep                              1/1 paths

  packages/utils/src/swallow_error.zig
    ok   swallowError                       3/3 paths

  packages/utils/src/test_uuid_generator.zig
    ok   generate                           1/1 paths
    ok   reset                              1/1 paths
    ok   dispatch                           1/1 paths
    ok   asUuidGenerator                    1/1 paths
    ok   generateDeterministicUuid          1/1 paths

  packages/utils/src/timestamp_provider.zig
    ok   now                                3/3 paths
    ok   dateNow                            1/1 paths
    ok   setTimestamp                       1/1 paths
    ok   advance                            2/2 paths

  packages/utils/src/trace.zig
    ok   countMatching                      6/6 paths
    ok   expectSeen                         3/3 paths
    ok   expectNever                        3/3 paths
    ok   expectCount                        3/3 paths
    ok   expectOrder                        10/10 paths
    ok   expectBalanced                     4/4 paths
    ok   expectNeverBetween                 10/10 paths, 6 unobservable

  packages/utils/src/try_or_log.zig
    ok   tryOrLog                           4/4 paths

  packages/utils/src/uuid_generator.zig
    ok   generate                           1/1 paths

  packages/utils/src/wrapped_error.zig
    ok   formatErrorChain                   5/5 paths, 4 unobservable

  Found 20 source files, tested 18 with 2 having nothing to test, drove 73 functions and executed 296 of 296 paths.
  Every call ran against a network that refuses every connection, one call in 4 against an allocator that runs out, and one in 4 against a writer with almost no room.
  Stepped over 153 calls, 2 of them after 5s of processor time without returning and the rest for crashing on an input the function was never written for. The paths they would have covered are not in the count above.
    packages/utils/src/fatal_error.zig declares no function, so there is nothing in it to test.
    packages/utils/src/index.zig declares no function, so there is nothing in it to test.
  Swept 32 seeds, with no crash and every recovery invariant holding.
  Full detail is in <work directory>/sim-coverage-report.txt.

  59 branches are not counted above, because nothing can observe them: a `try`,
  `and` or `or` has nowhere to put an annotation.


  Coverage: 296 of 296 paths, 100%.
```

Exit code: 0.

## A run with an annotation missing

A branch that could hold an annotation and does not cannot be seen to run, so the run gives it a name built from its kind, line and side, and that name can never be ticked. The checklist says where the line goes.

An `if` with no `else` is not this case: the run counts the function's own markers to decide whether the branch was skipped, so nothing has to be written for it.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

Deterministic simulation of 1 package. The report comes at the end.
  Read 2 source files, with 1 function to drive.
  .: scenarios first, then every function from its own types.
  Reading what those calls reached.
  .: sweeping 32 seeds.

Deterministic simulation

  sizing.zig
    MISS isLarge                            2/3 paths, 120 calls

  Found 1 source file, tested 1, drove 1 function and executed 2 of 3 paths.
  Every call ran against a network that refuses every connection, one call in 4 against an allocator that runs out, and one in 4 against a writer with almost no room.
  Swept 32 seeds, with no crash and every recovery invariant holding.
  Full detail is in <work directory>/sim-coverage-report.txt.


  FAIL 1 code path that nothing reached:
      sizing.zig:11 "if:11:false" in isLarge: this branch carries no annotation.

  One thing to do:
    Add an annotation to sizing.zig:11, on the false side of the if in isLarge.

  Coverage: 2 of 3 paths, 66%.

  Failed: 1 code path of 3 was never reached.
  The list above says what to do about each one.
  Took 0s.
```

Exit code: 1.

## A run where a path was never executed

The branch is annotated, so it has a name of its own, but nothing the run made up reached it. That is what a scenario is for.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

Deterministic simulation of 1 package. The report comes at the end.
  Read 2 source files, with 1 function to drive.
  .: scenarios first, then every function from its own types.
  Reading what those calls reached.
  .: sweeping 32 seeds.

Deterministic simulation

  gateway.zig
    MISS opens                              2/3 paths

  Found 1 source file, tested 1, drove 1 function and executed 2 of 3 paths.
  Every call ran against a network that refuses every connection, one call in 4 against an allocator that runs out, and one in 4 against a writer with almost no room.
  Swept 32 seeds, with no crash and every recovery invariant holding.
  Full detail is in <work directory>/sim-coverage-report.txt.


  FAIL 1 code path that nothing reached:
      gateway.zig:18 "opens-said-the-phrase" in opens: annotated, but gateway.sim.zig never drove it.

  One thing to do:
    Write a scenario reaching "opens-said-the-phrase" at gateway.zig:18 in opens. Nothing the run made up got there.

  Coverage: 2 of 3 paths, 66%.

  Failed: 1 code path of 3 was never reached.
  The list above says what to do about each one.
  Took 0s.
```

Exit code: 1.

## A run where a function needs a test input factory

A parameter whose type holds a function pointer cannot be built from its type, so the function is never called and none of its paths can run. The line names the function, the type and what to write, and that function's own paths are left off the list: writing the factory is the whole of the work.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

Deterministic simulation of 1 package. The report comes at the end.
  Read 2 source files, with 2 functions to drive.
  .: scenarios first, then every function from its own types.
  Reading what those calls reached.
  .: sweeping 32 seeds.

Deterministic simulation

  store.zig
    MISS valueFor                           0/3 paths, never called

  1 function covered every path, and is not listed above.

  Found 1 source file, tested 1, drove 2 functions and executed 1 of 4 paths.
  Every call ran against a network that refuses every connection, one call in 4 against an allocator that runs out, and one in 4 against a writer with almost no room.
  Swept 32 seeds, with no crash and every recovery invariant holding.
  Full detail is in <work directory>/sim-coverage-report.txt.


  FAIL 3 code paths that nothing reached:
      store.zig:15 "valueFor:entered" in valueFor: annotated, but store.sim.zig never drove it.
      store.zig:17 "valueFor-found" in valueFor: annotated, but store.sim.zig never drove it.
      store.zig:20 "valueFor-missing" in valueFor: annotated, but store.sim.zig never drove it.

  One thing to do:
    Write a test input factory returning store.Store, which valueFor takes. Without one, valueFor at store.zig:15 cannot be called at all.

  Coverage: 1 of 4 paths, 25%.

  Failed: 3 code paths of 4 were never reached.
  The list above says what to do about each one.
  Took 0s.
```

Exit code: 1.

## A run where a function has nowhere to send its annotations

A function that takes no `Log` cannot annotate anything, so every one of its paths is unreachable however hard the run drives it.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

Deterministic simulation of 1 package. The report comes at the end.
  Read 2 source files, with 2 functions to drive.
  .: scenarios first, then every function from its own types.
  Reading what those calls reached.
  .: sweeping 32 seeds.

Deterministic simulation

  hashing.zig
    MISS hashBytes                          0/3 paths, 2 unobservable

  1 function covered every path, and is not listed above.

  Found 1 source file, tested 1, drove 2 functions and executed 1 of 4 paths.
  Every call ran against a network that refuses every connection, one call in 4 against an allocator that runs out, and one in 4 against a writer with almost no room.
  Swept 32 seeds, with no crash and every recovery invariant holding.
  Full detail is in <work directory>/sim-coverage-report.txt.

  2 branches are not counted above, because nothing can observe them: a `try`,
  `and` or `or` has nowhere to put an annotation.


  FAIL 3 code paths that nothing reached:
      hashing.zig:14 "hashBytes:entered" in hashBytes: annotated, but hashing.sim.zig never drove it.
      hashing.zig:16 "if:16:true" in hashBytes: this branch carries no annotation.
      hashing.zig:20 "if:20:true" in hashBytes: this branch carries no annotation.

  Four things to do:
    Give hashBytes at hashing.zig:14 a Log parameter. It has nowhere to send its annotations, so none of its 3 paths can be ticked.
    Add an annotation to hashing.zig:16, on the true side of the if in hashBytes.
    Add an annotation to hashing.zig:20, on the true side of the if in hashBytes.
    Write a scenario reaching "hashBytes:entered" at hashing.zig:14 in hashBytes. Nothing the run made up got there.

  Coverage: 1 of 4 paths, 25%.

  Failed: 3 code paths of 4 were never reached.
  The list above says what to do about each one.
  Took 0s.
```

Exit code: 1.

## A run where a module will not compile

A module that imports something the command was not given cannot be built. The run prints the compiler's own error and the argument that supplies it.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

The simulation would not compile. The compiler said:

uuid.zig:8:25: error: no module named 'shortid' available within module 'root'
const shortid = @import("shortid");
referenced by:
    nextId: uuid.zig:12:12
    simulation: sim_root.zig:27:40

Supply the module shortid, which the code under test imports and this run had no path for. Run again with --module shortid=<path>.
```

Exit code: 1.

## A run that ends below a hundred per cent

The percentage on the last line is the whole verdict: below a hundred the run is red, whatever else it printed.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

Deterministic simulation of 1 package. The report comes at the end.
  Read 2 source files, with 1 function to drive.
  .: scenarios first, then every function from its own types.
  Reading what those calls reached.
  .: sweeping 32 seeds.

Deterministic simulation

  rounding.zig
    MISS upTo                               6/7 paths

  Found 1 source file, tested 1, drove 1 function and executed 6 of 7 paths.
  Every call ran against a network that refuses every connection, one call in 4 against an allocator that runs out, and one in 4 against a writer with almost no room.
  Stepped over 3 calls, 0 of them after 5s of processor time without returning and the rest for crashing on an input the function was never written for. The paths they would have covered are not in the count above.
  Swept 32 seeds, with no crash and every recovery invariant holding.
  Full detail is in <work directory>/sim-coverage-report.txt.


  FAIL 1 code path that nothing reached:
      rounding.zig:23 "upTo-the-one-number-nothing-reaches" in upTo: annotated, but rounding.sim.zig never drove it.

  One thing to do:
    Write a scenario reaching "upTo-the-one-number-nothing-reaches" at rounding.zig:23 in upTo. Nothing the run made up got there.

  Coverage: 6 of 7 paths, 85%.

  Failed: 1 code path of 7 was never reached.
  The list above says what to do about each one.
  Took 0s.
```

Exit code: 1.

## A seed scenario that failed

The run says which seed failed, in which directory, with which error, and prints the one command that reproduces it.

```sh
$ zig build flt
```

```
Fault testing the Zig source in this directory.

Deterministic simulation of 1 package. The report comes at the end.
  Read 3 source files, with 1 function to drive.
  .: scenarios first, then every function from its own types.
  Reading what those calls reached.
  .: sweeping 32 seeds.
Seed 1 failed in . with DrewOutOfBound.
Reproduce it with: zig build flt -Dreplay="seed=1"
error: DrewOutOfBound
```

Exit code: 1.

## Reproducing one run

A replay runs a strict subset of an ordinary run: the seed the plan names, and the injected faults it names.

```sh
$ zig build flt -Dreplay="seed=2"
```

```
Fault testing the Zig source in this directory.
The replay of "seed=2" passed.
```

Exit code: 0.
