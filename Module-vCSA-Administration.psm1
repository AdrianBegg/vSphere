##########################################################################################
# Name: Module-vCSA-Administration.psm1
# Date: 13/05/2017 (v0.1)
# Author: Adrian Begg (adrian.begg@ehloworld.com.au)
# 
# Purpose: PowerShell modules to extend the PowerCLI for vCSA to expose
# additional methods for configuring the vCSA using PowerShell cmdlets
##########################################################################################
# Change Log
# v0.1 - 13/5/2017 - Created module after responding to a forum post about amending DNS
##########################################################################################

#region: Common-API-Methods
function Connect-VIServerREST(){
	<#
	.SYNOPSIS
	 This cmdlet establishes a connection to the REST API of a vCenter Server system

	.DESCRIPTION
	 This cmdlet establishes a connection to a vCenter Server system. The cmdlet starts a new session with a vCenter Server system using the specified parameters.

	.PARAMETER Server
	Specifies the IP address or the DNS name of the vSphere server to which you want to connect.

	.PARAMETER Port
	Specifies the port on the server you want to use for the connection.

	.PARAMETER Credentials
	Specifies a PSCredential object that contains credentials for authenticating with the server.
	#>
	Param(
		[Parameter(Mandatory=$True)] [string] $Server,
		[Parameter(Mandatory=$False)] [int] $Port=443,
		[Parameter(Mandatory=$False)] [PSCredential] $Credentials = $Host.ui.PromptForCredential("Enter credentials for $Server", "Please enter your user name and password for the vSphere SSO Service in the same format as you use to conenct to vSphere.", "", "")
	)	
	[string] $authToken = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Credentials.UserName+':'+$Credentials.GetNetworkCredential().Password))
	$URIHeaders = @{
		'Authorization' = "Basic $authToken"
		'Accept' = "application/json"
		'vmware-use-header-authn' = "serenitynow"
		'Content-Type' = "application/json"
	}
	[string] $SessionURI = "https://" + $Server + ":" + $Port + "/rest/com/vmware/cis/session"
	try{
		$WebRequest = Invoke-WebRequest -Uri $SessionURI -Method Post -Headers $URIHeaders
			# Now set a Global Variable with the session state for use by other methods
		$objVIServer = New-Object System.Management.Automation.PSObject
		$objVIServer | Add-Member Note* Name $Server
		$objVIServer | Add-Member Note* ServiceURI ("https://" + $Server + ":" + $Port + "/rest")
		$objVIServer | Add-Member Note* Port $Port
		$objVIServer | Add-Member Note* User $Credentials.UserName
		$objVIServer | Add-Member Note* SessionSecret (ConvertFrom-Json $WebRequest.Content).value
		Set-Variable -Name "DefaultVIServerREST" -Value $objVIServer -Scope Global
	} catch {
		throw "An error occured connecting to $SessionURI with the provided credentials. Please check the Server Name, Port and Credentials"
	}
}

function Get-vSphereRESTResponseJSON(){
	<#
	.SYNOPSIS
	 This cmdlet performs a HTTP GET against the provided URI and returns the JSON Response

	.DESCRIPTION
	 This cmdlet performs a HTTP GET against the provided URI and returns the JSON Response

	.PARAMETER URI
	The URI to make the API GET Request against
	#>
	Param(
		[Parameter(Mandatory=$True)] [string] $URI
	)
	$URIHeaders = @{
		'vmware-api-session-id' = $Global:DefaultVIServerREST.SessionSecret
		'Accept' = "application/json"
		'Content-Type' = "application/json"
	}
	try{
		$Request = Invoke-WebRequest -Uri $URI -Method Get -Headers $URIHeaders
		(ConvertFrom-Json $Request.Content).value
	} catch {
		throw "An error occured attempting to make HTTP GET against $URI"
	}	
}

function Update-vSphereRESTDataJSON(){
	<#
	.SYNOPSIS
	 This cmdlet performs a HTTP PUT against the provided URI and returns the JSON Response

	.DESCRIPTION
	 This cmdlet performs a HTTP PUT against the provided URI and returns the JSON Response

	.PARAMETER URI
	The URI to make the API POST Request against
	#>
	Param(
		[Parameter(Mandatory=$True)] [string] $URI,
		[Parameter(Mandatory=$True)] [string] $Data
	)
	$URIHeaders = @{
		'vmware-api-session-id' = $Global:DefaultVIServerREST.SessionSecret
		'Accept' = "application/json"
		'Content-Type' = "application/json"
	}
	$Request = Invoke-WebRequest -Uri $URI -Method Put -Headers $URIHeaders -Body $Data
}

function Publish-vSphereRESTDataJSON(){
	<#
	.SYNOPSIS
	 This cmdlet performs a HTTP POST against the provided URI and returns the JSON Response

	.DESCRIPTION
	 This cmdlet performs a HTTP POST against the provided URI and returns the JSON Response

	.PARAMETER URI
	The URI to make the API POST Request against
	#>
	Param(
		[Parameter(Mandatory=$True)] [string] $URI,
		[Parameter(Mandatory=$True)] [string] $Data
	)
	$URIHeaders = @{
		'vmware-api-session-id' = $Global:DefaultVIServerREST.SessionSecret
	}
	$Request = Invoke-WebRequest -Uri $URI -Method Post -Headers $URIHeaders -Body $Data -ContentType "application/json"
}
#endregion

#region: Appliance-networkConfiguration
function Get-VCSANetworkConfigDNS(){
	<#
	.SYNOPSIS
	Returns the currently set DNS Servers on the vCenter Server Appliance

	.DESCRIPTION
	Returns the currently set DNS Servers on the vCenter Server Appliance. Returns an object containing the current DNS server configuration

	.PARAMETER Server
	The VCSA Server to query
	
	.NOTES
	  NAME: Get-VCSANetworkConfigDNS
	  AUTHOR: Adrian Begg
	  LASTEDIT: 2017-05-13
	  KEYWORDS: vmware vcsa
	  #Requires -Version 2.0
	#>
	# Check if there is a current connection to the REST API
	if(!(Test-Path variable:global:DefaultVIServerREST)){
		throw "You are not currently connected to the REST API for vSphere; please first connect using the Connect-VIServerREST cmdlet"
	}
	# Query the API for DNS information
	$DNSServerConfig = Get-vSphereRESTResponseJSON -URI ($global:DefaultVIServerREST.ServiceURI + "/appliance/networking/dns/servers")
	$DNSHostName = Get-vSphereRESTResponseJSON -URI ($global:DefaultVIServerREST.ServiceURI + "/appliance/networking/dns/hostname")
	$DNSDomains = Get-vSphereRESTResponseJSON -URI ($global:DefaultVIServerREST.ServiceURI + "/appliance/networking/dns/domains")
	
	# Create a new object to return to the caller
	$objNetDNS = New-Object System.Management.Automation.PSObject
	$objNetDNS | Add-Member Note* Hostname $DNSHostName
	$objNetDNS | Add-Member Note* DHCP ($DNSServerConfig.mode -eq "dhcp")
	$objNetDNS | Add-Member Note* Servers ($DNSServerConfig.servers)
	$objNetDNS | Add-Member Note* Domains $DNSDomains
	$objNetDNS
}

# NOTE: This throws "Host name is used as a network identity, the set operation is not allowed." 
# Further testing as I think this relates to the PCS on the device
function Set-VCSANetworkConfigDNSHostname(){
	<#
	.SYNOPSIS
	Sets the DNS Hostname for the vCenter Server Appliance to the provided string

	.DESCRIPTION
	Sets the DNS Hostname for the vCenter Server Appliance to the provided string

	.PARAMETER HostName
	The hostname to set the VCSA Server
	
	.NOTES
	  NAME: Set-VCSANetworkConfigDNSHostname
	  AUTHOR: Adrian Begg
	  LASTEDIT: 2017-05-13
	  KEYWORDS: vmware vcsa
	  #Requires -Version 2.0
	#>
	Param(
		[Parameter(Mandatory=$True)] [string] $HostName
	)
	if(!(Test-Path variable:global:DefaultVIServerREST)){
		throw "You are not currently connected to the REST API for vSphere; please first connect using the Connect-VIServerREST cmdlet"
	}
	# TO DO: Input checking for valid host name etc.
	# Cast the value to an object for conversion to JSON
	$objNetDNS = New-Object System.Management.Automation.PSObject
	$objNetDNS | Add-Member Note* name $HostName
	$objJSONData = ConvertTo-Json -InputObject $objNetDNS
	# Perform the update
	Update-vSphereRESTDataJSON -URI ($global:DefaultVIServerREST.ServiceURI + "/appliance/networking/dns/hostname") -Data $objJSONData
}

function Set-VCSANetworkConfigDNS(){
	<#
	.SYNOPSIS
	Sets the DNS Configuration for the vCenter Server Appliance

	.DESCRIPTION
	Sets the DNS Configuration (overwrites) for the currently connected vCenter Server Apppliance. If the UseDHCP flag is set the configured static values are removed and a DHCP refersh is forced. Otherwise if Servers are provided they will be statically set as provided. This camdlet can also set the DNS Search domains.

	.PARAMETER UseDHCP
	If set to True enables DHCP for DNS and will perform a renewal

	.PARAMETER Servers
	A collection of DNS servers to set statically, NOTE: Only the first two servers will be visable in the GUI however as many as required can be set
	
	.PARAMETER Domains
	A collection of DNS serach domains to configure
	
	.NOTES
	  NAME: Set-VCSANetworkConfigDNSHostname
	  AUTHOR: Adrian Begg
	  LASTEDIT: 2017-05-13
	  KEYWORDS: vmware vcsa
	  #Requires -Version 2.0
	#>
	Param(
		[Parameter(Mandatory=$False)] [bool] $UseDHCP = $false,
		[Parameter(Mandatory=$False)] [string[]] $Servers,
		[Parameter(Mandatory=$False)] [string[]] $Domains
	)
	if(!(Test-Path variable:global:DefaultVIServerREST)){
		throw "You are not currently connected to the REST API for vSphere; please first connect using the Connect-VIServerREST cmdlet"
	}
	if(!$UseDHCP -and ([string]::IsNullOrEmpty($Servers))){
		throw "If DHCP is not being used, you must specify at least one DNS server."
	}
	# Check if DHCP has been provided and if it is already enabled
	$currentConfiguration = Get-VCSANetworkConfigDNS
	# An object for DNS configuration
	$objNetDNS = New-Object System.Management.Automation.PSObject
	if($UseDHCP){
		if(!$currentConfiguration.DHCP){
			$objNetDNS | Add-Member Note* mode "dhcp"
			$objNetDNS | Add-Member Note* servers (New-object System.Collections.Arraylist) # Have I mentioned I really like the ArrayList object, must add an empty [] in order for the JSON to have the correct structure
		}
	} else {
		$objNetDNS | Add-Member Note* mode "is_static"
		$objNetDNS | Add-Member Note* servers $Servers
	}
	# Add the new configuration to an object for nesting in JSON
	$objNetConfig = New-Object System.Management.Automation.PSObject
	$objNetConfig | Add-Member Note* "config" $objNetDNS
	$objJSONData = ConvertTo-Json -InputObject $objNetConfig
	# Set DHCP on the VCSA
	Update-vSphereRESTDataJSON -URI ($global:DefaultVIServerREST.ServiceURI + "/appliance/networking/dns/servers") -Data $objJSONData
	
	# Next check the DNS Search domains and if not present set the search domain
	if($Domains -ne $null){
		$objNetDomains = New-Object System.Management.Automation.PSObject
		$objNetDomains | Add-Member Note* domains $Domains
		$objJSONData = ConvertTo-Json -InputObject $objNetDomains
		Update-vSphereRESTDataJSON -URI ($global:DefaultVIServerREST.ServiceURI + "/appliance/networking/dns/domains") -Data $objJSONData
	}
}
#endregion
