# Cluster Authentication<br><font size="3">Enabling IAM user and role access to an AWS EKS Cluster</font>

## Goal

As we're going to describe all the necessary steps to enable IAM users/groups/roles to an AWS EKS cluster (AWS auth map), this document aims to help the development of IaC automations like Terraform.

## Considerations

If your main goal is not to create an IaC automation you'd better go with eksctl to enable IAM users/groups/roles to an AWS EKS cluster.

We'll be focused on group management but you can use this guide for IAM user and role management as well.  

## References

* Must read that:
https://github.com/kubernetes-sigs/aws-iam-authenticator#full-configuration-format  
https://kubernetes.io/docs/reference/access-authn-authz/rbac/  


* You can need this:  
https://aws.amazon.com/premiumsupport/knowledge-center/eks-api-server-unauthorized-error/  
https://www.eksworkshop.com/beginner/091_iam-groups/create-iam-roles/

## General guidance

Adding users to your EKS cluster has 2 sides: one is IAM (Identity and Access Management on the AWS side). The other one is RBAC (Role Based Access Management on Kubernetes).

* IAM side
    1. Create an IAM Policy to allow an IAM Groups to assume an IAM Role
    2. Create an IAM Role
    3. Attach the Policy to the Role
    4. Create an IAM Group
    5. Add a new policy to the Group which allows Users from this Group to assume the IAM Role
    6. Add IAM Users to the Group
* Kubernetes side
    1. Create a Role (or a ClusterRole)
    2. Bind the new role/clusterRole to a group 
    3. Map the IAM User/Group/Role to the Kubernetes User/Group
* Verify the entry in the AWS auth map

## Step-by-Step
