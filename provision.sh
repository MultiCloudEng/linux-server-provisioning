#!/bin/bash
echo "Starting server provisioning..."
sudo apt update
sudo apt install nginx -y


echo "Configuring firewall..."
sudo ufw allow 22
sudo ufw allow 80
sudo ufw --force enable


echo "Creating custom homepage..."
echo "<h1>Provisioned by Asadbek's script</h1>" | sudo tee /var/www/html/index.nginx-debian.html


echo "Provisioning complete!"
