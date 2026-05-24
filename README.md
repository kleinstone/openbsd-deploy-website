# OpenBSD Atomic Web Deployment Scripts

This directory contains scripts to facilitate **Zero-Downtime (Atomic) Deployments** for web applications on OpenBSD using `httpd`.

## The Concept: Atomic Deployments
Instead of copying new files directly over the live website (which causes broken pages and missing assets for users currently browsing the site), this script uses a **Symlink Release Strategy**.

1. **Isolation**: New code is copied to a brand new, timestamped folder inside `releases/`.
2. **Preparation**: Permissions are strictly locked down on the new code *before* it goes live. Persistent files (like configs and uploads) are symlinked in.
3. **The Atomic Swap**: The live `public` symlink is instantly swapped to point to the new release folder. The web server sees the new files immediately, with zero downtime.

## Directory Structure
After your first deployment, your web root (e.g., `/var/www/htdocs/example.com/`) will look like this:

```text
example.com/
├── public -> releases/20231024203700/public  # Live symlink
├── releases/                                 # Contains the last 5 deployments
│   ├── 20231024190000/
│   └── 20231024203700/
│       ├── public/                           # App web root
│       └── config -> ../../shared/config     # Symlink to persistent config
└── shared/                                   # Persistent data across deployments
    ├── config/
    ├── uploads/
    └── .env
```

## Setup & Usage

### 1. Initial Setup (Shared Resources)
Before your first deploy, move any persistent configuration files, environment variables, or upload directories into the `shared/` folder. This keeps them safe and prevents them from being overwritten.

```bash
doas mkdir -p /var/www/htdocs/example.com/shared
doas mv /var/www/htdocs/example.com/config /var/www/htdocs/example.com/shared/config
```

### 2. Deploying
To deploy your application, upload your entire application folder (not just the public web root) to your server, then run:

```bash
doas ./deploy.ksh example.com ~/xfer
```

*Note: Any `config/`, `uploads/`, etc. directories included in `~/xfer` will be safely ignored/replaced with symlinks to your `shared/` directory during the deployment.*

### 3. Fast Rollbacks
If a deployment breaks your site, you can instantly roll back to the previous version by updating the symlink manually:

```bash
cd /var/www/htdocs/example.com/
# Find the previous timestamp in the releases directory
ls -l releases/
# Update the symlink
doas ln -sfn releases/PREVIOUS_TIMESTAMP/public public
```

## OpenBSD `httpd` Chroot Note
OpenBSD's `httpd` runs in a chroot jail (defaulting to `/var/www`). Because of this, absolute symlinks (e.g., `/var/www/htdocs/...`) will break when `httpd` tries to read them. These scripts explicitly use **relative symlinks** (e.g., `../../shared/config` and `releases/TIMESTAMP/public`) so that the paths remain valid both inside and outside the chroot.