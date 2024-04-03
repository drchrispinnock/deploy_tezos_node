#!/bin/sh
#
# Deploy a Tezos node
#

# Tezos packaging and snapshotting
#
PKGSITE="https://pkgbeta.tzinit.org"
VERS=19.0
REV=1
SNAPREG="eu"

# Tezos network defaults
#
NETWORK="mainnet"
MODE="rolling"
RPCALLOWLIST="null"
OVERRIDERPC="no" # For local support which sets to "yes"
RPC="no"

# Defaults XXX will need work for other cloud providers
#
OS=debian-12
ARCH=amd64
CLOUDPROVIDER=gcp
PNZMANDATORY=yes

# Disc sizes (root currently unused because it is a pain to
# deal with a second disc)
#
DISC_ROOT="20"
DISC_ROLLING="100"
DISC_FULL="300"
DISC_ARCHIVE="2000"
DISC_SIZE="100" # Default disc size

# External helper script to use
#
HELPERSCRIPT="_helper.sh"

WARNTIME=10

warn() {
    echo "$1" >&2
}

leave() {
    echo "$1" >&2
    exit 1
}

usage() {
    leave "Usage: $0 -p project -z zone [...options...] [name]
    where options are:
        -C         - Cloud Provider - gcp (default) aws, ...)
        -p project - specify the project to use (mandatory)
        -z zone    - specify the zone to use (mandatory) 
        -t type    - the type of node required rolling (default) or full or archive
        -n network - the Tezos network (default is mainnet)
        -R address list - RPC allow list for firewall
        -s region  - snapshot server region: eu (default), asia or us
        -m machine - machine profile (default is e2-standard-4)
        -d size    - Size of disc (defaults for each type)
        -o OS      - Name for OS (defaults to debian-12)
        -v ver     - version of Octez
        -r revision - package revision
        -F         - follow the installation log
        -S         - continue even if there are no snapshots
        -W         - suppress disclaimer

    and
        name       - the name of the node (or we construct one)" 
}       

# Setup
#
ZONE="___notset___"
PROJECT="___notset___"

FOLLOW="0"
IGNORESNAP="no"

# Initial checks
#
CHECKFORSNAP=1
which gcloud >/dev/null 2>&1
[ "$?" != "0" ] && CHECKFORSNAP=0 && warn "gcloud not installed - cannot check for snapshot"

which wget > /dev/null 2>&1
[ "$?" != "0" ] && \
    leave "Please install wget on your machine"



# Command-line magic
#
while [ $# -gt 0 ]; do
        case $1 in
        -d)     DISC_SIZE="$2"; shift ;;
        -C)     CLOUDPROVIDER="$2"; shift ;;
        -m)     MACHINE="$2"; shift; ;;
        -n)     NETWORK="$2"; shift; ;;
        -o)     OS="$2"; shift; ;;
        -p)     PROJECT="$2"; shift; ;;
        -r)     REV="$2"; shift; ;;
        -R)     [ "$OVERRIDERPC" = "no" ] && RPCALLOWLIST="$2"; shift; ;;
        -s)     SNAPREG="$2"; shift; ;;
        -S)     IGNORESNAP="yes"; ;;
        -t)     MODE="$2"; shift; ;;
        -v)     VERS="$2"; shift; ;;
        -z)     ZONE="$2" shift; ;;
        -F)     FOLLOW=1; ;;
        -W)     WARNTIME=0; ;;
        -*)     usage; ;;
        *)      break; # rest of args are targets
        esac
        shift
done

[ "$CHECKFORSNAP" = "0" ] && IGNORESNAP="yes"

# Cloud Provider specific functions
#
[ ! -f "functions_$CLOUDPROVIDER.sh" ] && leave "Cloud provider $CLOUDPROVIDER not supported"
. ./functions_$CLOUDPROVIDER.sh

software_checks;

NAME="tezos-node-$NETWORK-$MODE"
[ ! -z "$1" ] && NAME="$1"

if [ "$PNZMANDATORY" = "yes" ]; then
	[ "$ZONE" = "___notset___" ] && leave "Zone must be specified with -z for $CLOUDPROVIDER"
	[ "$PROJECT" = "___notset___" ] && leave "Project must be specified with -p for $CLOUDPROVIDER"
fi

# Check valid region
#
case $SNAPREG in
    eu)
        ;;
    asia|us)
        [ "$MODE" = "archive" ] && warn "Archives on in region eu"
        ;;
    *)
        leave "Unknown region $SNAPREG";
esac
        
# Specific mode handling here
#
case $MODE in 
    rolling)
        DISC_SIZE=${DISC_ROLLING};
        ;;

    full)
        DISC_SIZE=${DISC_FULL};
        ;;

    archive)
        DISC_SIZE=${DISC_ARCHIVE};
        ;;

    *)
        leave "Unknown node mode $MODE"
esac

# Disclaimer
#
if [ "$WARNTIME" != "0" ]; then
    echo "WARNING: This script will bring up resources in the cloud and they will cost money"
    echo "WARNING: Please make sure you understand your budget"
    echo "Ctrl-C now to exit if you are worried - you have $WARNTIME seconds"
    sleep $WARNTIME
fi

# Client package
#
CLIENTPKG="octez-client_${VERS}-${REV}_${ARCH}.deb" 

echo "===> Checking that packages exist"
wget -O /dev/null $PKGSITE/$OS/$CLIENTPKG > /dev/null 2>&1
[ "$?" != "0" ] && echo "Cannot find Octez package for ${OS} and version ${VERS}-${REV}" && exit 2

if [ "$IGNORESNAP" != "yes" ]; then
    echo "===> Checking that snapshot is available"
    TAIL=$MODE
    [ "$MODE" = "archive" ] && TAIL=archive.tar.lz4
    gcloud storage ls gs://tf-snapshot-${SNAPREG}/${NETWORK}/${TAIL}
    [ "$?" != "0" ] && leave "Cannot find a snapshot for $NETWORK/$MODE"
fi

enable_compute $PROJECT;

echo "===> Finding OS image for $OS"
IMAGE=$(findosimage $OS)

echo "===> Setting up Node $NAME ($NETWORK/$MODE)"
create_vm $NAME $PROJECT $ZONE $MACHINE $IMAGE $DISC_SIZE

wait_gracefully

if [ "$RPCALLOWLIST" != "null" ]; then
    create_firewall $NAME $PROJECT $RPCALLOWLIST
    RPC=yes
fi

print_ssh_details $PROJECT $ZONE $NAME

copy_and_exec $PROJECT $ZONE $HELPERSCRIPT $NAME "${NETWORK} ${MODE} ${RPC} ${SNAPREG} ${PKGSITE} ${OS} ${ARCH} ${VERS}-${REV}"

echo "===> Script running"

if [ "$FOLLOW" = "1" ]; then
    echo "===> Following log - it is safe to CTRL-C now if you want to exit"
    sleep 3
    followlog ${PROJECT} ${ZONE} ${NAME}
fi



