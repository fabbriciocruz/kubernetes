# AWS EKS and Rancher
* How-to publication date: November 2021
* How-to update: August 2022
    * Rancher Version: v2.6.2 ???
    * AWS EKS Version: 1.20.7 ????
    * Nginx Version: 1.19.4 ????

<bl >

* Intro

    Rancher users can perform full lifecycle management of their EKS environment, including node management, auto scaling, importing, provisioning, securing, and configuration of clusters—all within a single pane of glass.

## Goals
1. Set up an EC2 instance and install the EKS management tools

2. Set up a new AWS EKS Cluster and a Rancher Server into an existing VPC
    * Rancher Server will be deployed as pods in the EKS Cluster and it will be accessed via AWS Classic Load Balancer and Nginx Ingress Controller
    * Rancher Server will be accessed via HTTPS using the Rancher Server self-signed certificate
3. Launch an example application
    * The application will be accessed via HTTPS using the Rancher Server self-signed certificate
    * The application will access an AWS EFS as persistent storage

## Tests

* All tests have been run in the AWS sa-east-1 region
* Rancher Version: v2.6.2
* AWS EKS Version: 1.20.7
* Nginx Version: 1.19.4

## Considerations
* As per Rancher recommendations the Load Balancer for the Rancher Server must be a Layer 4 LB and per Rancher documentation the Load Balancer should be an AWS Classic LB
    * "We recommend configuring your load balancer as a Layer 4 balancer, forwarding plain 80/tcp and 443/tcp to the Rancher Management cluster nodes. The Ingress Controller on the cluster will redirect http traffic on port 80 to https on port 443."
    https://rancher.com/docs/rancher/v2.6/en/installation/install-rancher-on-k8s/chart-options/#external-tls-termination

## Architecture

![image](https://github.com/fabbriciocruz/kubernetes/blob/eadd8dd0d290365e149fdb238904002ee902e190/Amazon_EKS/Documentation_Images/Architecture_Rancher_EKS.jpg)

## Network Requirements

1. VPC
2. N Private Subnets (One private subnet per Availability Zone)
3. N Private Route Tables (One route table per Private Subnet)
4. N Public Subnets (One Public Subnet per Availability Zone)
5. One Public Route Table for the N Public Subnets above 
6. N Nat Gateways (One Nat Gateway per Public Subnet)

## Choosing a Rancher Version

1. Go to the link below, open the desired Rancher version and search for "Hosted Kubernetes"

    https://www.suse.com/suse-rancher/support-matrix/all-supported-versions/

2. Take note of the EKS Highest Version Validated/certified (In the image below the version is 1.20.x)
    * Obs.: You only need to use the first two numbers in the yaml cluster config file

![image](https://github.com/fabbriciocruz/kubernetes/blob/eadd8dd0d290365e149fdb238904002ee902e190/Amazon_EKS/Documentation_Images/Rancher_Hosted_Kubernetes_Version.png)

3. Gp to the link below and check the AWS EKS version 

    https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

* As we go through this howto we'll run the command to add the Rancher repo and we'll get the latest stable version. So, you don't need to bother with the link bellow. It's just to well document this howto (The link bellow will take you to Rancher 2.6 documentation)

   https://rancher.com/docs/rancher/v2.6/en/installation/resources/choosing-version/

* As you have taken note of the latest Rancher version then you'll need to check the Helm Version Requirements matrix (Rancher 2.6 documentation)
    
    https://rancher.com/docs/rancher/v2.6/en/installation/resources/helm-version/

    * For example: Helm v3.2.x or higher is required to install or upgrade Rancher v2.5

## Installing the environment tools

1. Create a IAM Role and attach the AdministratorAccess policy

2. Deploy an EC2 instance and attach the IAM Role

3. Run the commands from the shell script [Environment-setup.sh](https://github.com/fabbriciocruz/kubernetes/blob/eadd8dd0d290365e149fdb238904002ee902e190/Amazon_EKS/Config_Files/Environment-setup.sh)

## Create the EKS Cluster and Rancher Server
* Obs.: From the Rancher documentation we're following the option "Deploy Rancher into an existing VPC and a new Amazon EKS cluster"

1. Create the EKS Cluster
    * Edit the [manifest yaml file](https://github.com/fabbriciocruz/kubernetes/blob/eadd8dd0d290365e149fdb238904002ee902e190/Amazon_EKS/Config_Files/clusterConfig_EksRancherInss_NodeGroupSpotInstance.yaml) as you need and apply the configuration
        ```sh
        eksctl create cluster -f <FILE_NAME>
        ```
    * Test the Cluster
        ```sh
        eksctl get cluster
        ```

2. Import your EKS Console credentials to your new cluster

    * Add embratel.support role as cluster admin
        ```sh
        export EMBRATEL_ROLE=$(aws iam get-role --role-name embratel.support --query Role.Arn --output text)
        ```

    * With your ARN in hand, you can issue the command to create the identity mapping within the cluster.
        ```sh
        eksctl create iamidentitymapping \
        --cluster <CLUSTER_NAME> \
        --arn ${EMBRATEL_ROLE} \
        --username embratel.support \
        --group system:masters
        ```

    * To verify your entry in the AWS auth map within the console
        ```sh
        kubectl describe configmap -n kube-system aws-auth
        ```

3. Install Helm (Write something here about the Helm version matrix and Rancher)

    ```sh
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    ```
    * Check the Helm version
        ```sh
        helm version --short
        ```

4. Install an Ingress Controller (check the latest version for the ingress-nginx)

    * The cluster needs an Ingress so that Rancher can be accessed from outside the cluster.
    * The following command installs an nginx-ingress-controller with a LoadBalancer service.    
    * This will result in an AWS ELB (Classic) in front of NGINX:

        ```sh
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
        helm repo update
        helm upgrade --install \
        ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --set controller.service.type=LoadBalancer \
        --version 3.12.0 \
        --create-namespace
        ```

    * Get Load Balancer external-IP FQDN and save it for the DNS Servers configuration

        ```sh
        kubectl get service ingress-nginx-controller --namespace=ingress-nginx
        ```

5. Install/Upgrade Rancher on an EKS Cluster

    * Add the Helm Chart Repository (Stable: Recommended for production environments)

        ```sh
        helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
        ```

    * Update helm charts database
        ```sh
        helm repo update
        ```

    * Create a Namespace for Rancher

        ```sh
        kubectl create namespace cattle-system
        ```

    * Choose the SSL Configuration
        * There are three recommended options for the source of the certificate used for TLS termination at the Rancher server: Rancher-generated TLS certificate, Let’s Encrypt and Bring your own certificate.
        * This howto is based on the option Rancher-generated TLS certificate which requires to install Cert-Manager into the cluster.
            * Install cert-manager
                * Upgrade your CRD resources before upgrading the Helm chart:

                    ```sh
                    kubectl apply -f https://github.com/jetstack/cert-manager/releases/download/v1.5.1/cert-manager.crds.yaml
                    ```

                * Add the Jetstack Helm repository
                    ```sh
                    helm repo add jetstack https://charts.jetstack.io
                    ```

                * Update your local Helm chart repository cache
                    ```sh
                    helm repo update
                    ```

                * Install the cert-manager Helm chart
                    ```sh
                    helm install cert-manager jetstack/cert-manager \
                    --namespace cert-manager \
                    --create-namespace \
                    --version v1.5.1
                    ```
                * Verify cert-manager is deployed correctly
                    ```sh
                    kubectl get pods --namespace cert-manager
                    ```

6. Install Rancher with Helm and Your Chosen Certificate Option

    ```sh
    helm install rancher rancher-stable/rancher \
    --namespace cattle-system \
    --set hostname=<FQDN_FOR_YOUR_RANCHER_SERVER>
    ```

    Verify that the Rancher server is successfully deployed

    ```sh
    kubectl -n cattle-system rollout status deploy/rancher
    ```

7. Save your options (IMPORTANT !!)
    * Make sure you save the --set options you used. You will need to use the same options when you upgrade Rancher to new versions with Helm.

<bl >

8. Set up DNS

    Create the following CNAME on your DNS Server
    ```sh
    <FQDN_FOR_YOUR_RANCHER_SERVER> CNAME <LOADBALANCER_EXTERNAL-IP_FQDN>
    ```

9. Open a browser, access the Rancher admin web page using the Rancher Server FQDN, follow the instructions on the page and Welcome to Rancher !!

* Further information for this howto can be found in the following links

    * Installing Rancher on Amazon EKS

        https://rancher.com/docs/rancher/v2.6/en/installation/install-rancher-on-k8s/amazon-eks/

    * Install the Rancher Helm Chart
    
        https://rancher.com/docs/rancher/v2.6/en/installation/install-rancher-on-k8s/#install-the-rancher-helm-chart






## Configure EFS as persistent storage

* The overall workflow for setting up existing storage is as follows:
    * Set up your persistent storage. This may be storage in an infrastructure provider, or it could be your own storage. This howto covers the AWS EFS file system
    * Add a persistent volume (PV) that refers to the persistent storage.
    * Add a persistent volume claim (PVC) that refers to the PV.
    * Mount the PVC as a volume in your workload.

<bl >

* Create an Amazon EFS file system
    1. Retrieve the VPC ID that your EKS cluster is in

        ```sh
        vpc_id=$(aws eks describe-cluster \
            --name <CLUSTER_NAME> \
            --query "cluster.resourcesVpcConfig.vpcId" \
            --output text)
        ```

    2. Retrieve the CIDR range for your cluster's VPC
    TIP: The CIDR range must be the same as that of your EKS Cluster

        ```sh
        cidr_range=$(aws ec2 describe-vpcs \
            --vpc-ids $vpc_id \
            --query "Vpcs[].CidrBlock" \
            --output text)
        ```

    3. Create a security group with an inbound rule that allows inbound NFS traffic for your Amazon EFS mount points.

        * Create a security group

            ```sh
            security_group_id=$(aws ec2 create-security-group \
                --group-name MyEfsSecurityGroup \
                --description "My EFS security group" \
                --vpc-id $vpc_id \
                --output text)
            ```

        * Create an inbound rule

            ```sh
            aws ec2 authorize-security-group-ingress \
                --group-id $security_group_id \
                --protocol tcp \
                --port 2049 \
                --cidr $cidr_range
            ```

    4. Create an Amazon EFS file system for your Amazon EKS cluster

        * Create a file system

            ```sh
            file_system_id=$(aws efs create-file-system \
                --region <AWS_REGION> \
                --performance-mode generalPurpose \
                --query 'FileSystemId' \
                --output text)
            ```

        * Add mount targets for the subnets that your nodes are in
            * You'd run the command below once for each subnet in each AZ that you had a node in, replacing subnet-EXAMPLEe2ba886490 with the appropriate subnet ID

            ```sh
            aws efs create-mount-target \
                --file-system-id $file_system_id \
                --subnet-id subnet-EXAMPLEe2ba886490 \
                --security-groups $security_group_id
            ```

        * Wait untill the Mount Targets to be Available
            * You can check this on Aws console > EFS > File Systems > click on the new created file system > Network tab
        * Create a sub directory in the EFS file system (A sub directory of EFS can be mounted inside container. This gives cluster operator the flexibility to restrict the amount of data being accessed from different containers on EFS)

        * Run the following commands
        
            ```sh
            sudo yum install -y amazon-efs-utils
            !
            sudo mkdir /mnt/efs
            !
            sudo mount -t efs -o tls <EFS_FILE_SYSTEM_ID>:/ /mnt/efs/
            !
            sudo mkdir /mnt/efs/subdir_test
            !
            sudo ls /mnt/efs
            !
            ```

## Deploy an example application on Rancher Server UI (User Interface): Workload with Ingress

1. Using a browser, Open the Rancher Server UI

2. From the Clusters page, open the cluster that you just created.

3. From the main menu of the Dashboard, select "Projects/Namespaces"

4. Create a new Project

5. Still in the Projects/Namespaces page, create a Namespace for the new Project
    * Name: test

<bl >

6. Deploying a Workload 
    * Click "Workloads > Deployments > Create"
    * Select the new created Namespace
    * Name: test-01
    * Replicas: 2
    * Container Image: rancher/hello-world
    * Click Add Port
        * Service Type: Cluster IP
        * Name: test-01-service
        * Private Container Port: 80
        * Protocol: TCP
    * Go to Storage
        * Add Volume > NFS
            * Path: /subdir_test
            * Server: <EFS_ID>.efs.<AWS_REGION>.amazonaws.com
            * Mount Point: /mnt/efs
    * Click Create

<bl >

7. Deploying the Ingress

    * Go to "Service Discovery > Ingresses > Create"
    * Select the new created Namespace
    * Name: test-01-ingress
    * Required Host: THE APPLICATION FQDN
    * Prefix: /
    * Target Service: test-01
    * Port: 80
    * Click Default Backend
        * Target Service: test-01
        * Port: 80
    * Click Certificates
        * Add Certificate
        * Certificate - Secret Name: Default Ingress Controller Certificate
        * Write the application FQDN in the box    
    * Click Create

<bl >

8. Test the application

    * Open a browser and type the FQDN for you application

<bl >

9. Test the EFS access

    * Go back to the terminal

    * Get the application pods name

        ```sh
        kubectl get pods -n test
        ```
    
     * Get a shell to the application pods

        ```sh
        kubectl exec -ti -n test <POD_NAME> -- /bin/bash
        ```

    * List the content of the /mnt/efs directory, create a new file and exit the pod

        ```sh
        ls /mnt/efs
        !
        touch /mnt/efs/file01
        !
        ls /mnt/efs
        !
        exit
        ```

    * Get a shell to the second pod, list the directory /mnt/efs and check if the file01 does exist

## Cleanup

1. Delete the EKS Cluster
    ```sh
    eksctl delete cluster <EKS_CLUSTER_NAME>
    ```
2. Delete the KMS Customer-managed Key

3. Delete the Cloud9 environment

4. Delete the AWS EFS file system

### Further Tests for EFS 
1. Deploy the EFS CSI Driver (AWS Documentation)
    * Check if the AWS CSI driver will show on Deployments > test-01 > Edit > Storage > Add Volume > CSI > Driver
    * Check if the AWS CSI driver will show on Storage > PersistentVolumes > Create > Volume Plugin
    * Check if the AWS CSI driver will show on Storage > StorageClasses > Create > Provisioner

## References

* A very good article on Rancher AWS EKS benefits
    * Optimizing Your Kubernetes Clusters with Rancher and Amazon EKS

        https://aws.amazon.com/pt/blogs/apn/optimizing-your-kubernetes-clusters-with-rancher-and-amazon-eks/

## Checked but not so useful...

* Creating an EKS Cluster

    https://rancher.com/docs/rancher/v2.5/en/cluster-provisioning/hosted-kubernetes-clusters/eks/
    * From inside Rancher: As a prerequisite you must have deployed a Rancher Server in some other place than EKS


 
## To read after 

* Rancher on the AWS Cloud - Quick Start Reference Deployment

    https://aws-quickstart.github.io/quickstart-eks-rancher/

* Helm Tutorial: How To Install and Configure Helm

    https://devopscube.com/install-configure-helm-kubernetes/

* Creating a VPC for your Amazon EKS cluster

    https://docs.aws.amazon.com/eks/latest/userguide/create-public-private-vpc.html

* NGINX Ingress Controller

    https://kubernetes.github.io/ingress-nginx/

* Amazon ALB Configuration + RKE

    https://rancher.com/docs/rancher/v2.0-v2.4/en/installation/resources/advanced/helm2/rke-add-on/layer-7-lb/alb/


## Staging area (burn after reading...)
* let's encrypt discussion
    https://stackoverflow.com/questions/64541147/ingress-nginx-cert-manager-certificate-invalid-on-browser


* xip.io