FQDN=$(curl -s https://ip.thomascaptein.nl)
MYSQL_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
USER_PASSWORD=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c 16)
email="pterodactyl@mynode.nl"

memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
disk_space=$(df -B MB / | tail -n 1 | awk '{print $2}')

dependency_installation() {
    apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
    curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
    apt update
    apt-add-repository universe
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
}

installation() {
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan key:generate --force
}

environment_configuration() {
    php artisan p:environment:setup --author=$EMAIL --url=http://${FQDN} --timezone=Europe/Amsterdam --cache=file --session=file --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 --settings-ui=enabled --telemetry=disabled 
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
    curl -o /etc/systemd/system/pteroq.service https://raw.githubusercontent.com/Thomas5300/Pterodactyl-installation-script/main/configurations/pteroq.service
    sudo systemctl enable --now redis-server
    sudo systemctl enable --now pteroq.service
}

nginx_configuration() {
    rm /etc/nginx/sites-enabled/default
    curl -o /etc/nginx/sites-available/pterodactyl.conf https://raw.githubusercontent.com/Thomas5300/Pterodactyl-installation-script/main/configurations/nginx/no_ssl.conf
    sed -i -e "s/<domain>/${FQDN}/g" /etc/nginx/sites-available/pterodactyl.conf
    sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf
    sudo systemctl restart nginx
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

setup_node_on_panel() {
    cd /var/www/pterodactyl 
    php artisan p:location:make --short=EARTH --long="This server is hosted on Earth"
    php artisan p:node:make --name=Node01 --description=Node01 --locationId=1 --fqdn=$FQDN --public=1 --scheme=http --proxy=0 --maintenance=0 --maxMemory=$((memory / 1024)) --overallocateMemory=0 --maxDisk=$disk_space --overallocateDisk=0 --uploadSize=100 --daemonListeningPort=8080 --daemonSFTPPort=2022 --daemonBase=/var/lib/pterodactyl/volumes
    php artisan p:node:configuration 1 --format=yml > /etc/pterodactyl/config.yml
}

install_pterodactyl() {
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
    installing_docker
    start_docker_on_boot
    installing_wings
    daemonizing
    setup_node_on_panel
}

install_pterodactyl
