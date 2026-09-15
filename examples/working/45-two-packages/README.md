# Two packages in one project

`src/text` and `src/numbers` are separate packages: neither imports the other, and the walk finds both without being told where to look. The run compiles each on its own, exercises each on its own, and the report covers both.

Every other example here is one package, so this is the one that says what a run does with more than one.
