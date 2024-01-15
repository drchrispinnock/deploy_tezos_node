
PNZMANDATORY=no # No project or zone needed here
OVERRIDERPC=yes # No firewalls to access localhost
WARNTIME=0	# No need to warn about clouds

software_checks() {

	# Check and override OS supplied on CLI
	#
	_os=`uname -s`
	NEWOS=$OS

	case $_os in
		Linux)
			which apt >/dev/null 2>&1
    			[ "$?" != "0" ] \
				&& echo "Local Linux support only works on apt/dpkg systems" >&2 \
				exit 1
			;;

		*)
			echo "$_os not currently supported by the script"
			exit 1
			;;
	esac

	_brand=$(awk -F'\\' '{print $1}' < /etc/issue)
	_type=$(echo $_brand | awk -F' ' '{print $1}')
	case $_type in
		Debian)
			_ver=$(echo $_brand | awk -F' ' '{print $3}')
			NEWOS=debian-$_ver
		;;
		*)
			echo "$_brand not yet supported by this script"
			exit 1
			;;
	esac
	[ "$NEWOS" != "$OS" ] && echo "===> Overriding OS to $NEWOS" \
		&& OS=$NEWOS

	# Check sudo
	#
	which sudo >/dev/null 2>&1
	[ "$?" != "0" ] && echo "I need sudo installed" && exit 1

	sudo -v
	[ "$?" != "0" ] && echo "I need sudo access!" && exit 1

}

enable_compute() {
    # Usage: enable_compute PROJECT
    #
    true
}

findosimage() {
    # Usage: findosimage OS
}

create_vm() {
	true
}

wait_gracefully() {
	true
}

create_firewall() {

	true
}

print_ssh_details() {
	true
}

copy_and_exec() {
    P=$1
    Z=$2
    H=$3
    N=$4
    CLI=$5

    nohup sudo sh $H $CLI > /tmp/install.log 2>&1 &

}

getip() {
	# XXX

	true
}

followlog() {
        tail -f /tmp/install.log
}
