#!/bin/bash

main() {

# Clear the screen and scrollback buffer so the invoking curl|bash command
# (which contains the script URL) is no longer visible to the client.
printf '\033[3J\033[2J\033[H'

VERSION="1.0.6"
CATALOG_URL="https://raw.githubusercontent.com/iMrLopez/headunit-adb-scripts/refs/heads/main/app-catalog.json"

TEMP_DIR=$(mktemp -d)
ADB_CMD=""

CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

printf "${CYAN}"
printf '╔══════════════════════════════════════════════════════╗\n'
printf '║                                                      ║\n'
printf "║    ${BOLD}Head Unit ADB Script${RESET}${CYAN}                              ║\n"
printf '║    ADB-based Android APK installer for head units    ║\n'
printf '║                                                      ║\n'
printf "║                              ${DIM}by iMrLopez · 2025${RESET}${CYAN}      ║\n"
printf "║                                              ${DIM}v${VERSION}${RESET}${CYAN}  ║\n"
printf '╚══════════════════════════════════════════════════════╝\n'
printf "${RESET}\n"

echo "Using temp directory: $TEMP_DIR"

cleanup() {
    [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
}
trap 'echo ""; echo "Cancelled, cleaning up..."; exit 130' INT TERM
trap cleanup EXIT

# Redirect stdin to the terminal so read prompts work when piped via curl | bash.
# Must be inside main() so the entire script is buffered before this runs.
exec < /dev/tty

echo "Fetching app catalog..."
APPS_CATALOG=$(curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' "$CATALOG_URL") || { echo "Failed to fetch app catalog." >&2; exit 1; }

# ── App selection ────────────────────────────────────────────────────────────

APP_NAMES=()
APP_TYPES=()
APP_SOURCES=()
while IFS= read -r line; do APP_NAMES+=("$line");   done < <(echo "$APPS_CATALOG" | python3 -c "import json,sys; [print(a['name'])   for a in json.load(sys.stdin)]")
while IFS= read -r line; do APP_TYPES+=("$line");   done < <(echo "$APPS_CATALOG" | python3 -c "import json,sys; [print(a['type'])   for a in json.load(sys.stdin)]")
while IFS= read -r line; do APP_SOURCES+=("$line"); done < <(echo "$APPS_CATALOG" | python3 -c "import json,sys; [print(a['source']) for a in json.load(sys.stdin)]")
APP_COUNT=${#APP_NAMES[@]}

echo "Available apps to install:"
for i in "${!APP_NAMES[@]}"; do
    echo "  $((i+1))) ${APP_NAMES[$i]}  [${APP_TYPES[$i]}]"
done
echo ""
read -rp "Select apps to install (e.g. 1 2 3 or 'all'): " SELECTION_INPUT

SELECTED_INDICES=()
if [ "$SELECTION_INPUT" = "all" ]; then
    for i in "${!APP_NAMES[@]}"; do SELECTED_INDICES+=("$i"); done
else
    for num in $(echo "$SELECTION_INPUT" | tr ',' ' '); do
        if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$APP_COUNT" ]; then
            SELECTED_INDICES+=($((num - 1)))
        fi
    done
fi

if [ "${#SELECTED_INDICES[@]}" -eq 0 ]; then
    echo "No valid selection." >&2; exit 1
fi

# ── Download selected APKs ───────────────────────────────────────────────────

QUEUE_NAMES=()
QUEUE_PATHS=()
APK_COUNTER=0

for IDX in "${SELECTED_INDICES[@]}"; do
    NAME="${APP_NAMES[$IDX]}"
    TYPE="${APP_TYPES[$IDX]}"
    SOURCE="${APP_SOURCES[$IDX]}"

    if [ "$TYPE" = "gitrelease" ]; then
        echo "Fetching latest release from $SOURCE..."
        RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$SOURCE/releases/latest") || { echo "Warning: Failed to fetch $SOURCE, skipping." >&2; continue; }
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | python3 -c "
import json, sys
assets = [a for a in json.load(sys.stdin)['assets'] if a['name'].endswith('.apk')]
print(assets[0]['browser_download_url']) if assets else exit(1)
") || { echo "Warning: No APK found in latest release of $SOURCE, skipping." >&2; continue; }
        APK_PATH="$TEMP_DIR/app_${APK_COUNTER}.apk"
        APK_COUNTER=$((APK_COUNTER + 1))
        echo "Downloading $NAME..."
        curl -f -L --progress-bar "$DOWNLOAD_URL" -o "$APK_PATH" || { echo "Warning: Failed to download $NAME, skipping." >&2; continue; }
        QUEUE_NAMES+=("$NAME")
        QUEUE_PATHS+=("$APK_PATH")

    elif [ "$TYPE" = "gitcollection" ]; then
        echo "Fetching APK list from $SOURCE..."
        RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/$SOURCE/releases/latest") || { echo "Warning: Failed to fetch $SOURCE, skipping." >&2; continue; }
        ASSET_NAMES=()
        ASSET_URLS=()
        while IFS= read -r line; do ASSET_NAMES+=("$line"); done < <(echo "$RELEASE_JSON" | python3 -c "import json,sys; [print(a['name']) for a in json.load(sys.stdin)['assets'] if a['name'].endswith('.apk')]")
        while IFS= read -r line; do ASSET_URLS+=("$line");  done < <(echo "$RELEASE_JSON" | python3 -c "import json,sys; [print(a['browser_download_url']) for a in json.load(sys.stdin)['assets'] if a['name'].endswith('.apk')]")
        ASSET_COUNT=${#ASSET_NAMES[@]}
        if [ "$ASSET_COUNT" -eq 0 ]; then echo "Warning: No APKs found in $SOURCE, skipping." >&2; continue; fi

        echo ""
        echo "APKs in $NAME:"
        for i in "${!ASSET_NAMES[@]}"; do echo "  $((i+1))) ${ASSET_NAMES[$i]}"; done
        read -rp "Select APKs to download (e.g. 1 2 3 or 'all'): " APK_INPUT

        APK_INDICES=()
        if [ "$APK_INPUT" = "all" ]; then
            for i in "${!ASSET_NAMES[@]}"; do APK_INDICES+=("$i"); done
        else
            for num in $(echo "$APK_INPUT" | tr ',' ' '); do
                if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$ASSET_COUNT" ]; then
                    APK_INDICES+=($((num - 1)))
                fi
            done
        fi

        for AIDX in "${APK_INDICES[@]}"; do
            ANAME="${ASSET_NAMES[$AIDX]}"
            APK_PATH="$TEMP_DIR/app_${APK_COUNTER}.apk"
            APK_COUNTER=$((APK_COUNTER + 1))
            echo "Downloading $ANAME..."
            curl -f -L --progress-bar "${ASSET_URLS[$AIDX]}" -o "$APK_PATH" || { echo "Warning: Failed to download $ANAME, skipping." >&2; continue; }
            QUEUE_NAMES+=("$ANAME")
            QUEUE_PATHS+=("$APK_PATH")
        done

    elif [ "$TYPE" = "directdownload" ]; then
        APK_PATH="$TEMP_DIR/app_${APK_COUNTER}.apk"
        APK_COUNTER=$((APK_COUNTER + 1))
        echo "Downloading $NAME..."
        curl -f -L --progress-bar "$SOURCE" -o "$APK_PATH" || { echo "Warning: Failed to download $NAME, skipping." >&2; continue; }
        QUEUE_NAMES+=("$NAME")
        QUEUE_PATHS+=("$APK_PATH")
    else
        echo "Warning: Unknown type '$TYPE' for '$NAME', skipping." >&2
    fi
done

# ── ADB setup ────────────────────────────────────────────────────────────────

if command -v adb &>/dev/null; then
    ADB_CMD="adb"
else
    echo "adb not found. Downloading platform-tools..."
    PLATFORM_TOOLS_URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
    ZIP_PATH="$TEMP_DIR/platform-tools.zip"
    curl -f -L --progress-bar "$PLATFORM_TOOLS_URL" -o "$ZIP_PATH" || { echo "Failed to download platform-tools." >&2; exit 1; }
    unzip -q "$ZIP_PATH" -d "$TEMP_DIR" || { echo "Failed to extract platform-tools." >&2; exit 1; }
    ADB_CMD="$TEMP_DIR/platform-tools/adb"
    chmod +x "$ADB_CMD"
    echo "adb downloaded to temporary folder (will be deleted on exit)."
fi

# ── Connect to device ────────────────────────────────────────────────────────

read -rp "Enter device IP address: " DEVICE_IP
echo "Connecting to $DEVICE_IP..."
"$ADB_CMD" connect "$DEVICE_IP" || { echo "Failed to connect to $DEVICE_IP." >&2; exit 1; }

echo ""
echo "Packages on $DEVICE_IP:"
"$ADB_CMD" -s "$DEVICE_IP" shell pm list packages

# ── Confirm and install ──────────────────────────────────────────────────────

if [ "${#QUEUE_NAMES[@]}" -eq 0 ]; then
    echo "No apps were successfully downloaded. Exiting." >&2; exit 1
fi

echo ""
echo "Ready to install ${#QUEUE_NAMES[@]} app(s) on $DEVICE_IP:"
for name in "${QUEUE_NAMES[@]}"; do
    echo "  - $name"
done
echo ""
read -rp "Proceed with installation? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

for i in "${!QUEUE_PATHS[@]}"; do
    echo ""
    echo "Installing ${QUEUE_NAMES[$i]}..."
    "$ADB_CMD" -s "$DEVICE_IP" install "${QUEUE_PATHS[$i]}"
done

echo ""
echo "All done."
exit 0

}

main "$@"
