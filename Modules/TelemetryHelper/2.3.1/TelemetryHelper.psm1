$script:ModuleRoot = $PSScriptRoot
$script:ModuleVersion = (Import-PowerShellDataFile -Path "$($script:ModuleRoot)\TelemetryHelper.psd1").ModuleVersion

# Detect whether at some level dotsourcing was enforced
$script:doDotSource = Get-PSFConfigValue -FullName TelemetryHelper.Import.DoDotSource -Fallback $false
if ($TelemetryHelper_dotsourcemodule) { $script:doDotSource = $true }

<#
Note on Resolve-Path:
All paths are sent through Resolve-Path/Resolve-PSFPath in order to convert them to the correct path separator.
This allows ignoring path separators throughout the import sequence, which could otherwise cause trouble depending on OS.
Resolve-Path can only be used for paths that already exist, Resolve-PSFPath can accept that the last leaf my not exist.
This is important when testing for paths.
#>

# Detect whether at some level loading individual module files, rather than the compiled module was enforced
$importIndividualFiles = Get-PSFConfigValue -FullName TelemetryHelper.Import.IndividualFiles -Fallback $false
if ($TelemetryHelper_importIndividualFiles) { $importIndividualFiles = $true }
if (Test-Path (Resolve-PSFPath -Path "$($script:ModuleRoot)\..\.git" -SingleItem -NewChild)) { $importIndividualFiles = $true }
if ("<was compiled>" -eq '<was not compiled>') { $importIndividualFiles = $true }
	
function Import-ModuleFile
{
	<#
		.SYNOPSIS
			Loads files into the module on module import.
		
		.DESCRIPTION
			This helper function is used during module initialization.
			It should always be dotsourced itself, in order to proper function.
			
			This provides a central location to react to files being imported, if later desired
		
		.PARAMETER Path
			The path to the file to load
		
		.EXAMPLE
			PS C:\> . Import-ModuleFile -File $function.FullName
	
			Imports the file stored in $function according to import policy
	#>
	[CmdletBinding()]
	Param (
		[string]
		$Path
	)
	
	$resolvedPath = $ExecutionContext.SessionState.Path.GetResolvedPSPathFromPSPath($Path).ProviderPath
	if ($doDotSource) { . $resolvedPath }
	else { $ExecutionContext.InvokeCommand.InvokeScript($false, ([scriptblock]::Create([io.file]::ReadAllText($resolvedPath))), $null, $null) }
}

#region Load individual files
if ($importIndividualFiles)
{
	# Execute Preimport actions
	foreach ($path in (& "$ModuleRoot\internal\scripts\preimport.ps1")) {
		. Import-ModuleFile -Path $path
	}
	
	# Import all internal functions
	foreach ($function in (Get-ChildItem "$ModuleRoot\internal\functions" -Filter "*.ps1" -Recurse -ErrorAction Ignore))
	{
		. Import-ModuleFile -Path $function.FullName
	}
	
	# Import all public functions
	foreach ($function in (Get-ChildItem "$ModuleRoot\functions" -Filter "*.ps1" -Recurse -ErrorAction Ignore))
	{
		. Import-ModuleFile -Path $function.FullName
	}
	
	# Execute Postimport actions
	foreach ($path in (& "$ModuleRoot\internal\scripts\postimport.ps1")) {
		. Import-ModuleFile -Path $path
	}
	
	# End it here, do not load compiled code below
	return
}
#endregion Load individual files

#region Load compiled code
<#
This file loads the strings documents from the respective language folders.
This allows localizing messages and errors.
Load psd1 language files for each language you wish to support.
Partial translations are acceptable - when missing a current language message,
it will fallback to English or another available language.
#>
Import-PSFLocalizedString -Path "$($script:ModuleRoot)/en-us/*.psd1" -Module 'TelemetryHelper' -Language 'en-US'

try {
    Add-Type -Path "$script:moduleRoot/bin/netstandard2.0/TelemetryHelper.dll" -ErrorAction Stop
} catch {
    Write-PSFMessage -Message "Unable to import telemetry library."
}

<#
.SYNOPSIS
    Internal function to determine the module name
.DESCRIPTION
    Internal function to determine the module name of the calling cmdlet
.EXAMPLE
    Get-CallingModule

    Returns either null or the module name
#>
function Get-CallingModule
{
    [OutputType([string])]
    [CmdletBinding()]
    param ( )
    
    $moduleName = foreach ($stackEntry in (Get-PSCallStack))
    {
        if ($stackEntry.InvocationInfo.MyCommand.ModuleName -eq 'TelemetryHelper') { continue }

        if ($null -ne $stackEntry.InvocationInfo.MyCommand.ModuleName)
        {
            $stackEntry.InvocationInfo.MyCommand.ModuleName
            break
        }
    }
    
    if ($moduleName)
    {
        Write-PSFMessage -Message "Determined module name $moduleName"
        return $moduleName
    }

    Stop-PSFFunction -Message "Unable to determine module name. Telemetry collection will not work properly."
}


<#
.SYNOPSIS
    Add connection string
.DESCRIPTION
    Adds ApplicationInsights connection string to module's telemetry config
.PARAMETER ConnectionString
    The instrumentation API key, e.g. (Get-AzApplicationInsights -ResourceGroupName TotallyTerrificTelemetryTest -Name TurboTelemetry).ConnectionString
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.EXAMPLE
    Add-THAppInsightsConnectionString InstrumentationKey=4852e725-d412-4d7d-ad86-25df570b7f13;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/

    Adds API key InstrumentationKey=4852e725-d412-4d7d-ad86-25df570b7f13;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/ to the calling modules config
.EXAMPLE
    Add-THAppInsightsConnectionString InstrumentationKey=4852e725-d412-4d7d-ad86-25df570b7f13;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/ -ModuleName MyModule

    Adds API key InstrumentationKey=4852e725-d412-4d7d-ad86-25df570b7f13;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/ to the configuration of MyModule
#>
function Add-THAppInsightsConnectionString
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]
        $ConnectionString,

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule)
    )

    if ($null -eq (Get-THTelemetryConfiguration -ModuleName $CallingModule))
    {
        Set-THTelemetryConfiguration -ModuleName $CallingModule -OptInVariableName "$($CallingModule)telemetryOptIn"
    }

    (Get-THTelemetryConfiguration -ModuleName $CallingModule).UpdateConnectionString($ConnectionString)
    Set-PSFConfig -Module TelemetryHelper -Name "$CallingModule.ApplicationInsights.ConnectionString" -Value $ConnectionString -PassThru -Hidden | Register-PSFConfig
}


<#
.SYNOPSIS
    Get the current telemetry config
.DESCRIPTION
    Get the current telemetry config
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.EXAMPLE
    Get-THTelemetryConfiguration

    Returns the current configuration for the current module
#>
function Get-THTelemetryConfiguration
{
    [CmdletBinding()]
    param
    (
        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule)
    )

    (Get-PSFConfigValue -FullName TelemetryHelper.TelemetryStore)[$CallingModule]
}


<#
.SYNOPSIS
    Enable telemetry
.DESCRIPTION
    Enable telemetry by creating a new telemetry client in the global telemetry store.
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.EXAMPLE
    Initialize-THTelemetry

    Initialize telemetry
#>
function Initialize-THTelemetry
{
    [CmdletBinding()]
    param
    (
        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule)
    )

    Write-PSFMessage -Message "Creating new telemetry store for $CallingModule"
    (Get-PSFConfigValue -FullName TelemetryHelper.TelemetryStore)[$CallingModule] = New-Object -TypeName de.janhendrikpeters.TelemetryHelper -ArgumentList $CallingModule
}


<#
.SYNOPSIS
    Send custom availability
.DESCRIPTION
    Send custom availability with configurable properties and metrics.
.PARAMETER TestName
    Name of the test
.PARAMETER Location
    Location from which the test was executed
.PARAMETER Duration
    Duration the availablity test ran
.PARAMETER Available
    Indicates whether or not the tested endpoint was available. Defaults to true
.PARAMETER TimeStamp
    Timestamp when the test was executed. Defaults to current date
.PARAMETER Message
    Optional error message to include in availability trace
.PARAMETER PropertiesHash
    A Hashtable of properties and values. Both properties as well as values will be converted to string
.PARAMETER MetricsHash
    A Hashtable of metrics and values. Metric name will be converted to string, value to double
.PARAMETER DoNotFlush
    Indicates that data should be collected and flushed by the telemetry client at regular intervals
    Intervals are 30s or 500 metrics
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.EXAMPLE
    Send-THAvailability -TestName PublicEndpoint -Location 'Amsterdam' -Duration [TimeSpan]::FromMilliseconds(120)

    Sends availability info for a test called PublicEndpoint, tested from Amsterdam with a duration of 120ms.
#>
function Send-THAvailability
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $TestName,

        [Parameter(Mandatory = $true)]
        [string]
        $Location,

        [Parameter(Mandatory = $true)]
        [TimeSpan]
        $Duration,

        [Parameter()]
        [bool]
        $Available = $true,

        [Parameter()]
        [DateTimeOffset]
        $TimeStamp = (Get-Date),

        [Parameter()]
        [string]
        $Message,

        [Alias('Properties')]
        [Parameter()]
        [System.Collections.Hashtable]
        $PropertiesHash,

        [Alias('Metrics')]
        [Parameter()]
        [System.Collections.Hashtable]
        $MetricsHash,

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule),

        [Parameter()]
        [switch]
        $DoNotFlush
    )

    begin
    {
        $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule

        if ($null -eq $telemetryInstance)
        {
            Initialize-THTelemetry -ModuleName $CallingModule
            $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule
        }

        if ($MetricsHash)
        {
            $Metrics = New-Object -TypeName 'System.Collections.Generic.Dictionary[string, double]'
            foreach ($kvp in $MetricsHash.GetEnumerator())
            {
                $Metrics.Add([string]$kvp.Key, [double]$kvp.Value)
            }
        }

        if ($PropertiesHash)
        {
            $Properties = New-Object -TypeName 'System.Collections.Generic.Dictionary[string, string]'
            foreach ($kvp in $PropertiesHash.GetEnumerator())
            {
                $Properties.Add([string]$kvp.Key, [string]$kvp.Value)
            }
        }
    }

    process
    {
        # (string testName, DateTimeOffset timeStamp, TimeSpan duration, string location, bool success = true, string message = "", Dictionary<string, string> properties = null, Dictionary<string, double> metrics = null)
        try
        {
            if ($Properties -and $Metrics)
            {
                $telemetryInstance.SendAvailability($TestName, $TimeStamp, $Duration, $Location, $Available, $Message, $Properties, $Metrics)
            }
            elseif ($Properties)
            {
                $telemetryInstance.SendAvailability($TestName, $TimeStamp, $Duration, $Location, $Available, $Message, $Properties)
            }
            elseif ($Metrics)
            {
                $telemetryInstance.SendAvailability($TestName, $TimeStamp, $Duration, $Location, $Available, $Message, $null, $Metrics)
            }
            else
            {
                $telemetryInstance.SendAvailability($TestName, $TimeStamp, $Duration, $Location, $Available, $Message)
            }
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to send availability test $TestName to ApplicationInsights" -Exception $_.Exception
        }
    }

    end
    {
        if ($DoNotFlush)
        {
            return
        }

        try
        {
            $telemetryInstance.Flush()
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to flush telemetry client. Messages may be delayed." -Exception $_.Exception
        }
    }
}


<#
.SYNOPSIS
    Send custom event
.DESCRIPTION
    Send custom event with configurable properties and metrics. This is the most versatile
    telemetry instrument. Properties and Metrics can all be evaluated in e.g. PowerBI or an AppInsights query.
.PARAMETER EventName
    Name of the event
.PARAMETER PropertiesHash
    A Hashtable of properties and values. Both properties as well as values will be converted to string
.PARAMETER MetricsHash
    A Hashtable of metrics and values. Metric name will be converted to string, value to double
.PARAMETER DoNotFlush
    Indicates that data should be collected and flushed by the telemetry client at regular intervals
    Intervals are 30s or 500 metrics
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.EXAMPLE
    Send-THEvent -EventName ModuleImport -PropertiesHash @{PSVersionUsed = $PSVersionTable.PSVersion}

    Sends a ModuleImport event with the PowerShell Version that has been used.
#>
function Send-THEvent
{
    [CmdletBinding()]
    param
    (
        [Parameter(, Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $EventName,

        [Alias('Properties')]
        [Parameter()]
        [System.Collections.Hashtable]
        $PropertiesHash,

        [Alias('Metrics')]
        [Parameter()]
        [System.Collections.Hashtable]
        $MetricsHash,

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule),

        [Parameter()]
        [switch]
        $DoNotFlush
    )

    begin
    {
        $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule

        if ($null -eq $telemetryInstance)
        {
            Initialize-THTelemetry -ModuleName $CallingModule
            $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule
        }

        if ($MetricsHash)
        {
            $Metrics = New-Object -TypeName 'System.Collections.Generic.Dictionary[string, double]'
            foreach ($kvp in $MetricsHash.GetEnumerator())
            {
                $Metrics.Add([string]$kvp.Key, [double]$kvp.Value)
            }
        }

        if ($PropertiesHash)
        {
            $Properties = New-Object -TypeName 'System.Collections.Generic.Dictionary[string, string]'
            foreach ($kvp in $PropertiesHash.GetEnumerator())
            {
                $Properties.Add([string]$kvp.Key, [string]$kvp.Value)
            }
        }
    }

    process
    {
        
        try
        {
            if ($Properties -and $Metrics)
            {
                $telemetryInstance.SendEvent($EventName, $Properties, $Metrics)
            }
            elseif ($Properties)
            {
                $telemetryInstance.SendEvent($EventName, $Properties)
            }
            elseif ($Metrics)
            {
                $telemetryInstance.SendEvent($EventName, $null, $Metrics)
            }
            else
            {
                $telemetryInstance.SendEvent($EventName)
            }
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to send event $EventName to ApplicationInsights" -Exception $_.Exception
        }
    }

    end
    {
        if ($DoNotFlush)
        {
            return
        }

        try
        {
            $telemetryInstance.Flush()
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to flush telemetry client. Messages may be delayed." -Exception $_.Exception
        }
    }
}


<#
.SYNOPSIS
    Send an exception
.DESCRIPTION
    Send an exception
.PARAMETER Exception
    The exception to send
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.PARAMETER DoNotFlush
    Indicates that data should be collected and flushed by the telemetry client at regular intervals
    Intervals are 30s or 500 metrics
.EXAMPLE
    Send-THException -Exception $error[0].Exception

    Sends the recent exception to AppInsights
#>
function Send-THException
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Exception]
        $Exception,

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule),

        [Parameter()]
        [switch]
        $DoNotFlush
    )

    begin
    {
        $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule

        if ($null -eq $telemetryInstance)
        {
            Initialize-THTelemetry -ModuleName $CallingModule
            $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule
        }
    }

    process
    {
        try
        {
            $telemetryInstance.SendError($Exception)
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to send exception '$Message' to ApplicationInsights" -Exception $_.Exception
        }
    }

    end
    {
        if ($DoNotFlush)
        {
            return
        }

        try
        {
            $telemetryInstance.Flush()
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to flush telemetry client. Messages may be delayed." -Exception $_.Exception
        }
    }
}


<#
.SYNOPSIS
    Send a metric
.DESCRIPTION
    Send a metric (up to two dimensions) to AppInsights. Metrics will be correlated.
.PARAMETER MetricName
    Metric name (dimension 0)
.PARAMETER MetricDimension1
    Additional metric dimension 1
.PARAMETER MetricDimension2
    Additional metric dimension 2
.PARAMETER Value
    Value (double) of the metric
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.PARAMETER DoNotFlush
    Indicates that data should be collected and flushed by the telemetry client at regular intervals
    Intervals are 30s or 500 metrics
.EXAMPLE
    Send-THMetric -MetricName Layer8Errors -Value 300

    Sends the metric Layer8Errors with a value of 300
.EXAMPLE
    Send-THMetric -MetricName Layer8 -MetricDimension Errors -Value 300

    Sends a multidimensional metric
#>
function Send-THMetric
{
    [CmdletBinding(DefaultParameterSetName = 'NoDim')]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'NoDim')]
        [Parameter(Mandatory = $true, ParameterSetName = 'OneDim')]
        [Parameter(Mandatory = $true, ParameterSetName = 'TwoDim')]
        [string]
        $MetricName,

        [Parameter(Mandatory = $true, ParameterSetName = 'OneDim')]
        [Parameter(Mandatory = $true, ParameterSetName = 'TwoDim')]
        [string]
        $MetricDimension1,

        [Parameter(Mandatory = $true, ParameterSetName = 'TwoDim')]
        [string]
        $MetricDimension2,

        [Parameter(Mandatory = $true)]
        [double]
        $Value,

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule),

        [Parameter()]
        [switch]
        $DoNotFlush
    )

    $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule

    if ($null -eq $telemetryInstance)
    {
        Initialize-THTelemetry -ModuleName $CallingModule
        $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule
    }

    try
    {
        switch ($PSCmdlet.ParameterSetName)
        {
            'NoDim'
            {
                $telemetryInstance.SendMetric($MetricName, $Value)
            }
            'OneDim'
            {
                $telemetryInstance.SendMetric($MetricName, $MetricDimension1, $Value)
            }
            'TwoDim'
            {
                $telemetryInstance.SendMetric($MetricName, $MetricDimension1, $MetricDimension2, $Value)
            }
        }
    }
    catch
    {
        Stop-PSFFunction -Message "Unable to send metric '$MetricName$MetricDimension1$MetricDimension2' with value $Value to ApplicationInsights" -Exception $_.Exception
    }

    if ($DoNotFlush)
    {
        return
    }

    try
    {
        $telemetryInstance.Flush()
    }
    catch
    {
        Stop-PSFFunction -Message "Unable to flush telemetry client. Messages may be delayed." -Exception $_.Exception
    }
}


<#
.SYNOPSIS
    Send a trace message
.DESCRIPTION
    Send a trace message
.PARAMETER Message
    The text to send
.PARAMETER SeverityLevel
    The severity of the trace message
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.PARAMETER DoNotFlush
    Indicates that data should be collected and flushed by the telemetry client at regular intervals
    Intervals are 30s or 500 metrics
.EXAMPLE
    Send-THTrace -Message "Oh god! It burns!"

    Sends the message "Oh god! It burns!" with severity Information (default) to ApplicationInsights
.EXAMPLE
    Send-THTrace -Message "Oh god! It burns!" -SeverityLevel Critical

    Sends the message "Oh god! It burns!" with severity Critical to ApplicationInsights
#>
function Send-THTrace
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]
        $Message,

        [Parameter()]
        [ValidateSet('Critical', 'Error', 'Warning', 'Information', 'Verbose')]
        $SeverityLevel = 'Information',

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule),

        [Parameter()]
        [switch]
        $DoNotFlush
    )

    begin
    {
        $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule

        if ($null -eq $telemetryInstance)
        {
            Initialize-THTelemetry -ModuleName $CallingModule
            $telemetryInstance = Get-THTelemetryConfiguration -ModuleName $CallingModule
        }
    }

    process
    {
        try
        {
            $telemetryInstance.SendTrace($Message, $SeverityLevel)
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to send trace '$Message' to ApplicationInsights" -Exception $_.Exception
        }
    }

    end
    {
        if ($DoNotFlush)
        {
            return
        }

        try
        {
            $telemetryInstance.Flush()
        }
        catch
        {
            Stop-PSFFunction -Message "Unable to flush telemetry client. Messages may be delayed." -Exception $_.Exception
        }
    }
}


<#
.SYNOPSIS
    Configure the telemetry for a module
.DESCRIPTION
    Configure the telemetry for a module
.PARAMETER OptInVariableName
    The environment variable used to determine user-opt-in
.PARAMETER UserOptIn
    Override environment variable and opt-in
.PARAMETER StripPersonallyIdentifiableInformation
    Remove information such as the host name from telemetry
.PARAMETER CallingModule
    Auto-generated, used to select the proper configuration in case you have different modules
.PARAMETER PassThru
    Return the configuration object for further processing
.PARAMETER WhatIf
    Simulates the entire affair
.PARAMETER Confirm
    Requests confirmation that you really want to change the configuration
.EXAMPLE
    Set-THTelemetryConfiguration -UserOptIn $True

    Configures the basics and enables the user opt-in
#>
function Set-THTelemetryConfiguration
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
    param
    (
        [Parameter()]
        [string]
        $OptInVariableName = "$(Get-CallingModule)telemetryOptIn",

        [Parameter()]
        [bool]
        $UserOptIn = $false,

        [Parameter()]
        [bool]
        $StripPersonallyIdentifiableInformation = $true,

        [Alias('ModuleName')]
        [Parameter()]
        [string]
        $CallingModule = (Get-CallingModule),

        [Parameter()]
        [switch]
        $PassThru
    )

    if ($PSCmdlet.ShouldProcess("$CallingModule telemetry", "ACTIVATE!"))
    {
        if ($null -eq (Get-PSFConfigValue -FullName TelemetryHelper.TelemetryStore)[$CallingModule])
        {
            Initialize-THTelemetry -ModuleName $CallingModule
        }

        # Set object properties
        (Get-PSFConfigValue -FullName TelemetryHelper.TelemetryStore)[$CallingModule].StripPii = $StripPersonallyIdentifiableInformation

        # Register module-specific info
        Set-PSFConfig -Module 'TelemetryHelper' -Name "$($CallingModule).OptInVariable" -Value $OptInVariableName -Description 'The name of the environment variable used to indicate that telemetry should be sent' -PassThru | Register-PSFConfig
        Set-PSFConfig -Module 'TelemetryHelper' -Name "$($CallingModule).OptIn" -Value $UserOptIn -Validation bool -Description 'Whether user opts into telemetry or not' -PassThru | Register-PSFConfig
        Set-PSFConfig -Module 'TelemetryHelper' -Name "$($CallingModule).RemovePII" -Value $StripPersonallyIdentifiableInformation -Validation bool -Description "Whether information like the computer name should be stripped from the data that is sent" -PassThru | Register-PSFConfig


        if ($PassThru)
        {
            (Get-PSFConfigValue -FullName TelemetryHelper.TelemetryStore)[$CallingModule]
        }
    }
}


<#
This is an example configuration file

By default, it is enough to have a single one of them,
however if you have enough configuration settings to justify having multiple copies of it,
feel totally free to split them into multiple files.
#>

<#
# Example Configuration
Set-PSFConfig -Module 'TelemetryHelper' -Name 'Example.Setting' -Value 10 -Initialize -Validation 'integer' -Handler { } -Description "Example configuration setting. Your module can then use the setting using 'Get-PSFConfigValue'"
#>

Set-PSFConfig -Module 'TelemetryHelper' -Name 'Import.DoDotSource' -Value $true -Initialize -Validation 'bool' -Description "Whether the module files should be dotsourced on import. By default, the files of this module are read as string value and invoked, which is faster but worse on debugging."
Set-PSFConfig -Module 'TelemetryHelper' -Name 'Import.IndividualFiles' -Value $true -Initialize -Validation 'bool' -Description "Whether the module files should be imported individually. During the module build, all module code is compiled into few files, which are imported instead by default. Loading the compiled versions is faster, using the individual files is easier for debugging and testing out adjustments."

# Module-specific settings
Set-PSFConfig -Module 'TelemetryHelper' -Name 'TelemetryStore' -Value @{}

# Module telemetry settings
Set-PSFConfig -Module 'TelemetryHelper' -Name 'TelemetryHelper.ApplicationInsights.ConnectionString' -Value $null -Initialize -Validation string -Description 'Your ApplicationInsights connection string' -Hidden
Set-PSFConfig -Module 'TelemetryHelper' -Name 'TelemetryHelper.OptInVariable' -Value 'TelemetryHelperTelemetryOptIn' -Initialize -Validation string -Description 'The name of the environment variable used to indicate that telemetry should be sent'
Set-PSFConfig -Module 'TelemetryHelper' -Name 'TelemetryHelper.OptIn' -Value $false -Initialize -Validation bool -Description 'Whether user opts into telemetry or not'
Set-PSFConfig -Module 'TelemetryHelper' -Name 'TelemetryHelper.RemovePII' -VAlue $true -Initialize -Validation bool -Description "Whether information like the computer name should be stripped from the data that is sent"


<#
Stored scriptblocks are available in [PsfValidateScript()] attributes.
This makes it easier to centrally provide the same scriptblock multiple times,
without having to maintain it in separate locations.

It also prevents lengthy validation scriptblocks from making your parameter block
hard to read.

Set-PSFScriptblock -Name 'TelemetryHelper.ScriptBlockName' -Scriptblock {
	
}
#>

<#
# Example:
Register-PSFTeppScriptblock -Name "TelemetryHelper.alcohol" -ScriptBlock { 'Beer','Mead','Whiskey','Wine','Vodka','Rum (3y)', 'Rum (5y)', 'Rum (7y)' }
#>

<#
# Example:
Register-PSFTeppArgumentCompleter -Command Get-Alcohol -Parameter Type -Name TelemetryHelper.alcohol
#>

New-PSFLicense -Product 'TelemetryHelper' -Manufacturer 'Jan-Hendrik Peters' -ProductVersion $script:ModuleVersion -ProductType Module -Name MIT -Version "1.0.0.0" -Date (Get-Date "2022-05-23") -Text @"
Copyright (c) 2022 japete

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
#endregion Load compiled code