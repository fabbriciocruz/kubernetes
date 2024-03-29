
# Amazon VPC CNI plugin and Prefix assignment: Increase the amount of available IP addresses for your Amazon EC2 EKS nodes

## References

* [Increase the amount of available IP addresses for your Amazon EC2 nodes](https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html) (The base for this HowTo)

* [Amazon VPC CNI plugin increases pods per node limits](https://aws.amazon.com/blogs/containers/amazon-vpc-cni-increases-pods-per-node-limits/) (A great article on how it works. By Sheetal Joshi, Mike Stefaniak, and Jayanth Varavani)

* [Amazon EKS recommended maximum Pods for each Amazon EC2 instance type](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#determine-max-pods)

* [aws / amazon-vpc-cni-k8s (GitHub)](https://github.com/aws/amazon-vpc-cni-k8s)

* [Pod networking (CNI)](https://docs.aws.amazon.com/eks/latest/userguide/pod-networking.html)

* [EKS Managed Nodegroups](https://eksctl.io/usage/eks-managed-nodes/)

* [IP addresses per network interface per instance type](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI)


## Goal

The Amazon VPC CNI plugin for Kubernetes is the networking plugin for pod networking in Amazon EKS clusters. The plugin is responsible for allocating VPC IP addresses to Kubernetes nodes and configuring the necessary networking for pods on each node. Using this plugin allows Kubernetes pods to have the same IP address inside the pod as they do on the VPC network.

Since each Pod is assigned its own IP address, the number of IP addresses supported by an instance type (EKS node) is a factor in determining the number of Pods that can run on the instance. AWS Nitro System instance types optionally support significantly more IP addresses than non Nitro System instance types. Not all IP addresses assigned for an instance are available to Pods however.  
To determine how many Pods an instance type supports, see [Amazon EKS recommended maximum Pods for each Amazon EC2 instance type](https://docs.aws.amazon.com/eks/latest/userguide/choosing-instance-type.html#determine-max-pods).  

By default, the number of IP addresses available to assign to pods is based on the maximum number of elastic network interfaces and secondary IPs per interface that can be attached to an EC2 instance type.  
With prefix assignment mode, the maximum number of elastic network interfaces per instance type remains the same, but you can now configure Amazon VPC CNI to assign /28 (16 IP addresses) IPv4 address prefixes, instead of assigning individual secondary IPv4 addresses to network interfaces.  

![image](https://d2908q01vomqb2.cloudfront.net/fe2ef495a1152561572949784c16bf23abb28057/2021/09/03/image-8-1.png)

For example: A t3.small can have 3 ENIs and each one of its ENI can have 4 IP addresses. So, the maximum pods for a t3.small EKS node is 11 pods (11 IP addresses for Pods and 01 IP address for the EKS Node). When enabled, the CNI plugin and the Prefix Delegation will increase that number to 110 pods.  


Take a look at the link, download the max-pods-calculator.sh and run the following commands changing the instance-type and cni-version parameters as you need.  
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
For a list of the maximum number of pods supported by each instance type, see [eni-max-pods.txt](https://github.com/awslabs/amazon-eks-ami/blob/master/files/eni-max-pods.txt) on GitHub.

Managed node groups enforces a maximum number on the value of maxPods. For instances with less than 30 vCPUs the maximum number is 110 and for all other instances the maximum number is 250. This maximum number is applied whether prefix delegation is enabled or not.

The number of prefixes that can be assigned to an ENI is equal to the number of [IP addresses supported by each ENI of the instance](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-eni.html#AvailableIpPerENI) minus one (the primary ip address which is attached to the EKS node).  
For example, for a t3.small instance the number of IP addresses per ENI is 4. Therefore, the number of prefixes per ENI will be 3.


## Considerations

This HowTo has been validated against the following scenario:
* EKS Cluster Version 1.21
* Managed Node Group
* Node instance type: t3.small (spot instance)
* Region: sa-east-1
* The Cluster and all its resources have been created using the [eksctl](https://eksctl.io/) command.
* All config files can be found [here](https://github.com/fabbriciocruz/kubernetes/tree/main/AmazonEKS/Config_Files/Amazon_VPC_CNI_plugin)


## Prerequisites

* An existing cluster. To deploy one you can use this [config file](https://github.com/fabbriciocruz/kubernetes/blob/main/AmazonEKS/Config_Files/Amazon_VPC_CNI_plugin/ClusterConfig.yaml) and run the following command:

    ```sh
    eksctl create cluster -f <ClusterConfigFile.yaml>
    ```

* [Recommended version of the Amazon VPC CNI add-on for each cluster version](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html#w245aac20c17c17b7)

* Prefix assignment mode is supported on AWS Nitro based EC2 instance types with Amazon Linux 2. This capability is not supported on Windows.

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

2. (Optional, but recommended) The Amazon VPC CNI add-on configured with its own IAM role that has the necessary IAM policy attached to it. For more information, see [Configuring the Amazon VPC CNI plugin to use IAM roles for service accounts](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html)


3. Confirm that your currently-installed Amazon VPC CNI version is 1.9.0 or 1.10.1 or later

    ```sh
    kubectl describe daemonset aws-node --namespace kube-system | grep Image | cut -d "/" -f 2
    ```

    If your version is earlier than 1.9.0, then you must update it. For more information, see the updating sections of [Managing the Amazon VPC CNI add-on](https://docs.aws.amazon.com/eks/latest/userguide/managing-vpc-cni.html)

4. Enable the parameter to assign prefixes to network interfaces for the Amazon VPC CNI Daemonset (ENABLE_PREFIX_DELEGATION)<br>

    If the EKS Cluster version is 1.21 or later the parameter ENABLE_PREFIX_DELEGATION is true by default

    * Check if the parameter ENABLE_PREFIX_DELEGATION has been set

        ```sh
        kubectl describe daemonset -n kube-system aws-node | grep -in ENABLE_PREFIX_DELEGATION
        ```

    * If the parameter has not been set yet then run the following command:

        ```sh
        kubectl set env daemonset aws-node -n kube-system ENABLE_PREFIX_DELEGATION=true
        ```

5. Configure the parameter WARM_PREFIX_TARGET (Check out at the end of this HowTo some considerations on WARM_IP_TARGET and MINIMUM_IP_TARGET) <br>

    If the EKS Cluster version is 1.21 or later the parameter WARM_PREFIX_TARGET is configured to 1 by default

    * Check if the parameter WARM_PREFIX_TARGET has been set

        ```sh
        kubectl describe daemonset -n kube-system aws-node | grep -in WARM_PREFIX_TARGET
        ```

    * If the parameter has not been set yet then run the following command:

        ```sh
        kubectl set env daemonset aws-node -n kube-system WARM_PREFIX_TARGET=1
        ```

6. Create a new EKS Managed Node Group (Node Group Config file [here](https://github.com/fabbriciocruz/kubernetes/blob/main/AmazonEKS/Config_Files/Amazon_VPC_CNI_plugin/NodeGroupConfig.yaml))
    
    **Note ([Managing NodeGroups](https://eksctl.io/usage/managing-nodegroups/)):** By design, nodegroups are immutable. This means that if you need to change something (other than scaling) like the AMI or the instance type of a nodegroup, you would need to create a new nodegroup with the desired changes, move the load and delete the old one.  

    1. Create a new managed node group

        ```sh
        eksctl create nodegroup --config-file=<NodeGroupConfigFile.yaml>
        ```

    2. Check if it is ok

        ```sh
        kubectl get nodes
        ```
    
    3. Delete the old managed node group

        ```sh
        eksctl delete nodegroup --cluster <EksClusterName> --name <NodegrpName>
        ```

7. Describe one of the nodes to determine the max pods for the node

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

If the output doesn't show 110 pods you could try to uncomment the line maxPodsPerNode on the [node group config file](https://github.com/fabbriciocruz/kubernetes/blob/main/AmazonEKS/Config_Files/Amazon_VPC_CNI_plugin/NodeGroupConfig.yaml) and repeat the step 6:

```sh
maxPodsPerNode: 110
```

## Troubleshooting

* [How do I resolve kubelet or CNI plugin issues for Amazon EKS?](https://aws.amazon.com/premiumsupport/knowledge-center/eks-cni-plugin-troubleshooting/)

* [Troubleshooting Tips](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/troubleshooting.md)

## Must read

* [EKS Best Practices Guides: Networking in EKS](https://aws.github.io/aws-eks-best-practices/reliability/docs/networkmanagement/)


## Related topics

* [Kubernetes Scalability thresholds](https://github.com/kubernetes/community/blob/master/sig-scalability/configs-and-limits/thresholds.md)

* [Architecting Kubernetes clusters — choosing a worker node size](https://learnk8s.io/kubernetes-node-size#:~:text=On%20Amazon%20Elastic%20Kubernetes%20Service,of%20the%20type%20of%20node)


## The reason why we should not set the `WARM_IP_TARGET` parameter on the step 5 of this HowTo
From [Add additional documentation around IPs and ENIs](https://github.com/mogren/amazon-vpc-cni-k8s/commit/7f40d80b77859ba8854d997690cabc69ea645612)

The Amazon VPC CNI supports setting WARM_PREFIX_TARGET or either/both WARM_IP_TARGET and MINIMUM_IP_TARGET. The recommended (and default value set in EKS aws-node DaemonSet deployment [manifest file](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/config/master/aws-k8s-cni-cn.yaml)) configuration is to set WARM_PREFIX_TARGET to 1.  

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

WARM_IP_TARGET or MINIMUM_IP_TARGET – If either value is set, it overrides any value set for WARM_PREFIX_TARGET.

Regarding MINIMUM_IP_TARGET and WARM_IP_TARGET - Say suppose I will be deploying 10 pods on each node and if I set WARM_IP_TARGET to 10. Then when 10 pods are allocated, CNI tries to allocate another 10 IPs which might never be used. Hence we can set MINIMUM_IP_TARGET to 10 (based on number of pods) and WARM_IP_TARGET to maybe 2 or 3. Now we can deploy 10 pods (since MINIMUM_IP_TARGET sets the floor on number of IPs) and CNI would allocate an additional WARM_IP_TARGET number of IPs. Whereas WARM_ENI_TARGET specifies the number of ENIs to be kept in reserve (if available) for pod assignment.
