#!/bin/ksh

# This script strictly locks down web application permissions.
# When used alongside deploy.ksh, it prepares the isolated release directory 
# *before* the atomic symlink swap, ensuring visitors never see broken permissions.

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION ---
# Use environment variables if set, otherwise fallback to defaults
WEB_USER="${WEB_USER:-www}"
WEB_GROUP="${WEB_GROUP:-www}"
BASE_DIR="${BASE_DIR:-/var/www/htdocs}"
# ---------------------

LOG_TIME=$(date '+%Y-%m-%d %H:%M:%S')

usage() {
    echo "Usage: $0 [DIRECTORY]"
    echo "Fixes file and directory permissions for web deployments."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo ""
    echo "Environment Variables:"
    echo "  WEB_USER      User to own the files (default: ${WEB_USER})"
    echo "  WEB_GROUP     Group to own the files (default: ${WEB_GROUP})"
    echo "  BASE_DIR      Base directory for sites (default: /var/www/htdocs)"
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
    exit 0
fi

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[$LOG_TIME] ❌ Error: This script must be run as root." >&2
    exit 1
fi

echo "----------------------------------------------------------------------"
echo "[$LOG_TIME] 🔒 Starting permissions fix for web directories"
echo "[$LOG_TIME] 👤 Using User: ${WEB_USER} | 👥 Group: ${WEB_GROUP}"
echo "----------------------------------------------------------------------"

TARGET_DIR="${1:-$BASE_DIR}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "[$LOG_TIME] ❌ Error: Directory '$TARGET_DIR' does not exist." >&2
    exit 1
fi

fix_permissions() {
    local site_dir="$1"
    echo "  -> 📁 Processing: ${site_dir}"

    # 1. Set ownership
    chown -R "${WEB_USER}:${WEB_GROUP}" "${site_dir}"

    # 2. Fix directory permissions (755)
    find "${site_dir}" -type d -exec chmod 755 {} +

    # 3. Fix file permissions (644)
    find "${site_dir}" -type f -exec chmod 644 {} +

    # 4. Lock down sensitive configuration files and directories
    if [ -d "${site_dir}/config" ]; then
        # Appending a trailing slash (config/) is crucial here. Since config is often 
        # a symlink pointing to the shared directory, the slash forces 'find' to traverse it.
        find "${site_dir}/config/" -exec chown "${WEB_USER}:${WEB_GROUP}" {} +
        find "${site_dir}/config/" -type d -exec chmod 750 {} +
        find "${site_dir}/config/" -type f -exec chmod 640 {} +
    fi
    
    # Specifically protect common environment/hidden configuration files
    find "${site_dir}" -type f -name ".env*" -exec chmod 640 {} +

    echo "  -> ✅ Permissions successfully reset for $(basename "${site_dir}")"
}

if [ -n "$1" ]; then
    # Process a single specific directory provided as an argument
    fix_permissions "$TARGET_DIR"
else
    # Loop through each site directory inside the base directory
    for site_dir in "${TARGET_DIR}"/*; do
        # Handle case where directory is empty (glob returns literal '*')
        [ -e "$site_dir" ] || continue

        # Check if it's a directory (removed strict check for 'public' folder 
        # to make the script more generic for all web deployments)
        if [ -d "${site_dir}" ] && [ ! -L "${site_dir}" ]; then
            fix_permissions "${site_dir}"
        fi
    done
fi

echo "----------------------------------------------------------------------"
echo "[$LOG_TIME] ✨ All done! Web file permissions are secure."
echo "----------------------------------------------------------------------"
