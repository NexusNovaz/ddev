#!/bin/bash
set -euo pipefail

# Script to properly reconcile PHP 8.5 configs
# Takes upstream PHP 8.5 defaults and applies only DDEV value changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_BASE="${SCRIPT_DIR}/php-configs/upstream-php8.5/php/8.5"
TARGET_BASE="${SCRIPT_DIR}/etc/php/8.5"

if [ ! -d "$UPSTREAM_BASE" ]; then
    echo "ERROR: Upstream PHP 8.5 configs not found at $UPSTREAM_BASE"
    echo "Please run ./extract-php-configs.sh first"
    exit 1
fi

echo "=== PHP 8.5 Configuration Reconciliation ==="
echo "Upstream source: $UPSTREAM_BASE"
echo "Target: $TARGET_BASE"
echo ""

# Backup current configs
BACKUP_DIR="${SCRIPT_DIR}/php85-backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup at: $BACKUP_DIR"
cp -r "$TARGET_BASE" "$BACKUP_DIR"

# Function to apply DDEV customizations to a php.ini file
apply_ddev_customizations_ini() {
    local file=$1
    echo "  Applying DDEV customizations to $file..."

    # Resource limits
    sed -i.bak 's/^max_execution_time = 30$/max_execution_time = 600/' "$file"
    sed -i.bak 's/^max_input_time = 60$/max_input_time = -1/' "$file"
    sed -i.bak 's/^;max_input_vars = 1000$/max_input_vars = 5000/' "$file"
    sed -i.bak 's/^post_max_size = 8M$/post_max_size = 100M/' "$file"
    sed -i.bak 's/^upload_max_filesize = 2M$/upload_max_filesize = 100M/' "$file"

    # Error reporting
    sed -i.bak 's/^error_reporting = E_ALL & ~E_DEPRECATED$/error_reporting = E_ALL/' "$file"
    sed -i.bak 's/^display_errors = Off$/display_errors = On/' "$file"
    sed -i.bak 's/^display_startup_errors = Off$/display_startup_errors = On/' "$file"
    sed -i.bak 's/^;html_errors = On$/html_errors = On/' "$file"

    # Mailpit
    sed -i.bak 's|^;sendmail_path =$|sendmail_path="/usr/local/bin/mailpit sendmail -t --smtp-addr 127.0.0.1:1025"|' "$file"

    # OpCache
    sed -i.bak 's/^;opcache.enable=1$/opcache.enable=1/' "$file"
    sed -i.bak 's/^;opcache.enable_cli=0$/opcache.enable_cli=1/' "$file"
    sed -i.bak 's/^;opcache.memory_consumption=128$/opcache.memory_consumption=500/' "$file"
    sed -i.bak 's/^;opcache.interned_strings_buffer=8$/opcache.interned_strings_buffer=16/' "$file"
    sed -i.bak 's/^;opcache.max_accelerated_files=10000$/opcache.max_accelerated_files=1000000/' "$file"
    sed -i.bak 's/^;opcache.revalidate_freq=2$/opcache.revalidate_freq=0/' "$file"

    # For CLI, memory limit is already -1 by default, but let's be explicit
    if echo "$file" | grep -q "/cli/"; then
        sed -i.bak 's/^memory_limit = -1$/memory_limit = -1/' "$file"
    fi

    rm -f "$file.bak"
}

# Function to apply DDEV customizations to FPM pool config
apply_ddev_customizations_pool() {
    local file=$1
    echo "  Applying DDEV customizations to $file..."

    # User/group
    sed -i.bak 's/^user = www-data$/;user = www-data/' "$file"
    sed -i.bak 's/^group = www-data$/;group = www-data/' "$file"

    # Listen socket
    sed -i.bak 's|^listen = /run/php/php8.5-fpm.sock$|listen = /run/php-fpm.sock|' "$file"

    # Listen permissions
    sed -i.bak 's/^listen.owner = www-data$/; listen.owner = www-data/' "$file"
    sed -i.bak 's/^listen.group = www-data$/; listen.group = www-data/' "$file"
    sed -i.bak 's/^;listen.mode = 0660$/listen.mode = 0666/' "$file"

    # PM settings
    sed -i.bak 's/^pm.max_children = 5$/pm.max_children = 8/' "$file"
    sed -i.bak 's/^pm.start_servers = 2$/pm.start_servers = 3/' "$file"
    sed -i.bak 's/^pm.min_spare_servers = 1$/pm.min_spare_servers = 2/' "$file"
    sed -i.bak 's/^pm.max_spare_servers = 3$/pm.max_spare_servers = 4/' "$file"
    sed -i.bak 's/^;pm.max_requests = 500$/pm.max_requests = 200/' "$file"

    # Status
    sed -i.bak 's|^;pm.status_path = /status$|pm.status_path = /phpstatus|' "$file"

    # Worker output
    sed -i.bak 's/^;catch_workers_output = yes$/catch_workers_output = yes/' "$file"
    sed -i.bak 's/^;decorate_workers_output = no$/decorate_workers_output = no/' "$file"
    sed -i.bak 's/^;clear_env = no$/clear_env = no/' "$file"

    rm -f "$file.bak"
}

# Copy upstream files and apply customizations
echo ""
echo ">>> Reconciling CLI php.ini..."
cp "$UPSTREAM_BASE/cli/php.ini" "$TARGET_BASE/cli/php.ini"
apply_ddev_customizations_ini "$TARGET_BASE/cli/php.ini"

echo ""
echo ">>> Reconciling FPM php.ini..."
cp "$UPSTREAM_BASE/fpm/php.ini" "$TARGET_BASE/fpm/php.ini"
apply_ddev_customizations_ini "$TARGET_BASE/fpm/php.ini"

echo ""
echo ">>> Reconciling FPM php-fpm.conf..."
cp "$UPSTREAM_BASE/fpm/php-fpm.conf" "$TARGET_BASE/fpm/php-fpm.conf"
# No DDEV customizations needed for php-fpm.conf

echo ""
echo ">>> Reconciling FPM pool.d/www.conf..."
cp "$UPSTREAM_BASE/fpm/pool.d/www.conf" "$TARGET_BASE/fpm/pool.d/www.conf"
apply_ddev_customizations_pool "$TARGET_BASE/fpm/pool.d/www.conf"

echo ""
echo ">>> Copying mods-available (DDEV-managed extensions only)..."
# Only copy the 4 extensions DDEV manages
for ext in assert blackfire xdebug xhprof; do
    if [ -f "$TARGET_BASE/mods-available/${ext}.ini" ]; then
        echo "  Keeping DDEV-managed: ${ext}.ini"
    fi
done

echo ""
echo "=== Reconciliation Complete ==="
echo ""
echo "Changes:"
echo "- Upstream PHP 8.5 base configs copied"
echo "- DDEV value customizations applied"
echo "- PHP 8.5 comments preserved"
echo "- Backup saved to: $BACKUP_DIR"
echo ""
echo "Next steps:"
echo "1. Review changes: git diff etc/php/8.5/"
echo "2. Test with PHP 8.5 container"
echo "3. Delete backup if satisfied: rm -rf $BACKUP_DIR"