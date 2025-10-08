# One DO Experience - ADR, AIO, DTB

## Table of Contents

- [Overview](#overview)
  
- [Prerequisites](#prerequisites)

- [Step 0: Onboard deployment scripts](#step-0-onboard-deployment-scripts)
  
- [Step 1: Discover and Import OPC UA Assets](#step-1-discover-and-import-opc-ua-assets)
  
- [Step 2: Send Asset data to Microsoft Fabric](#step-2-send-asset-data-to-microsoft-fabric)
  
- [Step 3: Create Digital Representations of Assets](#step-3-create-digital-representations-of-assets-in-ontology)

## Overview

This private preview introduces powerful integration capabilities that enable customers to **seamlessly port assets from Azure Device Registry (ADR), their data models, and operational data from Azure IoT Operations (AIO) into Digital Twin Builder (DTB) within Microsoft Fabric**.   By consolidating contextual and operational data in one place, this integration eliminates manual steps and fragmented workflows, allowing users to unlock the full value of their digital operations by transforming raw data into actionable insights with minimal effort.

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

# Prerequisites

- An Azure subscription. 
  
- A deployed Azure IoT Operations instance (version 1.2.x).
  
- An Azure Device Registry namespace to store your namespace assets and devices.

- A Microsoft Fabric subscription. In your subscription, you need access to a workspace with Contributor or above permissions.
  
- A Fabric tenant that allows the creation of real-time dashboards. Your tenant administrator can enable this setting. For more information, see [Enable tenant settings in the admin portal](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/dashboard-real-time-create#enable-tenant-settings-in-the-admin-portal).
  
- An Ontology item in Microsoft Fabric. See [Digital Twin Builder (Preview) Tutorial: Set Up Resources](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/digital-twin-builder/tutorial-1-set-up-resources) for more details.

---

# Step 0: Onboard deployment scripts

> [!IMPORTANT]
> Some steps require using automation scripts, while others can be performed manually or through scripts. Before proceeding, ensure you’ve completed the [QuickStart Setup](./doc/QUICK_START_INIT.md)
 to onboard the scripts into your environment.

# Step 1: Discover and Import OPC UA Assets

Identify, annotate, and onboard OPC UA assets by asset type at the edge using **Akri** and **Azure IoT Operations**. While some steps can be performed directly in the [Operations Experience](https://iotoperations.azure.com/) portal, others — or certain portions of them — must be completed using the provided setup scripts.
 
### 1. Create an OPC Publisher Akri Connector
Use the following script to create an OPC Publisher and connect it to your MQ:
```bash
./deploy_opc_publisher_template.sh \
./deploy_opc_publisher_instance.sh
```
### 2. (Optional) Deploy Simulation Layer

Deploy the **UMATI MachineTool Simulator**, which generates realistic OPC UA MachineTool telemetry using the [UMATI Sample Server](https://github.com/umati/Sample-Server).
This is a simple way to ingest data **without needing real devices or assets connected**.
```bash 
./deploy_umati.sh
 ```

### 3. Create Devices, Discover and Import Assets 
Create a device with an OPCUA device inbound endpoint and enable it for discovery to start importing assets using the Operations Experience UI: *[Create Devices, Discover and Import Assets](./doc/CREATE_DEVICES_AND_ASSETS.md)*.

> [!NOTE]
> For more details on managing resources in the Operations Experience UI, see [Manage resources in the operations experience UI](https://learn.microsoft.com/en-us/azure/iot-operations/discover-manage-assets/howto-use-operations-experience).

> ⚡ **Fast-Track:** Run the following script to automate asset endpoint creation and asset onboarding:
>```bash 
>./register_umati_device.sh \
>./onboard_fullmachine.sh
>```
> See [Onboarding UMATI Assets](./doc/CREATE_DEVICES_AND_ASSETS.md) for more details.

---
# Step 2: Send Asset data to Microsoft Fabric

## Ingest Asset Telemetry 
Ingest asset telemetry from Azure IoT Operations (AIO) into a Lakehouse table within Microsoft Fabric. Once ingested, the telemetry can then be mapped to entities in Ontology, enabling rich digital representations of assets.

### 1. Create an Eventstream in Microsoft Fabric 
Set up an Eventstream destination to receive telemetry using the Microsoft Fabric UI: *[Create an Eventstream in Microsoft Fabric](./doc/CREATE_EVENTSTREAM.md)*.

> ⚡ **Fast-Track:** Run the following script to automate Eventstream creation.
> 
> This script:
> - Creates a Fabric Eventstream.
> - Saves source credentials to `./creds/dtb_hub_cred.json`.
>   
>```bash
># Optional: use a specific Fabric workspace instead of "My workspace"
># export FABRIC_WORKSPACE_ID="<workspace-guid>"
>
># Optional: change the display name (default: DTB-GP-Test)
># export DISPLAY_NAME="DTB-GP-Custom"
>
>./deploy_eventstream.sh
>```
> ⚠️ Treat that file as a secret and delete it once your deployment is configured.
>

### 2. Create an Azure IoT Operations Dataflow 
Configure a Dataflow to route telemetry from AIO to your Eventstream via the Operations Experience: *[Create a Dataflow](./doc/CREATE_DATAFLOW.md)*.

> ⚡ **Fast-Track:** Run the following script to automate Dataflow creation:
>```bash
>./deploy_dataflow.sh
>```
>
> ⚠️ This fast-track script can only be used if the Eventstream was created using the fast-track script from the previous step.

### 3. Setup Eventstream for Telemetry Ingestion in Microsoft Fabric 
See *[Ingest Asset Telemetry to Microsoft Fabric](./doc/EVENTSTREAM_TELEMETRY_FABRIC.md)* for full instructions.

## Ingest Asset Metadata from Azure Device Registry
Ingest asset metadata stored in Azure Device Registry (ADR) into a Lakehouse table within Microsoft Fabric. This metadata provides essential context, such as version, manufacturer, location, and custom attributes, that can be mapped to entities in Ontology. When combined with telemetry data, it enables more accurate modeling, monitoring, and analysis of your assets and operations. See *[Ingest Asset Metadata from ADR to Microsoft Fabric](doc/INGEST_ADR_METADATA.md)* for full instructions.

---
# Step 3: Create Digital Representations of Assets in Ontology
Use the imported metadata and telemetry of assets to build rich digital representations in Ontology.

### 1. Create Entities from Entity Types

### 2. Map Azure Device Registry Assets to Entities
Link asset metadata (static data) from a Lakehouse table to an entity instance: *[Map Asset Metadata to Entities](./doc/ONTOLOGY_MAPPING_METADATA.md)*

### 3. Map Asset Telemetry to Entities
Link asset telemetry (timeseries data) from Eventstream to an entity instance: *[Map Asset Telemetry to Entities](./doc/ONTOLOGY_MAPPING_TELEMETRY.md)*
