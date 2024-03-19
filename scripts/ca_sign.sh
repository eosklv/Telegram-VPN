#!/bin/bash
# Import and sign CSRs
export EASYRSA_BATCH=1
cd ~
~/easy-rsa/easyrsa import-req /tmp/server.req server

~/easy-rsa/easyrsa sign-req server server
sudo cp ~/pki/issued/server.crt ~/pki/ca.crt /etc/openvpn/server/

~/easy-rsa/easyrsa import-req /tmp/client.req client

~/easy-rsa/easyrsa sign-req client client
cp ~/pki/issued/client.crt /tmp/
sudo chown ovpn:ovpn /tmp/client.crt