#!/bin/bash
# Generate CSRs
export EASYRSA_BATCH=1

cd ~
mkdir ~/easy-rsa
ln -s /usr/share/easy-rsa/* ~/easy-rsa/
chmod 700 ~/easy-rsa
~/easy-rsa/easyrsa init-pki

cat << EOF >> ~/easy-rsa/vars
set_var EASYRSA_ALGO "ec"
set_var EASYRSA_DIGEST "sha512"
EOF

~/easy-rsa/easyrsa gen-req server nopass
sudo cp ~/pki/private/server.key /etc/openvpn/server/

mkdir -p ~/client-configs/keys
chmod -R 700 ~/client-configs

~/easy-rsa/easyrsa gen-req client nopass
cp ~/pki/private/client.key ~/client-configs/keys/

cp ~/pki/reqs/server.req ~/pki/reqs/client.req /tmp/
sudo chown ca:ca /tmp/server.req /tmp/client.req