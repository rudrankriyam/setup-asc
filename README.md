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
  ASC_NO_UPDATE: "1"
  # Optional default app ID (lets you omit --app on many commands)
  ASC_APP_ID: ${{ secrets.ASC_APP_ID }}
  ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
  ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
  ASC_PRIVATE_KEY_B64: ${{ secrets.ASC_PRIVATE_KEY_B64 }}

steps:
  - uses: actions/checkout@v4
  - uses: rudrankriyam/setup-asc@v1
  - run: asc apps list --paginate
```

## Example Workflows (Copy/Paste)

These examples assume you have:

- `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_B64` stored as GitHub Actions secrets
- `ASC_BYPASS_KEYCHAIN=1` in CI (so `asc` never tries to use macOS Keychain)

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

      # Build your IPA however you like (Xcode Cloud, xcodebuild, Fastlane, etc)
      # Then run:
      - name: Upload + distribute
        run: |
          asc publish testflight \
            --ipa "./path/to/app.ipa" \
            --group "Internal,External" \
            --wait \
            --notify
```

Notes:
- `--group` accepts **group names or IDs**, comma-separated
- Add `--test-notes "..." --locale "en-US"` to set "What to Test" notes

### Send Latest Build to a TestFlight Group (No Upload)

If your build is already uploaded by Xcode Cloud / another pipeline, you can just attach the latest build to a beta group.

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
      GROUP_NAME: "Internal"
    steps:
      - uses: actions/checkout@v4
      - uses: rudrankriyam/setup-asc@v1

      - name: Resolve build + group IDs
        shell: bash
        run: |
          BUILD_ID="$(asc builds latest --app \"$ASC_APP_ID\" --platform IOS | jq -r '.data.id')"
          GROUP_ID="$(asc testflight beta-groups list --app \"$ASC_APP_ID\" --paginate | jq -r --arg NAME \"$GROUP_NAME\" '.data[] | select(.attributes.name == $NAME) | .id' | head -n 1)"

          if [ -z \"$BUILD_ID\" ] || [ \"$BUILD_ID\" = \"null\" ]; then
            echo \"No build found\" >&2
            exit 1
          fi
          if [ -z \"$GROUP_ID\" ] || [ \"$GROUP_ID\" = \"null\" ]; then
            echo \"Group not found: $GROUP_NAME\" >&2
            echo \"Available groups:\" >&2
            asc testflight beta-groups list --app \"$ASC_APP_ID\" --output table >&2
            exit 1
          fi

          echo \"BUILD_ID=$BUILD_ID\" >> \"$GITHUB_ENV\"
          echo \"GROUP_ID=$GROUP_ID\" >> \"$GITHUB_ENV\"

      - name: Add group to build
        run: |
          asc builds add-groups --build \"$BUILD_ID\" --group \"$GROUP_ID\"
```

### Update App Store Metadata (Localizations)

`asc localizations upload` uses `.strings` files and needs an **App Store version ID**.
This workflow resolves the version ID from a version string (e.g. `1.2.3`), validates your localizations, then uploads them.

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
        shell: bash
        run: |
          VERSION_ID="$(asc versions list --app \"$ASC_APP_ID\" --version \"${{ inputs.version }}\" --limit 1 | jq -r '.data[0].id')"
          if [ -z \"$VERSION_ID\" ] || [ \"$VERSION_ID\" = \"null\" ]; then
            echo \"No App Store version found for ${{ inputs.version }}\" >&2
            echo \"Available versions:\" >&2
            asc versions list --app \"$ASC_APP_ID\" --output table >&2
            exit 1
          fi
          echo \"VERSION_ID=$VERSION_ID\" >> \"$GITHUB_ENV\"

      - name: Validate localizations (dry run)
        run: |
          asc localizations upload --version \"$VERSION_ID\" --path \"./localizations\" --dry-run

      - name: Upload localizations
        run: |
          asc localizations upload --version \"$VERSION_ID\" --path \"./localizations\"
```

Tip: you can generate `./localizations` initially via:
`asc localizations download --version "VERSION_ID" --path "./localizations"`

## Security

For release installs, the action downloads `asc_<version>_checksums.txt` from GitHub Releases and verifies the SHA-256 checksum before installing the binary.

