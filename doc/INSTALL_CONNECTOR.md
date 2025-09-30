### Install the OPC Publisher Connector

Once the **Connector Template** is in place, the next step is to create a **Connector instance** based on it. This cannot yet be done through the UI, so you’ll need to run a script. The script provisions the connector into your AIO instance and waits until its status is **Succeeded**.

```bash
./deploy_opc_publisher_instance.sh
```

