# setup-asc

GitHub Action to install [`asc`](https://github.com/rudrankriyam/App-Store-Connect-CLI) (App Store Connect CLI) in CI.

## Usage

Install the latest release:

```yaml
- uses: rudrankriyam/setup-asc@v1
  with:
    version: latest

- run: asc --help
```

Pin a specific version:

```yaml
- uses: rudrankriyam/setup-asc@v1
  with:
    version: 0.28.12
```

Install from `main` (builds from source via `go install`, slower but useful for testing):

```yaml
- uses: rudrankriyam/setup-asc@v1
  with:
    version: main
```

## Inputs

- `version` (default: `latest`): `latest`, `0.28.12`, `v0.28.12`, or `main`
- `cache` (default: `true`): cache the downloaded release asset
- `install-dir` (optional): where to install `asc` (defaults to `$RUNNER_TEMP/asc/bin`)

## Outputs

- `asc-path`: absolute path to the installed binary
- `asc-version`: resolved version that was installed

## Example (with auth env vars)

This action only installs `asc`. For auth, use GitHub Actions secrets + env vars:

```yaml
env:
  ASC_BYPASS_KEYCHAIN: "1"
  ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
  ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
  ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}

steps:
  - uses: actions/checkout@v4
  - uses: rudrankriyam/setup-asc@v1
  - run: asc apps list --paginate
```

## Security

For release installs, the action downloads `asc_<version>_checksums.txt` from GitHub Releases and verifies the SHA-256 checksum before installing the binary.

