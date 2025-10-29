#!/usr/bin/env bash
#
# test_simapi_endpoints.sh
#
# Default: print responses to stdout. Do NOT write files.
# "store" (or --store) subcommand: also write each response to files under OUTDIR.
#
# Requirements:
#   - ~/.netrc with SIM credentials
#   - curl installed
#   - jq optional (for pretty printing when storing or when --pretty is set)
#
# Usage:
#   ./test_simapi_endpoints.sh -f endpoints.txt
#   ./test_simapi_endpoints.sh -f endpoints.txt store
#   ./test_simapi_endpoints.sh -f endpoints.txt --store -o simapi_results
#   ./test_simapi_endpoints.sh -f endpoints.txt --pretty   # pretty-print to stdout if JSON
#
set -euo pipefail

BASE_URL="https://simapi.sim.lrz.de"
ENDPOINTS_FILE=""
OUTDIR="simapi_results"
STORE=0
PRETTY=0

print_usage() {
  cat <<EOF
Usage: $0 -f <endpoints.txt> [store|--store] [-b <base_url>] [-o <outdir>] [--pretty]

Options:
  -f FILE     File with one endpoint path per line. Lines starting with # are ignored.
  -b URL      Base URL. Default: ${BASE_URL}
  -o DIR      Output directory (used only with 'store'). Default: ${OUTDIR}
  --store     Same as the 'store' subcommand: save responses to files as well.
  --pretty    Pretty-print JSON to stdout (if jq available). No effect on stored files.
  -h|--help   Show this help.

Examples:
  $0 -f endpoints.txt
  $0 -f endpoints.txt store
  $0 -f endpoints.txt --store -o simapi_results
EOF
}

# ---- arg parsing (macOS/Bash 3.x friendly) ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f) ENDPOINTS_FILE="${2:-}"; shift 2 ;;
    -b) BASE_URL="${2:-}"; shift 2 ;;
    -o) OUTDIR="${2:-}"; shift 2 ;;
    store|--store) STORE=1; shift ;;
    --pretty) PRETTY=1; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; print_usage; exit 1 ;;
  esac
done

# ---- validate ----
[[ -z "${ENDPOINTS_FILE}" ]] && { echo "Error: -f endpoints file is required." >&2; print_usage; exit 1; }
[[ ! -f "${ENDPOINTS_FILE}" ]] && { echo "Error: endpoints file not found: ${ENDPOINTS_FILE}" >&2; exit 1; }
[[ ! -f "${HOME}/.netrc" ]] && { echo "Error: ${HOME}/.netrc not found." >&2; exit 1; }

# Create outdir only if we are storing
if [[ "${STORE}" -eq 1 ]]; then
  mkdir -p "${OUTDIR}"
fi

# ---- helpers ----

# Safe, explicit filename from endpoint + short hash to avoid collisions
safe_name() {
  # Keep it explicit: remove leading slash; replace '/' with '__', '?' with '_q_', '&' with '_and_', '=' with '-'
  # Also replace curly braces which may appear in param docs.
  local p="${1#/}"
  p="${p//\//__}"
  p="${p//\?/_q_}"
  p="${p//&/_and_}"
  p="${p//=/-}"
  p="${p//\{/-}"
  p="${p//\}/-}"
  # Short hash of the full path to guarantee uniqueness if two paths sanitize to same name
  local h
  if command -v shasum >/dev/null 2>&1; then
    h="$(printf "%s" "$1" | shasum | awk '{print $1}' | cut -c1-8)"
  else
    # Fallback: md5
    h="$(printf "%s" "$1" | md5 | cut -c1-8 2>/dev/null || printf "nohash")"
  fi
  printf "%s__%s" "$p" "$h"
}

pretty_cat_if_json() {
  # If PRETTY=1 and jq exists and content is JSON, pretty print; else cat raw
  local file="$1"
  if [[ "${PRETTY}" -eq 1 ]] && command -v jq >/dev/null 2>&1; then
    if jq -e . >/dev/null 2>&1 < "${file}"; then
      jq . < "${file}"
      return
    fi
  fi
  cat "${file}"
}

# Core request logic
request_endpoint() {
  local path="$1"

  if [[ "${STORE}" -eq 1 ]]; then
    local fname; fname="$(safe_name "${path}")"
    local outfile="${OUTDIR}/${fname}.json"
    local tmp="${outfile}.tmp"
    local meta="${OUTDIR}/${fname}.meta"

    # Always save to file, overwriting prior result
    # Also print body to stdout
    curl --silent --show-error \
      --netrc-file "${HOME}/.netrc" \
      -H "Accept: application/json" \
      -w "%{http_code} %{time_total} %{size_download}" \
      -o "${tmp}" \
      "${BASE_URL}${path}" > "${meta}" || true

    mv "${tmp}" "${outfile}"

    # Print body to stdout
    pretty_cat_if_json "${outfile}"
    printf "\n"  # ensure newline after body

    # Brief status to stderr so it doesn't mix with stdout
    read -r code t sz < "${meta}"
    >&2 printf "[%s] %s time=%ss bytes=%s -> %s\n" "${code}" "${path}" "${t}" "${sz}" "${outfile}"

    # Optional: log non-2xx
    if [[ ! "${code}" =~ ^2[0-9][0-9]$ ]]; then
      echo "${code} ${path}" >> "${OUTDIR}/errors.log"
    fi

  else
    # Do NOT write files; stream response to stdout
    # Still send minimal status to stderr after the body
    # Use a temp file to capture status without eating the body
    local meta; meta="$(mktemp -t simapi_meta.XXXXXX)"
    curl --silent --show-error \
      --netrc-file "${HOME}/.netrc" \
      -H "Accept: application/json" \
      -w "%{http_code} %{time_total} %{size_download}" \
      "${BASE_URL}${path}" \
      -o >(cat) > "${meta}" || true
    printf "\n"  # newline after body

    read -r code t sz < "${meta}"
    rm -f "${meta}"
    >&2 printf "[%s] %s time=%ss bytes=%s\n" "${code}" "${path}" "${t}" "${sz}"
  fi
}

# ---- run ----
# Read file line-by-line; ignore blanks and lines starting with #
while IFS= read -r line || [[ -n "$line" ]]; do
  # Trim whitespace
  ep="$(printf "%s" "$line" | awk '{$1=$1;print}')"
  [[ -z "${ep}" ]] && continue
  [[ "${ep}" =~ ^# ]] && continue
  request_endpoint "${ep}"
done < "${ENDPOINTS_FILE}"
