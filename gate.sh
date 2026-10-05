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

args=(verdict --component "$GATE_COMPONENT" --env "$GATE_ENVIRONMENT" --version "$GATE_VERSION")
[[ -n $GATE_REQUIRE ]] && args+=(--require "$GATE_REQUIRE")

output=$(kollaudo "${args[@]}" 2>&1)
code=$?
outcome=$(outcome_of "$code")
printf '%s\n' "$output"
echo "outcome=$outcome" >>"$GITHUB_OUTPUT"

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
  echo "\`$GATE_COMPONENT\` \`$GATE_VERSION\` in \`$GATE_ENVIRONMENT\`"
  echo
  echo '```text'
  printf '%s\n' "$output"
  echo '```'
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
