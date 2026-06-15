#!/bin/sh

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_mbim_lenovo_init_config() {
	available=1
	no_device=1
	proto_config_add_string "device:device"
	proto_config_add_string apn
	proto_config_add_string delay
	proto_config_add_defaults
}

mbim_lenovo_log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') netifd[$$] $*" >> /tmp/mbim-lenovo.log
}

mbim_lenovo_next_tid() {
	sed -n "s/.*TRID: '\([0-9][0-9]*\)'.*/\1/p" | tail -n 1
}

mbim_lenovo_wait_ifname() {
	local device="$1" i devname devpath ifname
	devname="$(basename "$device")"

	for i in $(seq 1 40); do
		devpath="$(readlink -f "/sys/class/usbmisc/$devname/device/" 2>/dev/null)"
		if [ -n "$devpath" ] && [ -d "$devpath/net" ]; then
			ifname="$(ls "$devpath/net" 2>/dev/null | head -n 1)"
			[ -n "$ifname" ] && echo "$ifname" && return 0
		fi
		sleep 1
	done

	return 1
}

mbim_lenovo_setup() {
	local interface="$1"
	local device apn delay ifname tid tid_file
	local out config cidr ip mask gw dns mtu dns1 i reg state
	local metric defaultroute peerdns $PROTO_DEFAULT_OPTIONS

	json_get_vars device apn delay $PROTO_DEFAULT_OPTIONS
	[ -n "$device" ] || device="/dev/cdc-wdm0"
	[ -n "$apn" ] || apn="cmnet"
	[ -n "$metric" ] || metric="2"
	tid_file="/var/run/mbim-lenovo-$interface.tid"
	rm -f "$tid_file"

	[ -c "$device" ] || {
		mbim_lenovo_log "ERROR: $device does not exist"
		proto_notify_error "$interface" NO_DEVICE
		proto_set_available "$interface" 0
		return 1
	}

	ifname="$(mbim_lenovo_wait_ifname "$device")" || {
		mbim_lenovo_log "ERROR: no network interface for $device"
		proto_notify_error "$interface" NO_IFNAME
		proto_set_available "$interface" 0
		return 1
	}

	[ -n "$delay" ] && sleep "$delay"
	mbim_lenovo_log "Starting Lenovo MBIM netifd protocol on $device ($ifname), APN=$apn"

	mbim_call() {
		local timeout_s="$1" newtid
		shift
		if [ -n "$tid" ]; then
			out="$(timeout "$timeout_s" mbimcli -d "$device" --no-open="$tid" "$@" --no-close 2>&1)"
		else
			out="$(timeout "$timeout_s" mbimcli -d "$device" "$@" --no-close 2>&1)"
		fi
		echo "$out" >> /tmp/mbim-lenovo.log
		newtid="$(echo "$out" | mbim_lenovo_next_tid)"
		[ -n "$newtid" ] && tid="$newtid" && echo "$tid" > "$tid_file"
		return 0
	}

	mbim_call 20 --set-radio-state=on >/dev/null
	sleep 4

	for i in $(seq 1 12); do
		mbim_call 20 --register-automatic >/dev/null
		mbim_call 20 --query-registration-state >/dev/null
		reg="$out"
		state="$(echo "$reg" | sed -n "s/.*Register state: '\([^']*\)'.*/\1/p" | head -n 1)"
		mbim_lenovo_log "Registration wait: state=${state:-unknown}"
		case "$state" in
			home|roaming) break ;;
		esac
		sleep 5
	done

	mbim_call 30 --attach-packet-service >/dev/null
	mbim_call 20 --query-packet-service-state >/dev/null
	mbim_call 45 --connect=apn="$apn" >/dev/null
	config="$out"

	for i in $(seq 1 8); do
		echo "$config" | grep -q "IP \[0\]: '[1-9]" && break
		sleep 2
		mbim_call 20 --query-ip-configuration=0 >/dev/null
		config="$out"
	done

	cidr="$(echo "$config" | sed -n "s/.*IP \[0\]: '\([0-9.][0-9.]*\/[0-9][0-9]*\)'.*/\1/p" | head -n 1)"
	gw="$(echo "$config" | sed -n "s/.*Gateway: '\([0-9.][0-9.]*\)'.*/\1/p" | head -n 1)"
	dns="$(echo "$config" | sed -n "s/.*DNS \[[0-9][0-9]*\]: '\([0-9.][0-9.]*\)'.*/\1/p")"
	mtu="$(echo "$config" | sed -n "s/.*MTU: '\([0-9][0-9]*\)'.*/\1/p" | head -n 1)"
	ip="${cidr%/*}"
	mask="${cidr#*/}"

	if [ -z "$cidr" ] || [ -z "$gw" ] || [ "$ip" = "0.0.0.0" ] || [ "$gw" = "0.0.0.0" ]; then
		mbim_lenovo_log "ERROR: invalid IP config: cidr=$cidr gw=$gw"
		proto_notify_error "$interface" CONFIG_FAILED
		return 1
	fi

	[ -n "$mtu" ] || mtu=1500
	ip link set "$ifname" mtu "$mtu" 2>/dev/null || true

	proto_init_update "$ifname" 1
	proto_add_ipv4_address "$ip" "$mask"
	[ "$defaultroute" = 0 ] || proto_add_ipv4_route "0.0.0.0" 0 "$gw" "$ip" "$metric"
	[ "$peerdns" = 0 ] || {
		for dns1 in $dns; do
			proto_add_dns_server "$dns1"
		done
	}
	proto_send_update "$interface"

	sleep 1
	ip link set "$ifname" up promisc on 2>/dev/null || true
	ip neigh replace "$gw" lladdr 00:00:00:00:00:00 nud permanent dev "$ifname" 2>/dev/null || true
	tc qdisc del dev "$ifname" ingress 2>/dev/null || true
	tc qdisc add dev "$ifname" ingress 2>/dev/null || true
	tc filter add dev "$ifname" ingress matchall action skbedit ptype host 2>/dev/null || true
	[ -x /usr/bin/mbim-lenovo-up.sh ] && /usr/bin/mbim-lenovo-up.sh repair >/dev/null 2>&1 || true

	mbim_lenovo_log "Lenovo MBIM netifd protocol is up: $interface ip=$cidr gw=$gw"
}

proto_mbim_lenovo_setup() {
	mbim_lenovo_setup "$@"
}

proto_mbim_lenovo_teardown() {
	local interface="$1"
	local device tid tid_file

	json_get_vars device
	[ -n "$device" ] || device="/dev/cdc-wdm0"
	tid_file="/var/run/mbim-lenovo-$interface.tid"
	[ -s "$tid_file" ] && tid="$(cat "$tid_file" 2>/dev/null)"

	mbim_lenovo_log "Stopping Lenovo MBIM netifd protocol: $interface"
	[ -n "$tid" ] && timeout 15 mbimcli -d "$device" --no-open="$tid" --disconnect=0 >/dev/null 2>&1 || true
	rm -f "$tid_file"

	proto_init_update "*" 0
	proto_send_update "$interface"
}

[ -n "$INCLUDE_ONLY" ] || add_protocol mbim_lenovo
