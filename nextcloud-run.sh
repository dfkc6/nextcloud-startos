#!/bin/bash

set -ea

# Environment Variables
LAN_ADDRESS=$(yq e '.lan-address' /root/start9/config.yaml)
TOR_ADDRESS=$(yq e '.tor-address' /root/start9/config.yaml)
SERVICE_ADDRESS='nextcloud.embassy'
PGDATA="/var/lib/postgresql/15"
POSTGRES_CONFIG="/etc/postgresql/15"
NEXTCLOUD_TRUSTED_DOMAINS="$TOR_ADDRESS $LAN_ADDRESS $SERVICE_ADDRESS"
TRUSTED_PROXIES="$TOR_ADDRESS $LAN_ADDRESS $SERVICE_ADDRESS"
FILE="/var/www/html/config/config.php"
NEXTCLOUD_ADMIN_USER='admin'
PASSWORD_FILE="/root/start9/password.dat"

# User Config
DEFAULT_LOCALE=$(yq e '.default-locale' /root/start9/config.yaml)
DEFAULT_PHONE_REGION=$(yq e '.default-phone-region' /root/start9/config.yaml)

# Properties Page
cat <<EOP > /root/start9/stats.yaml
version: 2
data:
  Admin Username:
    type: string
    value: "$NEXTCLOUD_ADMIN_USER"
    description: The admin username for Nextcloud
    copyable: true
    masked: false
    qr: false
  Admin Password:
    type: string
    value: "$NEXTCLOUD_ADMIN_PASSWORD"
    description: The default admin password for Nextcloud. If this password is changed inside the Nextcloud service, the change will not be reflected here. You will no longer be able to login with the default password. To reset to the default password, use the "Reset Password" Action.
    copyable: true
    masked: true
    qr: false
  WebDAV Base LAN URL:
    type: string
    value: "$LAN_ADDRESS/remote.php/dav/"
    description: Address for WebDAV syncing over LAN
    copyable: true
    masked: false
    qr: true
  WebDAV Base Tor URL:
    type: string
    value: "$TOR_ADDRESS/remote.php/dav/"
    description: Address for WebDAV syncing over Tor
    copyable: true
    masked: false
    qr: true
EOP

# Start Postgres
rm $PGDATA/postmaster.pid
echo "Starting PostgreSQL db server..."
sudo -u postgres pg_ctl start -D $PGDATA &

# Wait until Postgres is ready
echo "Waiting for Postgres to be ready..."
while ! su - postgres -c "pg_isready"; do
  sleep 1
done

# Modify config.php, add default locale settings from user config, and turn off UI update checker
sed -i "s/'overwrite\.cli\.url' => \c/'overwrite\.cli\.url' => 'https\:\/\/$LAN_ADDRESS'\,/" $FILE
sed -i "/'default_locale' => .*/d" $FILE
sed -i "/'default_phone_region' => .*/d" $FILE
sed -i "/'updatechecker' => .*/d" $FILE
sed -i "/'trusted_domains' => .*/d" $FILE
sed -i "/);/d" $FILE
echo "  'overwriteprotocol' => 'https',
'trusted_domains' => '$NEXTCLOUD_TRUSTED_DOMAINS',
'check_for_working_wellknown_setup' => true,
'updatechecker' => false,
'default_locale' => '$DEFAULT_LOCALE',
'default_phone_region' => '$DEFAULT_PHONE_REGION',
);" >> $FILE

# Start nginx web server
echo "Starting nginx server..."
nginx -g "daemon off;" &

# Start Nextcloud
echo "Starting Nextcloud frontend..."
/entrypoint.sh php-fpm
busybox crond -f -l 0 -L /dev/stdout &

touch /usr/local/bin/running