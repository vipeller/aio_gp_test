# Create an Eventhouse in Microsoft Fabric

An **Eventhouse** in Microsoft Fabric is a high-throughput, analytics-optimized destination for real-time event data. It’s designed to store and query large volumes of telemetry efficiently. 

This Eventhouse will later be used as the **destination** for an **Eventstream**, which serves as the pipeline for ingesting telemetry from sources like AIO. By setting up the Eventhouse first, you ensure it’s ready to receive data when you configure the Eventstream in the next step.

> [!NOTE]  
> For more information, see: [Create an eventhouse](https://learn.microsoft.com/en-us/fabric/real-time-intelligence/create-eventhouse)

1. In your **Fabric workspace** go to **New item → Eventhouse**.
   
   ![New Eventhouse](./images/new_eventhouse.png "New Eventhouse")
3. Enter a **Name** for the Eventhouse. Both an eventhouse and its default child Kusto Query Language (KQL) database are created with the same name. The database name, like all items in Fabric, can be renamed at any time.

   > ⚠️ **Heads-up:** : Remember the name of your Eventhouse — you’ll need it when selecting a destination during Eventstream setup.

5. Click **Create**.
6. The **system overview** will open in the main view area of the newly created eventhouse.
   
   ![New Eventhouse Overview](./images/new_eventhouse_overview.png "New Eventhouse Overview")

