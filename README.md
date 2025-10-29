# SIM API Test Script

This repository provides a Bash script for exercising endpoints of the SIM API. The script sends authenticated `curl` requests to each path listed in a plain-text file and optionally stores responses on disk for later inspection.

## Prerequisites

Before running the script, ensure the following requirements are met:

- Bash 3.2+
- `curl`
- Optional: `jq` for pretty-printing JSON output when requested
- A valid `~/.netrc` file containing your SIM API credentials

## Usage

Run the script and point it to a file that contains one endpoint path per line. Lines that begin with `#` are treated as comments and ignored.

```bash
./sim-api-test.sh -f endpoints.txt
```

### Command-line options

| Option | Description |
| --- | --- |
| `-f FILE` | Path to the text file containing endpoint paths. **Required.** |
| `-b URL` | Override the default base URL (`https://simapi.sim.lrz.de`). |
| `-o DIR` | Output directory used when storing responses. Defaults to `simapi_results`. |
| `store`, `--store` | Save each response to a file in addition to printing to stdout. |
| `--pretty` | Pretty-print JSON responses (requires `jq`). |
| `--show-request` | Print the curl command (with sanitized credentials) before each request. |
| `-h`, `--help` | Display usage information. |

### Storing responses

To store responses and metadata for later inspection, use the `store` subcommand (or the `--store` flag). The script will create the output directory if it does not exist.

```bash
./sim-api-test.sh -f endpoints.txt store
```

Each response is written to a `.json` file whose name includes a sanitized form of the endpoint path and a short hash to avoid collisions. A corresponding `.meta` file captures the HTTP status code, total time, and downloaded size.

### Pretty-printing JSON output

Enable pretty-printing with the `--pretty` flag when `jq` is installed. This affects only stdout; stored files always contain the raw response body.

```bash
./sim-api-test.sh -f endpoints.txt --pretty
```

### Showing requests

Add the `--show-request` flag to log the exact `curl` command (with credentials sanitized) before each request. This is useful for debugging or auditing the executed requests.

## Endpoint list format

Create a text file (for example, `endpoints.txt`) that contains one endpoint per line, such as:

```
# SIM API endpoints to query
/api/v1/status
/api/v1/users
/api/v1/devices?limit=10
```

The script trims whitespace, skips blank lines, and ignores comment lines that start with `#`.

## Error handling

The script terminates early if the required endpoint file or `~/.netrc` file is missing. When storing responses, non-2xx status codes are appended to `errors.log` inside the output directory for quick follow-up.
