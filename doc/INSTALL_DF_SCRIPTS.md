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
./deploy_umati.sh
```

Spins up the UMATI sample server in your cluster.

### 6) Onboard one **discovered UMATI asset**

```bash
./onboard_fullmachine.sh
```

This script waits for a discovered asset with prefix `fullmachinetool-` and onboards it into ADR.

### 7) Deploy **Eventstream**

```bash
# Optional: use a specific Fabric workspace instead of "My workspace"
# export FABRIC_WORKSPACE_ID="<workspace-guid>"

# Optional: change the display name (default: DTB-GP-Test)
# export DISPLAY_NAME="DTB-GP-Custom"

./deploy_eventstream.sh
```

Creates a Fabric Eventstream. Saves source credentials to `./creds/dtb_hub_cred.json`.

⚠️ Treat that file as a secret and delete it once your deployment is configured.


### 8) Deploy **Dataflow** (MQ ➜ Eventstream)

```bash
./deploy_dataflow.sh
```

Wires local MQTT to your Eventstream via a Dataflow.

**Heads-up:** Run `./deploy_eventstream.sh` first so `./creds/dtb_hub_cred.json` exists. That file contains secrets—treat it carefully and delete it after configuration.

---
# Azure IoT Operations – UMATI Machine Tool Simulation Layer

This repo adds a **simulation + ingestion layer** on top of an existing [Azure IoT Operations (AIO)][AIO] deployment:

* **UMATI MachineTool simulator** (Helm) → emits realistic OPC UA MachineTool data from the [UMATI Sample Server].
* **[Microsoft OPC Publisher]** as an **[Akri connector]** → subscribes to the simulator and publishes OPC UA **variables/events** into AIO’s built-in **MQTT** broker.
* *(Optional)* **Discovery Handler** → auto-discovers OPC UA endpoints and creates **discovered assets/devices** in ADR for you to onboard.
* **[Eventstream]** (Fabric) → a streaming item with a **[Custom Endpoint]** source (we’ll push data into it) and a destination you choose.
* **[AIO Dataflow]** → bridges AIO’s **MQTT** world to Fabric **Eventstream** (via a Kafka endpoint), moving simulator telemetry end-to-end.

**Result:** you get **simulated MachineTool OPC UA variables & events** flowing from the UMATI server → OPC Publisher (MQTT) → AIO Dataflow → Fabric Eventstream for downstream analytics or storage.

[AIO]: https://learn.microsoft.com/azure/iot-operations/
[UMATI Sample Server]: https://github.com/umati/Sample-Server
[Microsoft OPC Publisher]: https://azure.github.io/Industrial-IoT/opc-publisher/
[Akri connector]: https://learn.microsoft.com/en-us/azure/iot-operations/discover-manage-assets/overview-akri
[Eventstream]: https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/overview?tabs=enhancedcapabilities
[Custom Endpoint]: https://learn.microsoft.com/en-us/fabric/real-time-intelligence/event-streams/add-source-custom-app?pivots=enhanced-capabilities
[AIO Dataflow]: https://learn.microsoft.com/en-us/azure/iot-operations/connect-to-cloud/overview-dataflow

---

## What gets deployed (and why)

* **UMATI Simulator (Helm release)**
  Runs the UMATI OPC UA sample server(s) in your cluster (usually in `azure-iot-operations`). This is your **data source**.
  **Plus:** matching **ADR device** (endpoint points at the service in your cluster, with MachineTool asset type).

* **OPC Publisher – Akri Connector Template**
  Defines *how* OPC Publisher runs (container image/pull policy, schema references, misc runtime config). Think of this as the **class**.

* **OPC Publisher – Akri Connector (instance)**
  A **running connector** derived from the template that binds to your AIO Custom Location. It subscribes to OPC UA nodes/events and **publishes to MQTT**.

* **(Optional) Discovery Handler**
  Periodically probes for OPC UA endpoints and creates **discovered assets/devices** in ADR so you can promote (“onboard”) them to managed assets.

* **Onboarded Asset (ADR)**
  The **managed asset** created from a discovered UMATI `fullmachinetool-*` asset; used to identify and configure the device/asset in ADR.

* **Eventstream (Fabric)**
  A Fabric **Eventstream** item with a **Custom Endpoint source**. The script prints and saves **source credentials** (connection string / namespace / hub).
  These credentials are later used by the AIO side to send data **into** the Eventstream.

* **Kafka Secret & Endpoint (AIO)**
  A Kubernetes **Secret** (holds the Eventstream connection string) and an AIO **Kafka endpoint** pointing to the Eventstream’s namespace/hub.

* **AIO Dataflow**
  A Dataflow wiring **AIO MQ → the Kafka endpoint** above. This is the **bridge** into Eventstream.
  
---

## Scripts in this repo

* `bootstrap.sh`
  Convenience downloader: pulls scripts + required schema files into `./aio-tools/` (great in Cloud Shell).

* `discover_env.sh`
  **Discovers** resource names in your Resource Group and prints `export …` lines for:

  * AIO **instance** name & **location**
  * ADR **namespace** name
  * **Schema Registry** name
  * Also resolves **Fabric** “My workspace” + capacity if you have permissions.

* `deploy_opc_publisher_template.sh`
  Creates/updates the **Akri Connector Template** for OPC Publisher and **ensures schemas exist** in your Schema Registry (creating them if missing):

  * `opc-publisher-endpoint-schema`
  * `opc-publisher-dataset-schema`
  * `opc-publisher-event-schema`
  * `opc-publisher-dataset-datapoint-schema`

* `deploy_opc_publisher_instance.sh`
  Instantiates a **Connector** from the template and waits for provisioning to **Succeeded**.

* `deploy_opc_publisher_discovery_handler.sh` *(optional)*
  Deploys a Discovery Handler (cron) so AIO populates **discovered assets/devices** in ADR.

* `deploy_umati.sh`
  Deploys the **UMATI simulator** Helm chart from GitHub, waits for readiness, **and creates the corresponding ADR device** (with OPC UA endpoint and MachineTool asset type) so downstream discovery/onboarding can work immediately.

* `onboard_fullmachine.sh`
  **Waits** for a discovered asset whose name starts with `fullmachinetool-` and **onboards** it into ADR as a managed asset.

* `deploy_eventstream.sh`
  Creates a **Fabric Eventstream** (default display name `DTB-GP-Test`, override via `DISPLAY_NAME`) and prints **source connection credentials**, saving them to `./creds/dtb_hub_cred.json`.
  
  ⚠️ **Treat that file as a secret and delete it after use.**

* `deploy_dataflow.sh`
  Creates the **Kafka Secret/Endpoint** in AIO from the saved credentials and applies a **Dataflow** that sends data from AIO → **Eventstream** (no transformations).

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
