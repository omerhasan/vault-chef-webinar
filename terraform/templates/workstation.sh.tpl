#!/usr/bin/env bash
set -e

# Update apt
echo "Updating apt cache..."
sudo apt-get -qq update

# Install vault
echo "Installing Vault..."
sudo apt-get -yqq install curl jq unzip vim
curl -s -L -o "vault.zip" "https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_linux_amd64.zip"
unzip "vault.zip"
sudo mv "vault" "/usr/local/bin/vault"
sudo chmod +x "/usr/local/bin/vault"
sudo rm -f "vault.zip"

# Consul Template
echo "Installing Consul Template..."
curl -s -L -o "consul-template.zip" "https://releases.hashicorp.com/consul-template/0.18.0-rc1/consul-template_0.18.0-rc1_linux_amd64.zip"
unzip "consul-template.zip"
sudo mv "consul-template" "/usr/local/bin/consul-template"
sudo chmod +x "/usr/local/bin/consul-template"
sudo rm -f "consul-template.zip"

# Chef
echo "Installing Chef..."
curl -sLo "chef.deb" "https://packages.chef.io/stable/ubuntu/12.04/chef_12.16.42-1_amd64.deb"
sudo dpkg -i chef.deb
sudo rm -f chef.deb

# Vault env
sudo tee /etc/profile.d/vault.sh > /dev/null <<"EOF"
export VAULT_ADDR="https://vault.hashicorp.rocks"
export VAULT_TOKEN="root"
EOF
source /etc/profile.d/vault.sh

# Vault Postgresql
echo "Configuring Vault (postgresql)..."
# Sleep until ready
while true; do
  vault status && break
  sleep 2
done
vault auth root
if ! vault mounts | grep postgresql; then
  vault mount postgresql
fi
vault write postgresql/config/connection \
  connection_url="postgresql://${postgres_username}:${postgres_password}@${postgres_ip}/myapp"
vault write postgresql/config/lease \
  lease=2m \
  lease_max=24h
vault write postgresql/roles/readonly \
  sql=-<<"EOF"
CREATE ROLE "{{name}}"
WITH LOGIN PASSWORD '{{password}}'
VALID UNTIL '{{expiration}}';

GRANT SELECT ON ALL TABLES IN SCHEMA public
TO "{{name}}";
EOF

# Vault AWS
echo "Configuring Vault (aws)..."
if ! vault mounts | grep aws; then
  vault mount aws
fi
vault write aws/config/root \
  access_key="${access_key}" \
  secret_key="${secret_key}" \
  region="${region}"
vault write aws/config/lease \
  lease=2m \
  lease_max=24h
vault write aws/roles/developer \
  policy=-<<"EOF"
{
  "Version": "2012-10-17",
  "Statement": {
    "Effect": "Allow",
    "Action": "iam:*",
    "Resource": "*"
  }
}
EOF

# Vault Crowdsource
echo "Configuring Vault (crowdsource app)..."
vault write sys/policy/crowdsource rules=-<<"EOF"
path "postgresql/creds/readonly" {
  capabilities = ["read"]
}
EOF

home="/home/ubuntu/chef"
cookbooks="$home/cookbooks"

sudo mkdir -p "$cookbooks/direct/recipes"
sudo tee "$cookbooks/direct/recipes/default.rb" > /dev/null <<"EOF"
file "/tmp/database.yml" do
  content <<EOH
---
postgresql:
  username: "direct-user-1234"
  password: "direct-s3cr3t"
EOH
end
EOF

sudo mkdir -p "$cookbooks/attrs/recipes"
sudo tee "$cookbooks/attrs/recipes/default.rb" > /dev/null <<"EOF"
file "/tmp/database.yml" do
  content <<EOH
---
postgresql:
  username: "#{node['postgresql']['username']}"
  password: "#{node['postgresql']['password']}"
EOH
end
EOF
sudo mkdir -p "$cookbooks/attrs/attributes"
sudo tee "$cookbooks/attrs/attributes/default.rb" > /dev/null <<"EOF"
node.default["postgresql"]["username"] = "attr-user-1234"
node.default["postgresql"]["password"] = "attr-s3cr3t"
EOF

sudo mkdir -p /etc/chef
openssl rand -base64 512 | tr -d '\r\n' > /tmp/encrypted_data_bag_secret
sudo mv /tmp/encrypted_data_bag_secret /etc/chef/encrypted_data_bag_secret
sudo mkdir -p "$home/data_bags/secrets"
sudo /opt/chef/embedded/bin/ruby <<EOF
require 'chef/encrypted_data_bag_item'
secret = Chef::EncryptedDataBagItem.load_secret('/etc/chef/encrypted_data_bag_secret')
enc = Chef::EncryptedDataBagItem.encrypt_data_bag_item({
  username: "encrypted-user-1234",
  password: "encrypted-s3cr3t",
}, secret)
enc = JSON.pretty_generate(enc).strip
File.write('$home/data_bags/secrets/postgresql.json', enc)
EOF

sudo mkdir -p "$cookbooks/encrypted-databags/recipes"
sudo tee "$cookbooks/encrypted-databags/recipes/default.rb" > /dev/null <<"EOF"
creds = data_bag_item("secrets", "postgresql")

file "/tmp/database.yml" do
  content <<EOH
---
postgresql:
  username: "#{creds['username']}"
  password: "#{creds['password']}"
EOH
end
EOF

sudo mkdir -p "$cookbooks/api/recipes"
sudo tee "$cookbooks/api/recipes/default.rb" > /dev/null <<"EOF"
remote_file '/tmp/database.json' do
  backup false
  source 'https://vault.hashicorp.rocks/v1/postgresql/creds/readonly'
  headers({
    'X-Vault-Token' => ENV['VAULT_TOKEN'],
  })
  mode '0644'
  action :create
  notifies :create, 'ruby_block[write_config]', :immediately
  not_if { File.exist?('/tmp/database.json') }
end

ruby_block 'write_config' do
  block do
    data = JSON.parse(File.read('/tmp/database.json'))["data"]
    f = "---\npostgresql:\n  username: #{data["username"]}\n  password: #{data["password"]}"
    File.write("/tmp/database.yml", f)
  end
  action :nothing
end
EOF

sudo mkdir -p "$cookbooks/ct/recipes"
sudo tee "$cookbooks/ct/recipes/default.rb" > /dev/null <<"EOF"
package 'unzip'

remote_file '/tmp/consul-template.zip' do
  source 'https://releases.hashicorp.com/consul-template/0.18.0-rc1/consul-template_0.18.0-rc1_linux_amd64.zip'
  notifies :run, 'execute[unzip-and-install]', :immediately
  not_if { File.exist?('/usr/local/bin/consul-template') }
end

execute 'unzip-and-install' do
  command 'unzip /tmp/consul-template.zip && mv consul-template /usr/local/bin/ && chmod +x /usr/local/bin/consul-template'
  action :nothing
end

directory '/etc/consul-template.d'

file '/etc/consul-template.d/config.hcl' do
  content <<EOH.strip
log_level = "debug"

template {
  contents = <<EOT
{{- with secret "postgresql/creds/readonly" -}}
---
postgresql:
  username: {{ .Data.username }}
  password: {{ .Data.password }}
{{- end -}}
EOT
  destination = "/tmp/database.yml"
}
EOH
end

file '/etc/init/consul-template.conf' do
  content <<EOH.strip
description "Consul Template"

start on runlevel [2345]
stop on runlevel [06]

respawn

kill signal INT

env VAULT_ADDR="https://vault.hashicorp.rocks"
env VAULT_TOKEN="root"

exec /usr/local/bin/consul-template \
  -config=/etc/consul-template.d
EOH
  notifies :restart, 'service[consul-template]', :delayed
end

service 'consul-template' do
  action [:enable, :start]
end
EOF

# Make me own everything
sudo chown -R ubuntu:ubuntu "$home"

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
