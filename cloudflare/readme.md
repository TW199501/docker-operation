Container Cloudflare Tunnel
A Docker Compose container setup for a Cloudflare Tunnel. This setup allows you to securely expose a local service to the internet using Cloudflare's infrastructure.

Table of Contents
Introduction
Cloudflare Tunnel provides a secure way to expose a web server running on your local network to the public internet. This can be particularly useful for development, accessing internal services remotely, or securely publishing a service without opening ports on your router. The container in this project sets up a Cloudflare Tunnel, making it simple to deploy.

Setup
Requirements
Docker
Docker Compose
This setup assumes that Cloudflare is the DNS provider for your domain.

Environment Variables
Add the missing information for the environment variables in the .env file:

CLOUDFLARE_TUNNEL_TOKEN=''
CLOUDFLARE_TUNNEL_TOKEN: This token is provided by Cloudflare when you create a new tunnel. Replace '' with your actual token.
How to Obtain the Cloudflare Tunnel Token
To get the Cloudflare Tunnel token, follow these steps:

Log in to your Cloudflare Dashboard.
Navigate to the Zero Trust section or Access section (depending on the Cloudflare interface).
Select Tunnels from the navigation menu.
Click on Create a Tunnel.
Follow the on-screen instructions to name your tunnel and select your desired configuration.
Once the tunnel is created, Cloudflare will provide a Tunnel Token. Copy this token and paste it into the .env file under CLOUDFLARE_TUNNEL_TOKEN.
Make sure to edit the .env file and add your specific token:

nano .env
To prevent .env from being tracked by version control, run the following command:

git update-index --assume-unchanged .env
Hosts Configuration
Modify the hosts file if needed to define any custom hostname mappings:

nano config/hosts
Add any additional hosts that need to be mapped within the container. To avoid tracking changes to this file, run:

git update-index --assume-unchanged config/hosts

Usage
Starting the Container
To start the Cloudflare Tunnel container, run:

docker compose up -d
This command will start the container in detached mode.

Stopping the Container
To stop the running container, use:

docker compose down
Viewing Logs
To view the logs for the running container, which can help with troubleshooting:

docker logs cloudflare-tunnel
Cleanup
If you want to remove all containers, networks, and associated volumes:

docker compose down --volumes --remove-orphans