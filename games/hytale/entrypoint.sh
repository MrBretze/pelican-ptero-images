#!/bin/bash

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Simple colors via tput (fallback to no color if unavailable)
RED=$(tput setaf 1 2>/dev/null || echo '')
GREEN=$(tput setaf 2 2>/dev/null || echo '')
YELLOW=$(tput setaf 3 2>/dev/null || echo '')
BLUE=$(tput setaf 4 2>/dev/null || echo '')
CYAN=$(tput setaf 6 2>/dev/null || echo '')
NC=$(tput sgr0 2>/dev/null || echo '')

ERROR_LOG="/home/container/install_error.log"

# Message helpers
msg() {
    local color="$1"
    shift
    # If RED, also write the message to install_error.log
    if [ "$color" = "RED" ]; then
        printf "%b\n" "${RED}$*${NC}" | tee -a "$ERROR_LOG" >&2
    else
        printf "%b\n" "${!color}$*${NC}"
    fi
}

line() {
    local color="${1:-BLUE}"
    local term_width
    term_width=$(tput cols 2>/dev/null || echo 70)
    local sep
    sep=$(printf '%*s' "$term_width" '' | tr ' ' '-')
    msg "$color" "$sep"
}

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

# Refresh temporary directory to avoid stale downloads between restarts
rm -rf /home/container/.tmp
mkdir -p /home/container/.tmp

# Print Java version
echo "java -version"
java -version

# Hytale Downloader Configuration
DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
DOWNLOADER_BIN="${DOWNLOADER_BIN:-/home/container/hytale-downloader}"
AUTO_UPDATE=${AUTO_UPDATE:-0}
PATCHLINE=${PATCHLINE:-release}
CREDENTIALS_PATH="${CREDENTIALS_PATH:-/home/container/.hytale-downloader-credentials.json}"
DOWNLOADER_ARGS=()

# Auth is handled manually via URL; credentials file is optional but used when present
if [ -n "$CREDENTIALS_PATH" ] && [ -f "$CREDENTIALS_PATH" ]; then
    DOWNLOADER_ARGS+=("-credentials-path" "$CREDENTIALS_PATH")
fi
DOWNLOADER_TIMEOUT=${DOWNLOADER_TIMEOUT:-20}
TIMEOUT_BIN="$(command -v timeout || true)"

# Check for downloader updates first thing
if [ -f "$DOWNLOADER_BIN" ]; then
    msg BLUE "[startup] Checking for downloader updates..."
    UPDATE_OUT=$(run_downloader "Downloader update check" -check-update)
    UPDATE_RC=$?
    echo "$UPDATE_OUT" | sed "s/.*/  ${CYAN}&${NC}/"
    if [ "$UPDATE_RC" = "0" ]; then
        msg GREEN "  ✓ Downloader is up to date"
    else
        msg YELLOW "  Note: Downloader update check completed"
    fi
fi

# Function to install Hytale Downloader
install_downloader() {
    msg BLUE "[installer] Downloader not found, installing..."

    local TEMP_DIR="/home/container/.tmp/hytale-downloader-install"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # Download downloader
    msg BLUE "[installer] Downloading downloader package..."
    if ! wget -O "$TEMP_DIR/downloader.zip" "$DOWNLOADER_URL"; then
        msg RED "Error: Failed to download Hytale Downloader"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Extract downloader
    msg BLUE "[installer] Extracting downloader..."
    if ! unzip -o "$TEMP_DIR/downloader.zip" -d "$TEMP_DIR"; then
        msg RED "Error: Failed to extract Hytale Downloader"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Copy to target location
    if [ -f "$TEMP_DIR/hytale-downloader" ]; then
        cp "$TEMP_DIR/hytale-downloader" "$DOWNLOADER_BIN"
        chmod +x "$DOWNLOADER_BIN"
        msg GREEN "✓ Hytale Downloader installed successfully"
    else
        msg RED "Error: Downloader binary not found in archive"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    return 0
}

run_downloader() {
    # Runs the downloader with an optional timeout and returns stdout for further processing
    local description="$1"
    shift

    local output rc
    if [ -n "$TIMEOUT_BIN" ]; then
        output=$("$TIMEOUT_BIN" "$DOWNLOADER_TIMEOUT" "$DOWNLOADER_BIN" "${DOWNLOADER_ARGS[@]}" "$@" 2>&1)
        rc=$?
        if [ "$rc" = "124" ]; then
            msg RED "Error: $description timed out after ${DOWNLOADER_TIMEOUT}s"
        fi
    else
        output=$("$DOWNLOADER_BIN" "${DOWNLOADER_ARGS[@]}" "$@" 2>&1)
        rc=$?
    fi

    echo "$output"
    return "$rc"
}

# Check for updates
check_for_updates() {
    msg BLUE "[update] Checking for Hytale server updates..."

    if [ ! -f "$DOWNLOADER_BIN" ]; then
        if ! install_downloader; then
            msg RED "Error: Failed to install Hytale Downloader"
            return 1
        fi
    fi

    # Get current game version
    local VERSION_OUTPUT RC
    VERSION_OUTPUT=$(run_downloader "Version check" -print-version -skip-update-check)
    RC=$?
    if [ "$RC" != "0" ]; then
        msg YELLOW "Warning: Could not determine game version"
        return 1
    fi

    CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | head -1)

    if [ -z "$CURRENT_VERSION" ]; then
        msg YELLOW "Warning: Could not determine game version"
        return 1
    fi

    msg GREEN "Current game version: $CURRENT_VERSION"
    return 0
}

# Function to download and update Hytale
download_hytale() {
    msg BLUE "[update] Checking for Hytale updates..."

    if [ ! -f "$DOWNLOADER_BIN" ]; then
        if ! install_downloader; then
            msg RED "Error: Failed to install Hytale Downloader"
            return 1
        fi
    fi

    # Check local version
    LOCAL_VERSION=""
    if [ -f "/home/container/.version" ]; then
        LOCAL_VERSION=$(cat "/home/container/.version" 2>/dev/null)
    fi

    msg CYAN "  Local version: ${LOCAL_VERSION:-none installed}"

    # Get remote version without downloading
    msg BLUE "[update 1/3] Fetching remote version..."
    local REMOTE_OUT REMOTE_RC
    REMOTE_OUT=$(run_downloader "Remote version lookup" -patchline "$PATCHLINE" -print-version -skip-update-check)
    REMOTE_RC=$?
    if [ "$REMOTE_RC" != "0" ]; then
        msg RED "Error: Could not determine remote version"
        return 1
    fi

    REMOTE_VERSION=$(echo "$REMOTE_OUT" | head -1)

    if [ -z "$REMOTE_VERSION" ]; then
        msg RED "Error: Could not determine remote version"
        return 1
    fi

    msg CYAN "  Remote version: $REMOTE_VERSION"

    # Compare versions - if same, skip everything
    if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ] && [ -f "/home/container/HytaleServer.jar" ]; then
        msg GREEN "✓ Already running version $REMOTE_VERSION - no update needed"
        return 0
    fi

    # Version is different, download and install
    msg BLUE "[update 2/3] Downloading Hytale build..."

    # Create temporary directory for download
    DOWNLOAD_DIR="/home/container/.tmp/hytale-download"
    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"

    # Run downloader inside download dir so it names the zip itself
    local DOWNLOAD_LOG DOWNLOAD_RC
    DOWNLOAD_LOG=$(cd "$DOWNLOAD_DIR" && run_downloader "Download build" -patchline "$PATCHLINE" -skip-update-check)
    DOWNLOAD_RC=$?
    echo "$DOWNLOAD_LOG" | sed "s/.*/  ${CYAN}&${NC}/"
    if [ "$DOWNLOAD_RC" != "0" ]; then
        msg RED "Error: Hytale Downloader failed"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Locate downloaded zip (dynamic name by date/branch)
    GAME_ZIP=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*.zip" -type f | head -n 1)

    if [ -z "$GAME_ZIP" ] || [ ! -f "$GAME_ZIP" ]; then
        msg RED "Error: No zip file found in download directory"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Extract downloaded files
    msg BLUE "[update 3/3] Extracting and installing..."
    if ! unzip -o "$GAME_ZIP" -d "$DOWNLOAD_DIR"; then
        msg RED "Error: Failed to extract Hytale server files"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Copy Server folder contents and Assets.zip to container root
    if [ -d "$DOWNLOAD_DIR/Server" ]; then
        # Move all files from Server folder to /home/container
        cp -r "$DOWNLOAD_DIR/Server/"* /home/container/ || return 1
        msg GREEN "  ✓ Server files installed"
    else
        msg RED "Error: Server folder not found in downloaded files"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    if [ -f "$DOWNLOAD_DIR/Assets.zip" ]; then
        cp "$DOWNLOAD_DIR/Assets.zip" /home/container/ || return 1
        msg GREEN "  ✓ Assets installed"
    else
        msg YELLOW "Warning: Assets.zip not found in downloaded files"
    fi

    # Save version
    echo "$REMOTE_VERSION" > "/home/container/.version"

    # Cleanup
    rm -rf "$DOWNLOAD_DIR"

    msg GREEN "✓ Hytale server updated to version $REMOTE_VERSION"
    return 0
}

# Check for game files and handle AUTO_UPDATE
if [ "$AUTO_UPDATE" = "1" ]; then
    msg CYAN "Auto-update enabled, downloading latest version..."
    if download_hytale; then
        msg GREEN "✓ Server ready to start"
    else
        msg RED "Error: Auto-update failed, server will not start"
        exit 1
    fi
else
    # Check for existing game files
    if [ ! -f "/home/container/HytaleServer.jar" ] && [ ! -d "/home/container/Server" ]; then
        msg YELLOW "No Hytale server files found"
        msg CYAN "Set AUTO_UPDATE=1 to automatically download files"

        # Try to check for updates anyway
        check_for_updates || true
    else
        # Check for updates in background when server exists
        check_for_updates || true
    fi
fi

# Convert all of the "{{VARIABLE}}" parts of the command into the expected shell
# variable format of "${VARIABLE}" before evaluating the string and automatically
# replacing the values.
PARSED=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g' | eval echo "$(cat -)")

# Display the command we're running in the output, and then execute it with eval
printf "\033[1m\033[33mcontainer~ \033[0m"
echo "$PARSED"
# shellcheck disable=SC2086
exec env ${PARSED}
