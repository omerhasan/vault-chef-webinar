#!/usr/bin/env bash
set -e

# Update apt
echo "Updating apt cache..."
sudo apt-get -qq update

# Install vault
echo "Installing Vault..."
sudo apt-get -yqq install curl unzip
curl -sLo "vault.zip" "https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip"
unzip "vault.zip"
sudo mv "vault" "/usr/local/bin/vault"
sudo chmod +x "/usr/local/bin/vault"
sudo rm -rf "vault.zip"

# Install vault-crowdsource
echo "Installing Vault Crowdsource..."
curl -sLo "vault-crowdsource.tar.gz" "https://www.dropbox.com/s/npgsnm5xnrszzt7/vault-crowdsource_0.1.0_linux_amd64.tar.gz?dl=1"
tar -zxvf "vault-crowdsource.tar.gz"
sudo mv "vault-crowdsource" "/usr/local/bin/vault-crowdsource"
sudo chmod +x "/usr/local/bin/vault-crowdsource"
sudo rm -rf "vault-crowdsource.tar.gz"

# Set PS1
sudo tee /etc/profile.d/ps1.sh > /dev/null <<"EOF"
export PS1="\u@${hostname} > "
EOF
for d in /home/*; do
  if [ -d "$d" ]; then
    sudo tee -a $d/.bashrc > /dev/null <<"EOF"
export PS1="\u@${hostname} > "
EOF
  fi
done

# Start Vault on boot
echo "Writing Vault upstart config..."
sudo tee /etc/init/vault.conf > /dev/null <<"EOF"
description "Vault"

start on runlevel [2345]
stop on runlevel [06]

respawn

kill signal INT

env VAULT_DEV_ROOT_TOKEN_ID=root

exec /usr/local/bin/vault server \
  -dev
EOF

sleep 5
sudo service vault start

# Start Vault Crowdsource on boot
echo "Writing Vault Crowdsource upstart config..."
sudo tee /etc/init/vault-crowdsource.conf > /dev/null <<"EOF"
description "Vault Crowdsource"

start on runlevel [2345]
stop on runlevel [06]

respawn

kill signal INT

env VAULT_ADDR="http://127.0.0.1:8200"
env VAULT_TOKEN="root"
env VAULT_ENDPOINT="https://${hostname}/v1/postgresql/creds/readonly"

exec /usr/local/bin/vault-crowdsource \
  -listen=127.0.0.1:8080
EOF

sleep 5
sudo service vault-crowdsource start

echo "Installing certbot..."
pushd /usr/local/sbin
sudo curl -sLo certbot-auto https://dl.eff.org/certbot-auto
sudo chmod a+x /usr/local/sbin/certbot-auto
popd &>/dev/null

echo "Installing nginx..."
sudo apt-get -yqq install nginx

sudo tee /etc/nginx/sites-available/default > /dev/null <<"EOF"
server {
  listen 80 default_server;
  listen [::]:80 default_server ipv6only=on;

  root /usr/share/nginx/html;
  index index.html index.htm;

  location ~ /.well-known {
    allow all;
  }

  server_name localhost;

  location / {
    try_files $uri $uri/ =404;
  }
}
EOF

sudo service nginx restart

echo "Getting certificate..."
certbot-auto certonly \
  --agree-tos \
  --non-interactive \
  --quiet \
  --email "${certbot_email}" \
  --authenticator webroot \
  --webroot-path=/usr/share/nginx/html \
  --domain "${hostname}"

echo "Generating dhparam..."
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

echo "Updating default site..."
sudo tee /etc/nginx/sites-available/default > /dev/null <<"EOF"
server {
  listen 443 ssl;

  server_name ${hostname};

  ssl_certificate /etc/letsencrypt/live/${hostname}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${hostname}/privkey.pem;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_prefer_server_ciphers on;
  ssl_dhparam /etc/ssl/certs/dhparam.pem;
  ssl_ciphers 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA';
  ssl_session_timeout 1d;
  ssl_session_cache shared:SSL:50m;
  ssl_stapling on;
  ssl_stapling_verify on;

  add_header Strict-Transport-Security max-age=15768000;
  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;

  location ~ /.well-known {
    allow all;
  }

  location / {
    proxy_pass http://127.0.0.1:8200/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }

  location /app/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}

server {
  listen 80;
  server_name ${hostname};
  return 301 https://$host$request_uri;
}
EOF

sudo service nginx restart

echo "Setting up crontab..."
pushd /tmp
echo "30 2 * * 1 /usr/local/sbin/certbot-auto renew >> /var/log/le-renew.log" >> certbot-cron
echo "35 2 * * 1 /etc/init.d/nginx reload" >> certbot-cron
crontab certbot-cron
rm certbot-cron
popd &>/dev/null

echo "Done!"

echo "Setting hostname..."
echo "${hostname}" | sudo tee /etc/hostname
sudo hostname -F /etc/hostname
sudo sed -i'' '1i 127.0.0.1 ${hostname}' /etc/hosts
