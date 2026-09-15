# A branch on the line of its own condition

`isLarge` puts the body of its `if` on the same line as the condition. kcov reports that line as run whether or not the branch was taken, so it proves nothing about the true side, and a bare expression has no room for an annotation. The false side is proved by the `return false;` after the `if`. The checklist says to put the body on a line of its own or annotate it.

Returns `error.SimCoveragePathsUnticked`.
