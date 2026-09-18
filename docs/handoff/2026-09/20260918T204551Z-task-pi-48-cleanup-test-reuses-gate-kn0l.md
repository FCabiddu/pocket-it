## Fatti
- src_anchors' substr mode counts matching LINES, which is right for a range address and wrong for a plain s///: two occurrences on ONE line count as one and the mutation lands on the first only. Declare a single-anchor substitution with the occur mode.
