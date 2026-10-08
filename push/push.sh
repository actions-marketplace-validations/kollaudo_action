#!/usr/bin/env bash
# Sends test results to Kollaudo with `kollaudo push`, and writes what was sent to the summary of the
# run. Fails the step when Kollaudo doesn't store them; failed tests don't fail it. See action.yml.
set -uo pipefail

# One report, or glob pattern, per line of PUSH_PATH. The CLI expands the patterns.
reports=()
while IFS= read -r line; do
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  [[ -n $line ]] && reports+=("$line")
done <<<"$PUSH_PATH"
if [[ ${#reports[@]} -eq 0 ]]; then
  echo "::error::Give at least one report file in path."
  exit 1
fi

args=(push "${reports[@]}" --component "$PUSH_COMPONENT" --version "$PUSH_VERSION" --kind "$PUSH_KIND")
# Optional fields, sent only when set: an empty environment is a build-level run.
for option in env:ENVIRONMENT tool:TOOL commit:COMMIT branch:BRANCH tag:TAG pull-request:PULL_REQUEST digest:DIGEST; do
  name=PUSH_${option#*:}
  [[ -n ${!name} ]] && args+=("--${option%%:*}" "${!name}")
done

output=$(kollaudo "${args[@]}" 2>&1)
code=$?
printf '%s\n' "$output"

if [[ $code -ne 0 ]]; then
  {
    echo "### ⚠️ Kollaudo didn't store the results"
    echo
    echo '```text'
    printf '%s\n' "$output"
    echo '```'
  } >>"$GITHUB_STEP_SUMMARY"
  echo "::error title=Kollaudo::The results of $PUSH_COMPONENT $PUSH_VERSION weren't sent."
  exit "$code"
fi

link=$(tail -n 1 <<<"$output")
echo "test-run-url=$link" >>"$GITHUB_OUTPUT"
{
  echo "### 📤 Sent to Kollaudo"
  echo
  head -n 1 <<<"$output"
  echo
  echo "[See the test run in Kollaudo]($link)"
} >>"$GITHUB_STEP_SUMMARY"
