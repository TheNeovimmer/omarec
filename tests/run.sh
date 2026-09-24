#!/bin/bash
# Contract tests for bin/omarec. No camera needed and the overlay is never
# started: every case runs against the stopped state. State is isolated in a
# throwaway XDG_STATE_HOME, so the suite never touches the live install — and
# it also exercises the template-seeding path on first write.
#
# Usage: tests/run.sh

set -u

PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$PLUGIN_DIR/bin/omarec"
TEST_STATE="$(mktemp -d)"
export XDG_STATE_HOME="$TEST_STATE"
CONF="$TEST_STATE/omarec/omarec.conf"

PASS=0
FAIL=0

restore() { rm -rf "$TEST_STATE"; }
trap restore EXIT

ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }

expect_ok() { # desc, command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

expect_fail() { # desc, command...
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then bad "$desc (expected failure, got success)"; else ok "$desc"; fi
}

expect_out() { # desc, expected, command...
  local desc="$1" expected="$2"; shift 2
  local got
  got="$("$@" 2>/dev/null)" || { bad "$desc (command failed)"; return; }
  if [[ $got == "$expected" ]]; then ok "$desc"; else bad "$desc (expected '$expected', got '$got')"; fi
}

# --- help / version ---
expect_ok "help exits 0" "$CLI" help
expect_ok "--help exits 0" "$CLI" --help
expect_ok "version exits 0" "$CLI" version

# --- state seeding from the shipped template ---
"$CLI" resize medium >/dev/null 2>&1
if [[ -f $CONF ]]; then ok "first write seeds the state conf"; else bad "first write seeds the state conf"; fi
expect_out "seeded size reads back medium" "medium" "$CLI" get-size
expect_fail "unknown command fails" "$CLI" frobnicate

# --- validation ---
expect_fail "resize rejects junk" "$CLI" resize huge
expect_fail "orientation rejects junk" "$CLI" orientation diagonal
expect_fail "rounding rejects non-numeric" "$CLI" rounding lots
expect_fail "position rejects junk" "$CLI" position center
expect_ok "resize accepts small" "$CLI" resize small
expect_out "get-size reads back small" "small" "$CLI" get-size

# --- start/stop validation (no camera touched) ---
expect_fail "on rejects a missing device" "$CLI" on /dev/does-not-exist
expect_ok "off exits 0 when nothing runs" "$CLI" off

# --- rounding clamp ---
"$CLI" rounding 99 >/dev/null 2>&1
expect_out "rounding clamps to 20" "20" "$CLI" get-rounding
"$CLI" rounding 0 >/dev/null 2>&1
expect_out "rounding 0 sticks" "0" "$CLI" get-rounding

# --- size stepping (overlay stopped, so no restart) ---
"$CLI" resize large >/dev/null 2>&1
"$CLI" smaller >/dev/null 2>&1
expect_out "smaller steps large->medium" "medium" "$CLI" get-size
"$CLI" smaller >/dev/null 2>&1
expect_out "smaller steps medium->small" "small" "$CLI" get-size
"$CLI" smaller >/dev/null 2>&1
expect_out "smaller floors at small" "small" "$CLI" get-size
"$CLI" larger >/dev/null 2>&1
expect_out "larger steps small->medium" "medium" "$CLI" get-size

# --- orientation / position round-trip ---
"$CLI" orientation landscape >/dev/null 2>&1
expect_out "orientation landscape sticks" "landscape" "$CLI" get-orientation
"$CLI" position top-left >/dev/null 2>&1
expect_out "position top-left sticks" "top-left" "$CLI" get-position

# --- status / get-all ---
status="$("$CLI" status 2>/dev/null)"
if [[ $status == running || $status == stopped ]]; then ok "status prints running|stopped"; else bad "status prints running|stopped (got '$status')"; fi
if "$CLI" get-all --json 2>/dev/null | jq -e 'has("device") and has("size") and has("orientation") and has("rounding") and has("position") and has("status")' >/dev/null 2>&1; then
  ok "get-all --json has all keys"
else
  bad "get-all --json has all keys"
fi
if "$CLI" get-all 2>/dev/null | grep -q '^status='; then ok "get-all kv has status"; else bad "get-all kv has status"; fi

# --- config preservation (comments + unrelated lines survive a write) ---
printf '# test comment\n__probe_marker=keepme\n' >>"$CONF"
"$CLI" resize medium >/dev/null 2>&1
if grep -q '^__probe_marker=keepme$' "$CONF" && grep -q '^# test comment$' "$CONF"; then
  ok "write preserves comments and unrelated keys"
else
  bad "write preserves comments and unrelated keys"
fi

# --- concurrent writers serialise (stopped, so no overlay churn) ---
"$CLI" resize medium >/dev/null 2>&1
"$CLI" resize large >/dev/null 2>&1 &
"$CLI" resize small >/dev/null 2>&1 &
wait
if "$CLI" get-size 2>/dev/null | grep -qxE 'small|medium|large'; then
  ok "concurrent resize converges on a valid size"
else
  bad "concurrent resize converges on a valid size"
fi

# --- reset ---
"$CLI" reset >/dev/null 2>&1
expect_out "reset restores size" "medium" "$CLI" get-size
expect_out "reset restores orientation" "portrait" "$CLI" get-orientation
expect_out "reset restores rounding" "12" "$CLI" get-rounding
expect_out "reset restores position" "bottom-right" "$CLI" get-position

# --- check / devices (no camera required for exit 0 when deps exist) ---
expect_ok "devices exits 0" "$CLI" devices
if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v mpv >/dev/null 2>&1 && command -v v4l2-ctl >/dev/null 2>&1; then
  expect_ok "check exits 0 with deps present" "$CLI" check
else
  printf 'skip check exit-0 (optional deps missing)\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
((FAIL == 0))
