#!/bin/sh

# Test suite(TM)
#
# This is expensive
#
PROJECT=chris-temp-test-deploy-script
ZONE=europe-west6-a
NETWORKS="nairobinet oxfordnet ghostnet mainnet"
MODES="rolling full archive"
CLOUD=gcp
cleanupscript="test_cleanup.$$.sh"

HOSTLIST=""

export TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=yes

[ ! -z "$1" ] && CLOUD="$1"
[ ! -z "$2" ] && NETWORKS="$2"
[ ! -z "$3" ] && MODES="$3"

# 
#
[ "$CLOUD" = "local" ] && echo "Don't test locally - you'll get in a mess" \
		&& exit 0

# Multicloud TM
#
if [ ! -f "functions_$CLOUD.sh" ]; then
	echo "Cloud Provider $CLOUD not supported - create functions_$CLOUD.sh"
	exit 1
fi
. ./functions_$CLOUD.sh

# Specific test parameters
#
[ "$CLOUD" = "gcp" ] && PROJECT=chris-temp-test-deploy-script && ZONE=europe-west6-a

echo "===> Testing on $CLOUD"
echo "Networks: $NETWORKS"
echo "Modes:    $MODES"
echo "Proj/Act: $PROJECT"
echo "Zone:     $ZONE"
sleep 2

# Avoid publishing IP addresses in Git
#
RPC=""
if [ -f "rpcip" ]; then
	RPC="-R `cat rpcip`"
fi

rm -f $cleanupscript
for net in ${NETWORKS}; do
	for mode in ${MODES}; do

		echo "===> Deploying ${net}/${mode}"
		host=test-$mode-$net
		sh deploy.sh -W -z $ZONE -p $PROJECT -s eu -n ${net} -t $mode ${RPC} $host > log.$net.$mode.txt 2>&1
		if [ "$?" != "0" ]; then
			echo "FAILED: see log.$net.$mode.txt"
			echo "deploy.sh -W -z $ZONE -p $PROJECT -s eu -n ${net} -t $mode ${RPC} $host > log.$net.$mode.txt"
		else
			HOSTLIST="$HOSTLIST $host"
		fi

		print_ssh_details $PROJECT $ZONE $host yes >> $cleanupscript
		echo "rm -f log.$net.$mode.txt" >> $cleanupscript

	done
done
echo "rm -f $cleanupscript" >> $cleanupscript

[ -z "$RPC" ] && echo "No RPC setup - exiting" && exit 0

# Get IPs and check bootstrapped
#
while [ ! -z "$HOSTLIST" ]; do
	NHOSTLIST=""
	
	echo "===> Sleeping..."
	sleep 300 # 5 minutes

	TMP=`mktemp /tmp/_destroyXXXXXX`
	for host in $HOSTLIST; do
		_IP=$(getip $PROJECT $ZONE $host)
		printf "===> Testing host $host ($_IP): "
		octez-client -E http://$_IP:8732 bootstrapped >/dev/null 2>&1
		if [ "$?" != "0" ]; then
			 echo "Cannot connect"
			 NHOSTLIST="$NHOSTLIST $host"
		else
			echo "Bootstrapped"
			octez-client -E http://$_IP:8732 bootstrapped
			echo "===> Decommissioning $host"
			print_ssh_details $PROJECT $ZONE $host yes > $TMP
			source $TMP
			rm -f $TMP
		fi

	done
	HOSTLIST="$NHOSTLIST"

done

echo "===> Running cleanup script"
sh $cleanupscript


