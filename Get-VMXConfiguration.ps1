##########################################################################################
# Name: Get-VMXConfiguration.ps1
# Author: Adrian Begg (adrian.begg@ehloworld.com.au)
#
# Date: 16/07/2017
#
# Purpose: A quick script to take a list of virtual machines from a CSV and donwloads the VMX 
# file locally. Designed to quickly download from a CSV with a Header "GUID" and a list of VM
# names.
#
##########################################################################################
$colVMListCSV = Import-CSV "C:\_admin\VMList.csv"
[string] $strDestination = "C:\_admin\VMX"
[string] $srtvCenter = "labvc1.pigeonnuggets.com"

# Connect to vSphere
try{
	Connect-VIServer $srtvCenter
} catch {
	throw "Unable to connect with the provided credentials to vCenter. Exception: $_.Exception"
}

foreach($item in $colVMListCSV){
	$vm = get-vm "*$($item.GUID)*"
	[string] $vmxPath = $vm.extensiondata.config.files.vmpathname
	$Datastore = Get-Datastore ($vmxPath.Split("]")[0].Trim("["))
	[string] $vmxFile = $vmxPath.Split("]")[1].Trim(" ").Replace("/","\")
	[string] $vmStorePath = $Datastore.DatastoreBrowserPath + "\" + $vmxFile
	Copy-DatastoreItem $vmStorePath $strDestination
}
