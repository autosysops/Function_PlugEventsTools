using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Parse Top parameter (match UmbrellaEvents behavior)
$top = $Request.Query.Top
try {
    $top = [int]$top
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Please pass a valid 'Top' parameter in the url. This should be an integer."
        })
    return
}

# Parse Filter parameter (string). If empty or not provided, do not pass to cmdlet.
$filter = $Request.Query.Filter

Write-Host "Getting Orgs, Top: $top, Filter: $filter"

# Connect and fetch orgs using splatting so we only pass present parameters
Connect-PlugEvents
$params = @{}
if ($top -ne $null -and $top -ne 0) { $params.Top = $top }
if ($filter -ne $null -and $filter -ne '') { $params.Filter = $filter }

$response = Get-PlugEventsOrg @params

Write-Host "Retrieved $($response.Count) orgs."

# Return JSON response
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = $response
})

# Disconnect
Disconnect-PlugEvents
