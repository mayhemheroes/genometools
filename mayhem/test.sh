#!/usr/bin/env bash
#
# genometools/mayhem/test.sh — RUN genometools' in-process C unit-test runner (`gt -test`) → CTRF.
# Functional oracle for PATCH grading. mayhem/build.sh built a CLEAN, normal-flags `gt` and stashed it
# at /mayhem/gt-test-bin (the /mayhem/bin/gt used for fuzzing is sanitized + has UBSan's `function`
# check relaxed, so it is NOT an honest functional oracle). This only RUNS the stashed binary and maps
# its output to CTRF — it never compiles. We deliberately use `gt -test` (the gt_unit_test framework
# that runs the libgenometools unit tests) rather than the heavy Ruby testsuite/ stest harness.
#
# `gt -test` prints one line per registered unit test — "<name>...ok" or "<name>...error" (see
# src/core/unit_testing.c) — and exits non-zero iff any test errored. We count those lines for the CTRF
# summary and trust gt's own exit code for pass/fail.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

BIN=./gt-test-bin
[ -x "$BIN" ] || { echo "missing $BIN — run mayhem/build.sh first" >&2; exit 2; }

# Run the in-process unit-test runner. Capture output (per-test lines) and gt's own exit code.
out="$("$BIN" -test 2>&1)"; rc=$?
echo "$out"

# Per-test lines end in "...ok" (passed) or "...error" (failed) — count both.
passed=$(printf '%s\n' "$out" | grep -cE '\.\.\.ok[[:space:]]*$')
failed=$(printf '%s\n' "$out" | grep -cE '\.\.\.error[[:space:]]*$')
: "${passed:=0}" "${failed:=0}"

# Trust gt's exit code as the source of truth: if it failed but we parsed no per-test error line
# (e.g. an assertion/abort mid-test), record at least one failure so the oracle is honest.
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi

emit_ctrf "gt-unit-test" "$passed" "$failed"
