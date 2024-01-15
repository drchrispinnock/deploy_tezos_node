# Deploy a Tezos node using packages and snapshots

This is a prototype script to deploy Tezos nodes and initialise
them from the snapshot server.

It relies on pkgbeta.tzinit.org having packages and snapshot.tzinit.org
having snapshots.

The relevant cloud tools should be installed on your machine and ```wget```.
It's recommended to have the ```gcloud``` tools as it is the easiest way to
check the snapshot files exist before proceeding.

## Examples

1. Deploy a rolling node on mainnet in GCP in europe-west6-a

```
gcloud projects create "my-project"
gcloud beta billing projects link "my-project" \
    --billing-account 123456-789123-456789
sh deploy.sh -c gcp -p "my-project" -z europe-west6-a -n mainnet -t rolling
```

2. Deploy a full node on mainnet in GCP in us-central1-a

```
sh deploy.sh -c gcp -p "my-project" -z us-central1-a -s us -n mainnet -t full
```

3. Deploy an archive node on ghostnet in GCP in europe-west6-a

```
sh deploy.sh -c gcp -p "my-project" -z europe-west6-a -n mainnet -t archive
```

4. On Debian machines, you can deploy locally. Be careful.

```
sh deploy.sh -c local -n oxfordnet -t rolling
```
