dependency_installation() {
  apt -y install curl
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

information_message() {
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "Pterodactyl wings has been successfully installed all you have to do now is create a node in your panel and put the configuration in /etc/pterodactyl/config.yml then you have to do service wings start and everything should work!"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
    echo "If you need any help, please join our Discord server: https://discord.gg/"
    echo "Thank you for using this script."
    echo "Script created by Thomas Captein"
    echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
}

install_wings() {
    dependency_installation
    installing_docker
    start_docker_on_boot
    installing_wings
    daemonizing
    information_message
}

install_wings
