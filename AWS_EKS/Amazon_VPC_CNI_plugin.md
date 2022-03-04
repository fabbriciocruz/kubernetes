
# Amazon VPC CNI plugin (Amazon EKS): Increase the amount of available IP addresses for your Amazon EC2 nodes

## Documentation

* This howto is based on the following:
    * [Increase the amount of available IP addresses for your Amazon EC2 nodes](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)

<bl >

* [Amazon VPC CNI plugin](https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/)

* [Amazon EKS recommended maximum Pods for each Amazon EC2 instance type](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#determine-max-pods)

* [aws / amazon-vpc-cni-k8s (GitHub)](https://github.com/aws/amazon-vpc-cni-k8s)

* [Pod networking (CNI)](https://docs.aws.amazon.com/eks/latest/userguide/pod-networking.html)

* [EKS Managed Nodegroups](https://eksctl.io/usage/eks-managed-nodes/)


## Goal

* Since each Pod is assigned its own IP address, the number of IP addresses supported by an instance type (EKS node) is a factor in determining the number of Pods that can run on the instance. AWS Nitro System instance types optionally support significantly more IP addresses than non Nitro System instance types. Not all IP addresses assigned for an instance are available to Pods however.  
To determine how many Pods an instance type supports, see [Amazon EKS recommended maximum Pods for each Amazon EC2 instance type](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#determine-max-pods).  
To assign a significantly larger number of IP addresses to your instances, you must have version 1.9.0 or later of the Amazon VPC CNI add-on installed in your cluster and configured appropriately.  
For example: A t3.small can have 3 ENIs and each one of its ENI can have 4 IP addresses. So, the maximum pods for a t3.small EKS node is 11 pods (11 IP addresses for Pods and 01 IP address for the EKS Node). When enabled, the CNI plugin and the Prefix Delegation will increase that number to 110 pods.

    * Take a look at the link, download the max-pods-calculator.sh and run the following commands changing the instance-type and cni-version parameters as you need.  
    [Amazon EKS recommended maximum Pods for each Amazon EC2 instance type](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#determine-max-pods)

        * Command 01

            ```sh
            ./max-pods-calculator.sh --instance-type t3.small --cni-version 1.10.1-eksbuild.1
            ```

            Output:

            ```sh
            11
            ```
        * Command 02
        
            ```sh
            ./max-pods-calculator.sh --instance-type t3.small --cni-version 1.10.1-eksbuild.1 --cni-prefix-delegation-enabled
            ```

            Output:

            ```sh
            110
            ```

* Managed node groups enforces a maximum number on the value of maxPods. For instances with less than 30 vCPUs the maximum number is 110 and for all other instances the maximum number is 250. This maximum number is applied whether prefix delegation is enabled or not

## Considerations

* This HowTo has been validated with a t3.small EC2 instance as EKS Node in sa-east-1 region

## Prerequisites

* This apply only to AWS Nitro System EC2 instances

* Your VPC must have enough available contiguous /28 IPv4 address blocks to support this capability.

* Each instance type supports a maximum number of pods. If your managed node group consists of multiple instance types, the smallest number of maximum pods for an instance in the cluster is applied to all nodes in the cluster.

* Version 1.9.0 or later (for version 1.20 or earlier clusters or 1.21 or later clusters configured for IPv4) or 1.10.1 or later (for version 1.21 or later clusters configured for IPv6) of the Amazon VPC CNI add-on deployed to your cluster.

## HowTo

1. Check your EKS Cluster version (Server Version)

    ```sh
    kubectl version --short
    ```

    Output:
    ```sh
    Client Version: v1.22.2
    Server Version: v1.21.5-eks-bc4871b
    ```

2. Confirm that your currently-installed Amazon VPC CNI version is 1.9.0 or 1.10.1 or later

    ```sh
    kubectl describe daemonset aws-node --namespace kube-system | grep Image | cut -d "/" -f 2
    ```

    If your version is earlier than 1.9.0, then you must update it. For more information, see the updating sections of [Managing the Amazon VPC CNI add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)

2. Enable the parameter to assign prefixes to network interfaces for the Amazon VPC CNI Daemonset. When you deploy a 1.21 or later cluster, version 1.10.1 or later of the VPC CNI add-on is deployed with it, and this setting is true by default.

    * Check if the parameter is enabled

        ```sh
        kubectl describe daemonsets.apps -n kube-system | grep ENABLE_PREFIX_DELEGATION
        ```

    * If the command above returns "false" then run the following command

        ```sh
        kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
        ```

3. (Optional, but recommended) The Amazon VPC CNI add-on configured with its own IAM role that has the necessary IAM policy attached to it. For more information, see [Configuring the Amazon VPC CNI plugin to use IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html)

4. Enable the parameter to assign prefixes to network interfaces for the Amazon VPC CNI Daemonset (ENABLE_PREFIX_DELEGATION).<br> 
If the EKS Cluster version is 1.21 or later the parameter ENABLE_PREFIX_DELEGATION is true by default.

    * Check if the parameter ENABLE_PREFIX_DELEGATION has been set

        ```sh
        kubectl describe daemonset -n kube-system aws-node | grep -in ENABLE_PREFIX_DELEGATION
        ```

    * If the parameter has not been set yet then run the following command:

        ```sh
        kubectl describe daemonset -n kube-system aws-node | grep -in ENABLE_PREFIX_DELEGATION
        ```

5. Configure the parameter WARM_PREFIX_TARGET.<br>
If the EKS Cluster version is 1.21 or later the parameter WARM_PREFIX_TARGET is configured to 1 by default.

    * Check if the parameter WARM_PREFIX_TARGET has been set

        ```sh
        kubectl describe daemonset -n kube-system aws-node | grep -in WARM_PREFIX_TARGET
        ```

    * If the parameter has not been set yet then run the following command:

        ```sh
        kubectl set env daemonset aws-node -n kube-system WARM_PREFIX_TARGET=1
        ```

6. Add the following parameter to your NodeGroup config file

    ```sh
    maxPodsPerNode: 80
    ```

    The followind is an exemple of a NodeGroup config file:
    
    ```sh
    apiVersion: eksctl.io/v1alpha5
    kind: ClusterConfig

    metadata:
      name: <EksClusterName>
      region: <AwsRegion>

    managedNodeGroups:
      - name: <NodeGroupName>
        desiredCapacity: 1
    # Using spot instances and selecting ec2 instance types
        spot: true
        instanceTypes: 
        - t3.small
        maxPodsPerNode: 110
        ssh:
          enableSsm: true
        privateNetworking: true # This must be set to 'true' when only 'Private' subnets has been configured on the EKS Cluster config file
    ```

5. Describe one of the nodes to determine the max pods for the node.

    ```sh
    kubectl get nodes
    kubectl describe node <NodeName>
    ```

    Output:

    ```sh
    ...
    Allocatable:
    attachable-volumes-aws-ebs:  25
    cpu:                         1930m
    ephemeral-storage:           76224326324
    hugepages-1Gi:               0
    hugepages-2Mi:               0
    memory:                      7244720Ki
    pods:                        110
    ```

## Troubleshooting

* [How do I resolve kubelet or CNI plugin issues for Amazon EKS?](https://aws.amazon.com/premiumsupport/knowledge-center/eks-cni-plugin-troubleshooting/)

* [Troubleshooting Tips](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/troubleshooting.md)

## Doubts
* If you have an existing managed node group, the next AMI or launch template update of your node group results in new worker nodes coming up with the new IP address prefix assignment-enabled max-pod value (https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html)

* I think we should add the VPC CNI Plugin configuration to the Cluster config yaml file. That way we add this feature to our product (Remember the prerequisite of contiguous /28 IPv4 address blocks. For that to be always true we must always create the customer EKS cluster in one new VPC and carefully plan the VPC IPv4 CIDR block and the number of available IPv4 addresses per subnet)

## Must read

* [EKS Best Practices Guides: Networking in EKS](https://aws.github.io/aws-eks-best-practices/reliability/docs/networkmanagement/)


## Related topics

* [Kubernetes Scalability thresholds](https://github.com/kubernetes/community/blob/master/sig-scalability/configs-and-limits/thresholds.md)

* [Architecting Kubernetes clusters — choosing a worker node size](https://learnk8s.io/kubernetes-node-size#:~:text=On%20Amazon%20Elastic%20Kubernetes%20Service,of%20the%20type%20of%20node)


## The reason why we should not set the `WARM_IP_TARGET` parameter on the step xxx of the HowTo topic
From [Add additional documentation around IPs and ENIs](https://github.com/mogren/amazon-vpc-cni-k8s/commit/7f40d80b77859ba8854d997690cabc69ea645612)

To be extra clear, only set `WARM_IP_TARGET` for small clusters, or clusters with very low pod churn. It's also advised 
to set `MINIMUM_IP_TARGET` slightly higher than the expected number of pods you plan to run on each node.

The reason to be careful with this setting is that it will increase the number of EC2 API calls that ipamd has to do 
to attach and detach IPs to the instance. If the number of calls gets too high, they will get throttled and no new ENIs 
or IPs can be attached to any instance in the cluster. 

That is the main reason why we have `WARM_ENI_TARGET=1` as the default setting. It's a good balance between having too 
many unused IPs attached, and the risk of being throttled by the EC2 API.

## MINIMUM_IP_TARGET and WARM_IP_TARGET explained
From [Trouble understanding WARM_IP_TARGET, WARM_ENI and MINIMUM_IP_TARGET
#1077](https://github.com/aws/amazon-vpc-cni-k8s/issues/1077)

Regarding MINIMUM_IP_TARGET and WARM_IP_TARGET - Say suppose I will be deploying 10 pods on each node and if I set WARM_IP_TARGET to 10. Then when 10 pods are allocated, CNI tries to allocate another 10 IPs which might never be used. Hence we can set MINIMUM_IP_TARGET to 10 (based on number of pods) and WARM_IP_TARGET to maybe 2 or 3. Now we can deploy 10 pods (since MINIMUM_IP_TARGET sets the floor on number of IPs) and CNI would allocate an additional WARM_IP_TARGET number of IPs. Whereas WARM_ENI_TARGET specifies the number of ENIs to be kept in reserve (if available) for pod assignment.


## How to update a nodeGroup
 5809  eksctl create nodegroup --config-file=Nodegroup-new.yaml 
 5810  kubectl get nodes
 5811  eksctl delete nodegroup --cluster eks-rancher-server --name nodegrp-eks-rancher-server