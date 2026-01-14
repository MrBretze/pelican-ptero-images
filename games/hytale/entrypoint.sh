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

# Create temporary directory if it doesn't exist
mkdir -p /home/container/.tmp

# Set up machine-id: generate new one for this container instance
setup_machine_id() {
    msg BLUE "[setup] Initializing machine-id for this container instance..."

    # Remove existing machine-id
    if [ -f /etc/machine-id ]; then
        rm -f /etc/machine-id
        msg CYAN "  Cleared existing machine-id"
    fi

    # Generate new machine-id
    if dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null; then
        CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
        msg GREEN "  ✓ Generated new machine-id: $CURRENT_MACHINE_ID"
    else
        msg RED "  ✗ Failed to generate machine-id with dbus-uuidgen"
        # Fallback: create random UUID manually
        FALLBACK_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "unknown")
        echo "$FALLBACK_UUID" > /etc/machine-id 2>/dev/null
        CURRENT_MACHINE_ID=$(cat /etc/machine-id 2>/dev/null)
        msg YELLOW "  Using fallback machine-id: $CURRENT_MACHINE_ID"
    fi

    # Verify machine-id is readable
    if [ -s /etc/machine-id ]; then
        msg GREEN "  ✓ Machine-id setup complete"
    else
        msg RED "  ✗ Warning: machine-id file is empty or unreadable"
    fi
}

# Setup machine-id before anything else (runs as root via tini)
setup_machine_id

# Print Java version
echo "java -version"
java -version

# Hytale Downloader Configuration
DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
DOWNLOADER_BIN="${DOWNLOADER_BIN:-/home/container/hytale-downloader}"
AUTO_UPDATE=${AUTO_UPDATE:-0}

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

# check for updates
check_for_updates() {
    msg BLUE "[update] Checking for Hytale server updates..."

    if [ ! -f "$DOWNLOADER_BIN" ]; then
        if ! install_downloader; then
            msg RED "Error: Failed to install Hytale Downloader"
            return 1
        fi
    fi

    # Get current game version with timeout
    CURRENT_VERSION=$(timeout 10 "$DOWNLOADER_BIN" -print-version -skip-update-check 2>/dev/null | head -1)

    if [ -z "$CURRENT_VERSION" ]; then
        msg YELLOW "Warning: Could not determine game version"
        return 1
    fi

    msg GREEN "Current game version: $CURRENT_VERSION"
    return 0
}

# Function to download and update Hytale
download_hytale() {
    msg BLUE "[update] Preparing Hytale server files..."

    if [ ! -f "$DOWNLOADER_BIN" ]; then
        if ! install_downloader; then
            msg RED "Error: Failed to install Hytale Downloader"
            return 1
        fi
    fi

    # Create temporary directory for download
    DOWNLOAD_DIR="/home/container/.tmp/hytale-download"
    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"

    # Run downloader inside download dir so it names the zip itself
    msg BLUE "[update 1/4] Downloading latest Hytale build..."
    if ! (cd "$DOWNLOAD_DIR" && "$DOWNLOADER_BIN" -skip-update-check 2>&1 | sed "s/.*/  ${CYAN}&${NC}/"); then
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
    msg BLUE "[update 2/4] Extracting server files..."
    if ! unzip -o "$GAME_ZIP" -d "$DOWNLOAD_DIR"; then
        msg RED "Error: Failed to extract Hytale server files"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Copy Server folder contents and Assets.zip to container root
    if [ -d "$DOWNLOAD_DIR/Server" ]; then
        # Move all files from Server folder to /home/container
        cp -r "$DOWNLOAD_DIR/Server/"* /home/container/ || return 1
        msg GREEN "[update 3/4] ✓ Server files installed"
    else
        msg RED "Error: Server folder not found in downloaded files"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    if [ -f "$DOWNLOAD_DIR/Assets.zip" ]; then
        cp "$DOWNLOAD_DIR/Assets.zip" /home/container/ || return 1
        msg GREEN "[update 4/4] ✓ Assets installed"
    else
        msg YELLOW "Warning: Assets.zip not found in downloaded files"
    fi

    # Cleanup
    rm -rf "$DOWNLOAD_DIR"

    msg GREEN "✓ Hytale server ready"
    return 0
}

# Check for game files and handle AUTO_UPDATE
if [ "$AUTO_UPDATE" = "1" ]; then
    msg CYAN "Auto-update enabled, checking for updates..."
    check_for_updates

    # Always download latest on AUTO_UPDATE=1
    msg CYAN "Downloading latest Hytale server files..."
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
