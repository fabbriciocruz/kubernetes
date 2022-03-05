# Azure AKS Cluster with App Gateway Ingress Controller and Self-Signed Certificate from KeyVault

## Goals
1. Deploy AKS Cluster Using Azure CLI (az aks create)
2. Configure the Ingress Controller using the Application Gateway
3. Create a keyVault
4. Create a self-signed TLS certificate; store it in the KeyVault; upload the certicate to the Application Gateway
5. Deploy an example application (4-AKS-ingress_2048.yaml) which will be exposed via a public Application Gateway listening on HTTP and HTTPS protocols (HTTP will be redirected to HTTPS)

![image](https://gitlab.operacaomulticloud.com/arquitetura/kubernetes/-/raw/master/Azure%20AKS/Documentation_Images/AKS_AppGwIngressController_KeyVaultCertificate-75.png)

## Tests
All tests have been run in the Brazil South location with Standard_B2s VMs as Worker Nodes

## Considerations
* This howto uses the default Ubuntu AKS as node Operating System
* By default the command 'az aks create' creates a new Vnet and subnet for the AKS Cluster. It assigns the CIDR 10.0.0.0/8 to the Vnet and the CIDR 10.240.0.0/16 to the subnet.
    * If the Aks Vnet needs to communicate to another Vnet then a Vnet Peering must be configured
* At the time of this howto the Kubernetes version available is 1.21.2. This version uses the Containerd 1.4.9+azure as Container Runtime.

## First steps

1. Enable the Bash environment in Azure Cloud Shell

2. Enable kubectl bash_completion

    ```sh
    kubectl completion bash >>  ~/.bash_completion
    . /etc/profile.d/bash_completion.sh
    . ~/.bash_completion
    ```

## AKS and Kubernetes Version Matrix
Check the link below for the AKS Kubernetes Release Calendar

https://docs.microsoft.com/en-us/azure/aks/supported-kubernetes-versions?tabs=azure-cli#aks-kubernetes-release-calendar

* Supported kubectl versions

    You can use one minor version older or newer of kubectl (Client Version) relative to your kube-apiserver version (Server Version)

    For example, if your kube-apiserver is at 1.17, then you can use versions 1.16 to 1.18 of kubectl with that kube-apiserver.

    1. To get the current kubectl version running on the Cloud Shell
        ```sh
        kubectl version --short
        ```

    2. To find out what Kubernetes versions (Server Version) are currently available for your subscription and region, use the az aks get-versions command. 
        ```sh
        az aks get-versions \
            --location <AZURE_LOCATION> \
            --subscription <AZURE_SUBSCRIPTION> # Optional
        ```

## Create an AKS Cluster

1. Create some environment variables
    
    ```sh
    AksClusterRG="<RESOURCE_GROUP_NAME>"
    AksClusterName="<AKS_CLUSTER_NAME>"
    AksClusterVersion="<AKS_CLUSTER_VERSION>"
    AksAppGwName="<APPLICATION_GW_NAME>"
    Location="<AZURE_LOCATION>"
    ```

2. Create a Resource Group which will store the AKS Cluster
    
    ```sh
    az group create \
        --name $AksClusterRG \
        --location $Location
    ```

3. Create a Cluster running the following command:

    ```sh
    az aks create \
        --resource-group $AksClusterRG \
        --name $AksClusterName \
        --kubernetes-version $AksClusterVersion \
        --node-count <NUMBER_OF_WORKER_NODES> \
        --generate-ssh-keys \
        --node-vm-size <VM_SIZE> \
        --enable-managed-identity
    ```

4. When you create an AKS cluster, a second resource group is automatically created to store the AKS resources needed to support your cluster, so things like load balancers, public IPs and VMSS backing the node pools will be created here.

    4.1. Create an environment variable and store the name of the second resource group:

    ```sh
    AksClusterSecondRG=$(az aks show \
        --name $AksClusterName \
        --resource-group $AksClusterRG \
        -o tsv \
        --query "nodeResourceGroup")
    ```

5. Configure kubectl to connect to your Kubernetes cluster using the az aks get-credentials command

    ```sh
    az aks get-credentials \
        --name $AksClusterName \
        --resource-group $AksClusterRG
    ```

6. Test the cluster while getting some information 

    6.1. List managed Kubernetes clusters

    ```sh
    az aks list
    ```

    6.2. Get kubectl client and server versions

    ```sh
    kubectl version --short
    ```

    6.3. Get node information

    ```sh
    kubectl get nodes -o wide
    ```

    6.4. Get cluster information

    ```sh
    kubectl cluster-info
    ```

    6.5. Show the details for a managed Kubernetes cluster

    ```sh
    az aks show -g $AksClusterRG -n $AksClusterName
    ```

## Application Gateway Ingress Controller - AGIC

* What is Application Gateway Ingress Controller?

    https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview


* As per Microsoft recommendation, this howto deploys the AGIC through AKS as an add-on

* Pay attention that AGIC only supports Application Gateway v2 SKUs

* The App Gateway must be deployed into the same virtual network as AKS (To evolve the howto we'll need to check this prerequisite carefully !!)

* AKS — Different load balancing options. When to use what?

    https://medium.com/microsoftazure/aks-different-load-balancing-options-for-a-single-cluster-when-to-use-what-abd2c22c2825

* There’s three options when you enable the AGIC add-on:
    * Have an existing Application gateway that you want to integrate with the cluster.
    * Have the AGIC add-on create a new App Gateway to an existing subnet.
    * Have the AGIC add-on create a new App Gateway and its subnet having that you provide the subnet CIDR you want to use.

1. Enable the AGIC add-on in the cluster using the third option listed above (The command bellow enables the add-on and creates an Application Gateway and a Managed Identity for the AGIC):

    * Obs.: As mentioned before the command 'az aks create' creates a new Vnet and subnet for the AKS Cluster. It assigns the CIDR 10.0.0.0/8 to the Vnet and the CIDR 10.240.0.0/16 to the subnet. For the App Gw subnet you'll need to pick up anything different from 10.240.0.0/16.

    <br >

    ```sh
    az aks enable-addons \
        --resource-group $AksClusterRG \
        --name $AksClusterName \
        --addon ingress-appgw \
        --appgw-subnet-cidr <CIDR_BLOCK> \
        --appgw-name $AksAppGwName
    ```

    * Obs.: Note that even if the command has finished its execution it might take up to 15 minutes to deploy the Application gateway and the subnet. So, You need to wait before proceede to the next step. 

<br >

2. You can check with the following command the success of the Application Gateway deployment: 

    ```sh
    az network application-gateway show \
        --name $AksAppGwName \
        --resource-group $AksClusterSecondRG
    ```

## SSL/TLS: Configure a self-signed certificate from Key Vault to Application Gateway

* Appgw SSL/TLS redirect

    https://azure.github.io/application-gateway-kubernetes-ingress/annotations/#ssl-redirect

* Appgw SSL/TLS certificate

    https://azure.github.io/application-gateway-kubernetes-ingress/features/appgw-ssl-certificate/

    https://azure.github.io/application-gateway-kubernetes-ingress/annotations/#appgw-ssl-certificate


1. Declare a variable for the AGIC managed identity`s name which has been created when the ingress controller add-on was enabled

    ```sh
    AgicMngdIdentity=$(az aks addon show \
        --name $AksClusterName \
        --resource-group $AksClusterRG \
        --addon ingress-appgw \
        -o tsv --query "identity.resourceId")
    ```

2. Declare a variable for the AGIC Managed Identity's Principal ID

    ```sh
    AgicMngdIdentityPrincipalId=$(az identity show \
        --ids $AgicMngdIdentity \
        -o tsv \
        --query "principalId")
    ```

3. Check if the subscription has already a Key Vault. If not, then create a new one using the following command:

    ```sh
    vaultName="<KEY_VAULT_NAME>"
    !
    az keyvault create \
        --name $vaultName \
        --resource-group $AksClusterSecondRG  \
        --location $Location
    ```

4. Create a user-assigned managed identity for the Application Gateway and store into variables its identityID and PrincipalId

    ```sh
    az identity create \
        --name appgw-identity \
        --resource-group $AksClusterSecondRG \
        --location $Location
    !
    identityID=$(az identity show \
        -n appgw-identity \
        -g $AksClusterSecondRG \
        -o tsv \
        --query "id")
    !
    PrincipalId=$(az identity show \
        -n appgw-identity \
        -g $AksClusterSecondRG \
        -o tsv \
        --query "principalId")
    ```
5. Assign AGIC identity to have operator access over AppGw identity

    ```sh
    az role assignment create \
        --role "Managed Identity Operator" \
        --assignee $AgicMngdIdentityPrincipalId \
        --scope $identityID
    ```

6. Assign the appgw-identity managed identity to Application Gateway

    ```sh
    az network application-gateway identity assign \
        --gateway-name $AksAppGwName \
        --resource-group $AksClusterSecondRG \
        --identity $identityID
    ```

7. Assign the appgw-identity managed identity GET secret access to Azure Key Vault

    ```sh
    az keyvault set-policy \
        --name $vaultName \
        --resource-group $AksClusterSecondRG \
        --object-id $PrincipalId \
        --secret-permissions get
    ```

8. For each new certificate, declare the variable for the certificate name, create a cert on keyvault and add unversioned secret id to Application Gateway

    ```sh
    CertificateName="<CERTIFICATE_NAME>"
    !
    az keyvault certificate create \
        --vault-name $vaultName \
        --name $CertificateName \
        --policy "$(az keyvault certificate get-default-policy)"
    !
    versionedSecretId=$(az keyvault certificate show \
        --name $CertificateName \
        --vault-name $vaultName \
        -o tsv \
        --query "sid")
    !
    unversionedSecretId=$(echo $versionedSecretId | cut -d'/' -f-5) # remove the version from the url
    !
    ```

9. For each new certificate, upload the certificate to the Application Gateway

    ```sh
    az network application-gateway ssl-cert create \
        --name $CertificateName \
        --gateway-name $AksAppGwName \
        --resource-group $AksClusterSecondRG \
        --key-vault-secret-id $unversionedSecretId # ssl certificate with name $CertificateName will be configured on AppGw
    ```

10. List the certificates uploaded to the Application Gateway (Optional)

    ```sh
    az network application-gateway ssl-cert list \
        --gateway-name $AksAppGwName \
        --resource-group $AksClusterSecondRG \
        -o tsv \
        --query "[].name"
    ```

11. Add the following anottations into the configuration yaml file of your example application and add the name of the Certificate

    [4-AKS-ingress_2048.yaml](https://gitlab.operacaomulticloud.com/arquitetura/kubernetes/-/blob/master/Azure%20AKS/Example_Application/4-AKS-ingress_2048.yaml)

    ```sh
    appgw.ingress.kubernetes.io/appgw-ssl-certificate: "<Name of the Certificate which has been uploaded to the Application Gateway"
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    ```
* Obs.: For Trusted Root Certificates you can begin with the following link:

    https://azure.github.io/application-gateway-kubernetes-ingress/annotations/#appgw-trusted-root-certificate

## Deploy the application
1. Apply the yaml configuration file

    ```sh
    kubectl apply 4-AKS-ingress_2048.yaml
    ```

2. Check the ingress is deployed using the kubectl get ingress command

    ```sh
    kubectl get ingress -n game-2048
    ```

3. Copy the IP Address from the output of the command above and configure your DNS Server

## Account Management on Azure AKS with AAD and AKS RBAC (Coming soon !!)

https://ystatit.medium.com/account-management-on-azure-aks-with-aad-and-aks-rbac-fc178f90475b

## Clean up
Run the following command to delete all resources which have been created through this howto.

```sh
az aks delete \
    --name $AksClusterName \
    --resource-group $AksClusterRG
!
 az group delete \
    --name $AksClusterRG
```

## Useful commands

1. To delete a cluster
    ```sh
    az aks delete \
        --name $AksClusterName \
        --resource-group $AksClusterRG
    ```

2. Stop an AKS Cluster
    ```sh
    az aks stop \
        --name $AksClusterName \
        --resource-group $AksClusterRG
    ```

3. Verify when your cluster is stopped
    ```sh
    az aks show \
        --name $AksClusterName \
        --resource-group $AksClusterRG
    ```

4. Start an AKS Cluster
    ```sh
    az aks start \
        --name $AksClusterName \
        --resource-group $AksClusterRG
    ```

5. Delete a certificate uploaded to the Application Gateway
    ```sh
    az network application-gateway ssl-cert delete \
        --gateway-name $AksAppGwName \
        --resource-group $AksClusterSecondRG \
        --name <CERTIFICATE_NAME>
    ```

## Other References

* Quickstart: Deploy an Azure Kubernetes Service cluster using the Azure CLI

    https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough

* Azure/application-gateway-kubernetes-ingress

    https://github.com/Azure/application-gateway-kubernetes-ingress

* A must-read article !!!
    * Building an AKS baseline architecture - Part 1 - Cluster creation
    https://aztoso.com/aks/baseline-part-1/


# Draft

AksClusterRG="aks-tests-fcruz"
AksClusterName="cluster01"
AksClusterVersion="1.21.2"
AksAppGwName="aksappgw"
Location="brazilsouth"

AksClusterResourcesRG=$(az aks show --name $AksClusterName \
    --resource-group $AksClusterRG -o tsv \
    --query "nodeResourceGroup") 

vaultName="aks-tests-KeyVault"

----------

az aks create \
--resource-group $AksclusterRG \
--name $AksClusterName \
--kubernetes-version $AksClusterVersion \
--node-count 3 \
--generate-ssh-keys \
--node-vm-size Standard_B2s \
--enable-managed-identity

TempVarRg=$(az aks show --name $AksClusterName \
    --resource-group $AksClusterRG \
    --query "nodeResourceGroup") \
    && AksClusterResourcesRG=$(sed -e 's/^"//' -e 's/"$//' <<<"$TempVarRg")

az aks enable-addons --resource-group myAKSResourceGroup \
--name myAKSCluster -a ingress-appgw \
--appgw-subnet-cidr 192.168.2.0/24 \
--appgw-name myAKSAppGateway

az aks enable-addons --resource-group $AksClusterRG \
--name $AksClusterName --addon ingress-appgw \
--appgw-subnet-cidr 10.241.0.0/24 \
--appgw-name $AksAppGwName

-----Burn After reading !!
agicIdentityPrincipalId = AppGwIdendityPricipalID

appgwName = AksAppGwName
resgp = AksClusterResourcesRG


-----------------------------------------



az keyvault certificate create \
--vault-name $vaultName \
--name examplegame03 \
--policy "$(az keyvault certificate get-default-policy)"
versionedSecretId=$(az keyvault certificate show -n examplegame03 --vault-name $vaultName --query "sid" -o tsv)
unversionedSecretId=$(echo $versionedSecretId | cut -d'/' -f-5) 

az network application-gateway ssl-cert delete \
--name "examplegame03.operacaomulticloud.com" \
--gateway-name $AksAppGwName \
--resource-group $AksClusterResourcesRG \
--key-vault-secret-id $unversionedSecretId 


AksClusterResourcesRG
123