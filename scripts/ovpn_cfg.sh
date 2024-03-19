#!/bin/bash
# Configuring and launching OpenVPN Server, uploading VPN profile
openvpn --genkey secret ~/easy-rsa/ta.key
sudo cp ~/easy-rsa/ta.key /etc/openvpn/server/

cp ~/easy-rsa/ta.key /tmp/client.crt ~/client-configs/keys/
sudo cp /etc/openvpn/server/ca.crt ~/client-configs/keys/
sudo chown ovpn.ovpn ~/client-configs/keys/*

sudo aws s3 cp s3://esklv-vpn/configs/server.conf /etc/openvpn/server/

sudo sed -i 's/#\(net.ipv4.ip_forward\)/\1/' /etc/sysctl.conf
sudo sysctl -p

sudo systemctl -f enable openvpn-server@server.service
sudo systemctl start openvpn-server@server.service

mkdir -p ~/client-configs/files
aws s3 cp s3://esklv-vpn/configs/base.conf ~/client-configs/
ip_address=`curl ipinfo.io/ip`
sed -i "s/my-server-1/${ip_address}/" ~/client-configs/base.conf

KEY_DIR=~/client-configs/keys
OUTPUT_DIR=~/client-configs/files
BASE_CONFIG=~/client-configs/base.conf
 
cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${KEY_DIR}/client.crt \
    <(echo -e '</cert>\n<key>') \
    ${KEY_DIR}/client.key \
    <(echo -e '</key>\n<tls-crypt>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-crypt>') \
    > ${OUTPUT_DIR}/client.ovpn

aws s3 cp ~/client-configs/files/client.ovpn s3://esklv-vpn/profiles/