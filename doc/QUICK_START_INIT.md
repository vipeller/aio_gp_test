## System requirements

* `az` (Azure CLI) logged in, with access to the subscription / resource group
* `jq`
* `kubectl`
* `helm`
* An existing **AIO instance** (already installed & Arc-connected)
* A Kubernetes cluster associated with that AIO instance’s **Custom Location**

---

## Quick start

You can use these scripts either from **Azure Cloud Shell** *or* from your own terminal. Pick **one** of the two setup options below.

### 1) Option A — One-liner (no clone needed)

Good for Cloud Shell or anyone who doesn’t want to clone the repo.

```bash
# Download scripts into ./aio-tools and make them executable
curl -sSL https://raw.githubusercontent.com/vipeller/aio_gp_test/main/bootstrap.sh | bash
cd aio-tools
```

### 1) Option B — Clone the repo

Good if you want the full repository locally.

```bash
git clone https://github.com/vipeller/aio_gp_test.git
cd aio_gp_test/aio-tools
```


### 2) Discover environment (prints exports)

```bash
# either pass args…
./discover_env.sh <resource-group> <subscription-id>

# …or rely on env vars SUBSCRIPTION_ID & RESOURCE_GROUP
# ./discover_env.sh
```

Apply the exports to your shell:

```bash
eval "$(./discover_env.sh <resource-group> <subscription-id>)"
```

You can double-check the environment variables using `printenv`