function Add-PlugEventsOrgMember {
    <#
    .SYNOPSIS
        Add an organization as a member of another organization in Plug.Events.

    .DESCRIPTION
        Sends an InviteRoleFilledByOrg request over the Plug.Events websocket to
        add an organization to another organization with a specified role.
        Requires an authenticated connection (see Connect-PlugEvents -Credential).

    .PARAMETER Id
        Slug of the organization to add the member to.

    .PARAMETER Role
        Role the added organization will receive (e.g. "teacher", "performer").

    .PARAMETER Org
        Slug of the organization to add as a member. Only available in the default
        "Org" parameter set.

    .EXAMPLE
        Add "yourorg" to "balfolk-nl" with the role "teacher":

        PS> Add-PlugEventsOrgMember -Id "balfolk-nl" -Role "teacher" -Org "yourorg"
    #>

    [CmdLetBinding(DefaultParameterSetName = 'Org')]
    [OutputType([Object])]
    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [String] $Id,

        [Parameter(Mandatory = $true, Position = 2)]
        [String] $Role,

        [Parameter(Mandatory = $true, Position = 3, ParameterSetName = 'Org')]
        [String] $Org
    )

    # Check if the user is authenticated
    if (-not $Script:isAuthenticated) {
        throw "Plug Events: you must be authenticated to use this function. Please run Connect-PlugEvents with the -Credential parameter."
    }

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Add-PlugEventsOrgMember" -PropertiesHash @{ParameterSet = $PSCmdlet.ParameterSetName}

    # Set up the message
    $message = '{"target":"InviteRoleFilledByOrg","arguments":["' + $Id + '","' + $Role + '","' + $Org + '"],"invocationId":"28","type":1}'

    # Send the message
    Send-PlugEventsMessage -Message $message

    # Receive the response
    $response = Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive

    # Convert the response from JSON
    $result = ($response | ConvertFrom-Json).result

    if (-not $result.isSuccess) {
        throw "Plug Events: Add-PlugEventsOrgMember failed. Error $($result.errorCode): $($result.message)"
    }

    $result
}


function Connect-PlugEvents {
    <#
    .SYNOPSIS
        Connect to Plug.Events

    .DESCRIPTION
        Connect to Plug.Events. Optionally authenticate with a Plug.Events account
        by supplying a -Credential object containing your email address and password.

    .PARAMETER Endpoint
        Endpoint to connect to. When not entered it will retrieve the first production endpoint by default.

    .PARAMETER ConnectionToken
        Token to use in the connection. When not entered it will retrieve this automatically.

    .PARAMETER Credential
        PSCredential object containing the Plug.Events account email address (username)
        and password. The password is sent in plain text over the WebSocket connection,
        which is itself secured by TLS (wss://).

    .PARAMETER SkipWarning
        Suppress the plain-text password confirmation prompt. Use this for unattended
        or automated scenarios.

    .EXAMPLE
        Connect to Plug.Events anonymously:

        PS> Connect-PlugEvents

    .EXAMPLE
        Connect and authenticate with a credential:

        PS> $cred = Get-Credential
        PS> Connect-PlugEvents -Credential $cred

    .EXAMPLE
        Connect and authenticate without the plain-text warning (unattended):

        PS> $cred = Get-Credential
        PS> Connect-PlugEvents -Credential $cred -SkipWarning
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Its the name of the product')]

    [CmdLetBinding(DefaultParameterSetName = 'Anonymous')]
    Param (
        [Parameter(Mandatory = $false, Position = 1)]
        [String] $Endpoint = (Get-PlugEventsEndpoint -Type p -First 1).Types.Endpoint,

        [Parameter(Mandatory = $false, Position = 2)]
        [String] $ConnectionToken = (Open-PlugEventsWebsocket -Endpoint $Endpoint).connectionToken,

        [Parameter(Mandatory = $true, ParameterSetName = 'Authenticated')]
        [System.Management.Automation.PSCredential] $Credential,

        [Parameter(Mandatory = $false, ParameterSetName = 'Authenticated')]
        [Switch] $SkipWarning
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Connect-PlugEvents" -PropertiesHash @{Authenticated = ($PSCmdlet.ParameterSetName -eq 'Authenticated')}

    # Reset authentication state on each new connection
    $Script:isAuthenticated = $false

    # Create the websocket client and cancellation token
    $Script:websocket = [System.Net.WebSockets.ClientWebSocket]::new()
    $Script:cancellationToken = [System.Threading.CancellationTokenSource]::new()

    # Add the option for json
    $Script:websocket.Options.AddSubProtocol('json')

    # Connect
    $uriObj = [Uri]"wss://$Endpoint/hub1?id=$ConnectionToken"
    $null = $Script:websocket.ConnectAsync($uriObj, $Script:cancellationToken.Token).GetAwaiter().GetResult()

    # Send a message to establish the handshake
    Send-PlugEventsMessage -Message '{"protocol":"json","version":1}'

    # Check for a message
    $message = Receive-PlugEventsMessage -IgnoreKeepAlive
    if($message -ne "{}") {
        throw "Plug Events: the connection could not be established. Error message: $message"
    }

    # Authenticate if credentials were supplied
    if ($PSCmdlet.ParameterSetName -eq 'Authenticated') {

        # Warn the user about plain-text password transmission unless suppressed
        if (-not $SkipWarning) {
            Write-Warning "Your password will be sent in plain text over the WebSocket connection. The connection is secured by TLS (wss://), so it is still protected in transit."
            $confirmation = Read-Host "Type 'yes' or 'y' to continue"
            if ($confirmation -ne 'yes' -and $confirmation -ne 'y') {
                Disconnect-PlugEvents
                throw "Plug Events: authentication aborted by the user."
            }
        }

        # Build the authentication message
        $email    = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
        $authMessage = '{"target":"Authenticate2","arguments":["' + $email + '","' + $password + '",null],"invocationId":"6","type":1}'

        # Send the authentication message
        Send-PlugEventsMessage -Message $authMessage

        # Receive the authentication response
        $authResponse = Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive
        $authResult   = ($authResponse | ConvertFrom-Json).result

        if (-not $authResult.isSuccess) {
            Disconnect-PlugEvents
            throw "Plug Events: authentication failed. Error $($authResult.errorCode): $($authResult.message)"
        }

        $Script:isAuthenticated = $true
    }
}

function Disconnect-PlugEvents {
    <#
    .SYNOPSIS
        Disconnect from Plug.Events

    .DESCRIPTION
        Disconnect from Plug.Events

    .EXAMPLE
        Disconnect

        PS> Disconnect-PlugEvents
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Its the name of the product')]

    [CmdLetBinding()]
    Param ()

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Disconnect-PlugEvents"

    # Reset authentication state
    $Script:isAuthenticated = $false

    # Close the connection
    $null = $Script:websocket.CloseAsync(
        [System.Net.WebSockets.WebSocketCloseStatus]::Empty,
        "",
        $Script:cancellationToken.Token
    )

    # Dispose of the objects
    $Script:websocket.Dispose()
    $Script:cancellationToken.Dispose()
}

function Get-PlugEventsCancellationToken {
    <#
    .SYNOPSIS
        Get the CancellationToken for the connection to Plug.Events

    .DESCRIPTION
        Get the CancellationToken for the connection to Plug.Events

    .EXAMPLE
        Get the token

        PS> Get-PlugEventsCancellationToken
    #>

    [CmdLetBinding()]
    Param ()

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsCancellationToken"

    # Return the cancellationtoken object
    $Script:cancellationToken
}

function Get-PlugEventsConnection {
    <#
    .SYNOPSIS
        Get the object that contains the websocketconnection to plug.events

    .DESCRIPTION
        Get the object that contains the websocketconnection to plug.events

    .EXAMPLE
        Get the connection

        PS> Get-PlugEventsConnection
    #>

    [CmdLetBinding()]
    Param ()

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsConnection"

    # Return the websocket object
    $Script:websocket
}

function Get-PlugEventsEndpoint {
    <#
    .SYNOPSIS
        Return the endpoints for plug.events backend servers.

    .DESCRIPTION
        Return the endpoints for plug.events backend servers.

    .PARAMETER Type
        Type of the server. Can be p or i.

    .PARAMETER First
        Amount of entries to return.

    .EXAMPLE
        Get all endpoints

        PS> Get-PlugEventsEndpoint
        Id                 Types
        --                 -----
        639009792141241401 {@{Type=p; Endpoint=pi31.plug.events}, @{Type=i; Endpoint=ii31.plug.events}}
        639003195191559039 {@{Type=p; Endpoint=pi30.plug.events}, @{Type=i; Endpoint=ii30.plug.events}}

    .EXAMPLE
        Get first endpoint

        PS> Get-PlugEventsEndpoint -First 1
        Id                 Types
        --                 -----
        639009792141241401 {@{Type=p; Endpoint=pi31.plug.events}, @{Type=i; Endpoint=ii31.plug.events}}

    .EXAMPLE
        Get first endpoint of type p

        PS> Get-PlugEventsEndpoint -Type p -First 1
        Id                 Types
        --                 -----
        639009792141241401 {@{Type=p; Endpoint=pi31.plug.events}}
    #>

    [CmdLetBinding()]
    [OutputType([Array])]

    Param (
        [Parameter(Mandatory = $false, Position = 1)]
        [String] $Type = "none",

        [Parameter(Mandatory = $false, Position = 2)]
        [Int] $First = 0
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsEndpoint" -PropertiesHash @{Type = $Type; First = $First }

    # Get all the endpoints from the txt file
    $nodemap = Invoke-RestMethod -uri "https://www.plug.events/nodemap.txt" -Method GET

    # Parse the endpoints
    $endpoints = @()
    $nodemap | ConvertFrom-Csv -Header "id", "endpoints" | ForEach-Object {
        # Create an object
        $node = [PSCustomObject]@{
            Id = $_.Id
            Types = @()
        }

        # Split the different types
        foreach ($endpoint in $_.endpoints.split("|")) {
            # Check for the type
            if($Type -ne "none") {
                if($Type -ne $endpoint[0]) {
                    Continue
                }
            }

            $node.Types += [PSCustomObject]@{
                Type = $endpoint[0]
                Endpoint = $endpoint
            }
        }

        # Add the node to the endpoint array
        $endpoints += $node
    }

    # Filter amount
    if($First -gt 0) {
        $endpoints = $endpoints | Select-Object -First $First
    }

    $endpoints
}

function Get-PlugEventsEventView {
    <#
    .SYNOPSIS
        Get the full event view for a specific event in Plug.Events.

    .DESCRIPTION
        Sends a GetEventView request over the Plug.Events websocket and returns
        the result object for the specified event slug.

    .PARAMETER Id
        Slug of the event to retrieve the view for.

    .EXAMPLE
        Get the event view for "my-event-2026":

        PS> Get-PlugEventsEventView -Id "my-event-2026"
    #>

    [CmdLetBinding()]
    [OutputType([Object])]
    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [String] $Id
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsEventView"

    # Set up the message
    $message = '{"target":"GetEventView","arguments":["' + $Id + '"],"invocationId":"1","type":1}'

    # Send the message
    Send-PlugEventsMessage -Message $message

    # Receive the response
    $response = Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive

    # Convert the response from JSON
    ($response | ConvertFrom-Json).result
}


function Get-PlugEventsOrg {
    <#
    .SYNOPSIS
        Search and return organizations from Plug.Events.

    .DESCRIPTION
        Sends a search request over the Plug.Events websocket and returns
        the matching organization items. Use `-Filter` to search
        by name or description, and optional slugs to narrow by interest,
        sub-interest, or locale. The function returns the raw items array
        from the websocket response.

    .PARAMETER Filter
        Search term to match organization names or descriptions. Optional.

    .PARAMETER Interest
        Slug of the interest category to filter organizations. Optional.

    .PARAMETER SubInterest
        Slug of the sub-interest category to filter organizations. Optional.

    .PARAMETER Locale
        Locale slug to filter organizations. Optional.

    .PARAMETER Top
        Maximum number of organization items to return. Default is 999.

    .EXAMPLE
        Retrieve up to 50 organization results matching "balfolk":

        PS> Get-PlugEventsOrg -Filter "balfolk" -Top 50

    .NOTES
        This function requires an active Plug.Events websocket connection
        and uses the module's websocket messaging helpers (Send-PlugEventsMessage
        / Receive-PlugEventsMessage).
    #>

    [CmdLetBinding()]
    [OutputType([Array])]
    Param (
        [Parameter(Mandatory = $false, Position = 1)]
        [String] $Filter ,

        [Parameter(Mandatory = $false, Position = 2)]
        [String] $Interest ,

        [Parameter(Mandatory = $false, Position = 3)]
        [String] $SubInterest ,

        [Parameter(Mandatory = $false, Position = 4)]
        [String] $Locale ,

        [Parameter(Mandatory = $false, Position = 5)]
        [Int] $Top = 999
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsOrg" -PropertiesHash @{Top = $Top}

    # Set up the message
    $si = if ($SubInterest) { """$SubInterest""" } else { "null" }
    $li = if ($Locale) { """$Locale""" } else { "null" }
    $ii = if ($Interest) { """$Interest""" } else { "null" }
    $fi = if ($Filter) { """$Filter""" } else { "null" }
    $message = '{"target":"CapitalInSpaceSearch","arguments":[{"sortOrder":"AlphaByName","mode":"Single","criteria":{"subinterest":' + $si + ',"localeSlug":' + $li + ',"interestSlug":' + $ii + ',"ultracollapseCode":null,"ccKind":1,"minTime":null,"maxTime":null,"searchTerm":' + $fi + '},"nExpandedResults":' + $Top + ',"nCollapsedResults": 0}],"invocationId":"32","type":1}'

    # Send the message
    Send-PlugEventsMessage -Message $message

    # Receive the response
    $response = Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive

    # Convert the response from JSON
    ($response | ConvertFrom-Json).result.items
}

function Get-PlugEventsOrgView {
    <#
    .SYNOPSIS
        Get the full organization view for a specific organization in Plug.Events.

    .DESCRIPTION
        Sends a GetOrgView request over the Plug.Events websocket and returns
        the result object for the specified organization slug.

    .PARAMETER Id
        Slug of the organization to retrieve the view for.

    .EXAMPLE
        Get the organization view for "balfolk-nl":

        PS> Get-PlugEventsOrgView -Id "balfolk-nl"
    #>

    [CmdLetBinding()]
    [OutputType([Object])]
    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [String] $Id
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsOrgView"

    # Set up the message
    $message = '{"target":"GetOrgView","arguments":["' + $Id + '"],"invocationId":"1","type":1}'

    # Send the message
    Send-PlugEventsMessage -Message $message

    # Receive the response
    $response = Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive

    # Convert the response from JSON
    ($response | ConvertFrom-Json).result
}


function Get-PlugEventsUmbrellaEvent {
    <#
    .SYNOPSIS
        Get all events under a specific umbrella in Plug.Events

    .DESCRIPTION
        Get all events under a specific umbrella in Plug.Events

    .PARAMETER Id
        Id of the umbrella org

    .PARAMETER StartDate
        DateTime object containing the date to start filtering from. Default is 30 days in the past.

    .PARAMETER EndDate
        DateTime object containing the date to stop filtering from. Default is today.

    .PARAMETER Top
        Maximum amount of items to return. Default is 999.

    .EXAMPLE
        Get the events

        PS> Get-PlugEventsUmbrellaEvent -Id "balfolk-nl" -StartDate (Get-Date "2025-01-01") -EndDate (Get-Date "2025-12-31") -Top 200
    #>

    [CmdLetBinding()]
    [OutputType([Array])]
    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [String] $Id,

        [Parameter(Mandatory = $false, Position = 2)]
        [DateTime] $StartDate = (Get-Date).AddDays(-30),

        [Parameter(Mandatory = $false, Position = 3)]
        [DateTime] $EndDate = (Get-Date),

        [Parameter(Mandatory = $false, Position = 4)]
        [Int] $Top = 999
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Get-PlugEventsUmbrellaEvent" -PropertiesHash @{Top = $Top}

    # Set up the message
    $message = '{"target":"GetNetworkViewPage2","arguments":[{"recKind":1,"slug":"'+$Id+'","slugs":null,"direction":103,"startAt":0,"maxCount":'+$Top+',"nameContains":"","roleSlugFilters":null,"isClaimed":null,"seq1Filter":null,"seq1InverseFilter":null,"minEventTime":"'+($StartDate | Get-Date -Format "yyyyMMdd0000")+'","maxEventTime":"'+($EndDate | Get-Date -Format "yyyyMMdd0000")+'","interestSlug":null,"subinterest":null,"localeSlug":null,"toRoleNameContains":""}],"invocationId":"9","type":1}'

    # Send the message
    Send-PlugEventsMessage -Message $message

    # Receive the response
    $response = Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive

    # Convert the response from JSON
    ($response | ConvertFrom-Json).result.directionSets.items
}

function Open-PlugEventsWebsocket {
    <#
    .SYNOPSIS
        Open a websocket connection to plug.events and return the connectionToken.

    .DESCRIPTION
        Open a websocket connection to plug.events and return the connectionToken.

    .PARAMETER Endpoint
        Endpoint to connect to. When not entered it will retrieve the first production endpoint by default.

    .EXAMPLE
        Open the connection

        PS> Open-PlugEventsWebsocket
        negotiateVersion connectionId           connectionToken        availableTransports
        ---------------- ------------           ---------------        -------------------
                       1 abcdefabcdefabcdefabcd abcdefabcdefabcdefabcd {@{transport=WebSockets; transferFormats=System.Object[]}, @{transport=ServerSentEvents; transferFormats=System…

    .EXAMPLE
        Open the connection for a specific endpoint

        PS> Open-PlugEventsWebsocket -Endpoint "pi31.plug.events"
        negotiateVersion connectionId           connectionToken        availableTransports
        ---------------- ------------           ---------------        -------------------
                       1 abcdefabcdefabcdefabcd abcdefabcdefabcdefabcd {@{transport=WebSockets; transferFormats=System.Object[]}, @{transport=ServerSentEvents; transferFormats=System…

    #>

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $false, Position = 1)]
        [String] $Endpoint = (Get-PlugEventsEndpoint -Type p -First 1).Types.Endpoint
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Open-PlugEventsWebsocket"

    # Open the connection
    Invoke-RestMethod -Uri "https://$Endpoint/hub1/negotiate?negotiateVersion=1" -Method POST
}

function Receive-PlugEventsMessage {
    <#
    .SYNOPSIS
        Receive a message from the plug.events back-end.

    .DESCRIPTION
        Receive a message from the plug.events back-end. The end-of-message marker will automatically be removed from the output.

    .PARAMETER Connection
        Connection object for the websocket connection. Default this will be the connection set up via Connect-PlugEvents

    .PARAMETER Timeout
        Maximum time in seconds to wait for a response before cancelling the request (this will close the connection). Default is 21 seconds.

    .PARAMETER IgnoreKeepAlive
        Ignore the keepalive messages and only return other types of messages.

    .EXAMPLE
        Receive the data

        PS> Receive-PlugEventsMessage -Timeout 30 -IgnoreKeepAlive
    #>

    [CmdLetBinding()]
    [OutputType([String])]
    Param (
        [Parameter(Mandatory = $false, Position = 1)]
        [Object] $Connection = $Script:websocket,

        [Parameter(Mandatory = $false, Position = 2)]
        [Int] $Timeout = 21,

        [Parameter(Mandatory = $false, Position = 3)]
        [Switch] $IgnoreKeepAlive
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Receive-PlugEventsMessage" -PropertiesHash @{Timeout = $Timeout; IgnoreKeepAlive = $IgnoreKeepAlive}

    # Check if a connection is create
    if($Connection.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "Plug-Events: no open connection was detected. Please run Connect-PlugEvents first."
    }

    # Create a buffer to store the message
    $buffer        = New-Object byte[] 8192
    $stringbuilder = [System.Text.StringBuilder]::new()

    # Extra variable to prevent unending loop
    $time = Get-Date

    while ($Connection.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        # Create an async call
        $cancellationToken = [System.Threading.CancellationTokenSource]::new($Timeout*1000)
        $await = $Connection.ReceiveAsync([ArraySegment[byte]]::new($buffer), $cancellationToken.Token)

        # Wait untill the response is returned
        while($await.Status -ne "RanToCompletion") {
            # Check if the timeout has been reached
            if ($await.Status -eq "Canceled") {
                throw "Plug-Events: the timeout of $Timeout seconds has been exceeded while waiting for a response from the server."
            }

            # Check if not in unending loop
            if((Get-Date) -gt $time.AddSeconds($Timeout)) {
                $null = $cancellationToken.Cancel()
                throw "Plug-Events: waiting for more then $Timeout seconds for a reply of server. request has been cancelled."
            }
        }

        # Get the result from the await
        $result = $await.GetAwaiter().GetResult()

        if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
            Disconnect-PlugEvents
            break
        }

        # Accumulate chunk(s) until EndOfMessage
        $null = $stringbuilder.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))

        # If the message is done convert the stringbuilder to a string and stop the loop
        if ($result.EndOfMessage) {
            $text = $stringbuilder.ToString()

            # Check if the message is a keepalive
            if ($IgnoreKeepAlive -and $text -eq '{"type":6}') {
                # Continue and clear the stringbuilder
                $null = $stringbuilder.Clear()
            }
            else {
                # Break the loop
                break
            }
        }
    }

    # Check if the end of message character is still added
    if([int]$text[-1] -eq 30) {
        $text = $text.TrimEnd([char]0x1e)
    }

    # Return the message
    $text
}

function Send-PlugEventsMessage {
    <#
    .SYNOPSIS
        Send a message to the plug.events back-end.

    .DESCRIPTION
        Send a message to the plug.events back-end.

    .PARAMETER Message
        The message to send in string format. If the end-of-message marker is not added this will be added automatically.

    .PARAMETER Connection
        Connection object for the websocket connection. Default this will be the connection set up via Connect-PlugEvents

    .PARAMETER Timeout
        Maximum time in seconds to wait for a response before cancelling the request (this will close the connection). Default is 5 seconds.

    .PARAMETER Async
        Dont wait on confirmation that the message has been send.

    .EXAMPLE
        Send the message

        PS> $Message = '{"target":"GetLocalesBySlug","arguments":[["netherlands"]],"invocationId":"1","type":1}'
        PS> Send-PlugEventsMessage -Message $Message -Timeout 10 -Async
    #>

    [CmdLetBinding()]
    [OutputType([String])]
    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [String] $Message,

        [Parameter(Mandatory = $false, Position = 2)]
        [Object] $Connection = $Script:websocket,

        [Parameter(Mandatory = $false, Position = 3)]
        [Int] $Timeout = 5,

        [Parameter(Mandatory = $false, Position = 4)]
        [Switch] $Async
    )

    # Send telemetry data
    Send-THEvent -ModuleName "plugEvents" -EventName "Receive-PlugEventsMessage" -PropertiesHash @{Timeout = $Timeout; Async = $Async}

    # Check if a connection is create
    if ($Connection.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "Plug-Events: no open connection was detected. Please run Connect-PlugEvents first."
    }

    # Check if end of message marker is added (0x1e = 30)
    if ([int]$Message[-1] -ne 30) {
        $Message += [char]0x1e
    }

    # Create byte array
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
    $seg = [ArraySegment[byte]]::new($bytes)

    # Send the message
    $cancellationToken = [System.Threading.CancellationTokenSource]::new($Timeout * 1000)
    $await = $Connection.SendAsync(
        $seg,
        [System.Net.WebSockets.WebSocketMessageType]::Text,
        $true,
        $cancellationToken.Token
    )

    if ( -not $Async) {
        # Extra variable to prevent unending loop
        $time = Get-Date

        # Wait untill the message is semd
        while ($await.Status -ne "RanToCompletion") {
            # Check if the timeout has been reached
            if ($await.Status -eq "Canceled") {
                throw "Plug-Events: the timeout of $Timeout seconds has been exceeded while waiting for a response from the server."
            }

            # Check if not in unending loop
            if ((Get-Date) -gt $time.AddSeconds($Timeout)) {
                $null = $cancellationToken.Cancel()
                throw "Plug-Events: waiting for more then $Timeout seconds for a reply of server. request has been cancelled."
            }
        }
    }
}

# ===================================================================
# ================== WEBSOCKET ======================================
# ===================================================================

# Create env variables
$Script:websocket = [System.Net.WebSockets.ClientWebSocket]::new()
$Script:cancellationToken = [System.Threading.CancellationTokenSource]::new()
$Script:isAuthenticated = $false

# ===================================================================
# ================== TELEMETRY ======================================
# ===================================================================

# Create env variables
$Env:PLUGEVENTS_TELEMETRY_OPTIN = (-not $Evn:POWERSHELL_TELEMETRY_OPTOUT) # use the invert of default powershell telemetry setting

# Set up the telemetry
Initialize-THTelemetry -ModuleName "plugEvents"
Set-THTelemetryConfiguration -ModuleName "plugEvents" -OptInVariableName "PLUGEVENTS_TELEMETRY_OPTIN" -StripPersonallyIdentifiableInformation $true -Confirm:$false
Add-THAppInsightsConnectionString -ModuleName "plugEvents" -ConnectionString "InstrumentationKey=df9757a1-873b-41c6-b4a2-2b93d15c9fb1;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"

# Create a message about the telemetry
Write-Information ("Telemetry for plugEvents module is $(if([string] $Env:PLUGEVENTS_TELEMETRY_OPTIN -in ("no","false","0")){"NOT "})enabled. Change the behavior by setting the value of " + '$Env:PLUGEVENTS_TELEMETRY_OPTIN') -InformationAction Continue

# Send a metric for the installation of the module
Send-THEvent -ModuleName "plugEvents" -EventName "Import Module plugEvents"