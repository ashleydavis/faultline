# The checklist written where you asked

`-Dreport=<path>` moves the full checklist, the file listing every branch ticked or not. Without it the run writes it into the build's own cache, which is where it belongs when nobody is going to read it twice.

A relative path is taken as the project's own. The run stands in a sandbox directory of its own, so a relative path left alone would land somewhere nobody is looking.
