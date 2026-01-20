#!/bin/bash

# Verify script is running with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run with sudo."
  echo "Try: wget -qO- wifiscript.xyz | sudo bash"
  exit 1
fi

# Detect the first available wireless interface
WLAN_INT=$(nmcli -t -f DEVICE,TYPE device | grep ":wifi" | cut -d: -f1 | head -n 1)

if [ -z "$WLAN_INT" ]; then
    echo "Error: No WiFi interface detected."
    exit 1
fi

echo "--- WiFi Setup Utility ---"
echo "Detected Interface: $WLAN_INT"

# Prompt user for network credentials
read -p "Enter Network SSID (Name): " WIFI_SSID
if [ -z "$WIFI_SSID" ]; then
    echo "SSID cannot be empty."
    exit 1
fi

echo "Select Network Type:"
echo "1) School/Enterprise (PEAP/MSCHAPv2 - No Certs)"
echo "2) Standard Home/Public (WPA2/WPA3 Personal)"
read -p "Choice [1-2]: " NET_TYPE

# Define NetworkManager connection profile path
CONN_PATH="/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"

# Backup existing configuration if present
if [ -f "$CONN_PATH" ]; then
    mv "$CONN_PATH" "${CONN_PATH}.bak"
fi

if [ "$NET_TYPE" == "1" ]; then
    # Configure Enterprise/School network (WPA-EAP)
    read -p "Enter Identity (Username): " USER_ID
    read -s -p "Enter Password: " USER_PASS
    echo ""

    cat <<EOF > "$CONN_PATH"
[connection]
id=${WIFI_SSID}
type=wifi
interface-name=${WLAN_INT}

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-eap

[802-1x]
eap=peap;
identity=${USER_ID}
password=${USER_PASS}
phase2-auth=mschapv2
system-ca-certs=false

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF

else
    # Configure Standard Home/Public network (WPA-PSK)
    read -s -p "Enter WiFi Password: " USER_PASS
    echo ""

    cat <<EOF > "$CONN_PATH"
[connection]
id=${WIFI_SSID}
type=wifi
interface-name=${WLAN_INT}

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
auth-alg=open
key-mgmt=wpa-psk
psk=${USER_PASS}

[ipv4]
method=auto

[ipv6]
method=auto
addr-gen-mode=stable-privacy
EOF
fi

# Secure configuration file permissions
echo "Securing connection file..."
chmod 600 "$CONN_PATH"

# Reload and apply the new connection
echo "Reloading NetworkManager..."
nmcli connection reload

echo "Attempting to connect to $WIFI_SSID..."
if nmcli connection up "${WIFI_SSID}" timeout 20; then
    echo "Successfully connected to ${WIFI_SSID}!"
    
    # Synchronize system clock after establishing connection
    echo "Syncing system clock to current time..."
    
    # Enable Network Time Protocol (NTP) sync
    timedatectl set-ntp true 2>/dev/null
    
    # Force clock synchronization via HTTP header if NTP is restricted
    date -s "$(curl -sD - http://google.com | grep '^Date:' | cut -d' ' -f3-6)Z" > /dev/null 2>&1
    
    echo "Current system time is now: $(date)"
else
    echo "Failed to connect. Please check credentials."
fi