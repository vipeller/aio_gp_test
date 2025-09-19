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

### Option A — One-liner (no clone needed)

Good for Cloud Shell or anyone who doesn’t want to clone the repo.

```bash
# Download scripts into ./aio-tools and make them executable
curl -sSL https://raw.githubusercontent.com/vipeller/aio_gp_test/main/bootstrap.sh | bash
cd aio-tools
```

### Option B — Clone the repo

Good if you want the full repository locally.

```bash
git clone https://github.com/vipeller/aio_gp_test.git
cd aio_gp_test/aio-tools
```


### 1) Discover environment (prints exports)

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

### 2) Deploy the OPC Publisher **Connector Template**

```bash
./deploy_opc_publisher_template.sh
```

This ensures required **schemas** exist and binds them to the template.

### 3) Deploy the OPC Publisher **Connector instance**

```bash
./deploy_opc_publisher_instance.sh
```

This creates the **Akri Connector** for OPC Publisher and waits for it to be provisioned.

### 4) (Optional) Deploy the **Discovery Handler**

```bash
./deploy_opc_publisher_discovery_handler.sh
```

This enables scheduled discovery so **discovered assets/devices** appear in ADR.

### 5) Deploy the **UMATI simulator**

```bash
# You can change COUNT to spin up multiple simulators
export COUNT=1
./deploy_umati.sh
```

### 6) Onboard one **discovered UMATI asset**

```bash
./onboard_fullmachine.sh
```

This script waits for a discovered asset with prefix `fullmachinetool-` and onboards it into ADR.

### 7) Deploy the **Eventstream**

```bash
# Optional: change the display name (default: DTB-GP-Test)
export DISPLAY_NAME="DTB-GP-Custom"

./deploy_eventstream.sh
```

This creates an Eventstream.
The script also fetches the source connection credentials and saves them to `./creds/dtb_hub_cred.json` — **treat this file as a secret and delete it after your deployment is configured.**


---

# Azure IoT Operations – UMATI Machine Tool Simulation Layer

This repo adds a **simulation + ingestion layer** on top of an existing \[Azure IoT Operations (AIO)] deployment:

* **UMATI MachineTool simulator** (via Helm) → provides a realistic OPC UA MachineTool model (from the [UMATI Sample Server]).
* **Microsoft OPC Publisher** as an **Akri connector** → subscribes to the simulator and publishes *OPC UA data points/events* into AIO (via the built-in MQTT broker).
* Optional **Discovery Handler** → auto-discovers OPC UA endpoints and produces *discovered assets/devices* in Azure Device Registry (ADR); you can then onboard one with a script.

Result: you get **simulated MachineTool data points/events** (OPC UA “Variables” and Events from the MachineTool companion spec) flowing into AIO’s messaging layer (MQTT), perfect for end-to-end validation before connecting real equipment.

[AIO]: https://learn.microsoft.com/azure/iot-operations/
[UMATI Sample Server]: https://github.com/umati/Sample-Server
[Microsoft OPC Publisher]: https://github.com/Azure/Industrial-IoT/tree/main

---

## What gets deployed

* **UMATI simulator**: a Kubernetes Helm release in your cluster (typically namespace `azure-iot-operations`).
* **OPC Publisher Akri Connector Template**: an AIO resource that defines how OPC Publisher runs (image, pull policy, schemas, etc.).
* **OPC Publisher Akri Connector (instance)**: a running connector derived from the template (deploys workloads in your cluster via Custom Location).
* **(Optional) Discovery Handler**: schedules endpoint discovery and produces **discovered assets/devices** in ADR.
* **Onboarded Asset**: the script promotes a discovered UMATI asset (name prefix `fullmachinetool-`) to a managed ADR **asset**.

---

## Scripts in this repo

* `bootstrap.sh`
  Convenience downloader: fetches the scripts into `./aio-tools/` (handy in Cloud Shell).

* `discover_env.sh`
  **Discovers** resource names in your RG and prints `export …` lines:

  * AIO **instance** name & **location**
  * ADR **namespace** name
  * **Schema Registry** name
    Supports `discover_env.sh <resource-group> <subscription-id>` or env vars.

* `deploy_opc_publisher_template.sh`
  Creates/updates an **Akri Connector Template** for Microsoft OPC Publisher.
  Also **ensures required schemas** exist in your Schema Registry (creating them if missing) and binds them:

  * `opc-publisher-endpoint-schema`
  * `opc-publisher-dataset-schema`
  * `opc-publisher-event-schema`
  * `opc-publisher-dataset-datapoint-schema`

* `deploy_opc_publisher_instance.sh`
  Instantiates a **Connector** from the template (i.e., a running Akri connector bound to your Custom Location), then polls until the provisioning state is `Succeeded`.

* `deploy_opc_publisher_discovery_handler.sh` *(optional)*
  Deploys a **Discovery Handler** for OPC Publisher (cron schedule). When enabled, AIO will create **discovered assets/devices** in ADR for matching OPC UA endpoints.

* `deploy_umati.sh`
  Deploys the **UMATI simulator** with Helm and waits for readiness.

* `onboard_fullmachine.sh`
  **Waits** for a *discovered asset* whose name starts with `fullmachinetool-`, then **onboards** it into ADR as a managed **asset** (copies properties, fixes unsupported fields, sets `extendedLocation`, etc.).

---

## Notes & tips

* If you already have your own **template/connector names**, set:

  ```bash
  export TEMPLATE_NAME="opc-publisher-t1"
  export CONNECTOR_NAME="opc-publisher-c1"
  ```

  before running the deploy scripts.

* If your AIO instance uses a **non-default namespace** for workloads, set:

  ```bash
  export NAMESPACE="azure-iot-operations"
  ```
