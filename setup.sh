#!/bin/bash

# The Domain you want your API to run on 
DOMAIN="domain.com"

# The port your API webserver is running on
API_PORT="8080"

# The directory you want to install the server in
DIRECTORY = "~/server"

# Update system and install dependencies
sudo apt-get -y update && sudo apt-get -y upgrade
sudo apt-get install -y certbot python3-certbot-nginx build-essential pkg-config cmake
sudo apt install -y python3-dev python3-venv python3-pip python3-dev gcc nginx openssl

cd $DIRECTORY

# Set up Python environment
python3 -m venv venv
source venv/bin/activate

 # If any dependencies are needed
pip install -r "requirements.txt"

# Set up Nginx configuration for your API
cat > /tmp/webserver_nginx << EOL
server {
    listen 80;
    server_name ${DOMAIN};
    
    location / {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /websocket {
        proxy_pass http://127.0.0.1:${API_PORT}/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

sudo mv /tmp/webserver_nginx /etc/nginx/sites-available/
sudo ln -sf /etc/nginx/sites-available/webserver_nginx /etc/nginx/sites-enabled/

# Remove default Nginx configuration if it exists
sudo rm -f /etc/nginx/sites-enabled/default

# Make sure Nginx is completely stopped before restarting
sudo systemctl stop nginx
sudo killall nginx || true  # Don't fail if no process is running

# Test and restart Nginx
sudo nginx -t
sudo systemctl start nginx

# Get SSL certificate with Certbot
echo "Obtaining SSL certificate for ${DOMAIN}..."
sudo certbot --nginx -d ${DOMAIN}

# Create the final SSL configuration (Certbot should have already updated the config,
# but this ensures we have the right timeouts and other settings)
cat > /tmp/fastapi_nginx_ssl << EOL
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN};
    
    # SSL certificate paths will be managed by Certbot
    
    # SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    # Extended timeouts
    proxy_read_timeout 60000;
    proxy_connect_timeout 60000s;
    proxy_send_timeout 60000s;
    
    location / {
        proxy_pass http://127.0.0.1:${API_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    location /websocket {
        proxy_pass http://127.0.0.1:${API_PORT}/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL

# Let Certbot modify the SSL configuration
sudo mv /tmp/fastapi_nginx_ssl /etc/nginx/sites-available/fastapi_nginx
sudo certbot --nginx -d ${DOMAIN}

# Final Nginx restart
sudo nginx -t && sudo systemctl restart nginx

echo "Setup complete! Your FastAPI application should be running with HTTPS at ${DOMAIN}"