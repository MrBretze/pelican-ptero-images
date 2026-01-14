#!/bin/bash

# Default the TZ environment variable to UTC.
TZ=${TZ:-UTC}
export TZ

# Set environment variable that holds the Internal Docker IP
INTERNAL_IP=$(ip route get 1 | awk '{print $(NF-2);exit}')
export INTERNAL_IP

# Switch to the container's working directory
cd /home/container || exit 1

# Create temporary directory if it doesn't exist
mkdir -p /home/container/.tmp

# Print Java version
printf "\033[1m\033[33mcontainer~ \033[0mjava -version\n"
java -version

# Hytale Downloader Configuration
DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
DOWNLOADER_BIN="${DOWNLOADER_BIN:-/home/container/hytale-downloader}"
AUTO_UPDATE=${AUTO_UPDATE:-0}

# Function to install Hytale Downloader
install_downloader() {
    printf "\033[1m\033[33mcontainer~ \033[0mDownloader not found, installing...\n"

    local TEMP_DIR="/home/container/.tmp/hytale-downloader-install"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    # Download downloader
    if ! wget -q -O "$TEMP_DIR/downloader.zip" "$DOWNLOADER_URL"; then
        printf "\033[0;31mError: Failed to download Hytale Downloader\033[0m\n"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Extract downloader
    if ! unzip -q -o "$TEMP_DIR/downloader.zip" -d "$TEMP_DIR"; then
        printf "\033[0;31mError: Failed to extract Hytale Downloader\033[0m\n"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Copy to target location
    if [ -f "$TEMP_DIR/hytale-downloader" ]; then
        cp "$TEMP_DIR/hytale-downloader" "$DOWNLOADER_BIN"
        chmod +x "$DOWNLOADER_BIN"
        printf "\033[0;32m✓ Hytale Downloader installed successfully\033[0m\n"
    else
        printf "\033[0;31mError: Downloader binary not found in archive\033[0m\n"
        rm -rf "$TEMP_DIR"
        return 1
    fi

    # Cleanup
    rm -rf "$TEMP_DIR"
    return 0
}

# check for updates
check_for_updates() {
    printf "\033[1m\033[33mcontainer~ \033[0mChecking for Hytale server updates...\n"

    if [ ! -f "$DOWNLOADER_BIN" ]; then
        if ! install_downloader; then
            printf "\033[0;31mError: Failed to install Hytale Downloader\033[0m\n"
            return 1
        fi
    fi

    # Get current game version
    CURRENT_VERSION=$("$DOWNLOADER_BIN" -print-version -skip-update-check 2>/dev/null | head -1)

    if [ -z "$CURRENT_VERSION" ]; then
        printf "\033[0;31mWarning: Could not determine game version\033[0m\n"
        return 1
    fi

    printf "\033[0;36mCurrent game version: $CURRENT_VERSION\033[0m\n"
    return 0
}

# Function to download and update Hytale
download_hytale() {
    printf "\033[1m\033[33mcontainer~ \033[0mPreparing Hytale server files...\n"

    if [ ! -f "$DOWNLOADER_BIN" ]; then
        if ! install_downloader; then
            printf "\033[0;31mError: Failed to install Hytale Downloader\033[0m\n"
            return 1
        fi
    fi

    # Create temporary directory for download
    DOWNLOAD_DIR="/home/container/.tmp/hytale-download"
    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"

    # Run downloader - it downloads the zip file (named like 2026.01.13-50e69c385.zip)
    if ! "$DOWNLOADER_BIN" \
        -skip-update-check \
        -download-path "$DOWNLOAD_DIR/"; then
        printf "\033[0;31mError: Hytale Downloader failed\033[0m\n"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Find the downloaded zip file (name varies by date and branch)
    GAME_ZIP=$(find "$DOWNLOAD_DIR" -maxdepth 1 -name "*.zip" -type f | head -n 1)

    if [ -z "$GAME_ZIP" ]; then
        printf "\033[0;31mError: No zip file found in download directory\033[0m\n"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Extract downloaded files
    printf "\033[1m\033[33mcontainer~ \033[0mExtracting server files...\n"
    if ! unzip -q -o "$GAME_ZIP" -d "$DOWNLOAD_DIR"; then
        printf "\033[0;31mError: Failed to extract Hytale server files\033[0m\n"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    # Copy Server folder contents and Assets.zip to container root
    if [ -d "$DOWNLOAD_DIR/Server" ]; then
        # Move all files from Server folder to /home/container
        cp -r "$DOWNLOAD_DIR/Server/"* /home/container/ || return 1
        printf "\033[0;32m✓ Server files installed\033[0m\n"
    else
        printf "\033[0;31mError: Server folder not found in downloaded files\033[0m\n"
        rm -rf "$DOWNLOAD_DIR"
        return 1
    fi

    if [ -f "$DOWNLOAD_DIR/Assets.zip" ]; then
        cp "$DOWNLOAD_DIR/Assets.zip" /home/container/ || return 1
        printf "\033[0;32m✓ Assets installed\033[0m\n"
    else
        printf "\033[0;31mWarning: Assets.zip not found in downloaded files\033[0m\n"
    fi

    # Cleanup
    rm -rf "$DOWNLOAD_DIR"

    printf "\033[0;32m✓ Hytale server ready\033[0m\n"
    return 0
}

# Check for game files and handle AUTO_UPDATE
if [ "$AUTO_UPDATE" = "1" ]; then
    printf "\033[0;36mAuto-update enabled, checking for updates...\033[0m\n"
    check_for_updates

    # Always download latest on AUTO_UPDATE=1
    printf "\033[0;36mDownloading latest Hytale server files...\033[0m\n"
    if download_hytale; then
        printf "\033[0;32m✓ Server ready to start\033[0m\n"
    else
        printf "\033[0;31mError: Auto-update failed, server will not start\033[0m\n"
        exit 1
    fi
else
    # Check for existing game files
    if [ ! -f "/home/container/HytaleServer.jar" ] && [ ! -d "/home/container/Server" ]; then
        printf "\033[1m\033[33mcontainer~ \033[0mNo Hytale server files found\n"
        printf "\033[0;36mSet AUTO_UPDATE=1 to automatically download files\033[0m\n"

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
