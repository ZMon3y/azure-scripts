#!/bin/bash

## Author:          Matt Szafir
## Description:     This script is inteded to be used to create an Azure Synapse Workspace, SQL Pool, & run some initial scripts
#                   
## Requirements:    bash >= 4
#                   az cli version?
#                   az login already run

## TODO:            add logging 
#                   add tagging functionality
#                   add script flags & help
#                   add SQL Spark Pool
#                   use "&" for commands so they run in parallel


#### DEFINE VARIABLES ####
echo "DEFINING VARIABLES"
randomNumber=$((1 + RANDOM % 1000))
resourceGroupName="synapsePOC"
location="eastus2"
synapseStorageAccount="synapsestorageaccount$randomNumber" # synapseStorageAccount###
synapseFileSystem="synapsefilesystem$randomNumber" # synapseFileSystem### This is basically a container
synapseWorkspaceName="synapseworkspace$randomNumber"
synapseAdminName="sqladminuser"
synapseAdminPW="y0urg00dP@ssW0rd"
synapseSQLPoolName="sqlpool$randomNumber" # 15 char max
synapsePerformanceLevel="DW100c"
ipaddress=`curl -s checkip.dyndns.org | sed -e 's/.*Current IP Address: //' -e 's/<.*$//'`
createScripts="SQL/create_schemas.sql,SQL/create_tables.sql"

#### ENABLE SYNAPSE EXTENSION ####
echo "ENABLING SYNAPSE EXTENSION"
az extension add --name synapse

#### DELETE RG IF EXISTS ####
echo "DELETING RESOURCE GROUP $resourceGroupName IF IT EXISTS"
if [ `az group exists --name $resourceGroupName` = "true" ]
    then 
        echo "IT EXISTED....DELETING"
        az group delete --name $resourceGroupName
    else
        echo "IT DIDN'T EXIST...CONTINUING"
fi

#### CREATE RG ####
echo "CREATING RESOURCE GROUP $resourceGroupName"
az group create --name $resourceGroupName --location $location

#### CREATE STORAGE ACCOUNT #### --https://docs.microsoft.com/en-us/cli/azure/storage/account?view=azure-cli-latest#az-storage-account-create
echo "CREATING STORAGE ACCOUNT FOR SYNAPSE: $synapseStorageAccount"
az storage account create --name $synapseStorageAccount \
                          --resource-group $resourceGroupName \
                          --access-tier Hot \
                          --enable-hierarchical-namespace true \
                          --kind StorageV2 \
                          --location $location \
                          --sku Standard_RAGRS 

#### CREATE FILE SYSTEM / CONTAINER ####
echo "CREATING FILE SYSTEM (CONTAINER): $synapseFileSystem"
connectString=`az storage account show-connection-string -g $resourceGroupName -n $synapseStorageAccount -o tsv`

az storage container create --name $synapseFileSystem \
                            --account-name $synapseStorageAccount \
                            --connection-string $connectString

#### CREATE SYNAPSE WORKSPACE ####
echo "CREATING SYNAPSE WORKSPACE"
az synapse workspace create --name $synapseWorkspaceName \
                            --resource-group $resourceGroupName \
                            --storage-account $synapseStorageAccount \
                            --file-system $synapseFileSystem \
                            --sql-admin-login-user $synapseAdminName \
                            --sql-admin-login-password $synapseAdminPW \
                            --location $location

#### CREATE SYNAPSE SQL POOL ####
echo "CREATING SYNAPSE SQL POOL"
az synapse sql pool create  --resource-group $resourceGroupName \
                            --workspace-name $synapseWorkspaceName \
                            --name $synapseSQLPoolName \
                            --performance-level $synapsePerformanceLevel

# Allow web access to workspace workaround
identity=`az synapse workspace show --name $synapseWorkspaceName --resource-group $resourceGroupName --query "identity.principalId" -o tsv`
az role assignment create --role "Storage Blob Data Contributor" --assignee-object-id $identity --scope `az storage account show -g $resourceGroupName -n $synapseStorageAccount --query "id" -o tsv`
az synapse workspace firewall-rule create -g $resourceGroupName --workspace-name $synapseWorkspaceName --name allowAll --start-ip-address 0.0.0.0 --end-ip-address 255.255.255.255

#### MODIFY FIREWALL ####
echo "MODIFYING FIREWALL TO ALLOW ACCESS FROM THIS ENVIRONMENT ($ipaddress)"
az synapse workspace firewall-rule create --resource-group $resourceGroupName \
                                          --workspace-name $synapseWorkspaceName \
                                          --name azureCLI \
                                          --start-ip-address $ipaddress \
                                          --end-ip-address $ipaddress

#### CONNECT TO DB & CREATE SCHEMA & TABLES  #### --https://docs.microsoft.com/en-us/sql/tools/sqlcmd-utility?view=sql-server-ver15
echo "CONNECTING TO NEW SYNAPSE DB & CREATING SCHEMA AND TABLES"
sqlcmd -S $synapseWorkspaceName.sql.azuresynapse.net    -U $synapseAdminName \
                                                        -P $synapseAdminPW \
                                                        -I \
                                                        -d $synapseSQLPoolName \
                                                        -i $createScripts

#### PAUSE SQL POOL ####
az synapse sql pool pause --name $synapseSQLPoolName --resource-group $resourceGroupName --workspace-name $synapseWorkspaceName