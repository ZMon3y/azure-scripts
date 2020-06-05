#!/bin/bash

## Author:          Matt Szafir
## Description:     This script is inteded to be used to shut down resources at the end of the day to save costs while developing in Azure
#                   Currently only doing VMs and Synapse SQL Pools
## Requirements:    bash >= 4
#                   az cli version?
#                   az login already run

## TODO:            add logging & perhaps integrate with a morning script
#                   add tagging functionality - where every resource w/ a tag could be shut down
#                   add script flags & help
#                   check if already paused / shut down (VM:  "powerState": "VM deallocated")
#                   add more resource types
#                   use "&" for commands so they run in parallel


#### ENABLE SYNAPSE EXTENSION ####
printf '%s\n' "ENABLING SYNAPSE EXTENSION"
az extension add --name synapse


#### CONFIGURE RESOURCE GROUP ####
mapfile -t resourceGroupsArray < <( az group list --query "[].name" -o tsv )
j=1
for i in ${resourceGroupsArray[@]}; do
    printf '%s\n' "${j}: ${i}"
    j=$((j+1)) 
done
printf '%s\n' "Select Resource Group: [1 - ${#resourceGroupsArray[@]}]" &&
read rgNum
resourceGroup=${resourceGroupsArray[${rgNum}-1]}

printf '%s\n' "Configuring default resource group to "${resourceGroup}
az configure --defaults group=${resourceGroup}


#### VMs ####
cmd="az vm list --query [].name -o tsv"

mapfile -t VMArray < <( ${cmd} )
VMStopCommandsArray=()
for i in ${VMArray[@]}; do
    VMStopCommandsArray+=("az vm stop --name "${i})
done


#### SYNAPSE POOLS ####
# Get workspaces
cmd="az synapse workspace list -o tsv --query [].name"
mapfile -t SynapseWorkspaceArray < <( ${cmd} )

# Loop through workspaces and build array of SQL Pools
SynapsePauseCommandsArray=()
SynapseSQLPoolArray=()
for i in ${SynapseWorkspaceArray[@]}; do
    cmd="az synapse sql pool list --query [].name -o tsv --resource-group "${resourceGroup}" --workspace-name "${i}
    mapfile -t SynapseSQLPoolTempArray < <( ${cmd} )
    for j in ${SynapseSQLPoolTempArray[@]}; do
        SynapsePauseCommandsArray+=("az synapse sql pool pause --name "${j}" --workspace-name "${i})
    done
    SynapseSQLPoolArray=("${SynapseSQLPoolArray[@]}" "${SynapseSQLPoolTempArray[@]}")
done


#### ASK USER WHICH RESOURCES TO SHUT DOWN ####
# combine arrays
allResourceArray=("${SynapseSQLPoolArray[@]}" "${VMArray[@]}")
allDeleteCommandsArray=("${SynapsePauseCommandsArray[@]}" "${VMStopCommandsArray[@]}")

j=1
for i in ${allResourceArray[@]}; do
    printf '%s\n' "${j}: ${i}"
    j=$((j+1)) 
done
if [ ${#allResourceArray[@]} -ne 0 ]; then
    printf '%s\n' "Select the numbers cooresponding to resources above to shut down in comma separated list:" &&
    read csvnums
else 
    printf '%s\n' "No Resources to shut down in "${resourceGroup}". Exiting"
    return
fi

# Display pause commands for user
printf '%s\n' "About to run the following commands:"
for ((i=0; i< ${#allDeleteCommandsArray[@]}; i++))
do
    if [[ $csvnums == *$(( ${i}+1 ))* ]]; then
        printf '%s\n' "${allDeleteCommandsArray[$i]}"
        if [[ ${allDeleteCommandsArray[$i]} == *"az vm stop"* ]]; then
            printf '%s\n' "az vm deallocate --no-wait "${allDeleteCommandsArray[$i]:11:1000} # :1000 -> This is lazy
        fi
    fi
done
printf '%s\n' "Continue? (Y/N)" && 
read cont
if [ ${cont} == "Y" ] 
then
    for ((i=0; i< ${#allDeleteCommandsArray[@]}; i++))
    do
        if [[ ${csvnums} == *$(( ${i}+1 ))* ]]; then
            printf '%s\n' "Running ${allDeleteCommandsArray[${i}]}"
            # Run the command
            ( ${allDeleteCommandsArray[${i}]} )
            # If we are stopping a VM we should also deallocate it
            if [[ ${allDeleteCommandsArray[${i}]} == *"az vm stop"* ]]; then
                printf '%s\n' "Running az vm deallocate --no-wait ${allDeleteCommandsArray[${i}]:11:1000}" # :1000 -> This is lazy
                ( az vm deallocate ${allDeleteCommandsArray[${i}]:11:1000} ) # :1000 -> This is lazy
            fi
        fi
    done
    printf '%s\n' "Done!"
    return
else printf '%s\n' "Exiting"
fi
return