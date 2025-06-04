setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
  source "$DIR/../lib/proxmox_lib.sh"

  # PATH="$DIR/../src:$PATH"
}

@test "can run proxmox_authenticate" {
  run proxmox_authenticate
  echo "$output" >&3
}

@test "can run proxmox_list_vm_names" {
  run proxmox_list_vm_names
  echo "$output" >&3
}

@test "can run proxmox_list_tpl_names" {
  run proxmox_list_tpl_names
  echo "$output" >&3
}

@test "can run proxmox_get_vmid" {
  run proxmox_get_vmid "vm-gitlabrunner"
  echo "$output" >&3
}
