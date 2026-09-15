# CLAUDE.md

Instructions for an agent working in this repository. This doc is not for humans. Use one line per rule. Never pad this file or add unecessary filler.

## The toolchain

Install it with `mise install`, then type every command in `docs/DEVELOPMENT.md` as it is written.

## Tests

Every function must be comprehensively covered by automated tests.

Put every test in `<name>.test.zig` beside the source, never in a `test` block inside the source file, and name it from that source file's own `test` block with `_ = @import("<name>.test.zig");` or it never runs.

Embed every new file under `src/framework/` in `main.zig`'s `carried_sources`, test files included: a `test` block's imports are resolved even in a build that runs no tests, and that source is compiled inside whatever repository is being measured.

Never skip, disable or weaken a test.

Run the narrowest suite that covers your change first, then `bash scripts/test-everything.sh` before committing.

## The hook

Run `bash scripts/install-hooks.sh` in every fresh clone before committing.

Never bypass or edit the pre-commit hook, or the scripts it calls. When it refuses a commit, fix what failed and commit again.

## Commits

The subject line says what was done. The description says why, what was tried and rejected, and any measurement with the conditions it was taken under. Never restate the diff in prose.

Update the documentation in the same commit as the change it describes.

## Writing

Every message the tool prints reads as a proper sentence: a capital letter at the start and a full stop at the end.

Print one checklist line per thing the user has to do, each a sentence carrying the file and line: add an annotation, write a scenario, write a test input factory, give a function a `Log` parameter, supply a module.

Write one line per paragraph or bullet, with no hard wrapping, no `---` rules and no em dashes.

No jargon, no filler, no made up examples. 

Never commit an absolute path, a secret or a personal detail.

Never use these words: "shape"; "gate", "gated", "gating", "ungated"; credibility framing such as "honestly", "frankly", "clearly", "actually" and "plainly"; and meaningless causes for a mistake such as "habit", "instinct", "reflex" and "muscle memory".

Never write "nothing" or "nobody" in the documentation. Name the thing that is absent: "no annotation", "no call reached it", "no list refers to it".

## Code

Write Zig for the tool and shell for the scripts, and nothing else.

Give every shell script `#!/usr/bin/env bash`, a `.sh` extension, the executable bit staged with `git add --chmod=+x`, `bash -n` run over it, and usage printed when it is run with no arguments.

Comment every global symbol and every struct field.

Write beside every named constant why its value is what it is.

Use 4-space indentation, braces on the same line, and `else` and `catch` on a new line.

Never write an `if` or an `else` without braces. Every body goes on its own lines, whatever it does and however short it is: a bare `continue`, a `return`, a `break`. The one exception is `if (an) annotate(...)`, which is the marker itself and is read as a syntax by the code that builds a checklist.

## The contract

`docs/contract.md` is the human's. Never edit it, and never add to it, unless the human asks for that change in the message you are acting on.

Told to make the code match it, change the code. Editing the contract to describe what the code does inverts the one line at the top of it, which says the file is right and the behaviour is the defect.

Where the code cannot meet it, say so and stop. Do not write an exemption into it, and never record that the human asked for something they did not.

## Naming

**Not settled. These are proposed, and the names below are the ones that break them and have to be decided.**

Name a function that does something as a verb and what it does it to: `printTallies`, `readSources`, `writeRoot`.

Name a function that answers yes or no with `is`, `has` or `was`: `isHarness`, `hasExcludedPrefix`.

Name a function that only works something out after what it returns: `pathCounts`, `sourceDirectories`.

Never say `say` when you mean `print`, `get` when you mean `read`, or `handle` when you mean anything at all.

Never end a name in a preposition unless the call site reads as English: `percentageOf(ticked, total)` reads; `exitStatusFor(err)` does not.

A name that needs `and` in it is two functions. Split it, and the two names come out on their own.

A name is wrong when the comment above it says something the name could have: if the comment starts by correcting the name, rename it.

Names in the tool that break the rules above, to be renamed or the rule dropped: `isWanted` (wanted by what?), `terminalSplit` (a noun for a function that decides), `holdsPackage`, `executableDirectory`, `printWithoutMirrorPrefix`, `whereItGoes`, `countWord`, `moduleOwning`, `wanted`.
