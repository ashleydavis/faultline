# The Faultline contract

What flt promises and what it asks of you. Where the tool and this file disagree, this file is right and the behaviour is the defect.

## What flt is for

Every file, every function, every code path.

flt calls every function in a Zig project with every combination of inputs and injected faults until every code path has been exercised, and reports the ones that have not.

## What you add, once

Faultline is a library your project depends on. Two lines put it in, and they are the whole of it.

```sh
zig fetch --save=faultline git+https://github.com/ashleydavis/faultline#v0.1.0
```

```zig
// in your build.zig
@import("faultline").addFaultTest(b, .{ .imports = your_imports });
```

That adds one build step, and running it is the whole first run:

```sh
zig build flt
```

It finds your source by walking your tree, so you never list your files, your functions or your directories. Adding, renaming, moving or removing one changes the run without anything being typed.

What comes back is a list of errors naming the code paths nothing reached. Reducing that list is the work, and it is done by adding annotations and value factories to the project until every path is reachable.

An unreached code path is an error, so the run stays red until every one of them is reached.

## It writes nothing into your repository

This is the most important promise in this file, and it is absolute.

Faultline does not create a file in your repository, does not create a directory there, and does not change a single byte of anything already there.

What `zig build` puts in `.zig-cache` and `zig-out` is your own build's, exactly as it is for every other step in your `build.zig`, and those two are already gitignored by every Zig project. Faultline adds nothing beside them.

Everything a run generates goes in your build's own cache, which your project already ignores.

A run that is killed halfway leaves the repository exactly as it found it.

An earlier version of this tool wrote over three hundred thousand generated files into the what-changed repository during a single run, and the repository had to be thrown away and cloned again. That is the failure this promise exists to make impossible, and any amount of writing into a fault tested repository is that same failure in a smaller size.

## What flt promises

1. It runs on the two lines above. It finds your source, your functions and your directories by walking your tree, so the run stays right as they are added, renamed, moved and removed.

2. Its footprint in your repository is as small as it can be made: annotations and value factories, and nothing else.

3. It never edits your source. You add the annotations and the factories yourself, and flt only says where one is missing.

4. It writes nothing of its own into your repository, as above. Everything a run generates goes in your build's own cache.

5. Your repository depends on one small flt package to get the interfaces it needs, and that package is the only thing it takes from flt.

6. Your repository never supplies a recorder, an annotations table, or any other recording machinery. All of that lives inside flt.

7. The terminal gets a short report: what it drove, the coverage number, and the few things worth doing next. The full list goes to a file named on one line.

8. Every run is described by a plan, and the plan holds everything needed to reproduce that run. Failing or not, a run is replayed by handing its plan back, and nothing else is ever needed to do it: no environment, no log, no leftover state, no second flag.

9. A replayed plan drives the same calls in the same order and gives the same answer, on any machine, for the same source. A plan that does not reproduce its run is a defect in flt.

10. A run is quick enough to sit through. It drives everything there is to drive and reports the complete answer, and it takes a minute or two on a real repository rather than an afternoon. There is no time it has to come in under, and it never drives less to be faster.

11. It can be pointed at one file or one function, and then it fault tests only that.

12. It says what it decided and why: which directories it took as source, which it skipped, which functions it could not call, and what stopped each one.

13. No embedded code. flt does not carry the text of one language inside another, and does not build source by printing it. Where you have asked for it and there is no other way, the code says so beside itself, naming what was asked for. One exemption stands: the generated root and the options module it is compiled with, because Zig resolves every import at compile time from a path in the source and the list of files a run drives is only known once the repository has been walked.

14. Faultline arrives as a dependency your project declares, fetched and cached by Zig like any other, so your project pins the version it wants and gets that one.

15. Faultline takes every module from your build. Your build says what your modules are, and that is the only answer it uses.

16. A run is your build. Faultline adds one step to it, and that step compiles and runs through your build, in the cache your build already has.

## What flt asks of you

An annotation on a branch, so a run can say whether that branch was taken.

A value factory for a type flt cannot build for itself.

Both are asked for one at a time, by an error naming the file and the line, and neither is ever needed before the first run.

Everything else buys precision rather than entry, and a project that writes none of it still gets a report: a scenario for a path nothing random reaches, an invariant, a fault enum on a factory's state.

