#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Note: Please run the script under the root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
    fi
done

[[ -z $SYSTEM ]] && red "Does not support the current VPS system, please use the mainstream operating system" && exit 1

inst_cert(){
    green "Methods of applying certificate ："
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Bing self-signed certificate ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Acme script auto-apply"
    echo -e " ${GREEN}3.${PLAIN} Custom Certificate Path"
    echo ""
    read -rp "please enter options [1-3]: " certInput
    if [[ $certInput == 2 ]]; then
        if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]] && [[ -f /root/ca.log ]]; then
            domain=$(cat /root/ca.log)
            green "The original domain name was detected: the certificate of $domain is being applied"
            hy_ym=$domain
        else
            WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                systemctl stop warp-go >/dev/null 2>&1
                ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
                wg-quick up wgcf >/dev/null 2>&1
                systemctl start warp-go >/dev/null 2>&1
            else
                ip=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || ip=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
            fi
            
            read -p "Please enter the domain name to apply for a certificate：" domain
            [[ -z $domain ]] && red "No domain name entered, unable to perform operation！" && exit 1
            green "Domain name entered：$domain" && sleep 1
            domainIP=$(curl -sm8 ipget.net/?ip="${domain}")
            if [[ $domainIP == $ip ]]; then
                ${PACKAGE_INSTALL[int]} curl wget sudo socat openssl
                if [[ $SYSTEM == "CentOS" ]]; then
                    ${PACKAGE_INSTALL[int]} cronie
                    systemctl start crond
                    systemctl enable crond
                else
                    ${PACKAGE_INSTALL[int]} cron
                    systemctl start cron
                    systemctl enable cron
                fi
                curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
                source ~/.bashrc
                bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
                bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
                if [[ -n $(echo $ip | grep ":") ]]; then
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --listen-v6 --insecure
                else
                    bash ~/.acme.sh/acme.sh --issue -d ${domain} --standalone -k ec-256 --insecure
                fi
                bash ~/.acme.sh/acme.sh --install-cert -d ${domain} --key-file /root/private.key --fullchain-file /root/cert.crt --ecc
                if [[ -f /root/cert.crt && -f /root/private.key ]] && [[ -s /root/cert.crt && -s /root/private.key ]]; then
                    echo $domain > /root/ca.log
                    sed -i '/--cron/d' /etc/crontab >/dev/null 2>&1
                    echo "0 0 * * * root bash /root/.acme.sh/acme.sh --cron -f >/dev/null 2>&1" >> /etc/crontab
                    green "Successful! The certificate (cer.crt) and private key (private.key) files applied by the script have been saved to the /root folder"
                    yellow "The certificate crt file path is as follows: /root/cert.crt"
                    yellow "The private key file path is as follows: /root/private.key"
                    hy_ym=$domain
                fi
            else
                red "The IP resolved by the current domain name does not match the real IP used by the current VPS"
                green "suggestions below:"
                yellow "1. Please make sure CloudFlare is turned off (DNS only), other domain name resolution or CDN website settings are the same"
                yellow "2. Please check whether the IP set by the DNS resolution is the real IP of the VPS"
                yellow "3. The script may not keep up with the times, it is recommended to post screenshots to GitHub Issues, or TG groups for inquiries"
                exit 1
            fi
        fi
    elif [[ $certInput == 3 ]]; then
        read -p "Please enter the path of the public key file crt: " certpath
        yellow "The path of the public key file crt: $certpath"
        read -p "Please enter the path of the key file key: " keypath
        yellow "The path of the key file key: $keypath"
        read -p "Please enter the domain name of the certificate: " domain
        yellow "Certificate domain name: $domain"
        hy_ym=$domain
    else
        green "Will use Bing self-signed certificate as node certificate for Hysteria"

        cert_path="/etc/hysteria/cert.crt"
        key_path="/etc/hysteria/private.key"
        openssl ecparam -genkey -name prime256v1 -out /etc/hysteria/private.key
        openssl req -new -x509 -days 36500 -key /etc/hysteria/private.key -out /etc/hysteria/cert.crt -subj "/CN=www.bing.com"
        chmod +x /etc/hysteria/cert.crt
        chmod +x /etc/hysteria/private.key
        hy_ym="www.bing.com"
        domain="${sni:-www.bing.com}"
    fi
}

inst_pro(){
    green "The Hysteria node protocol is as follows:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} UDP ${YELLOW}（default）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} wechat-video"
    echo -e " ${GREEN}3.${PLAIN} faketcp"
    echo ""
    read -rp "Please enter options [1-3]: " proInput
    if [[ $proInput == 2 ]]; then
        protocol="wehcat-video"
    elif [[ $proInput == 3 ]]; then
        protocol="faketcp"
    else
        protocol="udp"
    fi
    yellow "Will use $protocol as Hysteria's node protocol"
}

inst_port(){
    read -p "Set the Hysteria port [1-65535] (Enter will randomly assign the port): " port
    [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
    until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; do
        if [[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]; then
            echo -e "${RED} $port ${PLAIN} The port is already occupied by another program, please change the port and try again!  "
            read -p "Set the Hysteria port [1-65535] (Enter will randomly assign the port): " port
            [[ -z $port ]] && port=$(shuf -i 2000-65535 -n 1)
        fi
    done

    yellow "The port that will be used on the Hysteria node is: $port"

    if [[ $protocol == "udp" ]]; then
        inst_jump
    fi
}

inst_jump(){
    yellow "The protocol you currently choose is udp, which supports port hopping function"
    green "The Hysteria port usage pattern is as follows: "
    echo ""
    echo -e " ${GREEN}1.${PLAIN} single port ${YELLOW} (default) ${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} port hopping"
    echo ""
    read -rp "Please enter options [1-2]: " jumpInput
    if [[ $jumpInput == 2 ]]; then
        read -p "Set the starting port of the range port (recommended between 10000-65535)：" firstport
        read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above)：" endport
        if [[ $firstport -ge $endport ]]; then
            until [[ $firstport -le $endport ]]; do
                if [[ $firstport -ge $endport ]]; then
                    red "The start port you set is less than the end port, please re-enter the start and end port"
                    read -p "Set the starting port of the range port (recommended between 10000-65535): " firstport
                    read -p "Set the end port of a range port (recommended between 10000-65535, must be larger than the start port above):" endport
                fi
            done
        fi
        iptables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        ip6tables -t nat -A PREROUTING -p udp --dport $firstport:$endport  -j DNAT --to-destination :$port
        iptables -t nat -F PREROUTING >/dev/null 2>&1
        netfilter-persistent save >/dev/null 2>&1
    else
        red "Will continue to use single port mode"
    fi
}

inst_pwd(){
    read -p "Set Hysteria password ( Enter for random password) :  " auth_pwd
    [[ -z $auth_pwd ]] && auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
    yellow "The password used on the Hysteria node is: $auth_pwd"
}

inst_speed(){
    read -p "Enter your download speed (Mbps): " down_mbps
    read -p "Enter your upload speed (Mbps): " up_mbps
    read -p "Enter your SNI (Default: www.bing.com) : " sni
}

inst_resolv(){
    green "The Hysteria domain name resolution mode is as follows:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} IPv4 priority ${YELLOW}（default）${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} IPv6 priority"
    echo ""
    read -rp "Please enter options [1-2]: " resolvInput
    if [[ $resolvInput == 2 ]]; then
        yellow "Hysteria name resolution mode has been set to IPv6 first"
        resolv=64
    else
        yellow "Hysteria name resolution mode has been set to IPv4 first"
        resolv=46
    fi
}

inst_hy(){
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl wget sudo qrencode procps iptables-persistent netfilter-persistent

    wget -N https://raw.githubusercontent.com/Ptechgithub/hysteria-install/main/install_server.sh
    bash install_server.sh
    rm -f install_server.sh

    if [[ -f "/usr/local/bin/hysteria" ]]; then
        green "Hysteria installed successfully!  "
    else
        red "Hysteria installation failed!  "
    fi

    # Ask user for Hysteria configuration
    inst_cert
    inst_pro
    inst_port
    inst_pwd
    inst_speed
    inst_resolv

    # Setting up the Hysteria configuration file
    cat <<EOF > /etc/hysteria/config.json
{
    "protocol": "$protocol",
    "listen": ":$port",
    "resolve_preference": "$resolv",
    "cert": "$cert_path",
    "key": "$key_path",
    "alpn": "h3",
    "auth": {
        "mode": "password",
        "config": {
            "password": "$auth_pwd"
        }
    }
}
EOF

    # Determine the final inbound port range
    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    # Determine whether the certificate is self-signed by Bing, if so, use the IP as the node inbound
    if [[ $hy_ym == "www.bing.com" ]]; then
        WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            systemctl stop warp-go >/dev/null 2>&1
            hy_ym=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || hy_ym="[$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)]"
            wg-quick up wgcf >/dev/null 2>&1
            systemctl start warp-go >/dev/null 2>&1
        else
            hy_ym=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || hy_ym="[$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)]"
        fi
    fi

    # Set up V2ray and Clash Meta configuration files
    mkdir /root/hy >/dev/null 2>&1
    cat <<EOF > /root/hy/hy-client.json
{
    "protocol": "$protocol",
    "server": "$hy_ym:$last_port",
    "server_name": "$domain",
    "alpn": "h3",
    "up_mbps": "$up_mbps",
    "down_mbps": "$down_mbps",
    "auth_str": "$auth_pwd",
    "insecure": true,
    "retry": 3,
    "retry_interval": 3,
    "fast_open": true,
    "lazy_start": true,
    "hop_interval": 60,
    "socks5": {
        "listen": "127.0.0.1:5080"
    }
}
EOF

    cat <<EOF > /root/hy/clash-meta.yaml
mixed-port: 7890
external-controller: 127.0.0.1:9090
allow-lan: false
mode: rule
log-level: debug
ipv6: true
dns:
  enable: true
  listen: 0.0.0.0:53
  enhanced-mode: fake-ip
  nameserver:
    - 8.8.8.8
    - 1.1.1.1
    - 114.114.114.114
proxies:
  - name: Peyman-Hysteria
    type: hysteria
    server: $hy_ym
    port: $port
    auth_str: $auth_pwd
    alpn:
      - h3
    protocol: $protocol
    up: $up_mbps
    down: $down_mbps
    sni: $domain
    skip-cert-verify: true
proxy-groups:
  - name: Proxy
    type: select
    proxies:
      - Peyman-Hysteria
      
rules:
  - DOMAIN-SUFFIX,speedtest.net,DIRECT
  - DOMAIN-SUFFIX,fast.com,DIRECT
  - DOMAIN-SUFFIX,speed.cloudflare.com,DIRECT  
  - DOMAIN-SUFFIX,ir,DIRECT
  - GEOIP,IR,DIRECT
  - MATCH,Proxy
EOF
    url="hysteria://$hy_ym:$port?protocol=$protocol&upmbps=$up_mbps&downmbps=$down_mbps&auth=$auth_pwd&peer=$domain&insecure=1&alpn=h3#Peyman-Hysteria"
    echo $url > /root/hy/url.txt

    systemctl daemon-reload
    systemctl enable hysteria-server
    systemctl start hysteria-server

    if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.json' ]]; then
        green "Hysteria service started successfully"
    else
        red "The Hysteria-server service failed to start, please run systemctl status hysteria-server to view the service status and give feedback, the script exits" && exit 1
    fi

    green "Hysteria proxy service installation complete"
    yellow "The content of the client configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    cat /root/hy/hy-client.json
    yellow "Clash Meta client configuration file saved to /root/hy/clash-meta.yaml"
    yellow "The Hysteria node sharing link is as follows and saved to /root/hy/url.txt"
    red $(cat /root/hy/url.txt)
}

uninst_hy(){
    systemctl stop hysteria-server.service >/dev/null 2>&1
    systemctl disable hysteria-server.service >/dev/null 2>&1
    rm -f /lib/systemd/system/hysteria-server.service /lib/systemd/system/hysteria-server@.service
    rm -rf /usr/local/bin/hysteria /etc/hysteria /root/hy /root/hysteria.sh
    sed -i '/systemctl restart hysteria-server/d' /etc/crontab
    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1
    green "Hysteria has been completely uninstalled!  "
}

starthy(){
    systemctl start hysteria-server
    systemctl enable hysteria-server >/dev/null 2>&1
}

stophy(){
    systemctl stop hysteria-server
    systemctl disable hysteria-server >/dev/null 2>&1
}

hyswitch(){
    yellow "Please select the operation you need:"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Start Hysteria"
    echo -e " ${GREEN}2.${PLAIN} Close Hysteria"
    echo -e " ${GREEN}3.${PLAIN} restart Hysteria"
    echo ""
    read -rp "Please enter options [0-3]: " switchInput
    case $switchInput in
        1 ) starthy ;;
        2 ) stophy ;;
        3 ) stophy && starthy ;;
        * ) exit 1 ;;
    esac
}

change_cert(){
    old_cert=$(cat /etc/hysteria/config.json | grep cert | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    old_key=$(cat /etc/hysteria/config.json | grep key | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    old_hyym=$(cat /root/hy/hy-client.json | grep server | sed -n 1p | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g" | awk -F ":" '{print $1}')
    old_domain=$(cat /root/hy/hy-client.json | grep server_name | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_cert
    if [[ $hy_ym == "www.bing.com" ]]; then
        WARPv4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        WARPv6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
        if [[ $WARPv4Status =~ on|plus ]] || [[ $WARPv6Status =~ on|plus ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            systemctl stop warp-go >/dev/null 2>&1
            hy_ym=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || hy_ym=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
            wg-quick up wgcf >/dev/null 2>&1
            systemctl start warp-go >/dev/null 2>&1
        else
            hy_ym=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p) || hy_ym=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
        fi
    fi
    sed -i "s|$old_cert|$cert_path|" /etc/hysteria/config.json
    sed -i "s|$old_key|$key_path|" /etc/hysteria/config.json
    sed -i "s|$old_hyym|$hy_ym|" /root/hy/hy-client.json
    sed -i "s|$old_hyym|$hy_ym|" /root/hy/clash-meta.yaml
    sed -i "s|$old_hyym|$hy_ym|" /root/hy/url.txt
    stophy && starthy
    green "The configuration is modified successfully, please re-import the node configuration file"
}

change_pro(){
    old_pro=$(cat /etc/hysteria/config.json | grep protocol | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_pro
    sed -i "s/$old_pro/$protocol/" /etc/hysteria/config.json
    sed -i "s/$old_pro/$protocol/" /root/hy/hy-client.json
    sed -i "s/$old_pro/$protocol/" /root/hy/clash-meta.yaml
    sed -i "s/$old_pro/$protocol/" /root/hy/url.txt
    stophy && starthy
    green "The configuration is modified successfully, please re-import the node configuration file"
}

change_port(){
    old_port=$(cat /etc/hysteria/config.json | grep listen | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g" | sed "s/://g")
    inst_port

    iptables -t nat -F PREROUTING >/dev/null 2>&1
    netfilter-persistent save >/dev/null 2>&1

    if [[ -n $firstport ]]; then
        last_port="$port,$firstport-$endport"
    else
        last_port=$port
    fi

    sed -i "s/$old_port/$port/" /etc/hysteria/config.json
    sed -i "s/$old_port/$last_port/" /root/hy/hy-client.json
    sed -i "s/$old_port/$last_port/" /root/hy/clash-meta.yaml
    sed -i "s/$old_port/$last_port/" /root/hy/url.txt

    stophy && starthy
    green "The configuration is modified successfully, please re-import the node configuration file"
}

change_pwd(){
    old_pwd=$(cat /etc/hysteria/config.json | grep password | sed -n 2p | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_pwd
    sed -i "s/$old_pwd/$auth_pwd/" /etc/hysteria/config.json
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/hy-client.json
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/clash-meta.yaml
    sed -i "s/$old_pwd/$auth_pwd/" /root/hy/url.txt
    stophy && starthy
    green "The configuration is modified successfully, please re-import the node configuration file"
}

change_resolv(){
    old_resolv=$(cat /etc/hysteria/config.json | grep resolv | awk -F " " '{print $2}' | sed "s/\"//g" | sed "s/,//g")
    inst_resolv
    sed -i "s/$old_resolv/$resolv/" /etc/hysteria/config.json
    stophy && starthy
    green "The configuration is modified successfully, please re-import the node configuration file"
}

editconf(){
    green "The Hysteria configuration change options are as follows:"
    echo -e " ${GREEN}1.${PLAIN} Modify certificate type"
    echo -e " ${GREEN}2.${PLAIN} Modify the transport protocol"
    echo -e " ${GREEN}3.${PLAIN} Modify connection port"
    echo -e " ${GREEN}4.${PLAIN} Modify authentication password"
    echo -e " ${GREEN}5.${PLAIN} Modify domain name resolution priority"
    echo ""
    read -p " Please select an action [1-5]：" confAnswer
    case $confAnswer in
        1 ) change_cert ;;
        2 ) change_pro ;;
        3 ) change_port ;;
        4 ) change_pwd ;;
        5 ) change_resolv ;;
        * ) exit 1 ;;
    esac
}

showconf(){
    yellow "The content of the client configuration file hy-client.json is as follows and saved to /root/hy/hy-client.json"
    cat /root/hy/hy-client.json
    yellow "Clash Meta client configuration file saved to /root/hy/clash-meta.yaml"
    yellow "The Hysteria node sharing link is as follows and saved to /root/hy/url.txt"
    red $(cat /root/hy/url.txt)
}

menu() {
    clear
    echo "###########################################################"
    echo -e "#        ${RED}Hysteria 一one-click installation script${PLAIN}         #"
    echo -e "# ${GREEN}Gihub ${PLAIN}: https://gitlab.com/Ptechgithub                  #"
    echo -e "# ${GREEN}Telegram ${PLAIN}: https://t.me/P_tech2024                      #"
    echo -e "# ${GREEN}YouTube ${PLAIN}: https://www.youtube.com/@IR_TECH              #"
    echo "###########################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install Hysteria"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall Hysteria${PLAIN}"
    echo " -------------"
    echo -e " ${GREEN}3.${PLAIN} Turn off/on, restart Hysteria"
    echo -e " ${GREEN}4.${PLAIN} Modify Hysteria configuration"
    echo -e " ${GREEN}5.${PLAIN} Show Hysteria configuration file"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} exit script"
    echo ""
    read -rp "Please enter options [0-5]: " menuInput
    case $menuInput in
        1 ) inst_hy ;;
        2 ) uninst_hy ;;
        3 ) hyswitch ;;
        4 ) editconf ;;
        5 ) showconf ;;
        * ) exit 1 ;;
    esac
}

menu