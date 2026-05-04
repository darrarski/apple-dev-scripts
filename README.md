# Apple Dev Scripts

Reusable [Mise Tasks](https://mise.jdx.dev/tasks) for common iOS and macOS development workflows.

## 📖 Documentation

This repository contains common scripts I use for the development of native iOS and macOS applications. It's an example of development tools configuration, not a fully featured solution. The scripts have minimal dependencies on some basic bash utilities. They do not depend on Ruby, Fastlane, Match, and other heavy tools. I use the scripts to build apps, run tests, archive, and deploy to App Store Connect and TestFlight. It works locally on a development machine, as well as on CI runners (both self-hosted and ephemeral).

### Prerequisites

- Xcode is installed, and developer tools are active.
- [Mise](https://mise.jdx.dev) is installed and available in `$PATH`.
- [Tuist](https://github.com/tuist/tuist) is used to generate Xcode workspace and projects.
- App targets are configured to use automatic code signing.

### Dependencies

Script dependencies are managed with Mise and defined in [`mise.toml`](mise.toml) file.

### Usage

Copy Mise Tasks to your project repository and configure environment variables with Mise.

## ⚙️ Environment

Repository-wide default environment variables are defined in [`mise.toml`](mise.toml):

|Variable|Description|
|:--|:--|
|`XCODE_APP_SCHEME`|Default app scheme used by deployment-oriented tasks such as `archive_app` when `--scheme` is not provided.|
|`IOS_SIMULATOR_NAME`|Default iOS simulator device name used by the `test` task.|
|`TESTFLIGHT_GROUPS`|Comma-separated default TestFlight groups used by `submit_to_testflight` and `deploy`.|

Build artifacts produced by repository tasks are stored under the repo-local `build/` directory, which is ignored by git.

Scripts that require access to App Store Connect use the following environment variables:

|Variable|Description|
|:--|:--|
|`APP_STORE_CONNECT_API_KEY_ID`|App Store Connect private key identifier.|
|`APP_STORE_CONNECT_API_ISSUER_ID`|App Store Connect private key issuer.|
|`APP_STORE_CONNECT_API_PRIVATE_KEY_PATH`|Path to App Store Connect private key file.|

Scripts assume Xcode is configured with automatic code signing. Certificates and provisioning profiles are retrieved from the App Store Connect automatically whenever needed.

## 🏗️ Mise Tasks

This repository defines development tasks as executable scripts in [`mise-tasks/*`](mise-tasks). Do not run the scripts directly. You can invoke a task from the command line using `mise run`:

```sh-session
$ mise run <task>
```

To list all available tasks, run:

```sh-session
$ mise tasks
```

### ▶️ Generate Workspace

Uses Tuist to:

1. Install any remote content (e.g. dependencies) necessary to interact with the project.
2. Inspect implicit and redundant dependencies in projects, failing when issues are found.
3. Generate the Xcode workspace and projects.

|Flag|Description|
|:--|:--|
|`--no-inspect`|Skip inspecting implicit and redundant dependencies in Tuist projects.|
|`--no-install`|Skip installing any remote content (e.g. dependencies).|
|`--open`|Open generated workspace.|

Source: [`mise-tasks/generate_workspace.sh`](mise-tasks/generate_workspace.sh)

### ▶️ Generate Workspace Graph

Uses Tuist to generate the workspace target dependency graph.

```sh-session
$ mise run generate_workspace_graph
```

Source: [`mise-tasks/generate_workspace_graph.sh`](mise-tasks/generate_workspace_graph.sh)

### ▶️ List Build Schemes

Lists all shared Xcode build schemes available in the workspace and project files.

```sh-session
$ mise run list_build_schemes
```

Source: [`mise-tasks/list_build_schemes.sh`](mise-tasks/list_build_schemes.sh)

### ▶️ Build

Builds the project using `tuist xcodebuild` and provided scheme and platform.

```sh-session
$ mise run build [--scheme <scheme>] --platform <platform>
```

|Argument|Description|
|:--|:--|
|`--scheme <scheme>`|Xcode scheme name. Defaults to `"{WorkspaceName}-Workspace"` derived from the generated workspace file name.|
|`--platform <platform>`|Platform. "macOS" or "iOS".|

The task expects the workspace is already generated. Derived data is written under the repo-local `build/DerivedData` directory.

Source: [`mise-tasks/build.sh`](mise-tasks/build.sh)

### ▶️ Test

Runs tests using `tuist xcodebuild` and provided scheme and platform.

```sh-session
$ mise run test [--scheme <scheme>] --platform <platform>
```

|Argument|Description|
|:--|:--|
|`--scheme <scheme>`|Xcode scheme name. Defaults to `"{WorkspaceName}-Workspace"` derived from the generated workspace file name.|
|`--platform <platform>`|Platform. "macOS" or "iOS". iOS tests use the `IOS_SIMULATOR_NAME` environment variable to choose the simulator device.|

The task expects the workspace is already generated. Derived data is written under the repo-local `build/DerivedData` directory.

Source: [`mise-tasks/test.sh`](mise-tasks/test.sh)

### ▶️ Set build number

Sets app build number by modifying generated Xcode workspace. The changes are not persisted (project manifest is not updated). Can be used to prepare the app for deployment.

```sh-session
$ mise run set_build_number [<build_number>]
```

|Argument|Description|
|:--|:--|
|`<build_number>`|Build number. Defaults to current build number + 1.|

Source: [`mise-tasks/set_build_number.sh`](mise-tasks/set_build_number.sh)

### ▶️ Get latest App Store Connect build number

Gets the latest uploaded build number or pending build upload number for the selected platform and current marketing version from App Store Connect.

```sh-session
$ mise run get_latest_app_store_build_number --platform <platform>
```

|Argument|Description|
|:--|:--|
|`--platform <platform>`|Platform. "macOS" or "iOS".|

The task expects the workspace is already generated and App Store Connect API credentials are available in the environment.

Source: [`mise-tasks/get_latest_app_store_build_number.sh`](mise-tasks/get_latest_app_store_build_number.sh)

### ▶️ Set next build number

Resolves the latest uploaded App Store Connect build numbers for iOS and macOS, takes the greater value, increments it by 1, and sets the generated Xcode project's build number to the result.

```sh-session
$ mise run set_next_build_number
```

The task expects the workspace is already generated and App Store Connect API credentials are available in the environment.

Source: [`mise-tasks/set_next_build_number.sh`](mise-tasks/set_next_build_number.sh)

### ▶️ Archive app

Archives the app for the selected platform using the `XCODE_APP_SCHEME` environment variable by default.

```sh-session
$ mise run archive_app [--scheme <scheme>] --platform <platform>
```

|Argument|Description|
|:--|:--|
|`--scheme <scheme>`|Xcode scheme name. Defaults to the `XCODE_APP_SCHEME` environment variable.|
|`--platform <platform>`|Platform. "macOS" or "iOS".|

The task expects the workspace is already generated and App Store Connect API credentials are set in the environment. Archives are written under the repo-local `build/archives` directory.

Source: [`mise-tasks/archive_app.sh`](mise-tasks/archive_app.sh)

### ▶️ Upload archive

Uploads the archived app for the selected platform to App Store Connect.

```sh-session
$ mise run upload_archive [--scheme <scheme>] --platform <platform>
```

|Argument|Description|
|:--|:--|
|`--scheme <scheme>`|Xcode scheme name. Defaults to the `XCODE_APP_SCHEME` environment variable. Use the same scheme value that was passed to `archive_app`.|
|`--platform <platform>`|Platform. "macOS" or "iOS".|

The task expects the matching archive has already been created and App Store Connect API credentials are available in the environment. Exported packages are written under the repo-local `build/exports` directory.

Source: [`mise-tasks/upload_archive.sh`](mise-tasks/upload_archive.sh)

### ▶️ Add release tag

Adds git release tag with current marketing version and build number (i.e., v1.2.3-456)

```sh-session
$ mise run add_release_tag
```

The task fails if the release tag already exists.

Source: [`mise-tasks/add_release_tag.sh`](mise-tasks/add_release_tag.sh)

### ▶️ Generate WhatToTest file

Generates WhatToTest file with changes from commit history since previous release tag.

```sh-session
$ mise run generate_whattotest
```

Source: [`mise-tasks/generate_whattotest.sh`](mise-tasks/generate_whattotest.sh)

### ▶️ Submit to TestFlight

Submits a previously uploaded build to the TestFlight groups defined by the `TESTFLIGHT_GROUPS` environment variable. If one or more selected groups are external, the task also submits the build for TestFlight App Review. When `TestFlight/WhatToTest.en-US.txt` exists, the task uses it to populate the build's "What To Test" information for the `en-US` localization.

```sh-session
$ mise run submit_to_testflight --platform <platform>
```

|Argument|Description|
|:--|:--|
|`--platform <platform>`|Platform. "macOS" or "iOS".|
|`--version <version>`|Marketing version. Defaults to current marketing version set in workspace.|
|`--build <build>`|Build number. Defaults to current build number set in workspace.|

The task expects the workspace is already generated, the build is already uploaded to App Store Connect, `TESTFLIGHT_GROUPS` defines at least one group, and App Store Connect API credentials are available in the environment.

Source: [`mise-tasks/submit_to_testflight.sh`](mise-tasks/submit_to_testflight.sh)

### ▶️ Deploy

Runs the local deploy pipeline for manual release. It generates the workspace, resolves and sets the next build number, archives iOS and macOS app, uploads the archives, creates a local release tag, generates `WhatToTest` notes, and submits both iOS and macOS builds to the TestFlight groups defined by `TESTFLIGHT_GROUPS`.

```sh-session
$ mise run deploy
```

The task expects App Store Connect API credentials in the environment.

Source: [`mise-tasks/deploy.sh`](mise-tasks/deploy.sh)

### ▶️ Validate Documentation

Runs lightweight documentation checks:

1. Verifies that internal Markdown links in `README.md` and `docs/*.md` resolve to existing files.
2. Verifies that `mise run <task>` commands referenced in docs map to tasks returned by `mise tasks -l`.

```sh-session
$ mise run validate_docs
```

Source: [`mise-tasks/validate_docs.sh`](mise-tasks/validate_docs.sh)

### ▶️ Lint Shell Scripts

Runs `shellcheck` against all shell scripts in the repository.

```sh-session
$ mise run lint_shell_scripts
```

Source: [`mise-tasks/lint_shell_scripts.sh`](mise-tasks/lint_shell_scripts.sh)

## 🔁 Continuous Integration

Mise tasks can be used on a CI server. You can find example GitHub Action workflow definitions below.

### 🧪 CI workflow: Test

Run all tests defined in Xcode workspace on macOS and iOS.

<details>
<summary><code>.github/workflows/test.yml</code></summary>

```yaml
name: Test

on:
  workflow_dispatch:
  pull_request:
    branches:
      - main
    types:
      - opened
      - ready_for_review
      - reopened
      - synchronize
  push:
    branches:
      - main

permissions:
  contents: read

concurrency:
  group: test-${{ github.event.pull_request.number || github.ref_name }}
  cancel-in-progress: true

jobs:
  test:
    runs-on: [self-hosted, macOS, ARM64]
    timeout-minutes: 30

    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          clean: true

      - name: Install Mise
        uses: jdx/mise-action@v4
        with:
          install: false

      - name: "Mise: Trust repo"
        run: mise trust

      - name: "Mise: Install dependencies"
        run: mise install --locked

      - name: Generate workspace
        run: mise run generate_workspace

      - name: Run tests (macOS)
        run: mise run test --platform macOS

      - name: Run tests (iOS)
        run: mise run test --platform iOS

```

</details>

### 🚀 CI workflow: Deploy

Bump app build number, archive iOS and macOS app, upload archives to App Store Connect, generate "What To Test" notes, and submit to TestFlight.

<details>
<summary><code>.github/workflows/deploy.yml</code></summary>

```yaml
name: Deploy

on:
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: deploy-${{ github.ref_name }}
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: [self-hosted, macOS, ARM64]
    timeout-minutes: 90

    steps:
      - name: Checkout
        uses: actions/checkout@v6
        with:
          clean: true
          fetch-depth: 0

      - name: Install Mise
        uses: jdx/mise-action@v4
        with:
          install: false

      - name: "Mise: Trust repo"
        run: mise trust

      - name: "Mise: Install dependencies"
        run: mise install --locked

      - name: Generate workspace
        run: mise run generate_workspace

      - name: Configure git identity
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

      - name: Configure App Store Connect API key
        env:
          APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
          APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
          APP_STORE_CONNECT_API_PRIVATE_KEY: ${{ secrets.APP_STORE_CONNECT_API_PRIVATE_KEY }}
        run: |
          set -euo pipefail

          private_key_path="$(mktemp "${RUNNER_TEMP}/app-store-connect-api-key.XXXXXX.p8")"
          printf '%s' "${APP_STORE_CONNECT_API_PRIVATE_KEY}" > "${private_key_path}"
          chmod 600 "${private_key_path}"

          {
            echo "APP_STORE_CONNECT_API_KEY_ID=${APP_STORE_CONNECT_API_KEY_ID}"
            echo "APP_STORE_CONNECT_API_ISSUER_ID=${APP_STORE_CONNECT_API_ISSUER_ID}"
            echo "APP_STORE_CONNECT_API_PRIVATE_KEY_PATH=${private_key_path}"
          } >> "${GITHUB_ENV}"

      - name: Resolve and set build number
        run: mise run set_next_build_number

      - name: Archive app (macOS)
        run: mise run archive_app --platform macOS

      - name: Archive app (iOS)
        run: mise run archive_app --platform iOS

      - name: Upload archive (macOS)
        run: mise run upload_archive --platform macOS

      - name: Upload archive (iOS)
        run: mise run upload_archive --platform iOS

      - name: Create and push release tag
        run: |
          set -euo pipefail
          release_tag="$(mise run --output quiet add_release_tag)"
          git push origin "refs/tags/${release_tag}"

      - name: Generate WhatToTest
        run: mise run generate_whattotest

      - name: Submit to TestFlight (macOS)
        run: mise run submit_to_testflight --platform macOS

      - name: Submit to TestFlight (iOS)
        run: mise run submit_to_testflight --platform iOS

      - name: Cleanup App Store Connect API key
        if: ${{ always() }}
        run: |
          if [[ -n "${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH:-}" ]]; then
            rm -f "${APP_STORE_CONNECT_API_PRIVATE_KEY_PATH}"
          fi

```

</details>

## ☕️ Do you like the project?

I would love to hear if you like my work. I can help you apply any of the solutions used in this repository in your app too! Feel free to reach out to me, or if you just want to say "thanks", you can buy me a coffee.

<a href="https://www.buymeacoffee.com/darrarski" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="60" width="217" style="height: 60px !important;width: 217px !important;" ></a>

## 📄 License

Copyright © 2026 Dariusz Rybicki Darrarski

[MIT LICENSE](LICENSE)
