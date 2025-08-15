#!/bin/bash
# Emergency Recovery Script for Raspberry Pi
# Use this when you can only access via SSH and need to restore VNC/WiFi

echo "========================================="
echo "EMERGENCY RASPBERRY PI RECOVERY"
echo "========================================="
echo "This script will attempt to restore VNC and WiFi connectivity"
echo ""

# Immediate fixes - run these first
immediate_fixes() {
    echo "Applying immediate fixes..."
    
    # Enable SSH (should already be working if you're running this)
    sudo systemctl enable ssh
    sudo systemctl start ssh
    
    # Enable VNC
    sudo systemctl enable vncserver-x11-serviced
    sudo systemctl start vncserver-x11-serviced
    sudo raspi-config nonint do_vnc 0
    
    # Ensure WiFi interface is up
    sudo ip link set wlan0 up
    
    # Restart essential services
    sudo systemctl restart dhcpcd
    sudo systemctl restart wpa_supplicant
    sudo systemctl restart networking
    
    echo "✓ Immediate fixes applied"
}

# Check what might have broken VNC/WiFi
diagnose_issues() {
    echo ""
    echo "Diagnosing potential issues..."
    echo "=============================="
    
    # Check if VNC is running
    if sudo systemctl is-active --quiet vncserver-x11-serviced; then
        echo "✓ VNC service is running"
    else
        echo "✗ VNC service is NOT running"
        echo "  Attempting to start VNC..."
        sudo systemctl start vncserver-x11-serviced
    fi
    
    # Check WiFi interface
    if ip link show wlan0 > /dev/null 2>&1; then
        echo "✓ WiFi interface exists"
        
        # Check if it's up
        if ip link show wlan0 | grep -q "state UP"; then
            echo "✓ WiFi interface is UP"
        else
            echo "✗ WiFi interface is DOWN"
            echo "  Bringing WiFi interface up..."
            sudo ip link set wlan0 up
        fi
    else
        echo "✗ WiFi interface not found"
    fi
    
    # Check wpa_supplicant config
    if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        echo "✓ WiFi configuration file exists"
        
        # Count configured networks
        network_count=$(grep -c "network={" /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null || echo "0")
        echo "  Configured networks: $network_count"
        
        if [ "$network_count" -eq 0 ]; then
            echo "⚠ No WiFi networks configured"
        fi
    else
        echo "✗ WiFi configuration file missing"
        echo "  Creating basic configuration..."
        create_basic_wifi_config
    fi
    
    # Check if connected to WiFi
    if iwconfig wlan0 2>/dev/null | grep -q "ESSID:"; then
        current_ssid=$(iwconfig wlan0 2>/dev/null | grep "ESSID:" | awk -F'"' '{print $2}')
        echo "✓ Connected to WiFi: $current_ssid"
    else
        echo "✗ Not connected to any WiFi network"
    fi
    
    # Check IP address
    wifi_ip=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$wifi_ip" ]; then
        echo "✓ WiFi IP address: $wifi_ip"
    else
        echo "✗ No IP address on WiFi interface"
    fi
}

# Create basic WiFi configuration
create_basic_wifi_config() {
    sudo tee /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null << 'EOF'
country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
    echo "✓ Basic WiFi configuration created"
}

# Interactive WiFi setup
setup_wifi_interactive() {
    echo ""
    echo "WiFi Network Setup"
    echo "=================="
    
    # Scan for networks
    echo "Scanning for available networks..."
    available_networks=$(sudo iwlist wlan0 scan 2>/dev/null | grep "ESSID:" | sed 's/.*ESSID:"\([^"]*\)".*/\1/' | grep -v "^$" | sort | uniq)
    
    if [ -n "$available_networks" ]; then
        echo "Available networks:"
        echo "$available_networks" | nl -w2 -s') '
        echo ""
    fi
    
    read -p "Enter your WiFi network name (SSID): " ssid
    if [ -z "$ssid" ]; then
        echo "SSID cannot be empty"
        return 1
    fi
    
    read -s -p "Enter WiFi password: " password
    echo ""
    
    if [ -z "$password" ]; then
        echo "Password cannot be empty"
        return 1
    fi
    
    # Add network to configuration
    echo "Adding WiFi network..."
    
    # Backup current config
    sudo cp /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.emergency_backup 2>/dev/null || true
    
    # Add network
    wpa_passphrase "$ssid" "$password" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf > /dev/null
    
    # Restart services
    echo "Restarting WiFi services..."
    sudo systemctl restart wpa_supplicant
    sudo systemctl restart dhcpcd
    
    # Wait for connection
    echo "Attempting to connect (this may take up to 30 seconds)..."
    for i in {1..30}; do
        if iwconfig wlan0 2>/dev/null | grep -q "ESSID:\"$ssid\""; then
            echo "✓ Successfully connected to $ssid!"
            
            # Get IP address
            sleep 5  # Wait for DHCP
            new_ip=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
            if [ -n "$new_ip" ]; then
                echo "✓ IP address obtained: $new_ip"
                echo ""
                echo "You should now be able to connect via VNC to: $new_ip"
                return 0
            fi
        fi
        echo -n "."
        sleep 1
    done
    
    echo ""
    echo "⚠ Connection failed. Please check:"
    echo "  - Network name is correct"
    echo "  - Password is correct"
    echo "  - Network is in range and working"
}

# Show final status and instructions
show_final_status() {
    echo ""
    echo "========================================="
    echo "RECOVERY STATUS"
    echo "========================================="
    
    # VNC Status
    if sudo systemctl is-active --quiet vncserver-x11-serviced; then
        echo "✓ VNC Server: RUNNING"
    else
        echo "✗ VNC Server: NOT RUNNING"
    fi
    
    # WiFi Status
    wifi_ip=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$wifi_ip" ]; then
        echo "✓ WiFi: CONNECTED ($wifi_ip)"
        current_ssid=$(iwconfig wlan0 2>/dev/null | grep "ESSID:" | awk -F'"' '{print $2}')
        echo "  Network: $current_ssid"
    else
        echo "✗ WiFi: NOT CONNECTED"
    fi
    
    # SSH Status
    if sudo systemctl is-active --quiet ssh; then
        echo "✓ SSH: RUNNING"
    else
        echo "✗ SSH: NOT RUNNING"
    fi
    
    echo ""
    echo "========================================="
    echo "NEXT STEPS"
    echo "========================================="
    
    if [ -n "$wifi_ip" ]; then
        echo "1. Try connecting via VNC to: $wifi_ip"
        echo "2. Use VNC port 5900 (default)"
        echo "3. If VNC still doesn't work, try rebooting:"
        echo "   sudo reboot"
    else
        echo "1. WiFi is not connected. Run this script again to set up WiFi"
        echo "2. Or manually configure WiFi using raspi-config:"
        echo "   sudo raspi-config"
    fi
    
    echo ""
    echo "If you need to run this script again:"
    echo "bash emergency_recovery.sh"
}

# Main execution
main() {
    immediate_fixes
    diagnose_issues
    
    echo ""
    read -p "Would you like to set up WiFi now? (y/n): " setup_wifi
    if [[ $setup_wifi =~ ^[Yy]$ ]]; then
        setup_wifi_interactive
    fi
    
    show_final_status
}

# Run main function
main

echo ""
echo "Emergency recovery script completed."
echo "If you're still having issues, try rebooting: sudo reboot"