#!/bin/bash
# TOOLKIT_NAME: Wi-Fi Password
# TOOLKIT_DESC: Show the password for your current Wi-Fi network
# TOOLKIT_KEY: 2

SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/ SSID/ {print $NF}')

if [[ -z "$SSID" ]]; then
    echo "Not connected to Wi-Fi."
    exit 1
fi

echo "Current network: $SSID"
echo ""
echo "Fetching password from Keychain (you may be prompted to allow access)..."
echo ""

PASS=$(security find-generic-password -D "AirPort network password" -a "$SSID" -w 2>/dev/null)

if [[ -n "$PASS" ]]; then
    echo "Password: $PASS"
else
    echo "Could not retrieve password. You may need to allow Keychain access."
fi
