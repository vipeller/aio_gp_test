### Manual Setup

Manual setup for the **UMATI Machine Tool Simulation Layer** involves a sequence of **UI-driven actions** broken into substeps. While much of the configuration can be completed through the **Azure Portal** and the **IoT Operations Experience portal**, **some steps cannot yet be performed entirely in the UI**. For those, you’ll need to run supporting setup scripts.

> ⚠️ **Heads-up:** These scripts are mandatory for a complete setup. Even if you choose the manual path, certain configuration (e.g., schema creation, onboarding) is only possible via scripts.

You can run the scripts from either **Azure Cloud Shell** *or* from your own terminal. Pick **one** of the two preparation options below.

---

### Preparation

For the script-driven parts, the same preparations apply as in the automated deployment.

#### Option A — One-liner (no clone needed)

Good for Cloud Shell or anyone who doesn’t want to clone the repo.

```bash
# Download scripts into ./aio-tools and make them executable
curl -sSL https://raw.githubusercontent.com/vipeller/aio_gp_test/main/bootstrap.sh | bash
cd aio-tools
```

#### Option B — Clone the repo

Good if you want the full repository locally.

```bash
git clone https://github.com/vipeller/aio_gp_test.git
cd aio_gp_test/aio-tools
```


#### Discover environment (prints exports)

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

### 1) Deploy the OPC Publisher [Connector Template](./INSTALL_CONNECTOR_TEMPLATE.md)
### 2) Deploy the OPC Publisher [Connector](./INSTALL_CONNECTOR.md)
### 3) Deploy the [UMATI simulator](./INSTALL_UMATI.md)
### 4) Onboard a discovered [UMATI asset](./ONBOARD_UMATI_ASSET.md)
### 5) Create [Eventstream](./CREATE_EVENTSTREAM.md)
### 6) Create [Dataflow](./CREATE_DATAFLOW.md)