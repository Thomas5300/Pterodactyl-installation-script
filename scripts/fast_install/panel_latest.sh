OS=$(lsb_release -i | awk '{print $3}')
VERSION=$(lsb_release -rs)
FQDN=$(curl -s https://ip.thomascaptein.nl)
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
USER_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
disk_space=$(df -B MB / | tail -n 1 | awk '{print $2}')

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
    php artisan p:environment:setup --author=unknown@example.com --url=http://${FQDN} --timezone=Europe/Amsterdam --cache=file --session=file --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=enabled --telemetry=disabled
    php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=pterodactyl --password=$MYSQL_PASSWORD
}

database_setup() {
    php artisan migrate --seed --force
}

add_the_first_user() {
    php artisan p:user:make --email=unknown@example.com --username=admin --name-first=admin --name-last=admin --password=$USER_PASSWORD --admin=1
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

nginx_configuration() {
    rm /etc/nginx/sites-enabled/default
    curl -o /etc/nginx/sites-available/pterodactyl.conf https://config.thomascaptein.nl/nginx/no_ssl.conf
    sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    sudo systemctl restart nginx
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

information_message() {
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Your Pterodactyl panel has been successfully installed and should be fully functional. If you encounter any issues or problems with the panel, please do not hesitate to reach out to the creator of this script for assistance."
    echo ""
    echo "Here are your login credentials:"
    echo "Username: admin"
    echo "Password: $USER_PASSWORD"
    echo "URL: http://$FQDN"
    echo "Warning! Because you use fast install, we have used the email unknown@example.com for your account, please change this as soon as possible"
    echo "phpMyAdmin URL: http://$FQDN/phpmyadmin"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Here's the additional information such as database details."
    echo "Database Host: 127.0.0.1:3306"
    echo "Database Name: panel"
    echo "Database User: pterodactyl"
    echo "Database Password: $MYSQL_PASSWORD"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "If you need any help, please join our Discord server: https://discord.gg/"
    echo "Thank you for using this script."
    echo "Script created by https://github.com/Thomas5300"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
}

install_panel() {
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
    nginx_configuration
    phpmyadmin_installation
    information_message
}

install_panel
