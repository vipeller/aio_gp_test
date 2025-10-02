# One DO Experience - ADR, AIO, DTB

## Overview
The private preview introduces powerful integration capabilities that enable customers to seamlessly port defined assets, data models, and operational data from Azure IoT Operations (AIO) and Azure Device Registry (ADR) into Digital Twin Builder (DTB) within Microsoft Fabric. By consolidating contextual and operational data in one place, this integration eliminates manual steps and fragmented workflows, allowing users to move from raw data to actionable insights with minimal effort, unlocking the full value of their digital operations. 

## How Each Service Fits In 
**Azure IoT Operations (AIO)**: A unified data plane for the edge, comprising modular, scalable, and highly available data services that operate on Azure Arc-enabled edge Kubernetes, enabling data capture from various systems. With AIO, customers can discover and onboard their physical assets on factory floors and send structured data with set schemas using connectors (Akri) at the edge all the way to destinations like Microsoft Fabric. 

**Azure Device Registry (ADR)**: A single unified registry for devices and assets across applications running in the cloud or on the edge. In the cloud, assets are represented as Azure resources, enabling management through Azure features like resource groups, tags, RBAC, and policy. On the edge, ADR creates Kubernetes custom resources for each asset and keeps cloud and edge representations in sync. It is the single source of truth for asset metadata, ensuring consistency and allowing customers to manage assets using Azure Resource Manager, APIs, and tools like Azure Resource Graph. 

**Fabric Ontology**: A new component within the Real-Time Intelligence workload in Microsoft Fabric. It creates digital representations of real-world assets and processes using imported models and operational data. With Ontology, customers can leverage low-code/no-code tools for modeling business concepts, building KPIs (such as OEE), and enabling advanced analytics for operational optimization. 

## **Why this matters:**
- **Single Pane of Glass**: All your operational data: models, assets, and telemetry, are accessible and actionable from Microsoft Fabric. 

- **Edge-to-Cloud Integration**: Data flows smoothly from devices at the edge, through the cloud, and into the applications of your choice. 

- **Operational Insights**: Enable use cases like remote monitoring, predictive maintenance, and more, without manual integration.

- **Accelerated Onboarding**: Use Microsoft-curated models and streamlined setup to reduce time-to-value for new assets and scenarios. 

- **Scalability & Flexibility**: Supports model-based data transformation at scale, BYO models from GitHub, and integration with Azure IoT Hub in later releases. 

## **How Data Comes Together**

#### 1. Model Management Workflow
- Microsoft-curated Asset definition, derived from OPC UA companion specs, define asset types and capabilities. These definitions are imported into DTB for entity creation and used in Azure IoT operations for asset discovery and selection. 

- Within Azure IoT operations, definitions are embedded in device endpoint configurations, enabling the discovery handler to identify matching assets. DTB models these definitions as entity types for downstream operations. 

- As a result, no manual model uploads are required and customers benefit from a curated, ready-to-use model library, ensuring consistency and accelerating onboarding.  

#### 2. Asset Data Ingestion Workflow 

- Assets are discovered via OPC UA handlers and onboarded into Azure Device Registry (ADR) with rich metadata. The ADR connector ingests these assets into a Lakehouse table in Microsoft Fabric, filtering by asset type, preserving all metadata and lineage. 

- Customers create entities in DTB based on the imported definitions, then manually map these entities to records in the ADR Lakehouse table using asset UUIDs or external IDs.  

- As a result, Customers gain full control and visibility over asset onboarding and mapping, ensuring data integrity and traceability across the stack.  

#### 3. Streaming Data Flow 

- Once assets are configured and operational, the AIO connector publishes telemetry to MQ broker and using AIO’s dataflow the data is sent to Fabric destination namely Eventstream with Cloud Events headers. DTB entities ingest this telemetry directly from Eventstream. 

- Messages must conform to the model’s structure and naming; no transformation or schema mapping is allowed at this stage for private preview to retain the structure of message. DTB relies on typeref and field name alignment for ingestion. 

- Hence, real-time, model-aware telemetry ingestion enables immediate operational insights, with minimal setup and no need for manual schema management.

--- 

## Prerequisites
- An Azure subscription. Go to [Get Azure free trial](https://azure.microsoft.com/pricing/free-trial/)
- A deployed AIO instance (version 1.2.x)
- An Ontology item in Microsoft Fabric. See [Digital Twin Builder (Preview) Tutorial: Set Up Resources](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/digital-twin-builder/tutorial-1-set-up-resources) for more details.

> **Important:** If you plan to use automation scripts for any step in this guide, you must first complete the [QuickStart setup](./doc/QUICK_START_INIT.md).
---

## Discover and Import OPC UA Assets by Asset Types
Identify, annotate, and onboard OPC UA assets at the edge using Akri and Azure IoT Operations. he following steps are performed in the [Operations Experience](https://iotoperations.azure.com/) web UI. See [Manage resources in the operations experience UI](https://learn.microsoft.com/en-us/azure/iot-operations/discover-manage-assets/howto-use-operations-experience) to learn more.


#### 1. Create an OPC Publisher Akri Connector
Use the following script to create an OPC Publisher and connect it to your MQ:
```bash
./deploy_opc_publisher_template.sh \
./deploy_opc_publisher_instance.sh
```
#### 2. (Optional) Deploy Simulation Layer 
Deploy a device simulator (UMATI) to simulate devices and assets:
```bash 
./deploy_umati.sh
 ```
#### 3. Create Devices, Discover and Import Assets 
Create a device with an OPCUA device inbound endpoint and enable it for discovery to start importing assets using the [Operations Experience](https://iotoperations.azure.com/) UI. For setup instructions, see [Create Devices, Discover and Import Assets](./doc/CREATE_DEVICES_AND_ASSETS.md).

> ⚡ **Fast-Track:** Run the following script to automate asset endpoint creation and asset onboarding:
>```bash 
>./deploy_umati_with_device.sh \
>./onboard_fullmachine.sh
>```

## Ingest Asset Telemetry to Microsoft Fabric  
Ingest asset telemetry from Azure IoT Operations (AIO) into a Lakehouse table within Microsoft Fabric. Once ingested, the telemetry can then be mapped to entities in Ontology, enabling rich digital representations of assets.

#### 1. Create an Eventstream in Microsoft Fabric 
Set up an Eventstream destination to receive telemetry using the [Microsoft Fabric UI](./doc/CREATE_EVENTSTREAM.md)

> ⚡ **Fast-Track:** Run the following script to automate Eventstream creation: 
>```bash
># Optional: use a specific Fabric workspace instead of "My workspace"
># export FABRIC_WORKSPACE_ID="<workspace-guid>"
>
># Optional: change the display name (default: DTB-GP-Test)
># export DISPLAY_NAME="DTB-GP-Custom"
>
>./deploy_eventstream.sh
>```
>
>Creates a Fabric Eventstream. Saves source credentials to `./creds/dtb_hub_cred.json`.
>
>⚠️ Treat that file as a secret and delete it once your deployment is configured.


#### 2. Create an Azure IoT Operations Dataflow 
Configure a dataflow to route telemetry from AIO to the Eventstream using the [Operations Experience UI](./doc/CREATE_DATAFLOW.md)

> ⚡ **Fast-Track:** Run the following script to automate Dataflow creation:
> ⚠️ This script only works if the **Eventstream** was created using the **fast-track script**. 
>
>```bash
>./deploy_dataflow.sh
>```

#### 3. Setup Eventstream for Telemetry Ingestion in Microsoft Fabric 
For step-by-step instructions see: [Ingest Asset Telemetry to Microsoft Fabric](./doc/EVENTSTREAM_TELEMETRY_FABRIC.md)

## Ingest Asset Metadata from ADR to Microsoft Fabric
Ingest asset metadata stored in Azure Device Registry (ADR) into a Lakehouse table within Microsoft Fabric. This metadata provides essential context, such as version, manufacturer, location, and custom attributes, that can be mapped to entities in Ontology. When combined with telemetry data, it enables more accurate modeling, monitoring, and analysis of your assets and operations. See [Ingest Asset Metadata from ADR to Microsoft Fabric](doc/INGEST_ADR_METADATA.md) for steps using the Microsoft Fabric UI.

## Create Digital Representations of Assets in Ontology
Use the imported metadata and telemetry of assets to build rich digital represenations in Ontology.

#### 1. Map Azure Device Registry Assets to Entities in Ontology 
Link asset metadata (non-timeseries data) from a Lakehouse table to an entity instance. For step-by-step instructions see: [Ingest Asset Telemetry to Microsoft Fabric](./doc/ONTOLOGY_MAPPING_METADATA.md)

#### 2. Map Asset Telemetry to Entities in Ontology 
Link asset telemetry (timeseries data) from Eventstream to an entity instance. For step-by-step instructions see: [ Map Asset Telemetry to Entities in Ontology](./doc/ONTOLOGY_MAPPING_TELEMETRY.md)
