#!/bin/sh

# I expect these on the command line and I expect to be called by
# a deployment script - see values for $1, ... below
# it has already checked for a snapshot.

OS=debian-12
PKGSITE=https://pkgbeta.tzinit.org
SNAPREG=eu
MODE=rolling
NETWORK=mainnet
TEZTNETS=https://teztnets.com
ARCH=amd64
VER="19.0rc1-1"

NODEHOME=/var/tezos/node # XXX in later packages this will change

[ ! -z "$8" ] && VER="$8"
[ ! -z "$7" ] && ARCH="$7" 
[ ! -z "$6" ] && OS="$6"
[ ! -z "$5" ] && PKGSITE="$5"
[ ! -z "$4" ] && SNAPREG="$4"
[ ! -z "$3" ] && RPC="$3"
[ ! -z "$2" ] && MODE="$2"
[ ! -z "$1" ] && NETWORK="$1"

CLIENTPKG="octez-client_${VER}_${ARCH}.deb" 
NODEPKG="octez-node_${VER}_${ARCH}.deb"

# Snapshot service
#
SNAPSHOTURL="https://snapshot.$SNAPREG.tzinit.org/$NETWORK/$MODE"

[ "$MODE" = "archive" ] && \
    SNAPSHOTURL="https://snapshot.$SNAPREG.tzinit.org/$NETWORK/archive.tar.lz4"

# Network URL
#
NETWORKURL="$NETWORK"

if [ "$NETWORK" != "mainnet" ] && [ "$NETWORK" != "ghostnet" ]; then
    # Test network
    #
    NETWORKURL="$TEZTNETS/$NETWORK"
fi

date
echo "===> Setting up node"
echo "Network URL: $NETWORKURL"
echo "Mode:        $MODE"
echo "Snapshot:    $SNAPSHOTURL"

echo "===> Upgrading OS"
apt update
apt upgrade -y
apt install -y lz4

echo "===> Fetching Octez"
wget $PKGSITE/$OS/$CLIENTPKG
wget $PKGSITE/$OS/$NODEPKG

echo "===> Installing Octez"
apt install -y ./$CLIENTPKG
apt install -y ./$NODEPKG

rm -f $CLIENTPKG $NODEPKG


mkdir -p $NODEHOME
chown tezos:tezos $NODEHOME
if [ $MODE = "archive" ]; then
    echo "===> Fetching and decompressing archive"
    cd $NODEHOME
    wget -nv -O - ${SNAPSHOTURL} | lz4cat | tar xvf -
    chown tezos:tezos -R $NODEHOME
    cd 
fi


RPCOPTIONS="--rpc-addr='127.0.0.1:8732'"
if [ "$RPC" = "yes" ]; then
    RPCOPTIONS="--rpc-addr='0.0.0.0:8732' --allow-all-rpc='0.0.0.0:8732'" # Assumed to be firewalled - could be better
fi

echo "===> Configuring node"
su - tezos -c "octez-node config init --data-dir ${NODEHOME} \
                        --network=${NETWORKURL} \
                        --history-mode=${MODE} \
                        --net-addr='[::]:9732' \
                        ${RPCOPTIONS}"

if [ $MODE != "archive" ] ; then
    echo "===> Fetching Snapshot"
    wget -nv ${SNAPSHOTURL} -O /var/tezos/__snapshot
    su - tezos -c "octez-node snapshot import /var/tezos/__snapshot --data-dir $NODEHOME"
    rm -f /var/tezos/__snapshot
    if [ ! -d $NODEHOME/context ]; then
        echo "Warning: Snapshot import has failed."
        echo "We will attempt to start the node anyway..."
    fi
fi

echo "===> Enabling services"
systemctl enable octez-node

echo "===> Rebooting to clean and start"
shutdown -r now


