#!/bin/bash
###
 # @Author: Vincent Young
 # @Date: 2022-07-01 15:29:23
 # @LastEditors: Mr.X
 # @LastEditTime: 2022-12-20 23:26:45
 # @FilePath: /MTProxy/mtproxy.sh
 # @Websie: https://mrx.la
 # 
 # Copyright © 2022 by Mr.X, All Rights Reserved. 
### 

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

BIN_PATH="/usr/bin/mtg"
CONFIG_PATH="/etc/mtg.toml"
SERVICE_PATH="/etc/systemd/system/mtg.service"
USER_CONFIG_DIR="/etc/mtg/users"
USER_SERVICE_TEMPLATE="/etc/systemd/system/mtg-user@.service"
SCRIPT_INSTALL_PATH="/usr/local/sbin/mtproxy"
SCRIPT_INSTALL_LINK="/usr/bin/mtproxy"
SCRIPT_REMOTE_URL="https://raw.githubusercontent.com/Mr-ByeBye/MTProxy-V2/main/mtproxy.sh"

# Define Color
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

# Make sure run with root
[[ $EUID -ne 0 ]] && echo -e "[${red}Error${plain}]请使用root账户运行脚本!" && exit 1

download_file(){
	echo "正在检查系统..."

	bit=`uname -m`
	if [[ ${bit} = "x86_64" ]]; then
		bit="amd64"
    elif [[ ${bit} = "aarch64" ]]; then
        bit="arm64"
    else
	    bit="386"
    fi

    last_version=$(curl -Ls "https://api.github.com/repos/9seconds/mtg/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$last_version" ]]; then
        echo -e "${red}未能获取到mtg版本可能是由于超过了Github API限制,请稍后重试."
        exit 1
    fi
    echo -e "Latest version of mtg detected: ${last_version}, start installing..."
    version=$(echo ${last_version} | sed 's/v//g')
    wget -N --no-check-certificate -O mtg-${version}-linux-${bit}.tar.gz https://github.com/9seconds/mtg/releases/download/${last_version}/mtg-${version}-linux-${bit}.tar.gz
    if [[ ! -f "mtg-${version}-linux-${bit}.tar.gz" ]]; then
        echo -e "${red}Download mtg-${version}-linux-${bit}.tar.gz failed, please try again."
        exit 1
    fi
    tar -xzf mtg-${version}-linux-${bit}.tar.gz
    mv mtg-${version}-linux-${bit}/mtg "${BIN_PATH}"
    rm -f mtg-${version}-linux-${bit}.tar.gz
    rm -rf mtg-${version}-linux-${bit}
    chmod +x "${BIN_PATH}"
    echo -e "mtg-${version}-linux-${bit}.tar.gz installed successfully, start to configure..."
}

write_service_file(){
	cat > "${SERVICE_PATH}" <<'EOF'
[Unit]
Description=mtg - MTProto proxy server
Documentation=https://github.com/Mr-ByeBye/MTProxy-V2
After=network.target

[Service]
ExecStart=/usr/bin/mtg run /etc/mtg.toml
Restart=always
RestartSec=3
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
}

write_user_service_template(){
	cat > "${USER_SERVICE_TEMPLATE}" <<'EOF'
[Unit]
Description=mtg - MTProto proxy server (%i)
Documentation=https://github.com/Mr-ByeBye/MTProxy-V2
After=network.target

[Service]
ExecStart=/usr/bin/mtg run /etc/mtg/users/%i.toml
Restart=always
RestartSec=3
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
}

read_config_value(){
	key="$1"
	file="$2"
	[ ! -f "${file}" ] && return 1
	sed -n -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$/\1/p" "${file}" | head -n 1
}

get_public_ip(){
	public_ip="$(curl -fsS ipv4.ip.sb 2>/dev/null || true)"
	[ -z "${public_ip}" ] && public_ip="$(curl -fsS ifconfig.me 2>/dev/null || true)"
	[ -z "${public_ip}" ] && public_ip="$(curl -fsS ipinfo.io/ip 2>/dev/null || true)"
	echo "${public_ip}"
}

try_open_firewall_port(){
	target_port="$1"
	read -p "是否自动放行端口 ${target_port} ? [y/N]: " allow_fw
	case "${allow_fw}" in
		y|Y|yes|YES)
			if command -v firewall-cmd >/dev/null 2>&1; then
				systemctl is-active --quiet firewalld && firewall-cmd --permanent --add-port="${target_port}/tcp" >/dev/null 2>&1 || true
				systemctl is-active --quiet firewalld && firewall-cmd --reload >/dev/null 2>&1 || true
				echo -e "${green}已尝试通过 firewalld 放行端口 ${target_port}/tcp${plain}"
			elif command -v ufw >/dev/null 2>&1; then
				ufw allow "${target_port}/tcp" >/dev/null 2>&1 || true
				echo -e "${green}已尝试通过 ufw 放行端口 ${target_port}/tcp${plain}"
			else
				echo -e "${yellow}未检测到 firewalld/ufw，跳过放行端口步骤${plain}"
			fi
			;;
		*)
			echo -e "${yellow}已跳过放行端口步骤${plain}"
			;;
	esac
}

generate_secret(){
	domain_value="$1"
	secret_value="$(mtg generate-secret --hex "${domain_value}" 2>/dev/null || true)"
	if [ -z "${secret_value}" ]; then
		secret_value="$(mtg generate-secret -c "${domain_value}" tls 2>/dev/null || true)"
	fi
	echo "${secret_value}"
}

install_quick_command(){
	script_source="${BASH_SOURCE[0]:-$0}"
	script_source="$(readlink -f "${script_source}" 2>/dev/null || realpath "${script_source}" 2>/dev/null || echo "${script_source}")"

	if [ -r "${script_source}" ]; then
		if command -v install >/dev/null 2>&1; then
			install -m 755 "${script_source}" "${SCRIPT_INSTALL_PATH}"
		else
			cp -f "${script_source}" "${SCRIPT_INSTALL_PATH}"
			chmod +x "${SCRIPT_INSTALL_PATH}"
		fi
	else
		tmp_file="$(mktemp)"
		if command -v curl >/dev/null 2>&1; then
			curl -fsSL "${SCRIPT_REMOTE_URL}" -o "${tmp_file}" || rm -f "${tmp_file}"
		elif command -v wget >/dev/null 2>&1; then
			wget -qO "${tmp_file}" "${SCRIPT_REMOTE_URL}" || rm -f "${tmp_file}"
		else
			rm -f "${tmp_file}"
			echo -e "${red}未找到 curl/wget，无法下载脚本以安装快捷命令${plain}"
			return 1
		fi
		if [ ! -s "${tmp_file}" ]; then
			echo -e "${red}下载脚本失败，无法安装快捷命令${plain}"
			return 1
		fi
		chmod +x "${tmp_file}"
		mv -f "${tmp_file}" "${SCRIPT_INSTALL_PATH}"
	fi

	if [ ! -e "${SCRIPT_INSTALL_LINK}" ]; then
		ln -s "${SCRIPT_INSTALL_PATH}" "${SCRIPT_INSTALL_LINK}" >/dev/null 2>&1 || true
	fi

	echo -e "${green}已安装快捷命令：mtproxy${plain}"
}

uninstall_quick_command(){
	rm -f "${SCRIPT_INSTALL_LINK}" >/dev/null 2>&1 || true
	rm -f "${SCRIPT_INSTALL_PATH}" >/dev/null 2>&1 || true
	echo -e "${green}已卸载快捷命令${plain}"
}

ensure_user_env(){
	mkdir -p "${USER_CONFIG_DIR}"
	if [ ! -f "${USER_SERVICE_TEMPLATE}" ]; then
		write_user_service_template
	fi
	systemctl daemon-reload
}

validate_username(){
	username="$1"
	echo "${username}" | grep -Eq '^[a-zA-Z0-9_-]+$'
}

get_used_ports(){
	for cfg in "${CONFIG_PATH}" "${USER_CONFIG_DIR}"/*.toml; do
		[ -f "${cfg}" ] || continue
		bind_to="$(read_config_value "bind-to" "${cfg}")"
		echo "${bind_to}" | sed -n -E 's/.*:([0-9]+)$/\1/p'
	done | sed '/^$/d' | sort -n | uniq
}

get_next_port(){
	max_port="$(get_used_ports | tail -n 1)"
	if [ -z "${max_port}" ]; then
		echo "8443"
		return 0
	fi
	echo $((max_port + 1))
}

user_service_name(){
	echo "mtg-user@${username}"
}

user_config_path(){
	echo "${USER_CONFIG_DIR}/${username}.toml"
}

create_user(){
	ensure_user_env

	echo ""
	read -p "输入用户名(仅字母数字_-): " username
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法，仅支持字母数字下划线与短横线${plain}"
		return 1
	fi

	cfg_file="$(user_config_path)"
	if [ -f "${cfg_file}" ]; then
		echo -e "${red}用户已存在: ${username}${plain}"
		return 1
	fi

	echo ""
	read -p "输入伪装域名 (默认 qifei.shabibaidu.com): " domain
	[ -z "${domain}" ] && domain="qifei.shabibaidu.com"

	next_port="$(get_next_port)"
	echo ""
	read -p "输入监听端口 (默认 ${next_port}): " port
	[ -z "${port}" ] && port="${next_port}"
	if ! echo "${port}" | grep -Eq '^[0-9]+$'; then
		echo -e "${red}端口必须为数字${plain}"
		return 1
	fi
	if [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
		echo -e "${red}端口范围必须在 1-65535${plain}"
		return 1
	fi

	secret="$(generate_secret "${domain}")"
	if [ -z "${secret}" ]; then
		echo -e "${red}生成 secret 失败，请确认 mtg 已安装且可执行${plain}"
		return 1
	fi

	cat > "${cfg_file}" <<EOF
secret = "${secret}"
bind-to = "0.0.0.0:${port}"
EOF

	systemctl enable "$(user_service_name)" >/dev/null 2>&1 || true
	systemctl restart "$(user_service_name)"
	try_open_firewall_port "${port}"

	echo -e "${green}用户创建成功: ${username}${plain}"
	show_user_links "${username}"
}

list_users(){
	ensure_user_env
	found=0
	for cfg in "${USER_CONFIG_DIR}"/*.toml; do
		[ -f "${cfg}" ] || continue
		found=1
		user="$(basename "${cfg}" .toml)"
		bind_to="$(read_config_value "bind-to" "${cfg}")"
		port_from_cfg="$(echo "${bind_to}" | sed -n -E 's/.*:([0-9]+)$/\1/p' | head -n 1)"
		status="$(systemctl is-active "mtg-user@${user}" 2>/dev/null || true)"
		echo "${user}  port=${port_from_cfg}  status=${status}"
	done
	if [ "${found}" -eq 0 ]; then
		echo -e "${yellow}暂无用户，请先创建用户${plain}"
	fi
}

delete_user(){
	ensure_user_env
	echo ""
	read -p "输入要删除的用户名: " username
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法${plain}"
		return 1
	fi
	cfg_file="$(user_config_path)"
	if [ ! -f "${cfg_file}" ]; then
		echo -e "${red}用户不存在: ${username}${plain}"
		return 1
	fi
	systemctl stop "$(user_service_name)" >/dev/null 2>&1 || true
	systemctl disable "$(user_service_name)" >/dev/null 2>&1 || true
	rm -f "${cfg_file}"
	systemctl reset-failed "$(user_service_name)" >/dev/null 2>&1 || true
	systemctl daemon-reload
	echo -e "${green}已删除用户: ${username}${plain}"
}

show_user_links(){
	username="$1"
	if [ -z "${username}" ]; then
		echo ""
		read -p "输入用户名: " username
	fi
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法${plain}"
		return 1
	fi
	cfg_file="$(user_config_path)"
	if [ ! -f "${cfg_file}" ]; then
		echo -e "${red}用户不存在: ${username}${plain}"
		return 1
	fi
	secret_from_cfg="$(read_config_value "secret" "${cfg_file}")"
	bind_to="$(read_config_value "bind-to" "${cfg_file}")"
	port_from_cfg="$(echo "${bind_to}" | sed -n -E 's/.*:([0-9]+)$/\1/p' | head -n 1)"
	public_ip="$(get_public_ip)"
	[ -z "${public_ip}" ] && public_ip="YOUR_SERVER_IP"
	echo "tg://proxy?server=${public_ip}&port=${port_from_cfg}&secret=${secret_from_cfg}"
	echo "https://t.me/proxy?server=${public_ip}&port=${port_from_cfg}&secret=${secret_from_cfg}"
}

start_user(){
	echo ""
	read -p "输入用户名: " username
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法${plain}"
		return 1
	fi
	systemctl start "$(user_service_name)"
	systemctl enable "$(user_service_name)" >/dev/null 2>&1 || true
	echo -e "${green}已启动用户: ${username}${plain}"
}

stop_user(){
	echo ""
	read -p "输入用户名: " username
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法${plain}"
		return 1
	fi
	systemctl stop "$(user_service_name)" >/dev/null 2>&1 || true
	systemctl disable "$(user_service_name)" >/dev/null 2>&1 || true
	echo -e "${green}已停止用户: ${username}${plain}"
}

restart_user(){
	echo ""
	read -p "输入用户名: " username
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法${plain}"
		return 1
	fi
	systemctl restart "$(user_service_name)"
	echo -e "${green}已重启用户: ${username}${plain}"
}

status_user(){
	echo ""
	read -p "输入用户名: " username
	if ! validate_username "${username}"; then
		echo -e "${red}用户名不合法${plain}"
		return 1
	fi
	systemctl status "$(user_service_name)" --no-pager
}

user_menu(){
	while true; do
		clear
		echo -e "  多用户管理
————————————
 ${green} 1.${plain} 创建用户
 ${green} 2.${plain} 列出用户
 ${green} 3.${plain} 删除用户
 ${green} 4.${plain} 输出用户订阅链接
 ${green} 5.${plain} 启动用户
 ${green} 6.${plain} 停止用户
 ${green} 7.${plain} 重启用户
 ${green} 8.${plain} 查看用户状态
————————————
 ${green} 0.${plain} 返回
————————————" && echo

		read -e -p " 请输入对应数字选择 [0-8]: " user_num
		case "${user_num}" in
			1) create_user ;;
			2) list_users ;;
			3) delete_user ;;
			4) show_user_links ;;
			5) start_user ;;
			6) stop_user ;;
			7) restart_user ;;
			8) status_user ;;
			0) return 0 ;;
			*) echo -e "${red}Error${plain} 请输入正确数字 [0-8]" ;;
		esac
		read -p "按回车键返回..." _
	done
}

configure_mtg(){
    echo -e "开始配置 mtg..."
    wget -N --no-check-certificate -O "${CONFIG_PATH}" https://raw.githubusercontent.com/missuo/MTProxy/main/mtg.toml
    
    echo ""
    read -p "输入伪装域名 (例如 qifei.shabibaidu.com): " domain
	[ -z "${domain}" ] && domain="qifei.shabibaidu.com"

	echo ""
	read -p "输入监听端口 (默认 8443):" port
	[ -z "${port}" ] && port="8443"

    secret="$(generate_secret "${domain}")"
    
    echo "正在配置中..."

    sed -i "s/secret.*/secret = \"${secret}\"/g" "${CONFIG_PATH}"
    sed -i "s/bind-to.*/bind-to = \"0.0.0.0:${port}\"/g" "${CONFIG_PATH}"

    echo "mtg配置成功,开始配置systemctl..."
}

configure_systemctl(){
    echo -e "正在配置 systemctl..."
    write_service_file
    systemctl daemon-reload
    systemctl enable mtg
    systemctl start mtg
    echo "mtg 配置成功,开始处理防火墙..."
    try_open_firewall_port "${port}"
    echo "mtg 启动成功,enjoy it!"
    echo ""
    public_ip="$(get_public_ip)"
    subscription_config="tg://proxy?server=${public_ip}&port=${port}&secret=${secret}"
    subscription_link="https://t.me/proxy?server=${public_ip}&port=${port}&secret=${secret}"
    echo -e "${subscription_config}"
    echo -e "${subscription_link}"
}

enable_autostart(){
	systemctl enable mtg
	echo -e "${green}已开启 MTProxy 开机自启${plain}"
}

disable_autostart(){
	systemctl disable mtg
	echo -e "${green}已关闭 MTProxy 开机自启${plain}"
}

show_status(){
	systemctl status mtg --no-pager
}

show_links(){
	if [ ! -f "${CONFIG_PATH}" ]; then
		echo -e "${red}未找到配置文件: ${CONFIG_PATH}${plain}"
		return 1
	fi
	secret_from_cfg="$(read_config_value "secret" "${CONFIG_PATH}")"
	bind_to="$(read_config_value "bind-to" "${CONFIG_PATH}")"
	port_from_cfg="$(echo "${bind_to}" | sed -n -E 's/.*:([0-9]+)$/\1/p' | head -n 1)"
	if [ -z "${secret_from_cfg}" ] || [ -z "${port_from_cfg}" ]; then
		echo -e "${red}无法从配置文件解析 secret/port，请检查 ${CONFIG_PATH}${plain}"
		return 1
	fi
	public_ip="$(get_public_ip)"
	if [ -z "${public_ip}" ]; then
		echo -e "${red}获取公网 IP 失败，请手动填写 server 参数${plain}"
		public_ip="YOUR_SERVER_IP"
	fi
	echo "tg://proxy?server=${public_ip}&port=${port_from_cfg}&secret=${secret_from_cfg}"
	echo "https://t.me/proxy?server=${public_ip}&port=${port_from_cfg}&secret=${secret_from_cfg}"
}

change_port(){
    read -p "输入你要修改的端口(默认 8443):" port
	[ -z "${port}" ] && port="8443"
    sed -i "s/bind-to.*/bind-to = \"0.0.0.0:${port}\"/g" "${CONFIG_PATH}"
    echo "正在重启MTProxy..."
    systemctl restart mtg
    echo "MTProxy 重启完毕...!"
}

change_secret(){
    echo -e "请注意,不正确的修改Secret可能会导致MTProxy无法正常工作。."
    read -p "输入你要修改的Secret密钥:" secret
	[ -z "${secret}" ] && secret="$(generate_secret "qifei.shabibaidu.com")"
    sed -i "s/secret.*/secret = \"${secret}\"/g" "${CONFIG_PATH}"
    echo "Secret密钥更改完成!"
    echo "正在重启MTProxy..."
    systemctl restart mtg
    echo "MTProxy 重启完毕...!"
}

update_mtg(){
    echo -e "正在升级 mtg..."
    download_file
    echo "mtg 升级成功,开始重新启动MTProxy..."
    systemctl restart mtg
    echo "MTProxy已成功启动...!"
}

start_menu() {
	while true; do
		clear
		echo -e "  MTProxy v2 一键安装脚本
---- 汉化 Mr.X | github.com/Mr-ByeBye/MTProxy-V2 ----
 ${green} 1.${plain} 安装MTproxy
 ${green} 2.${plain} 卸载MTproxy
————————————
 ${green} 3.${plain} 启动 MTProxy
 ${green} 4.${plain} 停止 MTProxy
 ${green} 5.${plain} 重启 MTProxy
 ${green} 6.${plain} 更改端口
 ${green} 7.${plain} 更改密钥
 ${green} 8.${plain} 升级 mtg
 ${green} 9.${plain} 开启开机自启
${green}10.${plain} 关闭开机自启
${green}11.${plain} 查看运行状态
${green}12.${plain} 输出订阅链接
${green}13.${plain} 安装快捷命令(mtproxy)
${green}14.${plain} 卸载快捷命令(mtproxy)
${green}15.${plain} 多用户管理
————————————
 ${green} 0.${plain} Exit
————————————" && echo

		read -e -p " 请输入对应数字选择 [0-15]: " num
		case "$num" in
			1)
				download_file
				configure_mtg
				configure_systemctl
				;;
			2)
				echo "Uninstall MTProxy..."
				systemctl stop mtg
				systemctl disable mtg
				rm -rf "${BIN_PATH}"
				rm -rf "${CONFIG_PATH}"
				rm -rf "${SERVICE_PATH}"
				rm -rf "${USER_CONFIG_DIR}"
				rm -rf "${USER_SERVICE_TEMPLATE}"
				rm -f "${SCRIPT_INSTALL_PATH}"
				rm -f "${SCRIPT_INSTALL_LINK}"
				systemctl daemon-reload
				systemctl reset-failed mtg >/dev/null 2>&1 || true
				echo "MTProxy已成功卸载!"
				;;
			3) 
				echo "正在启动MTProxy..."
				systemctl start mtg
				systemctl enable mtg
				echo "MTProxy 启动成功!"
				;;
			4) 
				echo "正在停止MTProxy..."
				systemctl stop mtg
				systemctl disable mtg
				echo "MTProxy 停止成功!"
				;;
			5)  
				echo "正在重启MTProxy..."
				systemctl restart mtg
				echo "MTProxy 重启成功!"
				;;
			6) 
				change_port
				;;
			7)
				change_secret
				;;
			8)
				update_mtg
				;;
			9)
				enable_autostart
				;;
			10)
				disable_autostart
				;;
			11)
				show_status
				;;
			12)
				show_links
				;;
			13)
				install_quick_command
				;;
			14)
				uninstall_quick_command
				;;
			15)
				user_menu
				;;
			0) exit 0 ;;
			*) echo -e "${red}Error${plain} 请输入正确数字 [0-15]" ;;
		esac
		read -p "按回车键继续..." _
	done
}
start_menu
