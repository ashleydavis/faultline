# Harness code is not measured

A file that imports the framework is exercising the run rather than being measured by it, so it is given no checklist however many functions it declares. That is read from the file itself: nothing lists which files are harness, so nothing goes stale when one is added or renamed.
