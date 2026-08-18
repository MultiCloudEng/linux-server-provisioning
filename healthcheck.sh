#!/bin/bash

echo "=== Server Health Check ==="
echo "Date: $(date)"

echo ""
echo "--- Disk Usage ---"
df -h /

echo ""
echo "--- Memory Usage ---"
free -h

echo ""
echo "--- Nginx Status ---"
systemctl is-active nginx

