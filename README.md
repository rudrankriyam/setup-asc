# setup-asc

[![CI](https://github.com/rudrankriyam/setup-asc/actions/workflows/ci.yml/badge.svg)](https://github.com/rudrankriyam/setup-asc/actions/workflows/ci.yml)

GitHub Action to install [`asc`](https://github.com/rudrankriyam/App-Store-Connect-CLI) (App Store Connect CLI) in CI.

## Usage

Install the latest release:

```yaml
- uses: rudrankriyam/setup-asc@v1

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

| Input | Default | Description |
|-------|---------|-------------|
| `version` | `latest` | `latest`, `0.28.12`, `v0.28.12`, or `main` |
| `cache` | `true` | Cache the downloaded release asset |
| `token` | `${{ github.token }}` | GitHub token (avoids API rate limits) |
| `install-dir` | `$RUNNER_TEMP/asc/bin` | Directory to install `asc` into |

## Outputs

| Output | Description |
|--------|-------------|
| `asc-path` | Absolute path to the installed binary |
| `asc-version` | Resolved version that was installed |
| `cache-hit` | Whether the binary was restored from cache |

## Authentication

This action only installs `asc`. For auth, use GitHub Actions secrets + env vars:

```yaml
env:
  ASC_BYPASS_KEYCHAIN: "1"
  ASC_NO_UPDATE: "1"
  ASC_APP_ID: ${{ secrets.ASC_APP_ID }}
  ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
  ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
  ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}

steps:
  - uses: actions/checkout@v4
  - uses: rudrankriyam/setup-asc@v1
  - run: asc apps list --paginate
```

## Example Workflows

These examples assume `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_B64` are stored as GitHub Actions secrets.

### Publish to TestFlight (Upload + Distribute to Group)

Uploads an IPA, waits for processing, and adds it to one or more TestFlight groups.

```yaml
name: Publish to TestFlight

on:
  workflow_dispatch:

jobs:
  testflight:
    runs-on: macos-latest
    env:
      ASC_BYPASS_KEYCHAIN: "1"
      ASC_NO_UPDATE: "1"
      ASC_APP_ID: ${{ secrets.ASC_APP_ID }}
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}
    steps:
      - uses: actions/checkout@v4
      - uses: rudrankriyam/setup-asc@v1

      # Build your IPA however you like (xcodebuild, Xcode Cloud, etc.)
      # Then distribute:
      - name: Upload and distribute
        run: |
          asc publish testflight \
            --ipa "./build/MyApp.ipa" \
            --group "Internal,External" \
            --wait \
            --notify
```

Notes:
- `--group` accepts **group names or IDs**, comma-separated
- Add `--test-notes "..." --locale "en-US"` to set "What to Test" notes

### Send Latest Build to a TestFlight Group (No Upload)

If your build is already uploaded by Xcode Cloud or another pipeline, just attach the latest build to a beta group.

```yaml
name: Add Latest Build to Group

on:
  workflow_dispatch:

jobs:
  distribute:
    runs-on: ubuntu-latest
    env:
      ASC_BYPASS_KEYCHAIN: "1"
      ASC_NO_UPDATE: "1"
      ASC_APP_ID: ${{ secrets.ASC_APP_ID }}
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}
    steps:
      - uses: actions/checkout@v4
      - uses: rudrankriyam/setup-asc@v1

      - name: Resolve build and group IDs
        run: |
          BUILD_ID=$(asc builds latest --platform IOS | jq -r '.data.id')
          GROUP_ID=$(asc testflight beta-groups list --paginate \
            | jq -r '.data[] | select(.attributes.name == "Internal") | .id' \
            | head -n 1)

          if [ -z "$BUILD_ID" ] || [ "$BUILD_ID" = "null" ]; then
            echo "::error::No build found"
            exit 1
          fi
          if [ -z "$GROUP_ID" ] || [ "$GROUP_ID" = "null" ]; then
            echo "::error::Group 'Internal' not found"
            asc testflight beta-groups list --output table >&2
            exit 1
          fi

          echo "BUILD_ID=$BUILD_ID" >> "$GITHUB_ENV"
          echo "GROUP_ID=$GROUP_ID" >> "$GITHUB_ENV"

      - name: Add group to build
        run: asc builds add-groups --build "$BUILD_ID" --group "$GROUP_ID"
```

### Update App Store Metadata (Localizations)

Resolves the version ID from a version string, validates localizations, then uploads.

```yaml
name: Upload Localizations

on:
  workflow_dispatch:
    inputs:
      version:
        description: "App Store version string (e.g., 1.2.3)"
        required: true

jobs:
  localizations:
    runs-on: ubuntu-latest
    env:
      ASC_BYPASS_KEYCHAIN: "1"
      ASC_NO_UPDATE: "1"
      ASC_APP_ID: ${{ secrets.ASC_APP_ID }}
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}
    steps:
      - uses: actions/checkout@v4
      - uses: rudrankriyam/setup-asc@v1

      - name: Resolve version ID
        run: |
          VERSION_ID=$(asc versions list \
            --version "${{ inputs.version }}" \
            --limit 1 \
            | jq -r '.data[0].id')
          if [ -z "$VERSION_ID" ] || [ "$VERSION_ID" = "null" ]; then
            echo "::error::No App Store version found for ${{ inputs.version }}"
            asc versions list --output table >&2
            exit 1
          fi
          echo "VERSION_ID=$VERSION_ID" >> "$GITHUB_ENV"

      - name: Validate localizations (dry run)
        run: asc localizations upload --version "$VERSION_ID" --path "./localizations" --dry-run

      - name: Upload localizations
        run: asc localizations upload --version "$VERSION_ID" --path "./localizations"
```

Tip: generate `./localizations` initially via:
`asc localizations download --version "VERSION_ID" --path "./localizations"`

### Publish to App Store (Upload + Submit)

```yaml
name: Publish to App Store

on:
  workflow_dispatch:
    inputs:
      version:
        description: "App Store version string (e.g., 1.2.3)"
        required: true
      submit:
        description: "Submit for review (true/false)"
        required: true
        default: "false"

jobs:
  appstore:
    runs-on: macos-latest
    env:
      ASC_BYPASS_KEYCHAIN: "1"
      ASC_NO_UPDATE: "1"
      ASC_APP_ID: ${{ secrets.ASC_APP_ID }}
      ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
      ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
      ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}
    steps:
      - uses: actions/checkout@v4
      - uses: rudrankriyam/setup-asc@v1

      # Build your IPA, then:
      - name: Upload and attach build
        if: ${{ inputs.submit != 'true' }}
        run: |
          asc publish appstore \
            --ipa "./build/MyApp.ipa" \
            --version "${{ inputs.version }}" \
            --wait

      - name: Upload and submit for review
        if: ${{ inputs.submit == 'true' }}
        run: |
          asc publish appstore \
            --ipa "./build/MyApp.ipa" \
            --version "${{ inputs.version }}" \
            --submit \
            --confirm \
            --wait
```

## Security

- Release binaries are verified against `asc_<version>_checksums.txt` (SHA-256) before installation
- The `token` input is used only for resolving the latest release tag and is never logged
- No secrets are read or stored by this action; authentication is handled entirely via environment variables
