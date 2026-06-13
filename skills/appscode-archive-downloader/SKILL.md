---
name: appscode-archive-downloader
description: >
  Download and extract ACE installer archives from appscode.com.
  Use this skill whenever the user asks to download an installer archive, fetch installer yamls,
  pull ACE installer files, or extract installer archives from appscode.com.
  Triggers on: "download installer", "fetch archive", "appscode installer", "ace installer download",
  installer names like "long-running-ghcr" or "prod-testing", or any request to get installer files
  into ~/yamls. Also triggers when the user says "download {name}" where {name} matches a known
  ACE installer. Even if the user just says an installer name casually, this skill should trigger.
---

# Appscode ACE Installer Archive Downloader

Downloads an ACE installer archive from appscode.com and extracts it to `~/yamls/archive/`.

## Prerequisites

- `curl`, `jq`, `tar` must be available.

## Credentials

Credentials are stored in `~/.claude/secrets/appscode.env`. Load them before use.

Use prod credentials when the user says "prod" or "appscode.com" (default).
Use ninja credentials when the user says "ninja" or "staging" or "appscode.ninja".

## Workflow

### Step 1: Set credentials

```bash
source ~/.claude/secrets/appscode.env

# Prod (appscode.com)
USERNAME="${APPSCODE_PROD_USERNAME}"
PASSWORD="${APPSCODE_PROD_PASSWORD}"
BASE_URL="https://appscode.com"

# Ninja/Staging (appscode.ninja)
USERNAME="${APPSCODE_NINJA_USERNAME}"
PASSWORD="${APPSCODE_NINJA_PASSWORD}"
BASE_URL="https://appscode.ninja"
```

### Step 2: Find the installer ID

The user gives an **installer name** (e.g. `long-running-ghcr`).

Fetch the installer list and extract the matching ID:

```bash
INSTALLER_NAME="<name-from-user>"

INSTALLER_ID=$(curl -s -u "${USERNAME}:${PASSWORD}" \
  "${BASE_URL}/api/v1/ace-installer/installers?org=appscode-dev" \
  | jq -r ".[] | select(.installerName==\"${INSTALLER_NAME}\") | .ID // .id")

echo "Installer ID: ${INSTALLER_ID}"
```

If `INSTALLER_ID` is empty, the name didn't match. List available installers:

```bash
curl -s -u "${USERNAME}:${PASSWORD}" \
  "${BASE_URL}/api/v1/ace-installer/installers?org=appscode-dev" \
  | jq -r '.[].installerName'
```

Show them to the user and ask to pick one.

### Step 3: Get the archive download URL

```bash
ARCHIVE_URL=$(curl -s -u "${USERNAME}:${PASSWORD}" \
  "${BASE_URL}/api/v1/ace-installer/installers/${INSTALLER_NAME}/${INSTALLER_ID}?org=appscode-dev" \
  | jq -r '.archiveTarURL')

echo "Archive URL: ${ARCHIVE_URL}"
```

**Never hardcode the URL** — always fetch it from the API. The internal IDs (like `332800`)
can change.

### Step 4: Download the archive

```bash
mkdir -p ~/yamls
curl -fsSL -u "${USERNAME}:${PASSWORD}" \
  -o ~/yamls/archive.tar.gz \
  "${ARCHIVE_URL}"
```

### Step 5: Extract the archive

```bash
rm -rf ~/yamls/archive
mkdir -p ~/yamls/archive
tar -xzf ~/yamls/archive.tar.gz -C ~/yamls/archive/
```

### Step 6: Clean up and verify

```bash
rm -f ~/yamls/archive.tar.gz
ls -la ~/yamls/archive/
```

Show the user what was extracted.

## Error Handling

- **401/403 on API call**: Credentials are wrong. Ask user to re-check.
- **Installer name not found**: List available names and ask user to pick.
- **Download fails**: Print the HTTP status and URL attempted.
- **tar fails**: Try `unzip` — the URL might have returned a zip file. Also check
  if `archiveZipURL` should be used instead of `archiveTarURL`.

## Notes

- The org is `appscode-dev` — hardcoded for now. If multi-org support is needed later,
  ask the user which org.
- The API returns both `archiveTarURL` and `archiveZipURL`. Prefer tar.gz.
- Clean up old archives before extracting (`rm -rf ~/yamls/archive`) to avoid stale files.
