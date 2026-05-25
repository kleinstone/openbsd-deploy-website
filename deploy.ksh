#!/bin/ksh
# deploy.ksh - Atomic deployment script for any web site

# This script automates zero-downtime deployments by building the new release 
# in isolation, preparing shared resources and permissions, and then atomically 
# switching a symlink to make it live.

# Exit immediately if a command exits with a non-zero status
set -e

LOG_TIME=$(date '+%Y-%m-%d %H:%M:%S')

# 1. Check for proper arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <site_domain> <source_directory>"
    echo "Example: $0 kleinstone.com ~/xfer"
    exit 1
fi

SITE_NAME="$1"
SOURCE_DIR="$2"

# Ensure the script is run as root (needed for permissions and /var/www access)
if [ "$(id -u)" -ne 0 ]; then
    echo "[$LOG_TIME] ❌ Error: This script must be run as root (e.g., using doas)." >&2
    exit 1
fi

# 2. Define the directory structure
BASE_DIR="/var/www/htdocs/${SITE_NAME}"
RELEASES_DIR="${BASE_DIR}/releases"
SHARED_DIR="${BASE_DIR}/shared"
SYMLINK_PATH="${BASE_DIR}/public"
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
NEW_RELEASE_DIR="${RELEASES_DIR}/${TIMESTAMP}"

printf "Deploying %s...\n\n" "${SITE_NAME}"

# 3. Validate source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "[$LOG_TIME] ❌ Error: Source directory '${SOURCE_DIR}' does not exist."
    exit 1
fi

# 4. Create the releases directory if it doesn't exist yet
mkdir -p "${RELEASES_DIR}" "${SHARED_DIR}"

# --- FIRST TIME SETUP TRANSITION ---
# If 'public' is still a real directory from your old workflow, we need 
# to back it up so we can replace it with a symlink.
if [ -d "${SYMLINK_PATH}" ] && [ ! -L "${SYMLINK_PATH}" ]; then
    printf "Notice:\tBacking up legacy 'public' directory to 'public_legacy_backup'...\n"
    mv "${SYMLINK_PATH}" "${BASE_DIR}/public_legacy_backup"
    echo ""
fi
# -----------------------------------

# 5. Copy new files to the isolated release directory
printf "Copying release to %s...\n" "${NEW_RELEASE_DIR}"
cp -Rf "${SOURCE_DIR}/." "${NEW_RELEASE_DIR}/"
echo ""

# 5b. Link Shared Resources
printf "Linking shared resources...\n"
# Add any directories or files here that should persist across deployments.
# We use relative symlinks (../../) so that OpenBSD's httpd can properly 
# follow them from inside its /var/www chroot.
SHARED_ITEMS="config uploads .env logs"

for item in $SHARED_ITEMS; do
    if [ -e "${SHARED_DIR}/${item}" ]; then
        # Remove the file/folder from the new release if it came over in the copy
        rm -rf "${NEW_RELEASE_DIR}/${item}"
        
        # Create a symlink pointing to the shared, persistent version
        ln -s "../../shared/${item}" "${NEW_RELEASE_DIR}/${item}"
        printf "\tLinked:\t%s\n" "${item}"
    else
        printf "\tSkipped:\t%s (not found)\n" "${item}"
    fi
done
echo ""

# 6. Fix permissions BEFORE going live
printf "Fixing permissions...\n"
# We pass the NEW release directory to your script so visitors don't experience a 
# window of time where files have the wrong permissions.
# We also apply it to the shared directory to ensure uploaded/persistent files 
# have the correct ownership before swapping the symlink.
SCRIPT_DIR="$(dirname "$0")"

if [ -x "${SCRIPT_DIR}/fix-web-perms.ksh" ]; then
    "${SCRIPT_DIR}/fix-web-perms.ksh" "${SHARED_DIR}"
    "${SCRIPT_DIR}/fix-web-perms.ksh" "${NEW_RELEASE_DIR}"
elif command -v fix-web-perms.ksh >/dev/null 2>&1; then
    fix-web-perms.ksh "${SHARED_DIR}"
    fix-web-perms.ksh "${NEW_RELEASE_DIR}"
else
    # Fallback if your script isn't in the global PATH
    printf "\tWarning:\tfix-web-perms.ksh not found.\n"
    # Optional: Put fallback chmod/chown commands here
fi
echo ""

# 7. The Atomic Switch
printf "Switching live traffic...\n"
# The -sfn flags create a soft link, forcefully replacing the old one without dereferencing.
# We use a relative path here as well so OpenBSD's httpd chroot understands the path.
ln -sfn "releases/${TIMESTAMP}/public" "${SYMLINK_PATH}"
echo ""

# 8. Clean up old releases (Keep only the latest 5 to save disk space)
printf "Cleaning up old releases...\n"
OLD_RELEASES=$(ls -dt "${RELEASES_DIR}"/* 2>/dev/null | tail -n +6)
if [ -n "$OLD_RELEASES" ]; then
    echo "$OLD_RELEASES" | xargs rm -rf
fi
echo ""

LOG_TIME=$(date '+%Y-%m-%d %H:%M:%S')
printf "Successfully deployed %s! [%s]\n" "${SITE_NAME}" "${LOG_TIME}"
