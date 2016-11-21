#!/usr/bin/env bash
set -e

# Get the current IP
PRIVATE_IP=$(ifconfig eth0 | grep "inet addr" | awk '{ print substr($2,6) }')

# Install and configure postgresql
echo "Installing and configuring postgresql..."
curl -s https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get -yqq update
sudo apt-get -yqq install postgresql postgresql-contrib
sudo tee /etc/postgresql/*/main/pg_hba.conf > /dev/null <<"EOF"
local   all             postgres                                trust
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
host    all             all             ${cidr_block}           md5
EOF
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '$$PRIVATE_IP'/" /etc/postgresql/*/main/postgresql.conf
sudo service postgresql restart
psql -U postgres -c "CREATE DATABASE myapp;"
psql -U postgres -c "CREATE ROLE \"${username}\" WITH SUPERUSER LOGIN PASSWORD '${password}';"

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

echo "Setting hostname..."
echo "${hostname}" | sudo tee /etc/hostname
sudo hostname -F /etc/hostname
sudo sed -i'' '1i 127.0.0.1 ${hostname}' /etc/hosts
