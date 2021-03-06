#requires -version 3

Function Test-ConnectionAsync{    
    <#
    .Synopsis
       Proxy function for Test-Connection that pings multiple hosts at a time.
    .DESCRIPTION
       Proxy function for Test-Connection that pings multiple hosts at a time, using the -AsJob parameter of Test-Connection.  The Test-Connection cmdlet performs these jobs in multiple threads of a single process, unlike Start-Job.
    .PARAMETER MaxConcurrent
       Specifies the maximum number of Test-Connection commands to run at a time.
    .EXAMPLE
       Get-Content .\IPAddresses.txt | Test-ConnectionAsync -MaxConcurrent 250 -Quiet

       Pings the devices listed in the IPAddresses.txt file, up to 250 at a time.
    .INPUTS
       Either an array of strings, or of objects containing a property named one of:
       ComputerName, CN, IPAddress, __SERVER, Server, or Destination.
    .OUTPUTS
       If the -Quiet parameter is not specified, the function outputs a collection of Win32_PingStatus objects, one for each ping result.
   
       If the -Quiet parameter is specified, the function outputs a collection of PSCustomObjects containing the properties "ComputerName" (a string with the address that was pinged) and "Success" (a boolean value indicating whether the computer responded to at least one ping successfully).
    .NOTES
       If found, this function makes use of Get-CallerPreference from http://gallery.technet.microsoft.com/Inherit-Preference-82343b9d .  This can be useful if you want to place Test-ConnectionAsync in a Script Module (psm1 file), and have it behave according to the caller's settings for variables like $ErrorActionPreference.
       Other than the MaxConcurrent and Quiet parameters, all other parameters behave identically to the Test-Connection cmdlet; refer to its help file for more details.
       Unlike Test-Connection, Test-ConnectionAsync does not have an AsJob parameter.
    .LINK
       Test-Connection
    #>
    
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [System.Management.AuthenticationLevel]
        ${Authentication},

        [Alias('Size','Bytes','BS')]
        [ValidateRange(0, 65500)]
        [System.Int32]
        ${BufferSize},

        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('CN','IPAddress','__SERVER','Server','Destination')]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        ${ComputerName},

        [ValidateRange(1, 4294967295)]
        [System.Int32]
        ${Count},

        [Parameter(ParameterSetName='Source')]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]
        ${Credential},

        [Parameter(ParameterSetName='Source', Mandatory=$true, Position=1)]
        [Alias('FCN','SRC')]
        [ValidateNotNullOrEmpty()]
        [System.String[]]
        ${Source},

        [System.Management.ImpersonationLevel]
        ${Impersonation},

        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='Source')]
        [ValidateRange(-2147483648, 1000)]
        [System.Int32]
        ${ThrottleLimit},

        [Alias('TTL')]
        [ValidateRange(1, 255)]
        [System.Int32]
        ${TimeToLive},

        [ValidateRange(1, 60)]
        [System.Int32]
        ${Delay},

        [ValidateScript({$_ -ge 1})]
        [System.UInt32]
        $MaxConcurrent = 20,

        [Parameter(ParameterSetName='Quiet')]
        [Switch]
        $Quiet
    )

    begin
    {
        if ($null -ne ${function:Get-CallerPreference})
        {
            Get-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        }

        $null = $PSBoundParameters.Remove('MaxConcurrent')
        $null = $PSBoundParameters.Remove('Quiet')
        
        $jobs = @{}
        $i = -1

        function ProcessCompletedJob
        {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [hashtable]
                $Jobs,

                [Parameter(Mandatory = $true)]
                [int]
                $Index,

                [switch]
                $Quiet
            )

            $quietStatus = New-Object psobject -Property @{ComputerName = $Jobs[$Index].Target; Success = $false}
                    
            if ($Jobs[$Index].Job.HasMoreData)
            {
                foreach ($ping in (Receive-Job $Jobs[$Index].Job))
                {
                    if ($Quiet)
                    {
                        $quietStatus.ComputerName = $ping.Address
                        if ($ping.StatusCode -eq 0)
                        {
                            $quietStatus.Success = $true
                            break
                        }
                    }
                            
                    else
                    {
                        Write-Output $ping
                    }
                }
            }

            if ($Quiet)
            {
                Write-Output $quietStatus
            }

            Remove-Job -Job $Jobs[$Index].Job -Force
            $Jobs[$Index] = $null

        } # function ProcessCompletedJob

    } # begin

    process
    {
        $null = $PSBoundParameters.Remove('ComputerName')

        foreach ($target in $ComputerName)
        {
            while ($true)
            {
                if (++$i -eq $MaxConcurrent)
                {
                    Start-Sleep -Milliseconds 100
                    $i = 0
                }

                if ($null -ne $jobs[$i] -and $jobs[$i].Job.JobStateInfo.State -ne [System.Management.Automation.JobState]::Running)
                {
                    ProcessCompletedJob -Jobs $jobs -Index $i -Quiet:$Quiet
                }

                if ($null -eq $jobs[$i])
                {
                    Write-Verbose "Job ${i}: Pinging ${target}."

                    $job = Test-Connection -ComputerName $target -AsJob @PSBoundParameters
                    $jobs[$i] = New-Object psobject -Property @{Target = $target; Job = $job}

                    break
                }
            }
        }
    }

    end
    {
        while ($true)
        {
            $foundActive = $false

            for ($i = 0; $i -lt $MaxConcurrent; $i++)
            {
                if ($null -ne $jobs[$i])
                {
                    if ($jobs[$i].Job.JobStateInfo.State -ne [System.Management.Automation.JobState]::Running)
                    {
                        ProcessCompletedJob -Jobs $jobs -Index $i -Quiet:$Quiet
                    }                    
                    else
                    {
                        $foundActive = $true
                    }
                }
            }

            if (-not $foundActive)
            {
                break
            }

            Start-Sleep -Milliseconds 100
        }
    }

}

Function Get-CAServers{
    <#
        .SYNOPSIS 
         Displays a list of online Cloud Archive servers.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server.
    
        .EXAMPLE
         Get-CAServers
         This command finds all online Cloud Archive servers in the default data center.

        .EXAMPLE
         Get-CAServers -Datacenter "ELS02CA"
         This command finds all servers Cloud Archive servers in the specified data center. 
         You must use the proper format. The data center is represented by the first 7
         characters of the computer name.
        
        .EXAMPLE
         Get-CAServers -Filter "SRC"
         This command finds all online Cloud Archive servers with SRC in their name.
    #>
    
    [CmdletBinding()]

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$Filter = ""
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #*********************************************************
        #Determine Data Center
        #********************************************************* 

        $MyDC = $Datacenter

        #*********************************************************
        #Specify Server Filter (OPTIONAL)
        #********************************************************* 

        $DestServers = $Filter
        
        #*********************************************************
        #Load Servers
        #********************************************************* 

        #Query Active Directory
        $root=New-Object System.DirectoryServices.DirectoryEntry
        $rootSearch=New-Object System.DirectoryServices.DirectorySearcher
        $rootSearch.SearchRoot = $root
        $rootSearch.PageSize = 10000
        $rootSearch.Filter = ("(objectCategory=computer)")
        $Servers=@()
        $propList="name"
        
        ForEach ($prop in $propList) {
	        $rootSearch.PropertiesToLoad.Add($prop) | Out-Null
        }

        #Execute Active Directory Query
        $results=$rootSearch.FindAll()
        
        #Parse results
        ForEach ($Result in $Results){
            #Return properties
	        $Computer = $Result.Properties
    	    [string]$Name = $Computer.name
    		
            #Filter out servers that we don't need
	        If ($Name -match "$MyDc" -and $Name -match "$DestServers" -and $Name -notmatch "SQL|PROCESS|ARCHIVE|REPORT|QUEUE|COLLECT|ATDB|RDP|TEMP|QA|DC|NTP|VRD|PUP|VQF|REPO|FILE|MTWEB"){
	 	        #Add servers that match the filter above to the array
                $Servers+=$Name
   	        }
        
        }
        
    }

    PROCESS{
        #Initialize array to hold list of servers that are online
        $UpServers = @()
        
        #Check each server that was returned from AD to see if it is online
        # $UpServers = $Servers | Test-ConnectionAsync -Count 2 -Quiet | Where-Object {$_.Success -eq $True} | Select-Object -ExpandProperty ComputerName
		$UpServers = $Servers

        #Sort Array
        If($UpServers){
            [Array]::Sort([array]$UpServers)
        }Else{
            #If no servers are found, notify user
            Write-Verbose "No servers found online."
        }
    }

    END{
        #Return list of servers that are online
        Return $UpServers
    }

}

Function Get-CAServicesList{
    <#
        .SYNOPSIS 
         Displays a list of online Cloud Archive servers and service status.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server.
    
        .EXAMPLE
         Get-CAServicesList
         This command finds the status of the services on all the Cloud Archive servers in the 
         default data center.

        .EXAMPLE
         Get-CAServicesList -Datacenter "ELS02CA"
         This command finds all servers Cloud Archive servers in the specified data center. 
         You must use the proper format. The data center is represented by the first 7
         characters of the computer name.
        
        .EXAMPLE
         Get-CAServicesList -Filter "SRC"
         This command queries all Cloud Archive servers with SRC in their name and retrieves 
         the services status.
    #>

    [CmdletBinding()]

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$Filter = ""
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #Get list of online Cloud Archive servers
        $UpServers = Get-CAServers -Filter $Filter -Datacenter $Datacenter

    }

    PROCESS{

        If($UpServers){
            #Clear any existing jobs
            Get-Job | Remove-Job | Out-Null

            #Initialize Failed Server Array
            $Failed = @()

            #Get all CA Services from all servers.  Filter out services that are set to Disabled.
            $CAServicesJobs = Invoke-Command -ScriptBlock {$Datacenter = $args[0];Get-WmiObject -Class Win32_Service -Property * | Where-Object {($_.StartName -match "loma|$Datacenter" -and $_.StartMode -notmatch "Disabled") -or ($_.Name -match "MsDepSvc" -and $_.StartMode -notmatch "Disabled")}} -ComputerName $UpServers -ArgumentList $Datacenter -AsJob

            Write-Verbose "Waiting for CAServicesList Jobs to finish"
            # Wait-Job $CAServicesJobs -Timeout 300 | Out-Null
			Wait-Job $CAServicesJobs | Out-Null

            #Stop any unfinished jobs
            Stop-Job $CAServicesJobs | Out-Null

            Write-Verbose "Getting Job Results"
            $CAServices = Get-Job -IncludeChildJob | Where-Object{$_.ChildJobs.Count -eq 0 -and $_.State -eq "Completed"} | Receive-Job

            #Get failed jobs
            $Failed = Get-Job -IncludeChildJob | Where-Object{$_.ChildJobs.Count -eq 0 -and $_.State -ne "Completed"} | Select-Object -ExpandProperty Location

            #Output failed jobs
            $Failed | ForEach{Write-Warning "Unable to query $($_)"}

            #Remove Jobs
            Get-Job | Remove-Job | Out-Null

        }

    }

    END{
        #Return list of Cloud Archive servers and services
        Return $CAServices
    }

}

Function Get-CAWebsitesList{
    <#
        .SYNOPSIS 
         Displays a list of online Cloud Archive servers and website status.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server.
    
        .EXAMPLE
         Get-CAServicesList
         This command finds the websites on all the Cloud Archive servers in the default data
         center.

        .EXAMPLE
         Get-CAServicesList -Datacenter "ELS02CA"
         This command finds all servers Cloud Archive servers in the specified data center. 
         You must use the proper format. The data center is represented by the first 7
         characters of the computer name.
        
        .EXAMPLE
         Get-CAServicesList -Filter "SRC"
         This command queries all Cloud Archive servers with SRC in their name and retrieves 
         the services status.
    #>

    [CmdletBinding()]

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$Filter = ""
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #Get list of online Cloud Archive servers
        $UpServers = Get-CAServers -Filter $Filter -Datacenter $Datacenter

    }

    PROCESS{


        If($UpServers){
            #Clear any existing jobs
            Get-Job | Remove-Job | Out-Null

            #Initialize Failed Server Array
            $Failed = @()

            #Get all CA Websites from all servers.  Filter out services that are set to Disabled.
            $CAWebsitesJobs = Invoke-Command -ScriptBlock {Get-WmiObject -Namespace "root/microsoftiisv2" -Query 'select * from IIsWebVirtualDirSetting' -Authentication 6 -ErrorAction 0 | Where {$_.Path -match "LOMA" -and $_.AppFriendlyName -NotMatch "Default"}} -ComputerName $UpServers -AsJob

            Write-Verbose "Waiting for CAWebsitesList Jobs to finish"
            # Wait-Job $CAWebsitesJobs -Timeout 300 | Out-Null
			Wait-Job $CAWebsitesJobs | Out-Null

            #Stop any unfinished jobs
            Stop-Job $CAWebsitesJobs | Out-Null

            Write-Verbose "Getting Job Results"
            $CAWebsites = Get-Job -IncludeChildJob | Where-Object{$_.ChildJobs.Count -eq 0 -and $_.State -eq "Completed"} | Receive-Job

            #Get failed jobs
            $Failed = Get-Job -IncludeChildJob | Where-Object{$_.ChildJobs.Count -eq 0 -and $_.State -ne "Completed"} | Select-Object -ExpandProperty Location

            #Output failed jobs
            $Failed | ForEach{Write-Warning "Unable to query $($_)"}

            #Remove Jobs
            Get-Job | Remove-Job | Out-Null

            #Add a Website name property to the object derived from the path
            $CAWebsites | Add-Member -Name "Website" -Value {($this.Path).Replace("Z:\LOMA_Apps\","")} -MemberType ScriptProperty -PassThru
        }

    }

    END{
        #Return list of Cloud Archive servers and websites
        Return $CAWebsites
    }

}

Function Get-CAServices{
    <#
        .SYNOPSIS 
         Displays a list of online Cloud Archive servers and service status with the ability
         to use filters.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the service name search filter. Use if you want to look for specific type
         of services.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the service names that should be excluded from the search filter. Use if 
         you want to exclude specific types of services. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAServiceList | Export-Csv ".\Filename.txt".

        .EXAMPLE
         Get-CAServices
         This command queries all the Cloud Archive servers in the default data center and
         retrieves service status.

        .EXAMPLE
         Get-CAServices -Datacenter "ELS02CA" | Select-Object -Property PSComputerName, Name, 
         Status | Out-Gridview
         This command queries all servers Cloud Archive in the specified data center and outputs
         services status to a sortable view.
                
        .EXAMPLE
         Get-CAServices -Filter "SMTP" -Include "Mail" -Exclude "Parser|Transfer"
         This command queries all Cloud Archive servers with SMTP in their name and retrieves 
         the services status. This only includes services with the name Mail but excludes Parser
         and Transfer.

        .EXAMPLE
         Get-CAServices -FilePath ".\Server.txt"
         This command queries all Cloud Archive servers using a pre-exported server list.
    #>

    [CmdletBinding()]

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = ""
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        # Get Start Time
        $startDTM = (Get-Date)
        
        #Get list of servers and services from the function, unless a file path is specified
        If(!$FilePath){
            $ServicesList = Get-CAServicesList -Filter $Filter -Datacenter $Datacenter
        }Else{
            #Import CSV file that contains a list of servers
            $ServicesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #Depending on which filters are specified, filter the service list
        If($Include -and !$Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -match $Include -and $_.Name -notmatch $Exclude}
        }

        #Ensure there are no duplicate servers in the list
        $Servers = $ServicesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Initialize array
        $Results = @()
    }

    PROCESS{
        #Parse through each server in the array
        ForEach($Server In $Servers){
            #Get list of services on each server
            Write-Verbose "Getting services status on $($Server)..."
            $Services = $ServicesList | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Name 
            
            #Get services status from each server and run each query as a job
            Invoke-Command -ScriptBlock {Get-Service -Name $args} -ArgumentList $Services -ComputerName $Server -AsJob | Out-Null
            
        }

        #Wait for jobs to finish
        Write-Verbose "Waiting for jobs to finish..."
        Get-Job | Wait-Job | Out-Null

        #Get results from the jobs
        Write-Verbose "Gathering results..."
        $Results = Get-Job | Receive-Job

        #Clean up the jobs
        Write-Verbose "Cleaning up jobs..."
        Get-Job | Remove-Job | Out-Null
        
        #Return the list of servers and the status of each service
        Return $Results
    }

    END{

        # Get End Time
        $endDTM = (Get-Date)

        # Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Stop-CAServices{
    <#
        .SYNOPSIS 
         Stops multiple Cloud Archive services with the ability include or exclude specific
         services using filters.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the service name search filter. Use if you want to look for specific type
         of services.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the service names that should be excluded from the search filter. Use if 
         you want to exclude specific types of services. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAServiceList | Export-Csv ".\Filename.txt".

        .PARAMETER Timeout
         The number of seconds to wait for a service to stop.  After the time out elapses,
         the script continues.

        .PARAMETER Delay
         The number of seconds to wait after stopping normal services before continuing to
         stop priority services.  Priority services include all Manager services and Crypto
         service.

        .EXAMPLE
         Stop-CAServices -Verbose
         This stops all Cloud Archive services in the default data center with verbose output.

        .EXAMPLE
         Stop-CAServices -Datacenter "ELS02CA" -Include "LogCleanup" -Confirm:$false -Verbose
         This command stops LogCleanup services on Cloud Archive servers without confirmation
         and outputting detailed logging messages.
                
        .EXAMPLE
         Stop-CAServices -Datacenter "ELS02CA" -Timeout 900 -Include "Indexing" -Filter "RIDX"
         This command stops Indexing service on Cloud Archive Re-Indexing servers in their name
         with a timeout of 15 minutes before the script stops waiting for the service to stop.

        .EXAMPLE
         Stop-CAServices -Datacenter "ELS02CA" -Delay 30
         This command stops all Cloud Archive services with a delay of 30 seconds in between
         normal services and priority services.
    #>

    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High"
    )]    

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = "",
        [int]$Timeout = 60,
        [int]$Delay = 60
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }
        
        #Specify pattern of which services need special handling
        $PriorityServices = "Crypto|Manager"

        # Get Start Time
        $startDTM = (Get-Date)
        
        #Get list of servers and services from the function, unless a file path is specified
        If(!$FilePath){
            $ServicesList = Get-CAServicesList -Filter $Filter -Datacenter $Datacenter
        }Else{
            #Import CSV file that contains a list of servers
            $ServicesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #Depending on which filters are specified, filter the service list
        If($Include -and !$Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -match $Include -and $_.Name -notmatch $Exclude}
        }

        #Prioritize starting of services
        $ServicesListPriority = $ServicesList | Where-Object{$_.Name -match $PriorityServices} | Sort-Object
        $ServersPriority = $ServicesListPriority | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Ensure there are no duplicate servers in the list
        $Servers = $ServicesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Intialize array
        $Results = @()
    }

    PROCESS{
        #Stop non-priority services first
        If($Servers){
            
            ForEach($Server In $Servers){
                If($pscmdlet.ShouldProcess($Server)) {
                    #Get list of services to stop on each server
                    Write-Verbose "Stopping services on $($Server)..."
                    $Services = $ServicesList | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Name

                    #Stop Services on each server and submit request as jobs
                    #The command will wait for service to reach stopped status until the timeout value is reached, after which it will continue
                    Invoke-Command -ScriptBlock {(Get-Service -Name $args | Stop-Service -Force -PassThru).WaitForStatus("Stopped",[Timespan]::FromSeconds($Timeout));Get-Service -Name $args} -ArgumentList $Services -ComputerName $Server -AsJob | Out-Null
                }
            }
        
            #Wait for jobs to complete
            Write-Verbose "Waiting for services to stop"
            Get-Job | Wait-Job | Out-Null
        }
        
        #Stop priority services last
        If($ServersPriority){
            #Sleep for specified delay before stopping priority services
            Write-Verbose "Sleeping for $($Delay) seconds"
            Start-Sleep -Seconds $Delay

            ForEach($Server In $ServersPriority){
                If($pscmdlet.ShouldProcess($Server)) {
                    #Get list of priority services to stop on each server
                    Write-Verbose "Stopping priority services on $($Server)..."
                    $Services = $ServicesListPriority | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Name 

                    #Stop Services on each server and submit request as jobs
                    #The command will wait for service to reach stopped status until the timeout value is reached, after which it will continue
                    Invoke-Command -ScriptBlock {(Get-Service -Name $args | Stop-Service -Force -PassThru).WaitForStatus("Stopped",[Timespan]::FromSeconds($Timeout));Get-Service -Name $args} -ArgumentList $Services -ComputerName $Server -AsJob | Out-Null
           
                }
            }
            
            #Wait for jobs to complete
            Write-Verbose "Waiting for jobs to finish..."
            Get-Job | Wait-Job | Out-Null
        }

        #Get results from the jobs
        Write-Verbose "Gathering results..."
        $Results = Get-Job | Receive-Job

        #Clean up the jobs
        Write-Verbose "Cleaning up jobs..."
        Get-Job | Remove-Job | Out-Null
        
        #Return the list of servers and the status of each service
        Return $Results
        
    }

    END{
        # Get End Time
        $endDTM = (Get-Date)

        # Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Start-CAServices{
    <#
        .SYNOPSIS 
         Starts multiple Cloud Archive services with the ability include or exclude specific
         services using filters.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the service name search filter. Use if you want to look for specific type
         of services.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the service names that should be excluded from the search filter. Use if 
         you want to exclude specific types of services. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAServiceList | Export-Csv ".\Filename.txt".

        .PARAMETER Timeout
         The number of seconds to wait for a service to start.  After the time out elapses,
         the script continues.

        .PARAMETER Delay
         The number of seconds to wait after starting priority services before continuing to
         start normal services.  Priority services include all Manager services and Crypto
         service.

        .PARAMETER IncludeManual
         Include starting services that are set to manual.  By default, only services that
         are set to automatic are started.

        .EXAMPLE
         Start-CAServices -Verbose
         This starts all Cloud Archive services in the default data center with verbose output.

        .EXAMPLE
         Start-CAServices -Datacenter "ELS02CA" -Include "MailParser" -Verbose
         This command starts MailParser services on Cloud Archive servers without confirmation
         and outputting detailed logging messages.
                
        .EXAMPLE
         Start-CAServices -Datacenter "ELS02CA" -Timeout 60 -Include "Indexing" -Filter "RIDX"
         This command starts Indexing service on Cloud Archive Re-Indexing servers in their name
         with a timeout of 1 minute before the script stops waiting for the service to start.

        .EXAMPLE
         Start-CAServices -Datacenter "ELS02CA" -Delay 30
         This command starts all Cloud Archive services with a delay of 30 seconds in between
         priority services and normal services.

        .EXAMPLE
         Start-CAServices -Datacenter "ELS02CA" -Include "Search.Agent" -IncludeManual $true
         This will start Search.Agent services even though they are set to start as manual.
    #>

    [CmdletBinding()]

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = "",
        [int]$Timeout = 60,
        [int]$Delay = 60,
        [bool]$IncludeManual = $false
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }
        
        #Specify pattern of which services need special handling
        $PriorityServices = "Crypto|Manager"

        #Get Start Time
        $startDTM = (Get-Date)
        
        #Get list of servers and services from the function, unless a file path is specified
        If(!$FilePath){
            $ServicesList = Get-CAServicesList -Filter $Filter -Datacenter $Datacenter
        }Else{
        #Import CSV file that contains a list of servers
            $ServicesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #Filter out services that are set to Manual mode unless otherwise specified
        If(!$IncludeManual){
            $ServicesList = $ServicesList | Where-Object{$_.StartMode -notmatch "Manual"}
        }

        #Depending on which filters are specified, filter the service list
        If($Include -and !$Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $ServicesList = $ServicesList | Where-Object{$_.Name -match $Include -and $_.Name -notmatch $Exclude}
        }

        #Prioritize starting of services
        $ServicesListPriority = $ServicesList | Where-Object{$_.Name -match $PriorityServices} | Sort-Object

        #Ensure there are no duplicate servers in the list
        $ServersPriority = $ServicesListPriority | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Ensure there are no duplicate servers in the list
        $Servers = $ServicesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Initialize array
        $Results = @()
    }

    PROCESS{
        #Start priority services first
        If($ServersPriority){
            #Parse through each server in the array
            ForEach($Server In $ServersPriority){
                #Get list of services to start on each server
                Write-Verbose "Starting priority services on $($Server)..."
                $Services = $ServicesListPriority | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Name 

                #Start Services on each server and submit request as jobs
                #The command will wait for service to reach running status until the timeout value is reached, after which it will continue
                Invoke-Command -ScriptBlock {(Get-Service -Name $args | Start-Service -PassThru).WaitForStatus("Running",[Timespan]::FromSeconds($Timeout));Get-Service -Name $args} -ArgumentList $Services -ComputerName $Server | Out-Null
          
            }
        
            #Wait for jobs to complete
            Write-Verbose "Waiting for priority services to start"
            Get-Job | Wait-Job | Out-Null
        
            #Sleep for specified delay before starting priority services
            Write-Verbose "Sleeping for $($Delay) seconds"
            Start-Sleep -Seconds $Delay

        }

        #Start non-priority services last
        If($Servers){
            #Start Remaining Services
            ForEach($Server In $Servers){
                #Get list of services to start on each server
                Write-Verbose "Starting services on $($Server)..."
                $Services = $ServicesList | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Name 
            
                #Start Services on each server and submit request as jobs
                #The command will wait for service to reach running status until the timeout value is reached, after which it will continue
                Invoke-Command -ScriptBlock {(Get-Service -Name $args | Start-Service -PassThru).WaitForStatus("Running",[Timespan]::FromSeconds($Timeout));Get-Service -Name $args} -ArgumentList $Services -ComputerName $Server -AsJob | Out-Null
                        
            }
        
            #Wait for jobs to complete
            Write-Verbose "Waiting for jobs to finish..."
            Get-Job | Wait-Job | Out-Null

        }

        #Get results from the jobs
        Write-Verbose "Gathering results..."
        $Results = Get-Job | Receive-Job

        #Clean up the jobs
        Write-Verbose "Cleaning up jobs..."
        Get-Job | Remove-Job | Out-Null
        
        Return $Results
    }

    END{

        #Get End Time
        $endDTM = (Get-Date)

        #Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Get-CAWebsites{
    <#
        .SYNOPSIS 
         Displays a list of online Cloud Archive servers and websites status with the ability
         to use filters.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the website name search filter. Use if you want to look for specific type
         of websites.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the website names that should be excluded from the search filter. Use if 
         you want to exclude specific types of websites. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAWebsitesList | Export-Csv ".\Filename.txt".

        .EXAMPLE
         Get-CAWebsites | Format-Table -Autosize
         This command queries all the Cloud Archive servers in the default data center and
         retrieves website status.

        .EXAMPLE
         Get-CAWebsites -Filter "FS" -Include "API" | Format-Table -Autosize
         This command queries all Cloud Archive servers with FS in their name and retrieves 
         the website status with a name of API in the name. 

        .EXAMPLE
         Get-CAWebsites -FilePath ".\Server.txt"
         This command queries all Cloud Archive servers for website status using a pre-exported 
         server list.
    #>

    [CmdletBinding()]

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = ""
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #Get Start Time
        $startDTM = (Get-Date)
        
        #Get list of servers and services from the function, unless a file path is specified
        If(!$FilePath){
            $WebsitesList = Get-CAWebsitesList -Filter $Filter -Datacenter $Datacenter
        }Else{
            $WebsitesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #Depending on which filters are specified, filter the service list
        If($Include -and !$Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include -and $_.Website -notmatch $Exclude}
        }

        #Ensure there are no duplicate servers in the list
        $Servers = $WebsitesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Initialize array
        $Results = @()
    }

    PROCESS{
        #Parse through each server in the array
        ForEach($Server In $Servers){
            #Get unique list of websites on each server
            Write-Verbose "Getting website status on $($Server)..."
            $Websites = $WebsitesList | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Path -Unique
            
            #Check to see if maintenance pages are up and create an object out of the results
            #Kick off process on each server as jobs
            Invoke-Command -ScriptBlock {
                $Args | foreach { 
	                New-Object PSObject -Property @{
                        Server = hostname
                        Path = $_
                        Online = !(Test-Path -Path "$_\App_Offline.htm")
                        Website = $_.Replace("Z:\LOMA_Apps\","")
                    }
                }
            } -ArgumentList $Websites -ComputerName $Server -AsJob | Out-Null
        }

        #Wait for jobs to finish
        Write-Verbose "Waiting for jobs to finish..."
        Get-Job | Wait-Job | Out-Null

        #Get results from jobs
        Write-Verbose "Gathering results..."
        $Results = Get-Job | Receive-Job

        #Clean up jobs
        Write-Verbose "Cleaning up jobs..."
        Get-Job | Remove-Job | Out-Null
        
        #Return list of servers and websites
        Return $Results
    }

    END{
        #Get End Time
        $endDTM = (Get-Date)

        #Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Stop-CAWebsites{
    <#
        .SYNOPSIS 
         Stops multiple Cloud Archive websites with the ability include or exclude specific
         websites using filters.

        .PARAMETER MaintenancePage
         Specifies the location of the maintenance page that will be put up to stop the website.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the website name search filter. Use if you want to look for specific type
         of websites.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the website names that should be excluded from the search filter. Use if 
         you want to exclude specific types of websites. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAWebsitesList | Export-Csv ".\Filename.txt".

        .EXAMPLE
         Stop-CAWebsites -MaintenancePage ".\App_Offline.htm" -Verbose
         This stops all Cloud Archive services in the default data center with verbose output.

        .EXAMPLE
         Stop-CAWebsites -MaintenancePage ".\App_Offline.htm" -Confirm:False -Include "FS"
         This command puts up maintenance pages on all FolderSync websites.
    #>

    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High"
    )]    

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = "",
        [Parameter(Mandatory=$True)]
        [string]$MaintenancePage
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #Get Start Time
        $startDTM = (Get-Date)
        
        #Get list of servers and services from the function, unless a file path is specified
        If(!$FilePath){
            $WebsitesList = Get-CAWebsitesList -Filter $Filter -Datacenter $Datacenter
        }Else{
            $WebsitesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #Depending on which filters are specified, filter the service list
        If($Include -and !$Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include -and $_.Website -notmatch $Exclude}
        }

        #Ensure there are no duplicate servers in the list
        $Servers = $WebsitesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Intialize array
        $Results = @()
    }

    PROCESS{
        If($Servers){
            #Stop Websites
            ForEach($Server In $Servers){
                If($pscmdlet.ShouldProcess($Server)) {
                    Write-Verbose "Stopping websites on $($Server)..."
                    $Websites = $WebsitesList | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Path -Unique 

                    #Put up maintenance pages that are specified
                    Invoke-Command -ScriptBlock {($args[0] -Replace "Z:","\\$($args[1])") | ForEach{Copy-Item $MaintenancePage -Destination $_}} -ArgumentList $Websites, $Server

                    #Confirm if Maintenance Pages have been copied
                    #If maintenance page is found, then mark the website's online status as false
                    #Create an object for each result
                    Invoke-Command -ScriptBlock {
                        $Args | ForEach { 
	                        New-Object PSObject -Property @{
                                Server = hostname
                                Path = $_
                                Online = !(Test-Path -Path "$_\App_Offline.htm")
                                Website = $_.Replace("Z:\LOMA_Apps\","")
                            }
                        }
                    } -ArgumentList $Websites -ComputerName $Server -AsJob | Out-Null
                }
            }
        
            #Wait for jobs to finish
            Write-Verbose "Waiting for websites to stop"
            Get-Job | Wait-Job | Out-Null
        }

        #Gather results of jobs
        Write-Verbose "Gathering results..."
        $Results = Get-Job | Receive-Job

        #Clean up jobs
        Write-Verbose "Cleaning up jobs..."
        Get-Job | Remove-Job | Out-Null

        #Return list of servers and website status 
        Return $Results
    }

    END{
        #Get End Time
        $endDTM = (Get-Date)

        #Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Start-CAWebsites{
    <#
        .SYNOPSIS 
         Starts multiple Cloud Archive websites with the ability include or exclude specific
         websites using filters.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the website name search filter. Use if you want to look for specific type
         of websites.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the website names that should be excluded from the search filter. Use if 
         you want to exclude specific types of websites. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAWebsitesList | Export-Csv ".\Filename.txt".

        .EXAMPLE
         Start-CAWebsites -Verbose
         This starts all Cloud Archive services in the default data center with verbose output.

        .EXAMPLE
         Start-CAWebsites -Include "FS"
         This command removes maintenance pages from all FolderSync websites.
    #>

    [CmdletBinding()]
    
    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = ""
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #Get Start Time
        $startDTM = (Get-Date)
        
        #Get list of servers and services from the function, unless a file path is specified
        If(!$FilePath){
            $WebsitesList = Get-CAWebsitesList -Filter $Filter -Datacenter $Datacenter
        }Else{
            $WebsitesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #Depending on which filters are specified, filter the service list
        If($Include -and !$Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include -and $_.Website -notmatch $Exclude}
        }

        #Ensure there are no duplicate servers in the list
        $Servers = $WebsitesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        #Initialize array
        $Results = @()
    }

    PROCESS{
        If($Servers){
            #Start Websites
            ForEach($Server In $Servers){

                #Get unique list of websites on each server
                Write-Verbose "Starting websites on $($Server)..."
                $Websites = $WebsitesList | Where-Object { $_.PSComputerName -eq $Server} | Select-Object -ExpandProperty Path -Unique 

                #Remove Maintenance Pages
                Invoke-Command -ScriptBlock {($args[0] -Replace "Z:","\\$($args[1])") | ForEach{Remove-Item "$_\App_Offline.htm" -ErrorAction SilentlyContinue}} -ArgumentList $Websites, $Server

                #Confirm if Maintenance Pages have been removed
                #Create an object for each result
                Invoke-Command -ScriptBlock {
                    $Args | ForEach { 
	                    New-Object PSObject -Property @{
                            Server = hostname
                            Path = $_
                            Online = !(Test-Path -Path "$_\App_Offline.htm")
                            Website = $_.Replace("Z:\LOMA_Apps\","")
                        }
                    }
                } -ArgumentList $Websites -ComputerName $Server -AsJob | Out-Null
                
            }
        
            #Wait for jobs to finish
            Write-Verbose "Waiting for websites to start"
            Get-Job | Wait-Job | Out-Null
        }

        #Get job results
        Write-Verbose "Gathering results..."
        $Results = Get-Job | Receive-Job

        #Clean up jobs
        Write-Verbose "Cleaning up jobs..."
        Get-Job | Remove-Job | Out-Null

        #Return list of servers and website status
        Return $Results
    }

    END{
        #Get End Time
        $endDTM = (Get-Date)

        #Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Restart-CAWebsites{
    <#
        .SYNOPSIS 
         Restarts IIS on multiple Cloud Archive websites with the ability include or exclude 
         specific websites using filters.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER Filter
         Specifies the computer name search filter. Use if you want to look for specific type
         of server. Separate multiple patterns with the pipe character.

        .PARAMETER Include
         Specifies the website name search filter. Use if you want to look for specific type
         of websites.  Separate multiple patterns with the pipe character.

        .PARAMETER Exclude
         Specifies the website names that should be excluded from the search filter. Use if 
         you want to exclude specific types of websites. Separate multiple patterns with the 
         pipe character.

        .PARAMETER FilePath
         Specifies the file path of a pre-exported server list. Use if you want to speed up
         retrieving results without doing a live check of server status.  The list can be
         exported using Get-CAWebsitesList | Export-Csv ".\Filename.txt".

        .PARAMETER Delay
         A delay can be specified if a specific waiting time is required between the restart
         of multiple websites.

        .EXAMPLE
         Restart-CAWebsites -Verbose
         This starts all Cloud Archive services in the default data center with verbose output.

        .EXAMPLE
         Restart-CAWebsites -Include "FS"
         This command removes maintenance pages from all FolderSync websites.

        .EXAMPLE
         Restart-CAWebsites -Include "MANAGE|WS" -Delay 120
         This command restarts IIS on websites that have MN and WSWEB in their names with a
         delay of 120 seconds in between.  Important: Order of websites in the Include
         parameter may not be honored.

        .EXAMPLE
         Restart-CAWebsites -Include "PM" -Confirm:$false | Format-Table -Autosize
         This command restarts IIS on PM websites without confirmation and formats the results
         in a table format.
    #>

    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High"
    )]    

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$FilePath,
        [string]$Include,
        [string]$Exclude,
        [string]$Filter = "",
        [int]$Delay
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        # Get Start Time
        $startDTM = (Get-Date)
        
        #Use file path if specified, otherwise use default in same folder
        If(!$FilePath){
            $WebsitesList = Get-CAWebsitesList -Filter $Filter -Datacenter $Datacenter
        }Else{
            $WebsitesList = Import-Csv $FilePath | Where-Object {$_.PSComputerName -match $Filter}
        }

        #If a filter is specified, filter the service list
        If($Include -and !$Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include}
        }ElseIf(!$Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -notmatch $Exclude}
        }ElseIf($Include -and $Exclude){
            $WebsitesList = $WebsitesList | Where-Object{$_.Website -match $Include -and $_.Website -notmatch $Exclude}
        }

        #Get unique list of servers
        $Servers = $WebsitesList | ForEach-Object{$_.PSComputerName} | Sort-Object -Unique

        $Results = @()
    }

    PROCESS{
        If($Servers){
            #Restart Websites
            #Confirm if restarting should continue
            If($pscmdlet.ShouldProcess($Servers)) {
                
                #If a delay is specified, restart IIS on each server individually
                If($Delay){
                    Write-Verbose "A delay of $($Delay)s was specified."

                    #Group all websites by server
                    $CAGroupWebsites = $WebsitesList | Group-Object -Property Website
                    If($CAGroupWebsites){
                        #Parse each server and group of websites
                        ForEach($CAGroupWebsite In $CAGroupWebsites){
                            #Parse each website in the group
                            ForEach($CAWebsite In  $CAGroupWebsite){
                                Write-Verbose "Restarting $($CAWebsite.Name)"
                                #Reset IIS on each group of servers one group at a time
                                $Results += Invoke-Command -ScriptBlock{
                                    #Create a new object with the results of the IISReset and grab output from IISReset
                                    New-Object PSObject -Property @{
                                        Server = hostname
                                        Message = Invoke-Expression -Command IISReset
                                        Exitcode = $lastexitcode
                                    }
                                } -ComputerName ($CAWebsite.Group.PSComputerName | Select-Object -Unique)
                                
                                #Sleep specified number of seconds before continuing to next group of websites
                                Start-Sleep -Seconds $Delay
                            }
                        }
                    }
                } Else {
                    Write-Verbose "Restarting websites on $($Servers)..."
                    $Results = Invoke-Command -ScriptBlock{
                        #Create a new object with the results of the IISReset and grab output from IISReset
                        New-Object PSObject -Property @{
                            Server = hostname
                            Message = Invoke-Expression -Command IISReset
                            Exitcode = $lastexitcode
                        } 
                    } -ComputerName $Servers
                }
            }
        }

        #Return results of IISReset
        Return $Results
    }

    END{
        #Get End Time
        $endDTM = (Get-Date)

        #Echo Time elapsed
        Write-Verbose "Elapsed Time: $(($endDTM-$startDTM).totalseconds) seconds"
    }
}

Function Start-CAServicesGUI{
    <#
        .SYNOPSIS 
         A GUI interface to start and stop Cloud Archive services and websites.

        .PARAMETER Datacenter
         Specifies the data center you want to query. If this is not specified, the default 
         data center is derived from the first 7 characters of the server the script is 
         running from.

        .PARAMETER MaintenancePage
         Specifies the path of the maintenance page. If parameter is not specified, it looks
         for the App_Offline.htm in the same folder as the module.

        .EXAMPLE
         Start-CAServicesGUI -Datacenter "ELS02CA" -Verbose
         This command starts the CAService GUI and sets the datacenter to ELS02CA.
    #>

    [CmdletBinding(
        SupportsShouldProcess=$true,
        ConfirmImpact="High"
    )]    

    PARAM(
        [ValidatePattern("^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]")]
        [string]$Datacenter = ($Hostname = HostName).Substring(0,7),
        [string]$MaintenancePage = ".\App_Offline.htm"
    )

    BEGIN{
        #Validate data center parameter for proper format
        If (!($Datacenter -match '^[AEIMJLSU][AHILMSUY][AENDRSW][0-2][0-4][C][A]')){
            Throw "$Datacenter is not a valid datacenter! Use -Datacenter Parameter to specify a valid datacenter (Example: ELS02CA)."
        }

        #Set Margin
        $LeftMargin = 10
        $TopMargin = 10

        #Set initial starting point for button
        $ButtonTopMargin = 650

        #Create Windows Form
        Add-Type -AssemblyName System.Windows.Forms
        $Form = New-Object Windows.Forms.Form

        #Set Form Title
        $Form.Text = "CA Services and Websites GUI"

        #Set Form Opacity
        $Form.Opacity = 0.95

        #Open Window in center of screen
        $form.StartPosition = "CenterScreen"

        #Specify Datacenter Font
        $DatacenterFont = New-Object System.Drawing.Font("Times New Roman",18,[System.Drawing.FontStyle]::Bold)
        # Font styles are: Regular, Bold, Italic, Underline, Strikeout

        #Specify CheckedBoxList Font
        $CheckedBoxListFont = New-Object System.Drawing.Font("Times New Roman",12,[System.Drawing.FontStyle]::Bold)
        # Font styles are: Regular, Bold, Italic, Underline, Strikeout

        #Set Log Path
        $LogPath = ".\Logs\"

        #Set Log File TimeStamp
        $Timestamp = ((Get-Date).ToString('MM-dd-yyyy_hh-mm-ss'))

        #Checking to see if Log Path exists
        If(!(Test-Path $LogPath)){
            New-Item -Path $LogPath -ItemType Directory
        }

        #Set Transcript Log File
        $CALog = $LogPath + "CAServicesGUI-$($Timestamp).log"

        #Start Logging
        Start-Transcript $CALog        

        #Set List of Services and Websites
        $CAServicesList = ".\$Datacenter-Services.csv"
        $CAWebsitesList = ".\$Datacenter-Websites.csv"


        #Check to see if Services and Websites list exists
        Write-Verbose "Checking to see if $($CAServicesList) exists"
        If(!(Test-Path $CAServicesList)){
            #Export Services
            Write-Verbose "Exporting list of online servers..."
            Invoke-Expression -Command "Get-CAServicesList -Datacenter $Datacenter | Export-Csv $CAServicesList -NoTypeInformation"
        }

        Write-Verbose "Checking to see if $($CAWebsitesList) exists"
        If(!(Test-Path $CAWebsitesList)){
            #Export Websites
            Write-Verbose "Exporting list of online servers..."
            Invoke-Expression -Command "Get-CAWebsitesList -Datacenter $Datacenter | Export-Csv $CAWebsitesList -NoTypeInformation"
        }

        #Import Deployment Tasks
        $CAServices = Import-Csv $CAServicesList
        $CAWebsites = Import-Csv $CAWebsitesList

        #Set Window Size based on number of items
        $Form.Size = New-Object Drawing.Size @(740,750)

        #Set Datacenter Label
        $lblDatacenter = New-Object System.Windows.Forms.Label
        $lblDatacenter.Text = "Datacenter: $Datacenter"
        $lblDatacenter.Location = "$LeftMargin,$TopMargin"
        $lblDatacenter.Autosize = "true"
        $lblDatacenter.Font = $DatacenterFont

        #Add Datacenter Label to Form
        $Form.Controls.Add($lblDatacenter)

        #Get Unique Services and Websites
        $UniqueServices = $CAServices | Select-Object -Property Name -Unique | Sort-Object -Property Name
        $UniqueWebsites = $CAWebsites | Select-Object -Property Path -Unique | Sort-Object -Property Path

        #Add Services Label
        $lblServices = New-Object System.Windows.Forms.Label
        $lblServices.Location = "$LeftMargin,50"
        $lblServices.Size = "180,20"
        $lblServices.Text = "Services:"
        $lblServices.Font = $CheckedBoxListFont
        $Form.Controls.Add($lblServices)

        # Create a CheckedListBox
        $ServicesCheckedListBox = New-Object -TypeName System.Windows.Forms.CheckedListBox
        # Add the CheckedListBox to the Form
        $Form.Controls.Add($ServicesCheckedListBox)
        # Widen the CheckedListBox
        $ServicesCheckedListBox.Location = "10,70"
        $ServicesCheckedListBox.Width = 350
        $ServicesCheckedListBox.Height = 500
        # Allows you to check box on first click
        $ServicesCheckedListBox.CheckOnClick = $true
        # Add Select All Option
        $ServicesCheckedListBox.Items.Add("Select All")
        # Add items to the CheckedListBox
        $ServicesCheckedListBox.Items.AddRange($UniqueServices.Name)

        #Configure Select All Check Box Functionality
        $ServicesCheckedListBox.Add_Click({
            If($This.SelectedItem -eq 'Select All'){
                If ($This.GetItemCheckState(0) -ne 'Checked') {
                    For($i=1;$i -lt $ServicesCheckedListBox.Items.Count; $i++){
                        $ServicesCheckedListBox.SetItemChecked($i,$True)
                    }            
                } Else {
                    For($i=1;$i -lt $ServicesCheckedListBox.Items.Count; $i++){
                        $ServicesCheckedListBox.SetItemChecked($i,$False)
                    } 
                }
            }
        })

        #Add Websites Label
        $lblWebsites = New-Object System.Windows.Forms.Label
        $lblWebsites.Location = "$($LeftMargin + 350),50"
        $lblWebsites.Size = "180,20"
        $lblWebsites.Text = "Websites:"
        $lblWebsites.Font = $CheckedBoxListFont
        $Form.Controls.Add($lblWebsites)

        # Create a CheckedListBox
        $WebsitesCheckedListBox = New-Object -TypeName System.Windows.Forms.CheckedListBox
        # Add the CheckedListBox to the Form
        $Form.Controls.Add($WebsitesCheckedListBox)
        # Widen the CheckedListBox
        $WebsitesCheckedListBox.Location = "365,70"
        $WebsitesCheckedListBox.Width = 350
        $WebsitesCheckedListBox.Height = 500
        # Allows you to check box on first click
        $WebsitesCheckedListBox.CheckOnClick = $true
        # Add Select All Option
        $WebsitesCheckedListBox.Items.Add("Select All")
        # Add items to the CheckedListBox
        $WebsitesCheckedListBox.Items.AddRange(($UniqueWebsites.Path -replace ("Z:\\LOMA_Apps\\","")))

        #Configure Select All Check Box Functionality
        $WebsitesCheckedListBox.Add_Click({
            If($This.SelectedItem -eq 'Select All'){
                If ($This.GetItemCheckState(0) -ne 'Checked') {
                    For($i=1;$i -lt $WebsitesCheckedListBox.Items.Count; $i++){
                        $WebsitesCheckedListBox.SetItemChecked($i,$True)
                    }            
                } Else {
                    For($i=1;$i -lt $WebsitesCheckedListBox.Items.Count; $i++){
                        $WebsitesCheckedListBox.SetItemChecked($i,$False)
                    } 
                }
            }
        })

        #Add Filter Label
        $lblFilter = New-Object System.Windows.Forms.Label
        $lblFilter.Location = "$LeftMargin,585"
        $lblFilter.Size = "240,20"
        $lblFilter.Text = "Please enter server filter (optional):"
        $Form.Controls.Add($lblFilter)

        #Add Filter Text Box
        $FilterTextBox = New-Object System.Windows.Forms.TextBox 
        $FilterTextBox.Location = "250,580" 
        $FilterTextBox.Size = "260,20"
        $Form.Controls.Add($FilterTextBox)

        #Add Delay Label
        $lblDelay = New-Object System.Windows.Forms.Label
        $lblDelay.Location = "$LeftMargin,610"
        $lblDelay.Size = "240,20"
        $lblDelay.Text = "Please enter website restart delay (optional):"
        $Form.Controls.Add($lblDelay)

        #Add Delay Text Box
        $DelayTextBox = New-Object System.Windows.Forms.TextBox 
        $DelayTextBox.Location = "250,605" 
        $DelayTextBox.Size = "260,20"
        $Form.Controls.Add($DelayTextBox)

        #Create Get Service(s) Button
        $btnGet = New-Object System.Windows.Forms.Button
        #Define button location
        $btnGet.Location = "$($LeftMargin + 15),$ButtonTopMargin"
        #Define button size
        $btnGet.Size = "150,25"
        #Define button description
        $btnGet.Text = "Get Service(s)"
        #Add Checkbox to form
        $form.Controls.Add($btnGet)
        #Add Button Action
        $btnGet.Add_Click({


            #Initialize array
            $ServiceInclude = @()

            $Filter = $FilterTextBox.Text

            If($ServicesCheckedlistbox.CheckedItems.Count -gt 0){
                ForEach($Item In $ServicesCheckedlistbox.CheckedItems){
                    #Edit Regex pattern for exact match
                    $ServiceInclude += "^$Item$"
                }

                #Join patterns to make filter
                $ServiceInclude = $ServiceInclude -join "|"
        
                Get-CAServices -Datacenter $Datacenter -Include $ServiceInclude -Filter $Filter -FilePath $CAServicesList | Select-Object -Property PSComputerName, Name, Status | Sort-Object -Property Status, Name, PSComputerName | Out-GridView

            }Else{
                Write-Warning "No services selected."
            }

            #Initialize array
            $WebInclude = @()

            If($WebsitesCheckedlistbox.CheckedItems.Count -gt 0){
                ForEach($Item In $WebsitesCheckedlistbox.CheckedItems){
                    #Edit Regex pattern for exact match
                    $WebInclude += "^$Item$"
                }
        
                #Join patterns to make filter
                $WebInclude = $WebInclude -join "|"

                Get-CAWebsites -Datacenter $Datacenter -Include $WebInclude -Filter $Filter -FilePath $CAWebsitesList | Select-Object -Property PSComputerName, Website, Online | Sort-Object -Property Online, Website, PSComputerName | Out-GridView
        
            }Else{
                Write-Warning "No websites selected."
            }

        })

        #Create Start Service(s) Button
        $btnStart = New-Object System.Windows.Forms.Button
        #Define button location
        $btnStart.Location = "$($LeftMargin + 185),$ButtonTopMargin"
        #Define button size
        $btnStart.Size = "150,25"
        #Define button description
        $btnStart.Text = "Start Service(s)"
        #Add Checkbox to form
        $form.Controls.Add($btnStart)
        #Add Button Action
        $btnStart.Add_Click({

            #Initialize array
            $ServiceInclude = @()

            $Filter = $FilterTextBox.Text

            If($ServicesCheckedlistbox.CheckedItems.Count -gt 0){
                ForEach($Item In $ServicesCheckedlistbox.CheckedItems){
                    #Edit Regex pattern for exact match
                    $ServiceInclude += "^$Item$"
                }

                #Join patterns to make filter
                $ServiceInclude = $ServiceInclude -join "|"
        
                Start-CAServices -Datacenter $Datacenter -Include $ServiceInclude -Filter $Filter -FilePath $CAServicesList | Select-Object -Property PSComputerName, Name, Status | Sort-Object -Property Status, Name, PSComputerName | Out-GridView

            }Else{
                Write-Warning "No services selected."
            }

            #Initialize array
            $WebInclude = @()

            If($WebsitesCheckedlistbox.CheckedItems.Count -gt 0){
                ForEach($Item In $WebsitesCheckedlistbox.CheckedItems){
                    #Edit Regex pattern for exact match
                    $WebInclude += "^$Item$"
                }
        
                #Join patterns to make filter
                $WebInclude = $WebInclude -join "|"

                Start-CAWebsites -Datacenter $Datacenter -Include $WebInclude -Filter $Filter -FilePath $CAWebsitesList | Select-Object -Property PSComputerName, Website, Online | Sort-Object -Property Online, Website, PSComputerName | Out-GridView
        
            }Else{
                Write-Warning "No websites selected."
            }
    

        })

        #Create Stop Service(s) Button
        $btnStop = New-Object System.Windows.Forms.Button
        #Define button location
        $btnStop.Location = "$($LeftMargin + 365),$ButtonTopMargin"
        #Define button size
        $btnStop.Size = "150,25"
        #Define button description
        $btnStop.Text = "Stop Service(s)"
        #Add Checkbox to form
        $form.Controls.Add($btnStop)
        #Add Button Action
        $btnStop.Add_Click({

            #Initialize array
            $ServiceInclude = @()

            $Filter = $FilterTextBox.Text

            If($ServicesCheckedlistbox.CheckedItems.Count -gt 0){
                ForEach($Item In $ServicesCheckedlistbox.CheckedItems){
                    #Edit Regex pattern for exact match
                    $ServiceInclude += "^$Item$"
                }

                #Join patterns to make filter
                $ServiceInclude = $ServiceInclude -join "|"
        
                Stop-CAServices -Datacenter $Datacenter -Include $ServiceInclude -Filter $Filter -FilePath $CAServicesList | Select-Object -Property PSComputerName, Name, Status | Sort-Object -Property Status, Name, PSComputerName | Out-GridView

            }Else{
                Write-Warning "No services selected."
            }

            #Initialize array
            $WebInclude = @()
            
            #Verify Maintenance Page Exists
            If(!(Test-Path $MaintenancePage)){
                Write-Warning "Maintenance page file not found: $($MaintenancePage)"
            }Else{

                If($WebsitesCheckedlistbox.CheckedItems.Count -gt 0){
                    ForEach($Item In $WebsitesCheckedlistbox.CheckedItems){
                        #Edit Regex pattern for exact match
                        $WebInclude += "^$Item$"
                    }
        
                    #Join patterns to make filter
                    $WebInclude = $WebInclude -join "|"

                    Stop-CAWebsites -Datacenter $Datacenter -Include $WebInclude -Filter $Filter -FilePath $CAWebsitesList -MaintenancePage $MaintenancePage | Select-Object -Property PSComputerName, Website, Online | Sort-Object -Property Online, Website, PSComputerName | Out-GridView
        
                }Else{
                    Write-Warning "No websites selected."
                }
            }
   
        })

        #Create Restart Website(s) Button
        $btnRestart = New-Object System.Windows.Forms.Button
        #Define button location
        $btnRestart.Location = "$($LeftMargin + 535),$ButtonTopMargin"
        #Define button size
        $btnRestart.Size = "150,25"
        #Define button description
        $btnRestart.Text = "Restart Website(s)"
        #Add Checkbox to form
        $form.Controls.Add($btnRestart)
        #Add Button Action
        $btnRestart.Add_Click({

            #Initialize array
            $WebInclude = @()

            $Filter = $FilterTextBox.Text

            If($WebsitesCheckedlistbox.CheckedItems.Count -gt 0){
                
                ForEach($Item In $WebsitesCheckedlistbox.CheckedItems){
                        #Edit Regex pattern for exact match
                        $WebInclude += "^$Item$"
                }

                #Join patterns to make filter
                $WebInclude = $WebInclude -join "|"
                
                #Check to see if a valid delay was specified
                If($DelayTextBox -match "\d"){
                    
                    Restart-CAWebsites -Datacenter $Datacenter -Include $WebInclude -Filter $Filter -FilePath $CAWebsitesList -Delay $DelayTextBox.Text | Select-Object -Property PSComputerName, Exitcode, Message | Sort-Object -Property Exitcode, PSComputerName | Out-GridView

                }Else{

                    Restart-CAWebsites -Datacenter $Datacenter -Include $WebInclude -Filter $Filter -FilePath $CAWebsitesList | Select-Object -Property PSComputerName, Exitcode, Message | Sort-Object -Property Exitcode, PSComputerName | Out-GridView

                }
            }Else{
                Write-Warning "No websites selected."
            }
    

        })

        #Makes the form the active
        $Form.Add_Shown({$Form.Activate()})

        #Show Form
        $drc = $Form.ShowDialog()

    }
    PROCESS{
    
    }

    END{
        Stop-Transcript
    }
}