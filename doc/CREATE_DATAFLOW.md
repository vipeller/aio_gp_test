### Create Dataflow

Setting up dataflow requires endpoint credentials from an [Event Stream setup](./CREATE_EVENTSTREAM.md).

#### Create Fabric Endpoint

Using the **Azure Iot Operations experience** portal, navigate to **Data flow endpoints**, and press **new**:

![Data flow endpoints](./images/fabric_endpoint.png "Data flow endpoints")

On the upcoming screen, copy the bootstrap server from the Fabric Credentials pane to the Host name. Also make sure that the Authentication method/SASL Type are aligned:

![Endpoint Host](./images/endpoint_bootstrap.png "Endpoint Host")

As a next step, the Username/Password needs to be set. To achieve this, we need to add these to a keystore. 

Add a reference to the username. Note, that the username value must be "$ConnectionString"

![Fabric Username](./images/username_reference.png "Fabric Username")

Add a reference to the password. For this step, you need to copy the **Connection string-primary key** from the Kafka credentials pane:

![Fabric Password](./images/username_reference.png "Fabric Password")

Finally, name the secret and press **Apply**. This will create a dataflow endpoint that we use later.

![Endpoint Apply](./images/endpoint_apply.png "Endpoint Apply")