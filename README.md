# One DO Experience - ADR, AIO, DTB

## Overview

This private preview brings together Azure IoT Operations, Azure Device Registry, and Digital Twin Builder into a seamless, unified experience within Microsoft Fabric. It enables customers to manage model data, metadata, and telemetry across their asset and device fleets in one place, unlocking the full value of their digital operations.

**Why this matters:**

- Single Pane of Glass: All your operational data: models, assets, and telemetry, are accessible and actionable from Microsoft Fabric. 
- Edge-to-Cloud Integration: Data flows smoothly from devices at the edge, through the cloud, and into the applications of your choice. 
- Operational Insights: With unified data, you can drive advanced use cases like remote monitoring, predictive maintenance, and more, without the friction of manual integration. 

**How Data Comes Together**

###### 1. Model Management Workflow

Microsoft-curated Asset definition, derived from OPC UA companion specs, define asset types and capabilities. These definitions are imported into DTB for entity creation and used in Azure IoT operations for asset discovery and selection. 

Within Azure IoT operations, definitions are embedded in device endpoint configurations, enabling the discovery handler to identify matching assets. DTB models these definitions as entity types for downstream operations. 

As a result, no manual model uploads are required and customers benefit from a curated, ready-to-use model library, ensuring consistency and accelerating onboarding.  

###### 2. Asset Data Ingestion Workflow 

Assets are discovered via OPC UA handlers and onboarded into Azure Device Registry (ADR) with rich metadata. The ADR connector ingests these assets into a Lakehouse table in Microsoft Fabric, filtering by asset type, preserving all metadata and lineage. 

Customers create entities in DTB based on the imported definitions, then manually map these entities to records in the ADR Lakehouse table using asset UUIDs or external IDs.  

As a result, Customers gain full control and visibility over asset onboarding and mapping, ensuring data integrity and traceability across the stack.  

###### 3. Streaming Data Flow 

Once assets are configured and operational, the AIO connector publishes telemetry to MQ broker and using AIO’s dataflow the data is sent to Fabric destination namely Eventstream with Cloud Events headers. DTB entities ingest this telemetry directly from Eventstream. 

Messages must conform to the model’s structure and naming; no transformation or schema mapping is allowed at this stage for private preview to retain the structure of message. DTB relies on typeref and field name alignment for ingestion. 

Hence, real-time, model-aware telemetry ingestion enables immediate operational insights, with minimal setup and no need for manual schema management.

**Customer Benefits & Use Cases**

- **Unified Data Experience:** Manage models, assets, and telemetry in one place—eliminating silos and manual integration. 
- **Accelerated Onboarding:** Microsoft-curated models and streamlined setup reduce time-to-value for new assets and scenarios. 
- **Edge-to-Cloud Consistency:** Data flows seamlessly from devices to the cloud, supporting hybrid and distributed edge deployment architecture. 
- **Operational Insights:** Enable scenarios like remote monitoring, predictive maintenance, and asset optimization with unified, real-time data in Microsoft Fabric. 

Scalability & Flexibility: Provide a pathway to support model-based data transformation at scale, BYO models from GitHub, and integration with Azure IoT Hub for high-volume data sources in later releases. 

## Prerequisites

This will be a very short sentence just to explain that a deployed aio is needed, and a link for a more detailed page listing what to check to see if things wil go well

< link to the checklist page>

## Deployment steps

This section should shortly explain that we will need ~3 phases of deployment. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam

### Device simulation (UMATI) + ingestion to event stream

The simulation layer and dataflow can be set up in two ways:

* **[Fast-track](doc/INSTALL_DF_SCRIPTS.md)** — Run a set of deployment scripts that install and wire up all components end-to-end. You’ll have MachineTool OPC UA variables & events flowing **UMATI → OPC Publisher (MQTT) → AIO Dataflow → Fabric Eventstream** with minimal interaction.

* **[Manual setup](doc/INSTALL_FD_MANUAL.md)** — After deploying the UMATI server, complete each step in the Azure portal and the IoT Operations experience. This takes longer, but it’s great for learning how the system works and how to manage it through the UI.

### Setting up event stream (Abhinav's stuff) 

Some description what it does and a link to the page that describes the steps

### Ingest Metadata from Azure Device Registry to Fabric 

Asingle sentence explaining why [following these steps](doc/INGEST_ADR_METADATA.md) is important
