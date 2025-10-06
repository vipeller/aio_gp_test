# Setup Eventstream for Telemetry Ingestion in Microsoft Fabric 

## 1. Prepare Eventhouse to receive telemetry from Eventstream 

1. Run Python setup scripts provided in repo to setup the Eventhouse which will receive telemetry from Eventstream. 

2. Save your Fabric Eventhouse URI.

## 2. Update Eventstream with a SQL Code Transform and Eventhouse as Target 

1. Add a Transform step of type **SQL Code** in Eventstream. 

2. Add a Destination of type **Eventhouse** in Eventstream, and connect it to the SQL Code step. Use the Eventhouse URI from the previous step.

Use the following SQL Code: 
```sql
SELECT 

stream AS data, 

GETMETADATAPROPERTYVALUE(stream,'[User].[ce_subject]') AS subject, 

GETMETADATAPROPERTYVALUE(stream,'[User].[ce_type]') AS type 

INTO [EventhouseName] FROM [EventStreamName-stream] AS stream
```

![Eventstream Flow](./images/eventstream_flow.png "Eventstream Flow")
