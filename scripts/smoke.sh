#!/usr/bin/env bash
# Runs Faultline against every example and checks what it printed.
#
# Every directory under examples/working/ and examples/non-working/ is a project of its own that the
# tool is run in exactly as it is run in a repository that has never seen it: no build file, no
# wiring, nothing added. That is what makes the examples a check that the tool needs nothing to be
# put in place before it works.
#
# Each example carries an expected.txt holding what the tool printed, with the lines that vary
# between runs taken out: the progress counts, the elapsed time and the per-function call counts and
# timings. A run that prints anything else is a failure, so a change to the output is seen here
# rather than being noticed months later.
#
# Examples run several at a time, because each one compiles a Zig project of its own and a run that
# waits for each build in turn spends most of its time idle. How many run at once comes from
# --parallel <n>, or from PARALLEL when the argument is absent, and is 4 when neither is set. Each
# example's output is collected on its own and printed whole when it finishes, so running several at
# once never interleaves two examples' output.
#
# Usage:
#   bash scripts/smoke.sh                  # every example
#   bash scripts/smoke.sh 01-one-function  # one of them, while it is being worked on
#   bash scripts/smoke.sh --update         # rewrite every expected.txt from what the tool printed
#   bash scripts/smoke.sh --parallel 1         # one after another, for a run that has to be read as it goes
#   bash scripts/smoke.sh --shard 2/6          # this shard's share of the examples, for one CI runner
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_DIR"

# How many examples run at once when nothing says otherwise. Four because an example's cost is
# mostly one Zig compilation, which is itself parallel, so more lanes than this contend for the same
# cores rather than finding new work.
DEFAULT_PARALLEL=4

UPDATE=false
ONLY=""
SHARD=""
PARALLEL="${PARALLEL:-$DEFAULT_PARALLEL}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --update)
            UPDATE=true
            ;;
        --shard)
            shift
            if [ "$#" -eq 0 ]; then
                echo "--shard needs <n>/<total>." >&2
                exit 1
            fi
            SHARD="$1"
            ;;
        --parallel)
            shift
            if [ "$#" -eq 0 ]; then
                echo "--parallel needs a number." >&2
                exit 1
            fi
            PARALLEL="$1"
            ;;
        --*)
            echo "Unknown option \"$1\". Known options: --update, --parallel <n>, --shard <n>/<total>." >&2
            exit 1
            ;;
        *)
            ONLY="$1"
            ;;
    esac
    shift
done

case "$PARALLEL" in
    ''|*[!0-9]*)
        echo "--parallel wants a number, and \"$PARALLEL\" is not one." >&2
        exit 1
        ;;
esac
if [ "$PARALLEL" -lt 1 ]; then
    echo "--parallel wants at least one." >&2
    exit 1
fi

# Each example's build cache has to sit in the example's own directory, because what the tool prints
# names it and that is what expected.txt was recorded against. ZIG_LOCAL_CACHE_DIR moves it
# somewhere shared, so a run with it set compares one set of paths against another and fails every
# example. GitHub's setup-zig action sets it on every job, whatever its caching is set to.
unset ZIG_LOCAL_CACHE_DIR

# Every example is a project of its own that declares Faultline and calls `addFaultTest`, so what
# runs one is `zig build flt` inside it, exactly as it is for any project using Faultline.
ZIG="$(command -v zig)"
if [ -z "$ZIG" ]; then
    echo "There is no zig on the PATH, and every example is run with it." >&2
    exit 1
fi

# The tool reads line coverage from kcov, and the captures the examples are compared against were
# made with it on the PATH. Without it the run still works, but it prints a line saying so and
# reaches fewer paths, and every example would fail its comparison for that reason alone.
if ! command -v kcov >/dev/null 2>&1; then
    echo "There is no kcov on the PATH, and every example is run under it." >&2
    exit 1
fi

EXAMPLES=()
for KIND in working non-working; do
    if [ ! -d "examples/$KIND" ]; then
        continue
    fi
    for DIRECTORY in examples/$KIND/*/; do
        [ -d "$DIRECTORY" ] || continue
        NAME="$(basename "$DIRECTORY")"
        if [ -n "$ONLY" ] && [ "$NAME" != "$ONLY" ]; then
            continue
        fi
        EXAMPLES+=("$KIND/$NAME")
    done
done

# One runner's share of the examples. Each one is a Zig compilation of its own and a hosted runner
# has four cores, so the suite is split across runners rather than made to fit on one. Taking every
# total-th example rather than a block of them spreads the slow ones over the shards.
if [ -n "$SHARD" ]; then
    SHARD_INDEX="${SHARD%%/*}"
    SHARD_TOTAL="${SHARD##*/}"
    case "$SHARD_INDEX/$SHARD_TOTAL" in
        ''|*[!0-9/]*|*/|/*)
            echo "--shard wants <n>/<total>, and \"$SHARD\" is not that." >&2
            exit 1
            ;;
    esac
    if [ "$SHARD_INDEX" -lt 1 ] || [ "$SHARD_INDEX" -gt "$SHARD_TOTAL" ]; then
        echo "--shard $SHARD asks for a shard outside 1 to $SHARD_TOTAL." >&2
        exit 1
    fi

    SHARDED=()
    INDEX=0
    for EXAMPLE in "${EXAMPLES[@]}"; do
        if [ "$((INDEX % SHARD_TOTAL))" -eq "$((SHARD_INDEX - 1))" ]; then
            SHARDED+=("$EXAMPLE")
        fi
        INDEX=$((INDEX + 1))
    done
    EXAMPLES=("${SHARDED[@]+"${SHARDED[@]}"}")
fi

if [ "${#EXAMPLES[@]}" -eq 0 ]; then
    if [ -n "$ONLY" ]; then
        echo "There is no example named \"$ONLY\"." >&2
    else
        echo "There are no examples under examples/." >&2
    fi
    exit 1
fi

# Everything this script writes goes here, and nothing is ever removed: it is a tmp directory, so
# what is in it is already throwaway, and the last run's logs are worth having until the next one
# overwrites them.
RESULT_DIR="$REPO_DIR/tmp/smoke"
mkdir -p "$RESULT_DIR"

# Takes out the lines and the parts of lines that are different every run, so what is compared is
# what the tool decided rather than how long it took to decide it.
normalise() {
    sed -E \
        -e "s|$REPO_DIR/||g" \
        -e '/^ +[0-9]+ calls exercised$/d' \
        -e '/^ +Took [0-9]+(m [0-9]+)?s\.$/d' \
        -e 's/, [0-9]+ calls//' \
        -e 's/ with [0-9]+ calls?//' \
        -e 's/, [0-9]+\.[0-9]+s//' \
        -e 's/, [0-9]+ms//' \
        -e '/src\/framework\//d' \
        -e '/\.flt\/lib\//d' \
        -e '/^ +[0-9]+ reference\(s\) hidden/d' \
        -e 's/thread [0-9]+ panic/thread panic/' \
        -e 's/0x[0-9a-f]+ in /in /' \
        -e 's/(kcov: Process exited with signal [0-9]+ \([A-Z]+\)) at 0x[0-9a-f]+/\1 at <address>/' \
        -e '/^ *\^~*$/d' \
        -e 's|/[A-Za-z0-9_./+-]*/lib/std/|<zig>/lib/std/|g' \
        -e 's|/[A-Za-z0-9_./+-]*/flt[A-Za-z0-9-]+/|<work>/|g' \
        -e 's|[A-Za-z0-9_./+-]*\.zig-cache/([A-Za-z0-9_.-]+\.txt)|<cache>/\1|g' \
        -e 's|\.\./o/[0-9a-f]+/flt-sim|<cache>/flt-sim|g' \
        -e 's|\.\./o/[0-9a-f]+|<cache>|g' \
        -e 's|\.zig-cache/o/[0-9a-f]+/|<cache>/|g' \
        -e '/^Build Summary:/,$d' \
        -e '/^error: the following build command failed/,$d'
}

# Where an example's full output is kept, so a line saying it failed can say where to read why.
LOG_DIR="$RESULT_DIR"

# Runs one example, writes its whole output to its own log, and records pass or fail beside it.
run_one() {
    local example="$1"
    local kind="${example%%/*}"
    local name="${example##*/}"
    local directory="$REPO_DIR/examples/$example"
    local slug="${kind}-${name}"
    local output="$RESULT_DIR/$slug.output"
    local log="$LOG_DIR/$slug.log"

    # Recorded before the run rather than after it, so an example whose run is interrupted reads as
    # failed rather than keeping whatever the last run said about it.
    echo "fail" > "$RESULT_DIR/$slug.verdict"

    # Type, size and modification time of every entry in the example, taken before the run and again
    # after it. An example is a repository being fault tested, so the contract's flat promise applies to
    # it: the tool writes nothing into it. Checking it here means every example is a check of that
    # promise as well as of what the run printed, against a different arrangement of source each
    # time.
    manifest_of() {
        (cd "$directory" && find . -mindepth 1 -not -path './.zig-cache*' -not -path './zig-out*' -printf '%y %s %T@ %p\n' | LC_ALL=C sort)
    }
    manifest_of > "$RESULT_DIR/$slug.before"

    # An example that has to be run with a build option carries it in run-flags.txt beside it,
    # because the option is part of what the example demonstrates.
    local arguments=()
    if [ -f "$directory/run-flags.txt" ]; then
        while IFS= read -r LINE; do
            if [ -n "$LINE" ]; then
                arguments+=("$LINE")
            fi
        done < "$directory/run-flags.txt"
    fi

    local code
    ( cd "$directory" && NO_COLOR=1 "$ZIG" build flt "${arguments[@]+"${arguments[@]}"}" ) > "$output.raw" 2>&1
    code="$?"
    normalise < "$output.raw" > "$output"

    {
        echo "$kind/$name"
        echo ""
        cat "$output"
        echo ""
        echo "Exit code: $code"
    } > "$log"

    # Says why this example failed, in the log rather than on the terminal, and records the verdict.
    refuse() {
        {
            echo ""
            echo "FAILED: $1"
        } >> "$log"
        echo "fail" > "$RESULT_DIR/$slug.verdict"
    }

    # Checked before what it printed, because a run that left something behind has broken the
    # promise the contract calls absolute whatever else it got right.
    manifest_of > "$RESULT_DIR/$slug.after"
    if ! diff -u "$RESULT_DIR/$slug.before" "$RESULT_DIR/$slug.after" > "$RESULT_DIR/$slug.footprint"; then
        {
            echo ""
            echo "What the run changed in the example's own directory:"
            cat "$RESULT_DIR/$slug.footprint"
        } >> "$log"
        refuse "it wrote into the repository it was fault testing, and the contract says it writes nothing."
        return
    fi

    if [ "$kind" = "working" ] && [ "$code" -ne 0 ]; then
        refuse "it exited $code, and a working example has to exit 0."
        return
    fi
    if [ "$kind" = "non-working" ] && [ "$code" -eq 0 ]; then
        refuse "it exited 0, and a non-working example has to exit non-zero."
        return
    fi

    if [ "$UPDATE" = true ]; then
        cp "$output" "$directory/expected.txt"
        echo "pass" > "$RESULT_DIR/$slug.verdict"
        return
    fi

    if [ ! -s "$directory/expected.txt" ]; then
        refuse "it has no expected.txt, or it is empty, so there is nothing to compare against."
        return
    fi

    if ! diff -u "$directory/expected.txt" "$output" > "$RESULT_DIR/$slug.diff"; then
        {
            echo ""
            echo "What it printed, against its expected.txt:"
            cat "$RESULT_DIR/$slug.diff"
        } >> "$log"
        refuse "it printed something other than its expected.txt."
        return
    fi

    echo "pass" > "$RESULT_DIR/$slug.verdict"
}

# What the run took, so a suite that has got slower says so rather than being noticed months later.
STARTED_AT="$(date +%s)"

echo "Running ${#EXAMPLES[@]} example(s), $PARALLEL at a time."
echo ""

RUNNING=0
for EXAMPLE in "${EXAMPLES[@]}"; do
    run_one "$EXAMPLE" &
    RUNNING=$((RUNNING + 1))
    if [ "$RUNNING" -ge "$PARALLEL" ]; then
        wait -n
        RUNNING=$((RUNNING - 1))
    fi
done
wait

# One line per example, in name order whatever order they finished in, so two runs of the same tree
# read the same way.
PASSED=0
FAILED=()
for EXAMPLE in "${EXAMPLES[@]}"; do
    KIND="${EXAMPLE%%/*}"
    NAME="${EXAMPLE##*/}"
    SLUG="${KIND}-${NAME}"
    if [ "$(cat "$RESULT_DIR/$SLUG.verdict" 2>/dev/null)" = "pass" ]; then
        printf '  pass  %s\n' "$NAME"
        PASSED=$((PASSED + 1))
    else
        printf '  FAIL  %s\n' "$NAME"
        FAILED+=("$EXAMPLE")
    fi
done

# Seconds as m:ss once there are enough of them to be worth reading that way.
elapsed() {
    local total="$1"
    if [ "$total" -ge 60 ]; then
        printf '%dm %02ds' "$((total / 60))" "$((total % 60))"
    else
        printf '%ds' "$total"
    fi
}

TOOK="$(elapsed $(( $(date +%s) - STARTED_AT )))"

echo ""
echo "Ran ${#EXAMPLES[@]} example(s), $PASSED passed, in $TOOK."

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "" >&2
    echo "These did not pass. The whole of what each one printed is in its log:" >&2
    for EXAMPLE in "${FAILED[@]}"; do
        KIND="${EXAMPLE%%/*}"
        NAME="${EXAMPLE##*/}"
        printf '  %-28s tmp/smoke/%s-%s.log\n' "$NAME" "$KIND" "$NAME" >&2
    done
    exit 1
fi

# A complete run marks the target up to date. A run of one example, and a run that rewrote the
# expected files, covered part of the target or changed what it compares against, so neither does.
if [ -z "$ONLY" ] && [ -z "$SHARD" ] && [ "$UPDATE" = false ]; then
    if command -v what-changed >/dev/null 2>&1; then
        # Its output is collected and echoed rather than left to go straight out, because it seeks
        # to the start of whatever it was handed and writes there. Sent to a terminal that is
        # harmless; sent to a file, it overwrites the first lines of this run's own report. A
        # command substitution hands it a pipe, which has no start to seek to.
        CAPTURED="$(what-changed baseline capture smoke 2>&1)"
        echo "$CAPTURED"
    else
        echo "what-changed is not installed, so the smoke baseline was not captured."
    fi
fi
