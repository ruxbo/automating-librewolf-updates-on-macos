# My LibreWolf Auto-Updater

## Background
As an "old dog" learning new tricks in Linux, I found myself getting tired of the repetitive task of manually updating LibreWolf. This project is a result of my experimentation with macOS's `launchd` and shell scripting to create a seamless, automated updater. I've learned a lot along the way, and I hope this project helps others who want to simplify their workflow.

## Features
- **Automated Updates:** The script checks for and installs the latest version of LibreWolf on a schedule you define.
- **System Notifications:** You get a notification when the update starts and finishes.
- **Clean and Simple:** It uses native macOS tools, so there are no extra dependencies outside of Homebrew.



# Automating LibreWolf Updates on macOS

This guide walks you through setting up an automatic, hands-off updater for LibreWolf on macOS using two native system tools: launchd and terminal-notifier.

*   launchd: The macOS equivalent of a task scheduler, this tool will run a script for you at a specified time (e.g., every night at 10 PM).
    
*   terminal-notifier: This tool, installed via Homebrew, allows the script to send you notifications, so you know exactly when the update is running and when it's finished.
    

### Disclaimer

This solution is provided "as is" and is not an official LibreWolf product. It is a custom script designed to automate a specific task. While thoroughly tested, the author makes no guarantees, and you use this guide at your own risk. It is your responsibility to understand the commands you are running and to back up any critical data.

### Prerequisites

Before you begin, you need to install terminal-notifier using Homebrew. If you don't have Homebrew installed, follow the instructions on the official website.

Open a Terminal and run this command:

`brew install terminal-notifier  `
  

### Step 1: Create the Updater Script

This script will check for a new LibreWolf version, download it, and install it.

1.  Open a Terminal and create a new directory for your scripts:  
    `mkdir -p ~/Documents/scripts ` 
      
    
2.  Use the nano text editor to create and open a new file named update\_librewolf.sh:  
    `nano ~/Documents/scripts/update\_librewolf.sh  `
      
    
3.  Copy and paste the entire script below into the nano window. Note: This guide uses the username ruxkbo. Please change all instances of `/Users/ruxkbo/` to your own username if you are not `ruxkbo`.
    
```bash
#!/bin/bash  
  
# This script checks the installed LibreWolf version on macOS against the latest  
# release and automatically updates it if a new version is available.  
# It is designed to be run as a launchd agent.  `
  
# Set the log file path with a timestamp. This creates a unique log file for each run,  
# ensuring a clear hi#story of the script's execution.  
LOG\_FILE="/tmp/librewolf\_update-$(date +%Y%m%d-%H%M%S).log"  
  
# Redirect all standard output and standard error to the log file.  
# We use 'tee' to also output to the console for real-time viewing during manual runs.  
exec 1> >(tee -a "$LOG\_FILE") 2> >(tee -a "$LOG\_FILE" >&2)  
  
echo "--- Starting LibreWolf Update Check at $(date) ---"  
  
# Explicitly set the PATH to include common Homebrew directories.  
# This ensures the script can find 'terminal-notifier' and other tools  
# even when run from a non-interactive shell (like a launchd agent).  
PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"  
  
# --- Helper Functions ---  
  
# Function to find the correct path for the terminal-notifier tool.  
# This makes the script portable across different macOS systems (Intel vs. Apple Silicon).  
get\_notifier\_path() {  
    if \[ -x "/opt/homebrew/bin/terminal-notifier" \]; then  
        echo "/opt/homebrew/bin/terminal-notifier"  
    elif \[ -x "/usr/local/bin/terminal-notifier" \]; then  
        echo "/usr/local/bin/terminal-notifier"  
    else  
        # Return an empty string if the tool is not found.  
        echo ""  
    fi  
}  
  
# Find the path to the notifier tool at the beginning of the script.  
TERMINAL\_NOTIFIER\_PATH=$(get\_notifier\_path)  
  
# Function to display a notification in the macOS Notification Center.  
# It now uses the dynamically found path for the tool.  
show\_notification() {  
    if \[ -n "$TERMINAL\_NOTIFIER\_PATH" \]; then  
        "$TERMINAL\_NOTIFIER\_PATH" -title "$2" -message "$1" -sender "org.mozilla.librewolf"  
    fi  
    echo "Notification Message: $1" >&2  
}  
  
# Function to get the installed version of LibreWolf.  
# It checks if the application exists and then reads the version directly from its Info.plist file.  
# This is the most reliable method on macOS.  
get\_installed\_version() {  
    echo "Checking for installed LibreWolf version..." >&2  
    if \[ -d "/Applications/LibreWolf.app" \]; then  
        version=$(defaults read "/Applications/LibreWolf.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null)  
        if \[ -n "$version" \]; then  
            echo "$version"  
        else  
            echo "not\_detected"  
        fi  
    else  
        echo "not\_installed"  
    fi  
}  
  
# Function to fetch and parse the latest version from the Atom feed.  
get\_latest\_version() {  
    echo "Fetching the latest version from the releases feed..." >&2  
    local atom\_url="\[https://gitlab.com/librewolf-community/browser/bsys6/-/releases.atom\](https://gitlab.com/librewolf-community/browser/bsys6/-/releases.atom)"  
     
    # Fetch the Atom feed content using curl.  
    local feed\_content=$(curl -s --fail "$atom\_url")  
    local curl\_status=$?  
  
    if \[ $curl\_status -ne 0 \]; then  
        show\_notification "Failed to connect to the update server. Please check your internet connection." "LibreWolf Update"  
        exit 1  
    fi  
  
    # Find the first entry block.  
    local latest\_entry=$(echo "$feed\_content" | grep -m1 -A 10 '<entry>')  
  
    # Extract the version from the title.  
    local version=$(echo "$latest\_entry" | grep '<title>' | sed 's/.\*<title>//;s/<\\/title>.\*//' | tr -d '\[:space:\]')  
     
    # Check if a version was found.  
    if \[ -z "$version" \]; then  
        show\_notification "Failed to parse the latest version from the releases feed." "LibreWolf Update"  
        exit 1  
    fi  
    echo "Latest version found: $version" >&2  
    echo "$version"  
}  
  
# Function to download and install the latest version.  
update\_librewolf() {  
    local version\_to\_download="$1"  
     
    # Construct the download URL.  
    local download\_url="\[https://gitlab.com/api/v4/projects/44042130/packages/generic/librewolf/$\](https://gitlab.com/api/v4/projects/44042130/packages/generic/librewolf/$){version\_to\_download}/librewolf-${version\_to\_download}-macos-x86\_64-package.dmg"  
  
    echo "Update process started for version: $version\_to\_download" >&2  
  
    # Check if LibreWolf is running and notify the user to quit.  
    if pgrep "LibreWolf" > /dev/null; then  
        show\_notification "LibreWolf is running. Please quit it manually for a successful update." "LibreWolf Update"  
    fi  
  
    # Check for and unmount any previously mounted disk images.  
    if \[ -d "/Volumes/LibreWolf" \]; then  
        echo "A previous LibreWolf disk image is still mounted. Unmounting it." >&2  
        hdiutil unmount "/Volumes/LibreWolf" -force  
    fi  
  
    echo "Downloading the latest version of LibreWolf from: $download\_url" >&2  
    show\_notification "Downloading LibreWolf version $version\_to\_download..." "LibreWolf Update"  
  
    # Check for and remove any existing temporary file to prevent corruption.  
    if \[ -f "/tmp/librewolf.dmg" \]; then  
        rm -f /tmp/librewolf.dmg  
    fi  
     
    # Download the file using curl.  
    curl -L --fail -o /tmp/librewolf.dmg "$download\_url"  
    local curl\_status=$?  
    if \[ $curl\_status -ne 0 \]; then  
        show\_notification "Download failed. Please check your internet connection and try again." "LibreWolf Update"  
        exit 1  
    fi  
  
    # Check if the download was successful.  
    if \[ ! -f "/tmp/librewolf.dmg" \] || \[ ! -s "/tmp/librewolf.dmg" \]; then  
        show\_notification "Download failed. The file is either missing or empty. Please check your internet connection and try again." "LibreWolf Update"  
        exit 1  
    fi  
    echo "Download completed successfully." >&2  
    show\_notification "Download complete. Starting installation..." "LibreWolf Update"  
  
    echo "Installing the latest version of LibreWolf..." >&2  
     
    # Mount the downloaded disk image.  
    hdiutil mount -nobrowse -quiet /tmp/librewolf.dmg  
     
    # Check if the mount was successful.  
    if \[ $? -ne 0 \]; then  
        show\_notification "Failed to mount the disk image. The download may be corrupted." "LibreWolf Update"  
        exit 1  
    fi  
     
    # Copy the application to the Applications folder, overwriting the old version.  
    cp -R /Volumes/LibreWolf/LibreWolf.app /Applications/  
     
    # Unmount the disk image and remove the temporary file.  
    hdiutil unmount -quiet "/Volumes/LibreWolf"  
    rm /tmp/librewolf.dmg  
  
    echo "LibreWolf has been updated to version $version\_to\_download." >&2  
    show\_notification "LibreWolf has been updated to version $version\_to\_download. You can now relaunch the application." "LibreWolf Update"  
}  
  
# Main script execution#
  
echo "Starting LibreWolf update check..." >&2  
  
# Get the versions  
latest\_version=$(get\_latest\_version)  
installed\_version=$(get\_installed\_version)  
  
echo "Installed version: $installed\_version" >&2  
echo "Latest version: $latest\_version" >&2  
  
if \[ "$installed\_version" == "not\_installed" \]; then  
    echo "LibreWolf is not installed." >&2  
    show\_notification "LibreWolf is not installed. The latest version is $latest\_version. Run the script again to install it." "LibreWolf Update"  
else  
    if \[ "$installed\_version" != "$latest\_version" \]; then  
        echo "A new version is available." >&2  
        show\_notification "A new version of LibreWolf is available. Starting the update process from $installed\_version to $latest\_version." "LibreWolf Update"  
        update\_librewolf "$latest\_version"  
    else  
        echo "LibreWolf is up to date." >&2  
        show\_notification "LibreWolf is already up to date with version $installed\_version." "LibreWolf Update"  
    fi  
fi  
  
echo "Script execution finished." >&2  
```  

4.  Press Ctrl + X to exit, then Y to save, and then Enter to confirm the filename.
    

### Step 2: Make the Script Executable

The system needs permission to run your new file. This command grants it that permission.

Open a Terminal and run this command:

`chmod +x ~/Documents/scripts/update\_librewolf.sh`  
  

### Step 3: Create the launchd Agent File

This file tells macOS's launchd service what script to run and when to run it.

1.  Open a Terminal and go to the correct directory:  
    `cd ~/Library/LaunchAgents`  
      
    
2.  Use nano to create a new file named "com.ruxkbo.librewolf.update.plist":  
    `nano com.ruxkbo.librewolf.update.plist ` 
      
    
3.  Copy and paste the entire content below into the nano window. The Hour integer is currently set to 22 for 10 PM. You can change this to any hour between 0 (for 12 AM) and 23 (for 11 PM).
    
```xml
<?xml version="1.0" encoding="UTF-8"?>  
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "\[http://www.apple.com/DTDs/PropertyList-1.0.dtd\](http://www.apple.com/DTDs/PropertyList-1.0.dtd)">  
<plist version="1.0">  
<dict>  
    <key>Label</key>  
    <string>com.ruxkbo.librewolf.update</string>  
    <key>ProgramArguments</key>  
    <array>  
        <string>/bin/bash</string>  
        <string>/Users/ruxkbo/Documents/scripts/update\_librewolf.sh</string>  
    </array>  
    <key>StandardOutPath</key>  
    <string>/tmp/com.ruxkbo.librewolf.update.log</string>  
    <key>StandardErrorPath</key>  
    <string>/tmp/com.ruxkbo.librewolf.update.log</string>  
    <key>StartCalendarInterval</key>  
    <dict>  
        <key>Hour</key>  
        <integer>22</integer>  
        <key>Minute</key>  
        <integer>0</integer>  
    </dict>  
</dict>  
</plist>  
```  

4.  Press Ctrl + X to exit, then Y to save, and then Enter to confirm.
    

### Step 4: Load the launchd Agent

This step tells macOS to start using the new agent file. If you ever make changes to the .plist file, you must run these commands again.

1.  Unload the old version of the agent (if it exists):  
    `launchctl unload ~/Library/LaunchAgents/com.ruxkbo.librewolf.update.plist`  
      
    
2.  Load the new agent:  
    `launchctl load ~/Library/LaunchAgents/com.ruxkbo.librewolf.update.plist`  
      
    

### Step 5: Grant Full Disk Access

This is a critical security step. macOS's privacy settings will prevent the script from running without your permission.

1.  Go to System Settings > Privacy & Security > Full Disk Access.
    
2.  Click the + button.
    
3.  Press Command + Shift + G and type /bin/bash into the "Go to the folder:" box. Click Go.
    
4.  Select bash and click Open.
    
5.  Make sure the toggle next to bash is on.
    

### You're All Set!

That's it! Your LibreWolf auto-updater is now configured to run every night at 10 PM. You've created a great, repeatable solution that you can share with others.

If you ever need to check if the script ran, you can view the log file by running this command:

`cat /tmp/com.ruxkbo.librewolf.update.log`  
