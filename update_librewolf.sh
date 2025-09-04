#!/bin/bash

# A script to check the installed LibreWolf version on macOS
# against the latest release and offer to update it.

# Set the log file path with a timestamp. This will create a unique log file for each run.
LOG_FILE="/tmp/librewolf_update-$(date +%Y%m%d-%H%M%S).log"

# Start by redirecting all stdout and stderr to the unique log file.
# This ensures all messages, including errors, are recorded.
# We use 'tee' to also output to the console for real-time viewing during manual runs.
# '>>' appends to the file, and 2>&1 redirects stderr to stdout.
exec 1> >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

echo "--- Starting LibreWolf Update Check at $(date) ---"

# Explicitly set the PATH to include Homebrew directories.
# This ensures the script can find 'terminal-notifier' even when
# run from a non-interactive shell (like a launchd agent).
PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

# Function to find the correct path for the terminal-notifier tool.
get_notifier_path() {
    if [ -x "/opt/homebrew/bin/terminal-notifier" ]; then
        echo "/opt/homebrew/bin/terminal-notifier"
    elif [ -x "/usr/local/bin/terminal-notifier" ]; then
        echo "/usr/local/bin/terminal-notifier"
    else
        echo ""
    fi
}

# Find the path to the notifier tool at the beginning of the script.
TERMINAL_NOTIFIER_PATH=$(get_notifier_path)

# Function to display a notification in the macOS Notification Center.
# This function uses the `terminal-notifier` tool, which we confirmed is working.
show_notification() {
    if [ -n "$TERMINAL_NOTIFIER_PATH" ]; then
        "$TERMINAL_NOTIFIER_PATH" -title "$2" -message "$1" -sender "org.mozilla.librewolf"
    fi
    echo "Notification Message: $1" >&2
}

# Function to get the installed version of LibreWolf.
# It checks if the application exists and then reads the version directly from its Info.plist file.
# This is the most reliable method on macOS.
get_installed_version() {
    echo "Checking for installed LibreWolf version..." >&2
    if [ -d "/Applications/LibreWolf.app" ]; then
        version=$(defaults read "/Applications/LibreWolf.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)
        if [ -n "$version" ]; then
            echo "$version"
        else
            echo "not_detected"
        fi
    else
        echo "not_installed"
    fi
}

# Function to fetch and parse the latest version from the Atom feed.
get_latest_version() {
    echo "Fetching the latest version from the releases feed..." >&2
    local atom_url="https://gitlab.com/librewolf-community/browser/bsys6/-/releases.atom"
    
    # Fetch the Atom feed content.
    local feed_content=$(curl -s --fail "$atom_url")
    local curl_status=$?

    if [ $curl_status -ne 0 ]; then
        show_notification "Failed to connect to the update server. Please check your internet connection." "LibreWolf Update"
        exit 1
    fi

    # Find the first entry block.
    local latest_entry=$(echo "$feed_content" | grep -m1 -A 10 '<entry>')

    # Extract the version from the title.
    local version=$(echo "$latest_entry" | grep '<title>' | sed 's/.*<title>//;s/<\/title>.*//' | tr -d '[:space:]')
    
    # Check if a version was found.
    if [ -z "$version" ]; then
        show_notification "Failed to parse the latest version from the releases feed." "LibreWolf Update"
        exit 1
    fi
    echo "Latest version found: $version" >&2
    echo "$version"
}

# Function to download and install the latest version.
# It now takes the version string and the full URL as arguments.
update_librewolf() {
    local version_to_download="$1"
    
    # Construct the download URL using the pattern provided by the user.
    local download_url="https://gitlab.com/api/v4/projects/44042130/packages/generic/librewolf/${version_to_download}/librewolf-${version_to_download}-macos-x86_64-package.dmg"

    echo "Update process started for version: $version_to_download" >&2

    # Notify the user to manually quit LibreWolf. This is a more reliable approach
    # for scripts run by cron, which may have issues with GUI interaction.
    if pgrep "LibreWolf" > /dev/null; then
        show_notification "LibreWolf is running. Please quit it manually for a successful update." "LibreWolf Update"
        # The script will continue and attempt to install, but the user is now aware
        # and can quit the app to ensure a smooth installation.
    fi

    # Check if the volume is already mounted from a previous run and unmount it if so.
    if [ -d "/Volumes/LibreWolf" ]; then
        echo "A previous LibreWolf disk image is still mounted. Unmounting it." >&2
        hdiutil unmount "/Volumes/LibreWolf" -force
    fi

    echo "Downloading the latest version of LibreWolf from: $download_url" >&2
    show_notification "Downloading LibreWolf version $version_to_download..." "LibreWolf Update"

    # Check for and remove any existing LibreWolf.dmg file to prevent corrupted download errors.
    if [ -f "/tmp/librewolf.dmg" ]; then
        rm -f /tmp/librewolf.dmg
    fi
    
    # Download the file using the constructed URL.
    curl -L --fail -o /tmp/librewolf.dmg "$download_url"
    local curl_status=$?
    if [ $curl_status -ne 0 ]; then
        show_notification "Download failed. Please check your internet connection and try again." "LibreWolf Update"
        exit 1
    fi

    # Check if the download was successful before proceeding.
    if [ ! -f "/tmp/librewolf.dmg" ] || [ ! -s "/tmp/librewolf.dmg" ]; then
        show_notification "Download failed. The file is either missing or empty. Please check your internet connection and try again." "LibreWolf Update"
        exit 1
    fi
    echo "Download completed successfully." >&2
    show_notification "Download complete. Starting installation..." "LibreWolf Update"

    echo "Installing the latest version of LibreWolf..." >&2
    
    # Mount the downloaded disk image.
    hdiutil mount -nobrowse -quiet /tmp/librewolf.dmg
    
    # Check if the mount was successful.
    if [ $? -ne 0 ]; then
        show_notification "Failed to mount the disk image. The download may be corrupted." "LibreWolf Update"
        exit 1
    fi
    
    # Copy the application from the mounted volume to the Applications folder.
    # The -R flag recursively copies the directory.
    cp -R /Volumes/LibreWolf/LibreWolf.app /Applications/
    
    # Unmount the disk image.
    hdiutil unmount -quiet "/Volumes/LibreWolf"
    
    # Remove the temporary DMG file.
    rm /tmp/librewolf.dmg

    echo "LibreWolf has been updated to version $version_to_download." >&2
    show_notification "LibreWolf has been updated to version $version_to_download. You can now relaunch the application." "LibreWolf Update"
}

# --- Main script execution ---

echo "Starting LibreWolf update check..." >&2

# Get the versions
latest_version=$(get_latest_version)
installed_version=$(get_installed_version)

echo "Installed version: $installed_version" >&2
echo "Latest version: $latest_version" >&2

if [ "$installed_version" == "not_installed" ]; then
    echo "LibreWolf is not installed." >&2
    show_notification "LibreWolf is not installed. The latest version is $latest_version. Run the script again to install it." "LibreWolf Update"
else
    if [ "$installed_version" != "$latest_version" ]; then
        echo "A new version is available." >&2
        show_notification "A new version of LibreWolf is available. Starting the update process from $installed_version to $latest_version." "LibreWolf Update"
        update_librewolf "$latest_version"
    else
        echo "LibreWolf is up to date." >&2
        show_notification "LibreWolf is already up to date with version $installed_version." "LibreWolf Update"
    fi
fi

echo "Script execution finished." >&2
