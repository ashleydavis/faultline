# A private function covered by lines

`clamp` is private and carries no annotation. The run reaches it only through `clampedDouble`, and kcov records its lines running there, so both of its sides and the statement after its `if` are ticked.

Exits 0.
