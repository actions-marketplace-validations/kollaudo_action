#!/usr/bin/env bash
# Asks Kollaudo for the verdict of a version in an environment, writes it to the summary of the run,
# and fails the step unless it is pass, or an outcome that GATE_ALLOW lets through. See action.yml.
set -uo pipefail

# What `kollaudo verdict` exits with, by outcome. Anything else means no verdict too.
outcome_of() {
  case $1 in
    0) echo pass ;;
    1) echo fail ;;
    2) echo unknown ;;
    *) echo no-verdict ;;
  esac
}

allowed=()
IFS=',' read -ra wanted <<<"${GATE_ALLOW// /}"
for value in ${wanted[@]+"${wanted[@]}"}; do
  case $value in
    unknown | no-verdict) allowed+=("$value") ;;
    *)
      # A typo must not let anything through: fail closed.
      echo "::error::allow can only contain unknown and no-verdict, not \"$value\"."
      exit 1
      ;;
  esac
done

args=(verdict --component "$GATE_COMPONENT" --env "$GATE_ENVIRONMENT" --version "$GATE_VERSION" --json)
[[ -n $GATE_REQUIRE ]] && args+=(--require "$GATE_REQUIRE")

# The answer is on stdout and the errors on stderr, so that an error is never read as an answer.
errors=$(mktemp)
answer=$(kollaudo "${args[@]}" 2>"$errors")
code=$?
outcome=$(outcome_of "$code")
message=""
if [[ $outcome != no-verdict ]]; then
  # The exit code and the answer must agree. If they don't, or the answer isn't JSON, there is no verdict.
  if jq -e --arg outcome "$outcome" '.outcome == $outcome and (.message | type == "string")' <<<"$answer" >/dev/null 2>&1; then
    message=$(jq -r '.message' <<<"$answer")
  else
    outcome=no-verdict
    message="Kollaudo's answer couldn't be read."
  fi
fi
if [[ $outcome == no-verdict ]]; then
  details=$(cat "$errors")
  [[ -z $details ]] && details=$answer
  [[ -z $message ]] && message=$details
fi
rm -f "$errors"
echo "outcome=$outcome" >>"$GITHUB_OUTPUT"
# A random delimiter, so that a message can't end the output early and set another one.
delimiter="kollaudo_$(date +%s%N)_$RANDOM$RANDOM"
{
  echo "message<<$delimiter"
  printf '%s\n' "$message"
  echo "$delimiter"
} >>"$GITHUB_OUTPUT"

# The reasons as a table, with a link to each test run, and the notes the CLI prints under its report.
table=""
notes=""
if [[ $outcome != no-verdict ]]; then
  table=$(jq -r --arg url "${KOLLAUDO_URL%/}" '
    def cell: tostring | gsub("\\|"; "\\|") | gsub("\r?\n"; " ");
    if (.reasons | length) == 0 then empty else
      "| | Kind | Result | Sent by | Test run |",
      "|---|---|---|---|---|",
      (.reasons[] |
        "| \(.outcome | cell) | \(.kind | cell) | \(.message | cell) | \((.run.sentBy // "-") | cell) | " +
        (if .run then "[\(.run.id[0:8])](\($url)/test-runs/\(.run.id))" else "-" end) + " |")
    end' <<<"$answer")
  notes=$(jq -r '
    (if .override then "Let through by an override. The evidence alone is \(.evidenceOutcome)." else empty end),
    (if .deployed and .deployed.version != .version
      then "\(.environment) runs \(.component) \(.deployed.version) since \(.deployed.deployedAt), not \(.version)." else empty end),
    (if .deployed.gate and (.deployed.gate.gated | not)
      then "\(.component) \(.deployed.version) was deployed to \(.environment) at \(.deployed.deployedAt) without a pass in \(.deployed.gate.from) before it." else empty end)' <<<"$answer")
fi
if [[ $outcome == no-verdict ]]; then
  printf '%s\n' "$message"
else
  echo "$outcome: $GATE_COMPONENT $GATE_VERSION in $GATE_ENVIRONMENT: $message"
  [[ -n $table ]] && printf '%s\n' "$table"
  [[ -n $notes ]] && printf '\n%s\n' "$notes"
fi

let_through=false
for value in ${allowed[@]+"${allowed[@]}"}; do [[ $value == "$outcome" ]] && let_through=true; done

case $outcome in
  pass) title="✅ Kollaudo: pass" ;;
  fail) title="❌ Kollaudo: fail" ;;
  unknown) title="⚠️ Kollaudo: unknown" ;;
  *) title="⚠️ Kollaudo didn't answer" ;;
esac
{
  echo "### $title"
  echo
  echo "\`$GATE_COMPONENT\` \`$GATE_VERSION\` in \`$GATE_ENVIRONMENT\`: $message"
  if [[ -n $table ]]; then
    echo
    printf '%s\n' "$table"
  fi
  if [[ -n $notes ]]; then
    echo
    printf '%s\n' "$notes"
  fi
  if $let_through; then
    echo
    echo "Let through by \`allow: $GATE_ALLOW\`."
  fi
} >>"$GITHUB_STEP_SUMMARY"

if [[ $outcome == pass ]]; then exit 0; fi
if $let_through; then
  echo "::warning title=Kollaudo::$outcome for $GATE_COMPONENT $GATE_VERSION in $GATE_ENVIRONMENT, let through by allow."
  exit 0
fi
echo "::error title=Kollaudo::$outcome for $GATE_COMPONENT $GATE_VERSION in $GATE_ENVIRONMENT."
exit 1
