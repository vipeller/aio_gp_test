### Onboard the UMATI Asset

With the **OPC Publisher Connector** and **UMATI Simulator** deployed, the system begins discovering OPC UA endpoints. After a short delay, the discovered assets will appear in the **Azure IoT Operations Experience** portal:

![Discovered Assets](./images/discovered_assets.png "Discovered Assets")

1. Locate the discovered asset whose name starts with `fullmachinetool-`.
2. Select it and click **Import and create asset**.
3. On the **Asset details** page, assign a clear name to the asset.

⚠️ **Heads-up:** Keep track of this name — it becomes part of the subscription string when you configure your **Dataflow** later.

![Asset Details](./images/asset_details.png "Asset Details")

4. Continue through the **Data points** and **Events** pages by clicking **Next**.
5. On the **Review** page, click **Create** to finalize the asset.

After some delay, the onboarded asset will appear in the **Assets** list:

![FullMachine Asset](./images/full_machine_asset.png "FullMachine Asset")
