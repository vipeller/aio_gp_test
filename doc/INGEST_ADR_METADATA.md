### Create a Dataflow Gen2  

1. Navigate to Fabric and open your workspace. 
2. Click **New item** and select **Dataflow Gen2**. 
3. Enter a **name** for the Dataflow Gen 2 and optionally enable **CI/CD and Git integration** for advanced scheduling and version control. 

### Configure the ADR Connector 

1. Click on Get Data or Get data from another source. 
2. In Choose a data source, search for the Azure Device Registry (preview) connector and click on it. 

*Configuration Options*

|Field|Description |
|-----|------------|
|Scope |Choose to retrieve data from all Azure subscriptions in the tenant or specific ones |
|Subscription ID(s)|*(Optional if choosing Tenant Scope)* Enter one or more Azure subscription IDs (comma-separated) to narrow scope|
|ADR Namespace |*(Optional)* Enter namespace name to filter results.|
|Custom Attributes|*(Optional)* Comma-separated list of up to 500 custom attribute names to include as separate columns. Note that a column named attributes will include all custom attributes in JSON format|

*Advanced Options*

|Option|Description |
|------|------------|
|Maximum Rows per Page|Default is 500. Change to improve performance. It refers to the maximum rows retrieved per API call. |
|Limit Results|Default is True. If set to true, only the first 100 records are returned. |

1. Select a **Scope** (e.g., subscription or tenant). In the example below we have chosen the subscription scope. 
2. If using **subscription scope**, enter your subscription ID. If you used the pipeline, use your team's On-Demand subscription ID (found in the Azure portal). 
3. (Optional + Recommended) If you chose the **Subscription** scope, specify **ADR namespace(s)**. If you used the pipeline, the **namespace** name should be adr-namespace. 
4. (Optional) Define **custom attributes** to extract as separate columns. 
5. Configure **Advanced Options** or leave as default. 
6. Under connection settings click on the **Sign in** button and sign in with your organizational account. 
7. Once the connection has been established, click **Next** to preview the data. 
8. Choose Assets or Devices. In this case, we'll choose Assets. Preview may take a few seconds to load. Once it loads, click **Create**. 

### Create Type-specific Tables 

[add] 

### Send data to a Lakehouse Table 

1. Click the **plus (+)** button next to **Data destination** at the bottom-right of the Dataflow page. Select **Lakehouse** as your destination. 
2. In the **Connect to destination** menu, verify you're signed in with your organizational account. If not, sign in and click **Next**. 
3. In the **Choose destination target** menu: 
a. Select **Create new table** at the top left 
b. Choose your **workspace folder**
c. Select your **Lakehouse** (see prerequisites step 3 for Lakehouse creation) 
d. Name your **table** (e.g., Namespace Asset Metadata) 
e. Click **Next **
4. Keep the toggle **on** for Use automatic settings and click **Save settings**.
5. Back on the Dataflow page: 
a. Click **Save and Run**
b. Navigate to your **workspace** by clicking on it from the left menu of the Fabric page. 
c. Click the **three dots** next to your Dataflow Gen2 
d. Select **Recent runs** to check status 
e. Refresh the page after ~1 minute if needed. Feel free to proceed to step 3 once some time has passed to check if data arrived to the **Lakehouse.**
6. Navigate to the *lakehouse* from your *workspace.*
7. Click on the table created for your **Dataflow Gen 2**. If it doesn’t appear, click the **Refresh** button at the top-left or refresh the page. 
8. (Optional) Use the built-in **Dataflow Gen2 scheduler** to automate and schedule recurring dataflow runs. This ensures your data stays current and reflects the latest state of the asset metadata. To set it up: 
a. Go to your workspace in Fabric. 
b. Locate the Dataflow Gen2 you created. 
c. Click the three dots (⋯) next to the dataflow name. 
d. Select Schedule from the dropdown menu. 
e. Configure the refresh frequency and time according to your needs. 