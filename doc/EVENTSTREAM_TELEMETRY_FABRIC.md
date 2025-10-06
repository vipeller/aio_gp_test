# Setup Eventstream for Telemetry Ingestion in Microsoft Fabric 

## 1. Prepare Eventhouse to Receive Telemetry
1. Navigate to the previously created **Eventhouse** in Microsoft Fabric.
2. Locate and copy the **Ingestion URI**, which will be used to connect Eventstream to Eventhouse.
   
## 2. Configure Eventstream with SQL Transform and Eventhouse Target
1. Open your **Eventstream** in Microsoft Fabric.
2. Add a **Transform** step of type SQL Code.
   
    **SQL Code Example:**
    ```sql
    SELECT 

    stream AS data, 

    GETMETADATAPROPERTYVALUE(stream,'[User].[ce_subject]') AS subject, 

    GETMETADATAPROPERTYVALUE(stream,'[User].[ce_type]') AS type 

    INTO [EventhouseName] FROM [EventStreamName] AS stream
    ```
    > Replace [EventhouseName] and [EventStreamName] with your actual resource names.
    
4. Add a **Destination** step of type Eventhouse, and connect it to the SQL Transform step.
5. Paste the **Ingestion URI** from Step 1 into the Eventhouse destination configuration.

    ![Eventstream Flow](./images/eventstream_flow.png "Eventstream Flow")

6. Select **Publich** to commit yout changes. This action switches your eventstream from Edit mode to Live view, initiating real-time data processing.

## 3. Verify Telemetry Flow
Navigate to your **Eventhouse** to confirm that telemetry is flowing from Azure IoT Operations.

![Eventhouse Telemetry](./images/eventhouse_telemetry.png "Eventhouse Telemetry")
