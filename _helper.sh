#!/bin/sh

# I expect these on the command line and I expect to be called by
# a deployment script
# ${NETWORK} ${MODE} ${SNAPREG} ${PKGSITE} ${OS}

set -eu

OS=debian-12
PKGSITE=https://pkgbeta.tzinit.org
SNAPREG=eu
MODE=rolling
NETWORK=mainnet
TEZTNETS=https://teztnets.com
VER="19.0rc1-1"

NODEHOME=/var/tezos/node # XXX in later packages this will change

[ ! -z "$6" ] && VER="$6" 
[ ! -z "$5" ] && OS="$5"
[ ! -z "$4" ] && PKGSITE="$4"
[ ! -z "$3" ] && SNAPREG="$3"
[ ! -z "$2" ] && MODE="$2"
[ ! -z "$1" ] && NETWORK="$1"

CLIENTPKG="octez-client_${VER}_amd64.deb" 
NODEPKG="octez-node_${VER}_amd64.deb"

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

echo "===> Configuring node"
su - tezos -c "octez-node config init --data-dir ${NODEHOME} \
                        --network=${NETWORKURL} \
                        --history-mode=${MODE} \
                        --rpc-addr='127.0.0.0:8732' \
                        --net-addr='[::]:9732'"

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


