USE_SSL=false
USE_DOMAIN=false
FQDN=$(curl -s https://ip.thomascaptein.nl)
echo "By using this script with SSL, you automatically agree to the terms and conditions of Let's Encrypt."

cerbot_usage() {
    sudo apt update
    sudo apt install -y certbot
    if dpkg -s nginx &>/dev/null; then
        sudo apt install -y python3-certbot-nginx
        certbot certonly --non-interactive --agree-tos --email $EMAIL --nginx -d $FQDN
    elif dpkg -s apache2 &>/dev/null; then
        sudo apt install -y python3-certbot-apache
        certbot certonly --non-interactive --agree-tos --email $EMAIL --apache -d $FQDN
    else
        certbot certonly --non-interactive --agree-tos --email $EMAIL --standalone -d $FQDN
    fi
}

domain_usage() {
    echo "Do you want wings installed on a domain (y/n)"
    read USE_DOMAIN_CHOICE
    if [ "$USE_DOMAIN_CHOICE" == "y" ]; then
        USE_DOMAIN=true
        echo "On which domain name should this wings be installed? (FQDN)"
        read FQDN
        certbot_usage
    elif [ "$USE_DOMAIN_CHOICE" == "Y" ]; then
        USE_DOMAIN=true
        echo "On which domain name should this panel be installed? (FQDN)"
        read FQDN
        certbot_usage
    elif [ "$USE_DOMAIN_CHOICE" == "n" ]; then
        USE_DOMAIN=false
    elif [ "$USE_DOMAIN_CHOICE" == "N" ]; then
        USE_DOMAIN=false
    else
        echo "Answer not found, no domain will be used."
        USE_DOMAIN=false
    fi
}

installing_docker() {
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
}

start_docker_on_boot() {
    systemctl enable docker
}

installing_wings() {
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
}

daemonizing() {
    curl -o /etc/systemd/system/wings.service https://raw.githubusercontent.com/Thomas5300/Pterodactyl-installation-script/main/configurations/wings.service
    systemctl enable --now wings
}

install_wings() {
    domain_usage
    installing_docker
    start_docker_on_boot
    installing_wings
    daemonizing
}

install_wings
