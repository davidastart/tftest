//Ashburn C4U02 ADB 23ai FREE

variable "ociTenancyOcid" { default = ""}
variable "ociUserOcid" {default = ""}
variable "ociCompartmentOcid" {default = ""}
variable "ociUserPassword" {default = ""}
variable "ociRegionIdentifier" { default = ""}
variable "resId" { default = ""}
variable "ociPrivateSubnetOcid" {default = ""}
variable "ociPublicSubnetOcid" {default = ""}
variable "ociVcnOcid" {default = ""}

// terraform version and providers
terraform {
  required_version = ">= 0.12.0"
  required_providers {
    oci = {
      source = "oracle/oci"
      version = "6.10.0"
    }
  }
}

provider "oci" {
  region           =  var.ociRegionIdentifier
}

#*****************************************
#             Random Password
#*****************************************
resource "random_string" "password" {
  length  = 16
  special = true
  min_special = 2
  min_numeric = 2
  override_special = "#"
}

#*************************************
#           Source ATP
#*************************************

resource  oci_database_autonomous_database source_autonomous_database  {
  #Required
  admin_password = random_string.password.result
  compartment_id =  var.ociCompartmentOcid
  compute_model = "ECPU"
  compute_count = 2
  data_storage_size_in_tbs = 1
  db_name   = "ATP${var.resId}"
  db_version = "23ai"
  display_name   = "AIATP${var.resId}"
  license_model = "BRING_YOUR_OWN_LICENSE"
  db_workload = "OLTP"
  is_free_tier = false
}

data "oci_database_autonomous_database" "source_autonomous_database" {
    #Required
    autonomous_database_id = oci_database_autonomous_database.source_autonomous_database.id
}

resource "oci_database_autonomous_database_wallet" "source_autonomous_database_wallet" {
    #Required
    autonomous_database_id = oci_database_autonomous_database.source_autonomous_database.id
    password = random_string.password.result

    #Optional
    base64_encode_content = "true"
    generate_type = "SINGLE"
}

resource "local_file" "source_autonomous_database_wallet_file" {
  content_base64 = oci_database_autonomous_database_wallet.source_autonomous_database_wallet.content
  filename       = "atp_wallet.zip"
}

resource "null_resource" "sqlcl-load-data-atp" {
    provisioner "local-exec" {
        command = "sql -cloudconfig atp_wallet.zip admin/${random_string.password.result}@ATP${var.resId}_high @./db_scripts/CREATE_USERS.sql"
    }
    depends_on = [
        local_file.source_autonomous_database_wallet_file
	]
	provisioner "local-exec" {
        command = "sql -cloudconfig atp_wallet.zip admin/${random_string.password.result}@ATP${var.resId}_high @./db_scripts/LOAD_DATA.sql"
    }
}

#*************************************
#         Outputs Displayed
#*************************************
output "atp_admin_password" {
  value = [ random_string.password.result ]
}
output "atp_name" {
  value =    [  "ATP${var.resId}" ]
}
