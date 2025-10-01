# One DO Experience - ADR, AIO, DTB

## Overview
The private preview introduces powerful integration capabilities that enable customers to seamlessly port defined assets, data models, and operational data from Azure IoT Operations (AIO) and Azure Device Registry (ADR) into Digital Twin Builder (DTB) within Microsoft Fabric. By consolidating contextual and operational data in one place, this integration eliminates manual steps and fragmented workflows, allowing users to move from raw data to actionable insights with minimal effort, unlocking the full value of their digital operations. 

## How Each Service Fits In 

- **Azure IoT Operations (AIO)**: a unified data plane for the edge, comprising modular, scalable, and highly available data services that operate on Azure Arc-enabled edge Kubernetes, enabling data capture from various systems. With AIO, customers can discover and onboard their physical assets on factory floors and send structured data with set schemas using connectors (Akri) at the edge all the way to destinations like Microsoft Fabric. 

- **Azure Device Registry (ADR)**: a single unified registry for devices and assets across applications running in the cloud or on the edge. In the cloud, assets are represented as Azure resources, enabling management through Azure features like resource groups, tags, RBAC, and policy. On the edge, ADR creates Kubernetes custom resources for each asset and keeps cloud and edge representations in sync. It is the single source of truth for asset metadata, ensuring consistency and allowing customers to manage assets using Azure Resource Manager, APIs, and tools like Azure Resource Graph. 

- **Fabric Ontology**: is a new component within the Real-Time Intelligence workload in Microsoft Fabric. It creates digital representations of real-world assets and processes using imported models and operational data. With Ontology, customers can leverage low-code/no-code tools for modeling business concepts, building KPIs (such as OEE), and enabling advanced analytics for operational optimization. 

### **Why this matters:**
- **Single Pane of Glass**: All your operational data: models, assets, and telemetry, are accessible and actionable from Microsoft Fabric. 

- **Edge-to-Cloud Integration**: Data flows smoothly from devices at the edge, through the cloud, and into the applications of your choice. 

- **Operational Insights**: With unified data, you can drive advanced use cases like remote monitoring, predictive maintenance, and more, without the friction of manual integration. 

- **Accelerated Onboarding**: Microsoft-curated models and streamlined setup reduce time-to-value for new assets and scenarios. 

- **Scalability & Flexibility**: Provides a pathway to support model-based data transformation at scale, BYO models from GitHub, and integration with Azure IoT Hub for high-volume data sources in later releases. 

## **How Data Comes Together**

### 1. Model Management Workflow

Microsoft-curated Asset definition, derived from OPC UA companion specs, define asset types and capabilities. These definitions are imported into DTB for entity creation and used in Azure IoT operations for asset discovery and selection. 

Within Azure IoT operations, definitions are embedded in device endpoint configurations, enabling the discovery handler to identify matching assets. DTB models these definitions as entity types for downstream operations. 

As a result, no manual model uploads are required and customers benefit from a curated, ready-to-use model library, ensuring consistency and accelerating onboarding.  

### 2. Asset Data Ingestion Workflow 

Assets are discovered via OPC UA handlers and onboarded into Azure Device Registry (ADR) with rich metadata. The ADR connector ingests these assets into a Lakehouse table in Microsoft Fabric, filtering by asset type, preserving all metadata and lineage. 

Customers create entities in DTB based on the imported definitions, then manually map these entities to records in the ADR Lakehouse table using asset UUIDs or external IDs.  

As a result, Customers gain full control and visibility over asset onboarding and mapping, ensuring data integrity and traceability across the stack.  

### 3. Streaming Data Flow 

Once assets are configured and operational, the AIO connector publishes telemetry to MQ broker and using AIO’s dataflow the data is sent to Fabric destination namely Eventstream with Cloud Events headers. DTB entities ingest this telemetry directly from Eventstream. 

Messages must conform to the model’s structure and naming; no transformation or schema mapping is allowed at this stage for private preview to retain the structure of message. DTB relies on typeref and field name alignment for ingestion. 

Hence, real-time, model-aware telemetry ingestion enables immediate operational insights, with minimal setup and no need for manual schema management.


## Prerequisites

This will be a very short sentence just to explain that a deployed aio is needed, and a link for a more detailed page listing what to check to see if things wil go well

< link to the checklist page>

## Deployment steps

This section should shortly explain that we will need ~3 phases of deployment. Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam

### Device simulation (UMATI) + ingestion to event stream

The simulation layer and dataflow can be set up in two ways:

* **[Fast-track](doc/INSTALL_DF_SCRIPTS.md)** — Run a set of deployment scripts that install and wire up all components end-to-end. You’ll have MachineTool OPC UA variables & events flowing **UMATI → OPC Publisher (MQTT) → AIO Dataflow → Fabric Eventstream** with minimal interaction.

* **[Manual setup](doc/INSTALL_DF_MANUAL.md)** — After deploying the UMATI server, complete each step in the Azure portal and the IoT Operations experience. This takes longer, but it’s great for learning how the system works and how to manage it through the UI.

### Setting up event stream

Some description what it does and a link to the page that describes the steps

### Ingest Metadata from Azure Device Registry to Fabric 

Asingle sentence explaining why [following these steps](doc/INGEST_ADR_METADATA.md) is important
