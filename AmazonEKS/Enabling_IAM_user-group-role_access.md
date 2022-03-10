# Cluster Authentication<br><font size="3">Enabling IAM user and role access to an AWS EKS Cluster</font>

## Goal

## General guidance
1. Create an IAM Policy to allow an IAM Groups to assume an IAM Role
2. Create an IAM Role
3. Attach the Policy to the Role
4. Create an IAM Group
5. Add a new policy to the Group which allows Users from this Group to assume the IAM Role
6. Add IAM Users to the Group
7. Map the IAM Role to a Kubernetes Group
8. Verify the entry in the AWS auth map
