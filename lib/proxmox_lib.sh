## [@bashly-upgrade github:yade-io/yade-bashly-libs;proxmox]

# Function to authenticate and extract ticket and CSRF token
# Inputs:
#   - Environment variables:
#       - PROXMOX_HOST: The Proxmox server hostname or IP.
#       - PROXMOX_USERNAME: The username for authentication.
#       - PROXMOX_PASSWORD: The password for authentication.
# Outputs:
#   - Prints a space-separated string containing:
#       - ticket: The authentication ticket.
#       - csrf_token: The CSRF prevention token.
function proxmox_authenticate() {
  local auth_response
  auth_response=$(curl -sk -X POST https://$PROXMOX_HOST:8006/api2/json/access/ticket \
    -d "username=$PROXMOX_USERNAME" -d "password=$PROXMOX_PASSWORD")

  echo "$(echo "$auth_response" | jq -r '.data.ticket') $(echo "$auth_response" | jq -r '.data.CSRFPreventionToken')"
}

# Function to fetch the list of VM names from the Proxmox server
# Inputs:
#   - Environment variables:
#       - PROXMOX_HOST: The Proxmox server hostname or IP.
#       - PROXMOX_API_USER: The API user for authentication.
#       - PROXMOX_API_TOKEN: The API token for authentication.
#       - PROXMOX_PVE_NAME: The Proxmox node name.
# Outputs:
#   - Prints the names of all template VMs (not regular VMs) to stdout, one per line.
#   - Note: This function currently prints only template VM names, not all VMs.
function proxmox_list_vm_names() {
  json_output=$(curl -s -k \
    -H "Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN}" \
    https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_PVE_NAME}/qemu)

  names=$(echo "$json_output" | jq -r '.data[] | select((.template // 0) == 0) | .name' | paste -sd' ')

  echo "$names"
}

# Function to fetch the list of template names from the Proxmox server
# Inputs:
#   - Environment variables:
#       - PROXMOX_HOST: The Proxmox server hostname or IP.
#       - PROXMOX_API_USER: The API user for authentication.
#       - PROXMOX_API_TOKEN: The API token for authentication.
#       - PROXMOX_PVE_NAME: The Proxmox node name.
# Outputs:
#   - Populates the TPL_NAMES array with the names of all template VMs.
function proxmox_list_tpl_names() {
  json_output=$(curl -s -k \
    -H "Authorization: PVEAPIToken=${PROXMOX_API_USER}=${PROXMOX_API_TOKEN}" \
    https://${PROXMOX_HOST}:8006/api2/json/nodes/${PROXMOX_PVE_NAME}/qemu)

  names=$(echo "$json_output" | jq -r '.data[] | select(.template == 1) | .name' | paste -sd' ')

  echo "$names"
}

# Function to prompt the user to select a VM from the list of available VMs
# Inputs:
#   - Calls proxmox_list_vm_names to populate the list of VMs.
#   - Uses the gum CLI tool for interactive selection.
# Outputs:
#   - Prints the selected VM name.
function proxmox_select_vm() {
  names=$(proxmox_list_vm_names)

  read -a arr <<< "$names"

  name=$(gum choose --header "Please select the vm." "${arr[@]}")

  echo "$name"
}

function proxmox_select_tpl() {
  names=$(proxmox_list_tpl_names)

  read -a arr <<< "$names"

  name=$(gum choose --header "Please select the vm." "${arr[@]}")

  echo "$name"
}

# Function to retrieve the VM ID (vmid) for a given VM name
# Inputs:
#   - vm_name: The name of the VM to look up.
# Outputs:
#   - Prints the vmid of the specified VM.
function proxmox_get_vmid() {
  local vm_name="$1"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  curl -sk -b "PVEAuthCookie=$ticket" https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_PVE_NAME/qemu \
    | jq -r --arg name "$vm_name" '.data[] | select(.name == $name) | .vmid'
}

function proxmox_clone_vm() {
  local src_vm_name="$1"
  local dest_vm_name="$2"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  # Get the source VM ID
  local src_vmid
  src_vmid=$(proxmox_get_vmid "$src_vm_name")

  nextid=$(curl -sk -b "PVEAuthCookie=$ticket" "https://$PROXMOX_HOST:8006/api2/json/cluster/nextid" | jq -r .data)

  # Clone the VM
  curl -sk -X POST https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_PVE_NAME/qemu/$src_vmid/clone \
    -H "CSRFPreventionToken: $csrf_token" \
    -b "PVEAuthCookie=$ticket" \
    -d "newid=$nextid" \
    -d "name=$dest_vm_name" \
    -d "full=1"
}

function proxmox_update_cloudinit() {
  local vmid="$1"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  local ciuser="ubuntu"
  local cipassword="ubuntu"
  local ipconfig0="ip=dhcp"
  local sshkeyfile="/Users/seba/projects/homelab-yade/src/sflab-packer/keys/build_id_ecdsa.pub"

  scp -q -o IdentitiesOnly=yes "$sshkeyfile" root@$PROXMOX_HOST:/root/id_ecdsa.pub.put

  ssh -o IdentitiesOnly=yes root@$PROXMOX_HOST "
    qm set $vmid --ciuser ubuntu --cipassword ubuntu --sshkey /root/id_ecdsa.pub.put --ipconfig0 ip=dhcp
  " >/dev/null 2>&1
}

# Starts a virtual machine (VM) on a Proxmox server.
# 
# Usage:
#   proxmox_start_vm <vm_id>
#
# Arguments:
#   vm_id - The unique identifier of the VM to start.
#
# Description:
#   This function initiates the startup process for a specified VM
#   on the configured Proxmox server. It requires the VM ID as an argument.
#   Ensure that the user has the necessary permissions to start VMs on Proxmox.
#
# Returns:
#   0 if the VM was started successfully, non-zero on error.
function proxmox_start_vm() {
  local vmid="$1"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  curl -sk -X POST https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_PVE_NAME/qemu/$vmid/status/start \
    -H "CSRFPreventionToken: $csrf_token" \
    -b "PVEAuthCookie=$ticket"
}

# Function to stop a VM on the Proxmox server
# Inputs:
#   - vmid: The ID of the VM to stop.
# Outputs:
#   - Sends a POST request to the Proxmox API to stop the VM.
function proxmox_stop_vm() {
  local vmid="$1"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  curl -sk -X POST https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_PVE_NAME/qemu/$vmid/status/stop \
    -H "CSRFPreventionToken: $csrf_token" \
    -b "PVEAuthCookie=$ticket"
}
# Function to delete a VM on the Proxmox server
# Inputs:
#   - vmid: The ID of the VM to delete.
# Outputs:
#   - Sends a DELETE request to the Proxmox API to delete the VM.
#   - Note: This action is irreversible and will permanently delete the VM.
#   - Ensure that the VM is stopped before attempting to delete it.
#   - Use with caution.
function proxmox_delete_vm() {
  local vmid="$1"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  curl -sk -X DELETE https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_PVE_NAME/qemu/$vmid \
    -b "PVEAuthCookie=$ticket" -H "CSRFPreventionToken: $csrf_token"
}

# Function to connect to a VM via SSH using its IP address
# Inputs:
#   - vmid: The ID of the VM to connect to.
# Outputs:
#   - Retrieves the VM's IP address using the Proxmox API.
#   - Establishes an SSH connection to the VM.
function proxmox_connect_vm() {
  local vmid="$1"
  local ticket csrf_token
  read ticket csrf_token < <(proxmox_authenticate)

  ip_response=$(curl -sk -b "PVEAuthCookie=$ticket" \
    "https://$PROXMOX_HOST:8006/api2/json/nodes/$PROXMOX_PVE_NAME/qemu/$vmid/agent/network-get-interfaces")

  ipv4_address=$(echo "$ip_response" | jq -r '.data.result[] | select(.name == "ens18") | .["ip-addresses"][] | select(."ip-address-type" == "ipv4") | ."ip-address"')

  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i /Users/seba/projects/homelab-yade/src/sflab-packer/keys/build_id_ecdsa -o IdentitiesOnly=yes \
    "packer@${ipv4_address}"
}
