OS=$(lsb_release -i | awk '{print $3}')
VERSION=$(lsb_release -rs)
FQDN=$(curl -s https://ip.thomascaptein.nl)
USE_SSL=false
USE_DOMAIN=false
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
disk_space=$(df -B MB / | tail -n 1 | awk '{print $2}')

echo "By using this script with SSL, you automatically agree to the terms and conditions of Let's Encrypt."

domain_usage() {
    echo "Do you want pterodactyl installed on a domain (y/n)"
    read USE_DOMAIN_CHOICE
    if [ "$USE_DOMAIN_CHOICE" == "y" ]; then
        USE_DOMAIN=true
        echo "On which domain name should this panel be installed? (FQDN)"
        read FQDN
        echo "Do you want SSL on this domain? (IPs cannot have SSL!) (y/n)"
        read USE_SSL_CHOICE
        if [ "$USE_SSL_CHOICE" == "y" ]; then
            USE_SSL=true
        elif [ "$USE_SSL_CHOICE" == "Y" ]; then
            USE_SSL=true
        elif [ "$USE_SSL_CHOICE" == "n" ]; then
            USE_SSL=false
        elif [ "$USE_SSL_CHOICE" == "N" ]; then
            USE_SSL=false
        else
            echo "Answer not found, no SSL will be used."
            USE_SSL=false
        fi
    elif [ "$USE_DOMAIN_CHOICE" == "Y" ]; then
        USE_DOMAIN=true
        echo "On which domain name should this panel be installed? (FQDN)"
        read FQDN
        echo "Do you want SSL on this domain? (IPs cannot have SSL!) (y/n)"
        read USE_SSL_CHOICE
        if [ "$USE_SSL_CHOICE" == "y" ]; then
            USE_SSL=true
        elif [ "$USE_SSL_CHOICE" == "Y" ]; then
            USE_SSL=true
        elif [ "$USE_SSL_CHOICE" == "n" ]; then
            USE_SSL=false
        elif [ "$USE_SSL_CHOICE" == "N" ]; then
            USE_SSL=false
        else
            echo "Answer not found, no SSL will be used."
            USE_SSL=false
        fi
    elif [ "$USE_DOMAIN_CHOICE" == "n" ]; then
        USE_DOMAIN=false
    elif [ "$USE_DOMAIN_CHOICE" == "N" ]; then
        USE_DOMAIN=false
    else
        echo "Answer not found, no domain will be used."
        USE_DOMAIN=false
    fi
}

email_usage() {
    echo "What is your email address? (This is used for SSL & your panel account)"
    read EMAIL
}

phpmyadmin_usage() {
    echo "Do you want phpmyadmin installed? (y/n)"
    read PHPMYADMIN_CHOICE
    if [ "$PHPMYADMIN_CHOICE" == "y" ]; then
        PHPMYADMIN=true
    elif [ "$PHPMYADMIN_CHOICE" == "Y" ]; then
        PHPMYADMIN=true
    elif [ "$PHPMYADMIN_CHOICE" == "n" ]; then
        PHPMYADMIN=false
    elif [ "$PHPMYADMIN_CHOICE" == "N" ]; then
        PHPMYADMIN=false
    else
        echo "Answer not found, no phpmyadmin will be installed."
        PHPMYADMIN=false
    fi
}

dependency_installation() {
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    if [ "$OS" = "Ubuntu" ]; then
        if [ "$VERSION" = "22.04" ]; then
                curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
        fi
    fi
    apt update
    if [ "$OS" = "Ubuntu" ]; then
        if [ "$VERSION" = "18.04" ]; then
            apt-add-repository universe
        fi
    fi
    apt -y install php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server
}

installing_composer() {
    curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
}

download_files() {
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
}

database_configuration() {
    mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '${MYSQL_PASSWORD}';"
    mysql -u root -e "CREATE DATABASE panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"
}

installation() {
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan key:generate --force
}

environment_configuration() {
    if [ "$USE_SSL" == true ]; then
        php artisan p:environment:setup --author=$EMAIL --url=http://${FQDN} --timezone=Europe/Amsterdam --cache=file --session=file --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=enabled --telemetry=disabled
    elif [ "$USE_SSL" == false ]; then
        php artisan p:environment:setup --author=$EMAIL --url=http://${FQDN} --timezone=Europe/Amsterdam --cache=file --session=file --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=enabled --telemetry=disabled 
    fi
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password=$MYSQL_PASSWORD
}

database_setup() {
    php artisan migrate --seed --force
}

add_the_first_user() {
    php artisan p:user:make --email=$EMAIL --username=admin --name-first=admin --name-last=admin --password=$USER_PASSWORD --admin=1 
}

set_permissions() {
    chown -R www-data:www-data /var/www/pterodactyl/*
}

crontab_configuration() {
    (sudo crontab -l; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | sudo crontab -
}

create_queue_worker() {
    curl -o /etc/systemd/system/pteroq.service https://config.thomascaptein.nl/pteroq.service
    sudo systemctl enable --now redis-server
    sudo systemctl enable --now pteroq.service
}

webserver_configuration() {
    echo "Do you want to use nginx or apache2? (n/a)"
    read WEBSERVER_CHOICE
    if [ "$WEBSERVER_CHOICE" == "n" ]; then
        nginx_configuration
    elif [ "$WEBSERVER_CHOICE" == "N" ]; then
        nginx_configuration
    elif [ "$WEBSERVER_CHOICE" == "a" ]; then
        apache2_configuration
    elif [ "$WEBSERVER_CHOICE" == "A" ]; then
        apache2_configuration
    else
        echo "Answer not found, nginx will be used."
        nginx_configuration
    fi
}

nginx_certbot() {
    sudo apt update
    sudo apt install -y certbot
    sudo apt install -y python3-certbot-nginx
    certbot certonly --non-interactive --agree-tos --email $EMAIL --nginx -d $FQDN
}

nginx_configuration() {
    rm /etc/nginx/sites-enabled/default
    if [ "$USE_SSL" == true ]; then
        nginx_certbot
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://config.thomascaptein.nl/nginx/ssl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
        sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        sudo systemctl restart nginx
        crontab -l > mycron && echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart nginx\"" >> mycron && crontab mycron && rm mycron
    elif [ "$USE_SSL" == false ]; then
        curl -o /etc/nginx/sites-available/pterodactyl.conf https://config.thomascaptein.nl/nginx/no_ssl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
        sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
        sudo systemctl restart nginx
    fi
}

apache2_certbot() {
    sudo apt update
    sudo apt install -y certbot
    sudo apt install -y python3-certbot-apache
    certbot certonly --non-interactive --agree-tos --email $EMAIL --apache -d $FQDN
}

apache2_configuration() {
    a2dissite 000-default.conf
    if [ "$USE_SSL" == true ]; then
        apache2_certbot
        curl -o /etc/apache2/sites-available/pterodactyl.conf https://config.thomascaptein.nl/apache2/ssl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/apache2/sites-available/pterodactyl.conf
        sudo ln -s /etc/apache2/sites-available/pterodactyl.conf /etc/apache2/sites-enabled/pterodactyl.conf
        sudo a2enmod rewrite
        sudo a2enmod ssl
        sudo systemctl restart apache2
        crontab -l > mycron && echo "0 23 * * * certbot renew --quiet --deploy-hook \"systemctl restart apache2\"" >> mycron && crontab mycron && rm mycron
    elif [ "$USE_SSL" == false ]; then
        curl -o /etc/apache2/sites-available/pterodactyl.conf https://config.thomascaptein.nl/apache2/no_ssl.conf
        sed -i -e "s/<domain>/${FQDN}/g" /etc/apache2/sites-available/pterodactyl.conf
        sudo ln -s /etc/apache2/sites-available/pterodactyl.conf /etc/apache2/sites-enabled/pterodactyl.conf
        sudo a2enmod rewrite
        sudo systemctl restart apache2
    fi
}

phpmyadmin_installation() {
    cd /var/www/pterodactyl/public 
    mkdir phpmyadmin
    wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-english.tar.gz
    tar xvzf phpMyAdmin-latest-english.tar.gz
    mv phpMyAdmin-*-english/* phpmyadmin
    rm -rf phpMyAdmin-*-english
    rm -rf phpMyAdmin-latest-english.tar.gz
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
    curl -o /etc/systemd/system/wings.service https://config.thomascaptein.nl/wings.service
    systemctl enable --now wings
}

setup_node_on_panel() {
    cd /var/www/pterodactyl 
    php artisan p:location:make --short=EARTH --long="This server is hosted on Earth"
    if [ "$USE_SSL" == true ]; then
        php artisan p:node:make --name=Node01 --description=Node01 --locationId=1 --fqdn=$FQDN --public=1 --scheme=https --proxy=0 --maintenance=0 --maxMemory=$((memory / 1024)) --overallocateMemory=0 --maxDisk=$disk_space --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
    elif [ "$USE_SSL" == false ]; then
        php artisan p:node:make --name=Node01 --description=Node01 --locationId=1 --fqdn=$FQDN --public=1 --scheme=http --proxy=0 --maintenance=0 --maxMemory=$((memory / 1024)) --overallocateMemory=0 --maxDisk=$disk_space --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
    fi
    php artisan p:node:configuration 1 --format=yml > /etc/pterodactyl/config.yml
}

information_message() {
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Your Pterodactyl panel has been successfully installed and should be fully functional. If you encounter any issues or problems with the panel, please do not hesitate to reach out to the creator of this script for assistance."
    echo ""
    echo "Here are your login credentials:"
    echo "Username: admin"
    echo "Password: $PASSWORD"
    if [ "$USE_SSL" == true ]; then
        echo "URL: https://$FQDN"
        echo "phpMyAdmin URL: https://$FQDN/phpmyadmin"
    elif [ "$USE_SSL" == false ]; then
        echo "URL: http://$FQDN"
        echo "phpMyAdmin URL: http://$FQDN/phpmyadmin"
    fi
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Here's the additional information such as database details."
    echo "Database Host: 127.0.0.1:3306"
    echo "Database Name: panel"
    echo "Database User: pterodactyl"
    echo "Database Password: $MYSQL_PASSWORD"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "If you need any help, please join our Discord server: https://discord.gg/"
    echo "Thank you for using this script."
    echo "Script created by Thomas Captein"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
}

install_pterodactyl() {
    domain_usage
    phpmyadmin_usage
    dependency_installation
    installing_composer
    download_files
    database_configuration
    installation
    environment_configuration
    database_setup
    add_the_first_user
    set_permissions
    crontab_configuration
    create_queue_worker
    webserver_configuration
    if [ "$PHPMYADMIN" == true ]; then
        phpmyadmin_installation
    fi
    installing_docker
    start_docker_on_boot
    installing_wings
    daemonizing
    setup_node_on_panel
    information_message
}

install_pterodactyl
