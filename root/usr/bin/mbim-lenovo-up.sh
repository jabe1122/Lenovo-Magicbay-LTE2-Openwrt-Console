#!/bin/sh
# Lenovo MagicBay LTE2 / ASR1803 MBIM bring-up for OpenWrt.
# The modem returns data frames with all-zero Ethernet MACs, so tc marks ingress
# packets as host packets and the gateway neighbor is pinned to 00:00:00:00:00:00.

CONFIG="${CONFIG:-mbim-lenovo}"
SECTION="${SECTION:-main}"

uci_get() {
	local key="$1" def="$2" val
	val="$(uci -q get "$CONFIG.$SECTION.$key" 2>/dev/null)"
	[ -n "$val" ] && echo "$val" || echo "$def"
}

DEV="${DEV:-$(uci_get device /dev/cdc-wdm0)}"
IFACE="${IFACE:-$(uci_get iface wwan0)}"
APN="${APN:-$(uci_get apn cmnet)}"
USE_NETIFD="${USE_NETIFD:-$(uci_get use_netifd 1)}"
NETIFD_IFACE="${NETIFD_IFACE:-$(uci_get netifd_iface auto)}"
LAN_IF="${LAN_IF:-$(uci_get lan_if br-lan)}"
LOG="${LOG:-/tmp/mbim-lenovo.log}"
TID_FILE="${TID_FILE:-/var/run/mbim-lenovo.tid}"
PID_FILE="${PID_FILE:-/var/run/mbim-lenovo.pid}"
STATS_FILE="${STATS_FILE:-/tmp/mbim-lenovo-traffic.tsv}"
STATS_PID_FILE="${STATS_PID_FILE:-/var/run/mbim-lenovo-stats.pid}"
SIGNAL_FILE="${SIGNAL_FILE:-/tmp/mbim-lenovo-signal.env}"
METRIC="${METRIC:-$(uci_get metric 2)}"
TEST_HOST="${TEST_HOST:-$(uci_get test_host 223.5.5.5)}"
DISABLE_NETIFD_MBIM="${DISABLE_NETIFD_MBIM:-$(uci_get disable_netifd_mbim 0)}"
NATIVE_GL_MARKER="${NATIVE_GL_MARKER:-$(uci_get native_gl_marker 0)}"
STATUS_MBIM_QUERY="${STATUS_MBIM_QUERY:-$(uci_get status_mbim_query 0)}"
USB_PRODUCT="${USB_PRODUCT:-$(uci_get usb_product 17ef:7005)}"
STATS_INTERVAL="${STATS_INTERVAL:-$(uci_get stats_interval 60)}"
STATS_SAMPLES="${STATS_SAMPLES:-$(uci_get stats_samples 240)}"
ZERO_MAC="00:00:00:00:00:00"

ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "$(ts) $*" | tee -a "$LOG"; }

wait_for_device() {
	local i
	modprobe cdc_mbim 2>/dev/null || true
	modprobe usb_wwan 2>/dev/null || true

	for i in $(seq 1 40); do
		[ -c "$DEV" ] && [ -d "/sys/class/net/$IFACE" ] && return 0
		sleep 1
	done

	log "ERROR: $DEV or $IFACE not found"
	return 1
}

detect_usb_bus() {
	local vendor product d v p
	vendor="${USB_PRODUCT%:*}"
	product="${USB_PRODUCT#*:}"

	for d in /sys/bus/usb/devices/*; do
		[ -f "$d/idVendor" ] && [ -f "$d/idProduct" ] || continue
		v="$(cat "$d/idVendor" 2>/dev/null)"
		p="$(cat "$d/idProduct" 2>/dev/null)"
		[ "$v:$p" = "$vendor:$product" ] || continue
		basename "$d"
		return 0
	done

	return 1
}

bus_to_netifd_iface() {
	echo "modem_$(echo "$1" | sed 's/[-.:]/_/g')"
}

resolve_netifd_iface() {
	local bus
	[ -n "$NETIFD_IFACE" ] && [ "$NETIFD_IFACE" != "auto" ] && return 0

	bus="$(detect_usb_bus 2>/dev/null)"
	if [ -n "$bus" ]; then
		NETIFD_IFACE="$(bus_to_netifd_iface "$bus")"
	else
		NETIFD_IFACE="modem_1_1"
	fi
}

clear_gl_native_modem_marker() {
	local bus changed pids
	bus="$(detect_usb_bus 2>/dev/null)" || return 0
	[ -n "$bus" ] || return 0

	if [ "$(cat /var/run/modem/extern_modem_bus 2>/dev/null)" = "$bus" ]; then
		rm -f /var/run/modem/extern_modem_bus
		changed=1
	fi

	if command -v uci >/dev/null 2>&1 && [ "$(uci -q get glmodem.global.usbnode 2>/dev/null)" = "$bus" ]; then
		uci -q delete glmodem.global.usbnode
		uci -q commit glmodem
		changed=1
	fi

	rm -f "/tmp/usbnode/$bus/node" 2>/dev/null || true
	rmdir "/tmp/usbnode/$bus" 2>/dev/null || true
	if [ "$changed" = "1" ]; then
		pids="$(ps w 2>/dev/null | awk '/modem_sim_status_check\\.sh/ && !/awk/ {print $1}')"
		[ -n "$pids" ] && kill $pids >/dev/null 2>&1 || true
	fi
	log "Skipped GL native modem marker for MagicBay LTE2 bus $bus to avoid unsupported SIM-check teardown"
}

ensure_gl_cellular_marker() {
	local bus
	[ "$USE_NETIFD" = "1" ] || return 0
	bus="$(detect_usb_bus 2>/dev/null)" || return 0
	[ -n "$bus" ] || return 0

	if [ "$NATIVE_GL_MARKER" != "1" ]; then
		clear_gl_native_modem_marker
		return 0
	fi

	mkdir -p /var/run/modem "/tmp/usbnode/$bus"
	[ -d "/sys/bus/usb/devices/$bus" ] && ln -snf "/sys/bus/usb/devices/$bus" "/tmp/usbnode/$bus/node"
	echo "$bus" > /var/run/modem/extern_modem_bus

	if command -v uci >/dev/null 2>&1 && uci -q show glmodem.global >/dev/null 2>&1; then
		uci -q set glmodem.global.usbnode="$bus"
		uci -q commit glmodem
	fi

	log "Registered MagicBay LTE2 as GL native cellular bus $bus ($NETIFD_IFACE)"
}

ensure_firewall_wan_member() {
	local zone networks network changed
	command -v uci >/dev/null 2>&1 || return 0
	resolve_netifd_iface

	zone="$(uci -q show firewall 2>/dev/null | sed -n "s/^firewall\.\([^.]*\)\.name='wan'.*/\1/p" | head -n 1)"
	[ -n "$zone" ] || return 0

	networks="$(uci -q get "firewall.$zone.network" 2>/dev/null)"
	for network in $networks; do
		[ "$network" = "$NETIFD_IFACE" ] && return 0
	done

	uci -q add_list "firewall.$zone.network=$NETIFD_IFACE"
	uci -q commit firewall
	changed=1
	log "Added $NETIFD_IFACE to firewall wan zone for NAT and LAN forwarding"

	[ "$changed" = "1" ] && /etc/init.d/firewall reload >/dev/null 2>&1 || true
}

ensure_kmwan_member() {
	command -v uci >/dev/null 2>&1 || return 0
	[ -f /etc/config/kmwan ] || return 0
	resolve_netifd_iface

	uci -q batch <<EOF
set kmwan.$NETIFD_IFACE=member
set kmwan.$NETIFD_IFACE.interface='$NETIFD_IFACE'
set kmwan.$NETIFD_IFACE.metric='$METRIC'
set kmwan.$NETIFD_IFACE.weight='1'
set kmwan.$NETIFD_IFACE.track_mode='force'
set kmwan.$NETIFD_IFACE.addr_type='4'
set kmwan.$NETIFD_IFACE.disabled='0'
set kmwan.$NETIFD_IFACE.check='1'
delete kmwan.$NETIFD_IFACE.tracks
add_list kmwan.$NETIFD_IFACE.tracks='ping,223.5.5.5'
add_list kmwan.$NETIFD_IFACE.tracks='ping,223.6.6.6'
add_list kmwan.$NETIFD_IFACE.tracks='ping,119.29.29.29'
add_list kmwan.$NETIFD_IFACE.tracks='ping,182.254.118.118'
commit kmwan
EOF

	if [ -r /lib/functions/kmwan.sh ] && [ -e /proc/gl-kmwan/config ]; then
		. /lib/functions/kmwan.sh
		type add_netcell >/dev/null 2>&1 && add_netcell "$NETIFD_IFACE" >/dev/null 2>&1 || true
		type gen_weight_route >/dev/null 2>&1 && gen_weight_route >/dev/null 2>&1 || true
	fi

	log "Registered $NETIFD_IFACE as GL cellular WAN member"
}

cidr_to_netmask() {
	local prefix="$1" mask="" i part
	case "$prefix" in
		''|*[!0-9]*) return 1 ;;
	esac
	[ "$prefix" -ge 0 ] 2>/dev/null && [ "$prefix" -le 32 ] 2>/dev/null || return 1

	for i in 1 2 3 4; do
		if [ "$prefix" -ge 8 ]; then
			part=255
			prefix=$((prefix - 8))
		elif [ "$prefix" -gt 0 ]; then
			part=$((256 - (1 << (8 - prefix))))
			prefix=0
		else
			part=0
		fi
		mask="${mask:+$mask.}$part"
	done
	echo "$mask"
}

current_cidr() {
	ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4; exit}'
}

current_dns() {
	awk '/^nameserver / {if (out) out=out" "$2; else out=$2} END {print out}' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null
}

sync_direct_netifd_interface() {
	local cidr="$1" gw="$2" dns="$3" ip prefix netmask dns1
	[ "$USE_NETIFD" = "1" ] && return 0
	command -v uci >/dev/null 2>&1 || return 0

	resolve_netifd_iface
	clear_gl_native_modem_marker

	ip="${cidr%/*}"
	prefix="${cidr#*/}"
	netmask="$(cidr_to_netmask "$prefix")" || {
		log "WARN: cannot sync GL cellular interface, invalid prefix in $cidr"
		return 0
	}
	[ -n "$ip" ] && [ -n "$gw" ] || return 0

	log "Syncing GL cellular interface $NETIFD_IFACE for direct mode ip=$cidr gw=$gw"
	uci -q batch <<EOF
set network.$NETIFD_IFACE=interface
set network.$NETIFD_IFACE.proto='static'
set network.$NETIFD_IFACE.device='$IFACE'
set network.$NETIFD_IFACE.ipaddr='$ip'
set network.$NETIFD_IFACE.netmask='$netmask'
set network.$NETIFD_IFACE.gateway='$gw'
set network.$NETIFD_IFACE.metric='$METRIC'
set network.$NETIFD_IFACE.force_link='1'
set network.$NETIFD_IFACE.defaultroute='1'
set network.$NETIFD_IFACE.disabled='0'
set network.$NETIFD_IFACE.auto='0'
delete network.$NETIFD_IFACE.dns
commit network
EOF

	for dns1 in $dns; do
		uci -q add_list "network.$NETIFD_IFACE.dns=$dns1"
	done
	uci -q commit network

	ensure_firewall_wan_member
	ensure_kmwan_member
	ifup "$NETIFD_IFACE" >/tmp/mbim-lenovo-ifup.log 2>&1 || true
	sleep 1
	log "GL cellular interface $NETIFD_IFACE is marked online for direct mode"
}

sync_current_direct_netifd_interface() {
	local cidr gw dns
	[ "$USE_NETIFD" = "1" ] && return 0
	cidr="$(current_cidr)"
	gw="$(gateway_for_iface)"
	dns="$(current_dns)"
	[ -n "$cidr" ] && [ -n "$gw" ] || return 0
	sync_direct_netifd_interface "$cidr" "$gw" "$dns"
}

configure_netifd_interface() {
	[ "$USE_NETIFD" = "1" ] || return 0
	command -v uci >/dev/null 2>&1 || return 0
	resolve_netifd_iface
	ensure_gl_cellular_marker

	uci -q batch <<EOF
set network.$NETIFD_IFACE=interface
set network.$NETIFD_IFACE.proto='mbim_lenovo'
set network.$NETIFD_IFACE.device='$DEV'
set network.$NETIFD_IFACE.apn='$APN'
set network.$NETIFD_IFACE.auth='none'
set network.$NETIFD_IFACE.metric='$METRIC'
set network.$NETIFD_IFACE.force_link='1'
set network.$NETIFD_IFACE.disabled='0'
set network.$NETIFD_IFACE.auto='1'
commit network
EOF

	ensure_firewall_wan_member
	ensure_kmwan_member
}

netifd_proto_available() {
	command -v ubus >/dev/null 2>&1 || return 0
	ubus call network get_proto_handlers 2>/dev/null | grep -q '"mbim_lenovo"'
}

ensure_netifd_proto_handler() {
	[ "$USE_NETIFD" = "1" ] || return 0
	netifd_proto_available && return 0

	log "Reloading network to register mbim_lenovo protocol handler"
	/etc/init.d/network reload >/dev/null 2>&1 || true
	sleep 2
	netifd_proto_available && return 0

	log "Restarting network once to register mbim_lenovo protocol handler"
	/etc/init.d/network restart >/dev/null 2>&1 || true
	sleep 6
	netifd_proto_available && return 0

	log "WARN: mbim_lenovo protocol handler is still not visible to netifd"
	return 0
}

gateway_for_iface() {
	ip route show default dev "$IFACE" 2>/dev/null | awk '{print $3; exit}'
}

apply_lenovo_link_fix() {
	local gw i
	wait_for_device || return 1

	for i in $(seq 1 30); do
		gw="$(gateway_for_iface)"
		[ -n "$gw" ] && break
		sleep 1
	done

	[ -n "$gw" ] || {
		log "ERROR: no default gateway found on $IFACE"
		return 1
	}

	ip link set "$IFACE" up promisc on 2>/dev/null || true
	ip neigh replace "$gw" lladdr "$ZERO_MAC" nud permanent dev "$IFACE" 2>/dev/null || true
	tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
	tc qdisc add dev "$IFACE" ingress 2>/dev/null || true
	tc filter add dev "$IFACE" ingress matchall action skbedit ptype host 2>/dev/null || true
	apply_firewall
	ensure_kmwan_member
	log "Applied Lenovo LTE2 receive fix on $IFACE gw=$gw"
	return 0
}

wait_for_netifd_up() {
	local i
	for i in $(seq 1 60); do
		if ip -4 -o addr show dev "$IFACE" 2>/dev/null | grep -q ' inet ' && [ -n "$(gateway_for_iface)" ]; then
			return 0
		fi
		sleep 1
	done
	return 1
}

disable_conflicting_netifd() {
	local sections section changed
	[ "$DISABLE_NETIFD_MBIM" = "1" ] || return 0
	command -v uci >/dev/null 2>&1 || return 0

	sections="$(uci -q show network 2>/dev/null | sed -n "s/^network\.\([^.]*\)\.proto='mbim'.*/\1/p")"
	[ -n "$sections" ] || return 0

	for section in $sections; do
		uci -q set "network.$section.disabled=1"
		uci -q set "network.$section.auto=0"
		changed=1
		log "Disabled conflicting netifd MBIM interface: network.$section"
	done

	if [ "$changed" = "1" ]; then
		uci -q commit network
		/etc/init.d/network reload >/dev/null 2>&1 || true
	fi
}

next_tid() {
	sed -n "s/.*TRID: '\([0-9][0-9]*\)'.*/\1/p" | tail -n 1
}

save_tid() {
	[ -n "$TID" ] && echo "$TID" > "$TID_FILE"
}

load_tid() {
	[ -n "$TID" ] && return
	[ -s "$TID_FILE" ] && TID="$(cat "$TID_FILE" 2>/dev/null)"
	[ -n "$TID" ] && return
	TID="$(sed -n "s/.*TRID: '\([0-9][0-9]*\)'.*/\1/p" "$LOG" 2>/dev/null | tail -n 1)"
}

mbim() {
	local timeout_s="$1" out newtid
	shift

	if [ -n "$TID" ]; then
		out="$(timeout "$timeout_s" mbimcli -d "$DEV" --no-open="$TID" "$@" --no-close 2>&1)"
	else
		out="$(timeout "$timeout_s" mbimcli -d "$DEV" "$@" --no-close 2>&1)"
	fi

	echo "$out" >> "$LOG"
	newtid="$(echo "$out" | next_tid)"
	[ -n "$newtid" ] && TID="$newtid" && save_tid
	echo "$out"
}

mbim_query() {
	local timeout_s
	if [ "$USE_NETIFD" = "1" ]; then
		timeout_s="$1"
		shift
		timeout "$timeout_s" mbimcli -d "$DEV" "$@" 2>&1
		return $?
	fi
	load_tid
	mbim "$@"
}

save_signal_cache() {
	local source="$1" provider rssi err reg_state packet_state old_provider old_rssi old_err old_reg_state old_packet_state
	[ -n "$source" ] || return 0

	if [ -s "$SIGNAL_FILE" ]; then
		. "$SIGNAL_FILE"
		old_provider="$provider"
		old_rssi="$rssi"
		old_err="$error_rate"
		old_reg_state="$registration_state"
		old_packet_state="$packet_state"
	fi

	provider="$(echo "$source" | sed -n "s/.*Provider name: '\([^']*\)'.*/\1/p" | tail -n 1)"
	rssi="$(echo "$source" | sed -n "s/.*RSSI \[0-31,99\]: '\([^']*\)'.*/\1/p" | tail -n 1)"
	err="$(echo "$source" | sed -n "s/.*Error rate \[0-7,99\]: '\([^']*\)'.*/\1/p" | tail -n 1)"
	reg_state="$(echo "$source" | sed -n "s/.*Register state: '\([^']*\)'.*/\1/p" | tail -n 1)"
	packet_state="$(echo "$source" | sed -n "s/.*Packet service state: '\([^']*\)'.*/\1/p" | tail -n 1)"
	[ -n "$provider" ] || provider="$old_provider"
	[ -n "$rssi" ] || rssi="$old_rssi"
	[ -n "$err" ] || err="$old_err"
	[ -n "$reg_state" ] || reg_state="$old_reg_state"
	[ -n "$packet_state" ] || packet_state="$old_packet_state"

	{
		[ -n "$provider" ] && printf "provider='%s'\n" "$(printf '%s' "$provider" | sed "s/'/'\\\\''/g")"
		[ -n "$rssi" ] && printf "rssi='%s'\n" "$(printf '%s' "$rssi" | sed "s/'/'\\\\''/g")"
		[ -n "$err" ] && printf "error_rate='%s'\n" "$(printf '%s' "$err" | sed "s/'/'\\\\''/g")"
		[ -n "$reg_state" ] && printf "registration_state='%s'\n" "$(printf '%s' "$reg_state" | sed "s/'/'\\\\''/g")"
		[ -n "$packet_state" ] && printf "packet_state='%s'\n" "$(printf '%s' "$packet_state" | sed "s/'/'\\\\''/g")"
		echo "updated='$(date +%s)'"
	} > "$SIGNAL_FILE.tmp"
	mv "$SIGNAL_FILE.tmp" "$SIGNAL_FILE"
}

write_dns() {
	local dns="$1" dns1
	mkdir -p /tmp/resolv.conf.d
	: > /tmp/resolv.conf.d/resolv.conf.auto

	for dns1 in $dns; do
		echo "nameserver $dns1" >> /tmp/resolv.conf.d/resolv.conf.auto
	done

	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
}

apply_firewall_iptables() {
	iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
		iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
	iptables -C FORWARD -i "$LAN_IF" -o "$IFACE" -j ACCEPT 2>/dev/null || \
		iptables -I FORWARD 1 -i "$LAN_IF" -o "$IFACE" -j ACCEPT
	iptables -C FORWARD -i "$IFACE" -o "$LAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
		iptables -I FORWARD 1 -i "$IFACE" -o "$LAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

apply_firewall_nft() {
	command -v nft >/dev/null 2>&1 || return 1

	nft delete table inet mbim_lenovo >/dev/null 2>&1 || true
	nft -f - <<EOF
table inet mbim_lenovo {
	chain postrouting {
		type nat hook postrouting priority 100; policy accept;
		oifname "$IFACE" masquerade comment "mbim-lenovo"
	}
	chain forward {
		type filter hook forward priority 0; policy accept;
		iifname "$LAN_IF" oifname "$IFACE" accept comment "mbim-lenovo"
		iifname "$IFACE" oifname "$LAN_IF" ct state established,related accept comment "mbim-lenovo"
	}
}
EOF
}

apply_firewall() {
	if command -v fw4 >/dev/null 2>&1 && command -v nft >/dev/null 2>&1; then
		apply_firewall_nft && return 0
	fi

	apply_firewall_iptables
}

remove_firewall_iptables() {
	while iptables -t nat -D POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null; do :; done
	while iptables -D FORWARD -i "$LAN_IF" -o "$IFACE" -j ACCEPT 2>/dev/null; do :; done
	while iptables -D FORWARD -i "$IFACE" -o "$LAN_IF" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; do :; done
}

remove_firewall() {
	nft delete table inet mbim_lenovo >/dev/null 2>&1 || true
	remove_firewall_iptables
}

normalize_stats_config() {
	case "$STATS_INTERVAL" in
		''|*[!0-9]*) STATS_INTERVAL=60 ;;
	esac
	case "$STATS_SAMPLES" in
		''|*[!0-9]*) STATS_SAMPLES=240 ;;
	esac
	[ "$STATS_INTERVAL" -gt 0 ] 2>/dev/null || STATS_INTERVAL=60
	[ "$STATS_SAMPLES" -gt 2 ] 2>/dev/null || STATS_SAMPLES=240
}

read_bytes() {
	local name="$1" value
	value="$(cat "/sys/class/net/$IFACE/statistics/${name}_bytes" 2>/dev/null)"
	[ -n "$value" ] && echo "$value" || echo 0
}

record_stats() {
	local rx tx now tmp
	[ -d "/sys/class/net/$IFACE" ] || return 0

	normalize_stats_config
	now="$(date +%s)"
	rx="$(read_bytes rx)"
	tx="$(read_bytes tx)"

	echo "$now $rx $tx" >> "$STATS_FILE"
	tmp="$STATS_FILE.tmp"
	tail -n "$STATS_SAMPLES" "$STATS_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$STATS_FILE"
}

start_stats() {
	local pid
	normalize_stats_config

	if [ -s "$STATS_PID_FILE" ]; then
		pid="$(cat "$STATS_PID_FILE" 2>/dev/null)"
		[ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && return 0
	fi

	record_stats
	(
		while :; do
			sleep "$STATS_INTERVAL"
			record_stats
		done
	) >/dev/null 2>&1 &
	echo $! > "$STATS_PID_FILE"
}

stop_stats() {
	local pid
	if [ -s "$STATS_PID_FILE" ]; then
		pid="$(cat "$STATS_PID_FILE" 2>/dev/null)"
		[ -n "$pid" ] && kill "$pid" >/dev/null 2>&1 || true
	fi
	rm -f "$STATS_PID_FILE"
}

traffic_history() {
	awk '
		$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ {
			if (out) out = out ";"
			out = out $1 "," $2 "," $3
		}
		END { print out }
	' "$STATS_FILE" 2>/dev/null
}

log_comment() {
	case "$1" in
		"")
			echo "空行：模块输出分隔符"
			;;
		*"Starting MBIM dial on"*)
			echo "开始拨号：准备打开射频、注册网络并建立 MBIM 数据会话"
			;;
		*"Starting netifd MBIM interface"*)
			echo "启动标准接口：让 OpenWrt/GL 后台接管拨号并上报联网状态"
			;;
		*"Added "*" to firewall wan zone"*)
			echo "加入 WAN 防火墙区域：让系统防火墙负责 NAT 和 LAN 转发"
			;;
		*"Registered MagicBay LTE2 as GL cellular bus"*)
			echo "注册为 GL 蜂窝设备：把 Lenovo 模块所在 USB 总线交给 GL 蜂窝网络识别"
			;;
		*"Registered MagicBay LTE2 as GL native cellular bus"*)
			echo "注册为 GL 原生蜂窝设备：仅在手动打开 native_gl_marker 时启用"
			;;
		*"Skipped GL native modem marker"*)
			echo "跳过 GL 原生 modem 标记：避免系统把不受原生支持的 LTE2 误判为无 SIM 并拉下线"
			;;
		*"Reloading network to register mbim_lenovo protocol handler"*)
			echo "刷新网络服务：让 netifd 识别新安装的 mbim_lenovo 协议"
			;;
		*"Restarting network once to register mbim_lenovo protocol handler"*)
			echo "重启一次网络服务：首次安装协议脚本后需要让 netifd 重新加载处理器"
			;;
		*"WARN: mbim_lenovo protocol handler is still not visible"*)
			echo "协议处理器仍未出现：如果持续失败，需要检查 netifd 或协议脚本安装路径"
			;;
		*"Registered "*" as GL cellular WAN member"*)
			echo "注册为 GL 蜂窝上网接口：让 kmwan、联网检测和灯控把它当作蜂窝网络"
			;;
		*"Applied Lenovo LTE2 receive fix"*)
			echo "应用 Lenovo LTE2 收包修正：固定零 MAC 网关并把入站包标记为本机包"
			;;
		*"MBIM netifd interface is up"*)
			echo "标准接口已上线：OpenWrt/GL 后台现在应能识别这条移动网络"
			;;
		*"MBIM netifd interface stopped"*)
			echo "标准接口已停止：已通过 netifd 断开移动网络并清理本包补丁"
			;;
		*"ERROR: "*"did not become ready"*)
			echo "标准接口未就绪：netifd 没有在等待时间内拿到 IP 和默认路由"
			;;
		*"ERROR: no default gateway found"*)
			echo "缺少默认网关：接口可能还没拿到运营商下发的网关"
			;;
		*"Disabled conflicting netifd MBIM interface"*)
			echo "关闭系统自带 MBIM 拨号：避免 netifd 和本脚本同时控制模块"
			;;
		*"ERROR:"*"not found"*)
			echo "设备未识别：没有找到 MBIM 控制口或 wwan 网卡，请检查 USB、驱动和供电"
			;;
		*"ERROR: invalid MBIM IPv4 config"*)
			echo "IP 配置无效：运营商没有下发可用 IPv4，常见原因是 APN、SIM、套餐或信号问题"
			;;
		*"WARN: software radio did not report on yet"*)
			echo "射频状态未确认开启：脚本会继续后续注册和拨号流程"
			;;
		*"WARN: connect did not report activated"*)
			echo "拨号结果未明确显示激活：后续会继续读取 IP 配置确认是否实际成功"
			;;
		*"Configuring "*" ip="*)
			echo "配置数据网卡：写入 IP、网关、DNS、默认路由，并应用零 MAC 接收修正"
			;;
		*"Syncing GL cellular interface "*" for direct mode"*)
			echo "同步蜂窝接口：把直连拨号拿到的 IP、网关和 DNS 写给 GL 网络状态使用"
			;;
		*"GL cellular interface "*" is marked online for direct mode"*)
			echo "蜂窝接口已标记在线：GL 首页应把 MagicBay LTE2 识别为可用网络"
			;;
		*"WARN: cannot sync GL cellular interface"*)
			echo "蜂窝接口同步警告：当前 IP 前缀异常，保留真实链路但暂不更新 GL 状态"
			;;
		*"MBIM is up"*)
			echo "拨号完成：模块链路已建立，路由器应可通过 wwan 上网"
			;;
		*"MBIM already has IPv4 on"*)
			echo "已经在线：本次启动只确认防火墙/NAT 规则，不重新拨号"
			;;
		*"MBIM dial already running as pid"*)
			echo "已有拨号进程：避免重复启动导致模块状态混乱"
			;;
		*"Stopping MBIM"*)
			echo "正在停止：断开 MBIM 会话并清理路由、tc 和防火墙规则"
			;;
		*"MBIM stopped"*)
			echo "已停止：接口和临时状态已清理"
			;;
		*"Session not closed:"*)
			echo "MBIM 会话保持打开：这是为了复用事务 ID，方便连续查询模块状态"
			;;
		*"TRID:"*)
			echo "事务编号：后续 mbimcli 命令会复用这个编号"
			;;
		*"Signal state:"*)
			echo "信号状态：下面几行是模块返回的信号强度和误码相关信息"
			;;
		*"RSSI threshold:"*)
			echo "信号阈值：RSSI 变化超过这个阈值时模块才会上报变化"
			;;
		*"RSSI "*"'"*)
			echo "信号强度：0 到 31，数值越高越好；99 表示未知"
			;;
		*"Error rate threshold:"*)
			echo "误码阈值：误码率变化超过这个阈值时模块才会上报变化"
			;;
		*"Error rate"*"'"*)
			echo "误码率：0 到 7 越低越好；99 或异常值通常以实际联网状态为准"
			;;
		*"Signal strength interval:"*)
			echo "信号上报间隔：模块周期性刷新信号状态的时间"
			;;
		*"Packet service status:"*)
			echo "数据业务状态：下面几行说明是否已附着移动数据网络"
			;;
		*"Network error:"*)
			echo "网络错误字段：unknown 通常表示没有明确错误码"
			;;
		*"Packet service state:"*"attached"*)
			echo "数据网络已附着：SIM 已进入可传输数据的状态"
			;;
		*"Packet service state:"*)
			echo "数据网络状态：attached 表示可用，detached 表示未附着"
			;;
		*"Available data classes:"*)
			echo "可用网络制式：例如 lte 表示当前可用 4G 数据网络"
			;;
		*"Uplink speed:"*)
			echo "模块报告的理论上行速率：不等同于实际测速"
			;;
		*"Downlink speed:"*)
			echo "模块报告的理论下行速率：不等同于实际测速"
			;;
		*"Registration status:"*|*"Registration state:"*|*"Register state:"*)
			echo "注册状态：home 表示本地网络，roaming 表示漫游，searching 表示正在搜网"
			;;
		*"Provider name:"*)
			echo "运营商名称：模块当前注册到的移动网络"
			;;
		*"IP ["*)
			echo "运营商下发的 IP 地址：脚本会把它配置到 wwan 接口"
			;;
		*"Gateway:"*)
			echo "运营商下发的网关：脚本会用它设置默认路由"
			;;
		*"DNS ["*)
			echo "运营商下发的 DNS：脚本会写入 dnsmasq 使用的 resolv 配置"
			;;
		*"MTU:"*)
			echo "链路 MTU：脚本会同步设置到 wwan 接口"
			;;
		*)
			echo "原始模块/系统输出：暂无专门规则，保留原文用于排查"
			;;
	esac
}

annotate_log() {
	local line comment
	printf '%s\n' "$1" | while IFS= read -r line; do
		comment="$(log_comment "$line")"
		if [ -n "$line" ]; then
			printf '%s    # %s\n' "$line" "$comment"
		else
			printf '# %s\n' "$comment"
		fi
	done
}

parse_and_configure() {
	local config="$1"
	local cidr ip gw dns dns1 mtu

	cidr="$(echo "$config" | sed -n "s/.*IP \[0\]: '\([0-9.][0-9.]*\/[0-9][0-9]*\)'.*/\1/p" | head -n 1)"
	gw="$(echo "$config" | sed -n "s/.*Gateway: '\([0-9.][0-9.]*\)'.*/\1/p" | head -n 1)"
	dns="$(echo "$config" | sed -n "s/.*DNS \[[0-9][0-9]*\]: '\([0-9.][0-9.]*\)'.*/\1/p")"
	mtu="$(echo "$config" | sed -n "s/.*MTU: '\([0-9][0-9]*\)'.*/\1/p" | head -n 1)"

	ip="${cidr%/*}"
	if [ -z "$cidr" ] || [ -z "$gw" ] || [ "$ip" = "0.0.0.0" ] || [ "$gw" = "0.0.0.0" ]; then
		log "ERROR: invalid MBIM IPv4 config: cidr=$cidr gw=$gw"
		return 1
	fi
	[ -n "$mtu" ] || mtu=1500

	log "Configuring $IFACE ip=$cidr gw=$gw dns=$(echo $dns) mtu=$mtu"
	ip link set "$IFACE" down 2>/dev/null || true
	ip addr flush dev "$IFACE" 2>/dev/null || true
	ip link set "$IFACE" up promisc on mtu "$mtu"
	ip addr add "$cidr" dev "$IFACE"
	ip neigh replace "$gw" lladdr "$ZERO_MAC" nud permanent dev "$IFACE"
	ip route replace default via "$gw" dev "$IFACE" src "$ip" metric "$METRIC" onlink

	tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
	tc qdisc add dev "$IFACE" ingress 2>/dev/null || true
	tc filter add dev "$IFACE" ingress matchall action skbedit ptype host 2>/dev/null || true

	[ -n "$dns" ] && write_dns "$dns"
	sync_direct_netifd_interface "$cidr" "$gw" "$dns"
	ip link set "$IFACE" up promisc on mtu "$mtu"
	ip neigh replace "$gw" lladdr "$ZERO_MAC" nud permanent dev "$IFACE"
	ip route replace default via "$gw" dev "$IFACE" src "$ip" metric "$METRIC" onlink
	tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
	tc qdisc add dev "$IFACE" ingress 2>/dev/null || true
	tc filter add dev "$IFACE" ingress matchall action skbedit ptype host 2>/dev/null || true
	apply_firewall
	return 0
}

dial_netifd() {
	local pid
	resolve_netifd_iface

	if [ -s "$PID_FILE" ]; then
		pid="$(cat "$PID_FILE" 2>/dev/null)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			log "MBIM netifd start already running as pid $pid"
			return 0
		fi
	fi

	echo $$ > "$PID_FILE"
	trap 'rm -f "$PID_FILE"' EXIT INT TERM
	log "Starting netifd MBIM interface $NETIFD_IFACE on $DEV, APN=$APN"
	configure_netifd_interface
	ensure_netifd_proto_handler
	wait_for_device || return 1

	ifup "$NETIFD_IFACE" >/tmp/mbim-lenovo-ifup.log 2>&1 || true
	if wait_for_netifd_up; then
		apply_lenovo_link_fix || return 1
		start_stats
		log "MBIM netifd interface is up: $NETIFD_IFACE ($IFACE)"
		rm -f "$PID_FILE"
		trap - EXIT INT TERM
		return 0
	fi

	log "ERROR: $NETIFD_IFACE did not become ready"
	tail -n 20 /tmp/mbim-lenovo-ifup.log 2>/dev/null >> "$LOG"
	return 1
}

dial() {
	local out config i pid

	if [ "$USE_NETIFD" = "1" ]; then
		dial_netifd
		return $?
	fi

	if ip -4 -o addr show dev "$IFACE" 2>/dev/null | grep -q ' inet '; then
		sync_current_direct_netifd_interface
		apply_lenovo_link_fix || true
		apply_firewall
		start_stats
		log "MBIM already has IPv4 on $IFACE"
		return 0
	fi

	if [ -s "$PID_FILE" ]; then
		pid="$(cat "$PID_FILE" 2>/dev/null)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			log "MBIM dial already running as pid $pid"
			return 0
		fi
	fi

	TID=""
	echo $$ > "$PID_FILE"
	trap 'rm -f "$PID_FILE"' EXIT INT TERM
	: > "$LOG"
	log "Starting MBIM dial on $DEV ($IFACE), APN=$APN"

	disable_conflicting_netifd
	wait_for_device || return 1

	mbim 20 --set-radio-state=on >/dev/null || true
	sleep 3
	out="$(mbim 20 --query-radio-state)"
	echo "$out" | grep -q "Software radio state: 'on'" || log "WARN: software radio did not report on yet"

	mbim 20 --register-automatic >/dev/null || true
	sleep 5
	out="$(mbim 20 --query-registration-state)"
	save_signal_cache "$out"
	mbim 30 --attach-packet-service >/dev/null || true
	out="$(mbim 20 --query-packet-service-state)"
	save_signal_cache "$(cat "$SIGNAL_FILE" 2>/dev/null; printf '\n%s\n' "$out")"
	out="$(mbim 20 --query-signal-state)"
	save_signal_cache "$(cat "$SIGNAL_FILE" 2>/dev/null; printf '\n%s\n' "$out")"

	out="$(mbim 45 --connect=apn=$APN)"
	echo "$out" | grep -q "Activation state: 'activated'" || log "WARN: connect did not report activated"
	config="$out"

	for i in 1 2 3 4 5; do
		echo "$config" | grep -q "IP \[0\]: '[1-9]" && break
		sleep 2
		config="$(mbim 20 --query-ip-configuration=0)"
	done

	parse_and_configure "$config" || return 1
	log "MBIM is up"
	rm -f "$PID_FILE"
	trap - EXIT INT TERM
	start_stats
}

stop_modem() {
	local pid
	resolve_netifd_iface
	log "Stopping MBIM"

	if [ -s "$PID_FILE" ]; then
		pid="$(cat "$PID_FILE" 2>/dev/null)"
		[ -n "$pid" ] && [ "$pid" != "$$" ] && kill "$pid" >/dev/null 2>&1 || true
	fi

	if [ "$USE_NETIFD" = "1" ]; then
		ifdown "$NETIFD_IFACE" >/tmp/mbim-lenovo-ifdown.log 2>&1 || true
		ip route del default dev "$IFACE" 2>/dev/null || true
		tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
		ip link set "$IFACE" promisc off 2>/dev/null || true
		stop_stats
		rm -f "$PID_FILE"
		log "MBIM netifd interface stopped: $NETIFD_IFACE"
		return 0
	fi

	load_tid
	[ -n "$TID" ] && timeout 15 mbimcli -d "$DEV" --no-open="$TID" --disconnect=0 >/dev/null 2>&1 || true
	timeout 10 mbimcli -d "$DEV" --set-radio-state=off >/dev/null 2>&1 || true
	ifdown "$NETIFD_IFACE" >/tmp/mbim-lenovo-ifdown.log 2>&1 || true
	ip route del default dev "$IFACE" 2>/dev/null || true
	ip addr flush dev "$IFACE" 2>/dev/null || true
	tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
	ip link set "$IFACE" promisc off down 2>/dev/null || true
	remove_firewall
	stop_stats
	rm -f "$TID_FILE" "$PID_FILE"
	log "MBIM stopped"
}

detach_modem() {
	resolve_netifd_iface
	log "MagicBay LTE2 detached, cleaning runtime state"
	ifdown "$NETIFD_IFACE" >/tmp/mbim-lenovo-ifdown.log 2>&1 || true
	ip route del default dev "$IFACE" 2>/dev/null || true
	tc qdisc del dev "$IFACE" ingress 2>/dev/null || true
	ip link set "$IFACE" promisc off down 2>/dev/null || true
	remove_firewall
	stop_stats
	rm -f "$TID_FILE" "$PID_FILE" "$SIGNAL_FILE"
	log "Detached cleanup complete"
}

status_kv() {
	local ipv4 ipv6 gw dns route rx tx reg sig packet provider rssi err internet enabled running logtail annotated netifd_status netifd_up reg_state packet_state
	resolve_netifd_iface
	ipv4="$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -n 1)"
	ipv6="$(ip -6 -o addr show dev "$IFACE" scope global 2>/dev/null | awk '{if (out) out=out" "$4; else out=$4} END {print out}')"
	gw="$(ip route show default dev "$IFACE" 2>/dev/null | awk '{print $3; exit}')"
	dns="$(awk '/^nameserver / {if (out) out=out" "$2; else out=$2} END {print out}' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null)"
	route="$(ip route show default dev "$IFACE" 2>/dev/null | head -n 1)"
	rx="$(cat /sys/class/net/$IFACE/statistics/rx_bytes 2>/dev/null)"
	tx="$(cat /sys/class/net/$IFACE/statistics/tx_bytes 2>/dev/null)"
	[ -n "$rx" ] || rx=0
	[ -n "$tx" ] || tx=0
	/etc/init.d/mbim-lenovo enabled >/dev/null 2>&1 && enabled=1 || enabled=0
	netifd_status="$(ifstatus "$NETIFD_IFACE" 2>/dev/null)"
	echo "$netifd_status" | grep -q '"up": true' && netifd_up=1 || netifd_up=0
	[ -n "$ipv4" ] && running=1 || running=0
	[ "$running" = "1" ] && record_stats
	ping -c 1 -W 1 "$TEST_HOST" >/dev/null 2>&1 && internet=1 || internet=0

	if [ "$STATUS_MBIM_QUERY" = "1" ] && [ -c "$DEV" ] && [ "$running" != "1" ]; then
		reg="$(mbim_query 8 --query-registration-state 2>/dev/null)"
		sig="$(mbim_query 8 --query-signal-state 2>/dev/null)"
		packet="$(mbim_query 8 --query-packet-service-state 2>/dev/null)"
	elif [ -s "$LOG" ]; then
		reg="$(tail -n 220 "$LOG" 2>/dev/null)"
		sig="$reg"
		packet="$reg"
	fi
	if [ -s "$SIGNAL_FILE" ]; then
		. "$SIGNAL_FILE"
	fi

	[ -n "$provider" ] || provider="$(echo "$reg" | sed -n "s/.*Provider name: '\([^']*\)'.*/\1/p" | tail -n 1)"
	[ -n "$provider" ] || provider="$(sed -n "s/.*Provider name: '\([^']*\)'.*/\1/p" "$LOG" 2>/dev/null | tail -n 1)"
	[ -n "$rssi" ] || rssi="$(echo "$sig" | sed -n "s/.*RSSI \[0-31,99\]: '\([^']*\)'.*/\1/p" | tail -n 1)"
	[ -n "$err" ] || err="$(echo "$sig" | sed -n "s/.*Error rate \[0-7,99\]: '\([^']*\)'.*/\1/p" | tail -n 1)"
	[ -n "$reg_state" ] || reg_state="$(echo "$reg" | sed -n "s/.*Register state: '\([^']*\)'.*/\1/p" | tail -n 1)"
	[ -n "$packet_state" ] || packet_state="$(echo "$packet" | sed -n "s/.*Packet service state: '\([^']*\)'.*/\1/p" | tail -n 1)"
	if [ "$running" = "1" ]; then
		case "$reg_state" in
			""|deregistered|searching) reg_state="home" ;;
		esac
		case "$packet_state" in
			""|detached) packet_state="attached" ;;
		esac
	elif [ ! -c "$DEV" ] && [ ! -d "/sys/class/net/$IFACE" ]; then
		provider=""
		rssi=""
		err=""
		reg_state=""
		packet_state=""
	fi
	logtail="$(tail -n 18 "$LOG" 2>/dev/null | sed 's/[[:cntrl:]]//g')"
	annotated="$(annotate_log "$logtail")"

	echo "dev_present=$([ -c "$DEV" ] && echo 1 || echo 0)"
	echo "iface_present=$([ -d "/sys/class/net/$IFACE" ] && echo 1 || echo 0)"
	echo "mode=$([ "$USE_NETIFD" = "1" ] && echo netifd || echo direct)"
	echo "netifd_iface=$NETIFD_IFACE"
	echo "netifd_up=$netifd_up"
	echo "enabled=$enabled"
	echo "running=$running"
	echo "internet=$internet"
	echo "iface=$IFACE"
	echo "apn=$APN"
	echo "lan_if=$LAN_IF"
	echo "ipv4=$ipv4"
	echo "ipv6=$ipv6"
	echo "gateway=$gw"
	echo "dns=$dns"
	echo "route=$route"
	echo "rx_bytes=$rx"
	echo "tx_bytes=$tx"
	echo "provider=$provider"
	echo "rssi=$rssi"
	echo "error_rate=$err"
	echo "stats_interval=$STATS_INTERVAL"
	echo "stats_samples=$STATS_SAMPLES"
	echo "traffic_history=$(traffic_history)"
	echo "registration_state=$reg_state"
	echo "packet_state=$packet_state"
	echo "log=$(printf '%s' "$annotated" | sed ':a;N;$!ba;s/\n/\\n/g')"
}

ui_action() {
	local action="$1"
	case "$action" in
		ui-start)
			/etc/init.d/mbim-lenovo start >/tmp/mbim-lenovo-ui.log 2>&1 &
			echo "action=start"
			;;
		ui-stop)
			( "$0" stop >/tmp/mbim-lenovo-ui.log 2>&1 ) &
			echo "action=stop"
			;;
		ui-restart)
			( "$0" restart >/tmp/mbim-lenovo-ui.log 2>&1 ) &
			echo "action=restart"
			;;
	esac
	status_kv
}

refresh_signal() {
	local out
	load_tid
	out="$(mbim 12 --query-signal-state)"
	save_signal_cache "$out"
	status_kv
}

case "$1" in
	firewall)
		apply_firewall
		;;
	repair)
		apply_lenovo_link_fix
		start_stats
		;;
	stop)
		stop_modem
		;;
	detach)
		detach_modem
		;;
	restart)
		stop_modem
		sleep 2
		dial
		;;
	status)
		status_kv
		;;
	signal)
		refresh_signal
		;;
	ui-start|ui-stop|ui-restart)
		ui_action "$1"
		;;
	start|"")
		dial
		;;
	*)
		echo "Usage: $0 {start|stop|detach|restart|status|signal|firewall|repair|ui-start|ui-stop|ui-restart}" >&2
		exit 2
		;;
esac
