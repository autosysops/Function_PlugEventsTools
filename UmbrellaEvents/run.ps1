using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

# Check the parameters
$umbrella = $Request.Query.Umbrella
if (-not $umbrella) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Please pass an 'Umbrella' parameter in the url."
        })
}

$startdate = $Request.Query.StartDate
try {
    $startdate = Get-Date $startdate
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Please pass a valid 'StartDate' parameter in the url. This should be in the format 'YYYY-MM-DD'."
        })
}

$enddate = $Request.Query.EndDate
try {
    $enddate = Get-Date $enddate
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Please pass a valid 'EndDate' parameter in the url. This should be in the format 'YYYY-MM-DD'."
        })
}

$top = $Request.Query.Top
try {
    $top = [int]$top
}
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Please pass a valid 'Top' parameter in the url. This should be an integer."
        })
}

$format = $Request.Query.Format
if (-not $format) {
    $format = "JSON"
}

if ($format -ne "JSON" -and $format -ne "CSV") {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = "Please pass a valid 'Format' parameter in the url. This should be either 'JSON' or 'CSV'."
        })
}

Write-Host "Getting Umbrella Events for Umbrella: $umbrella, StartDate: $startdate, EndDate: $enddate, Top: $top"

# Get the output
Connect-PlugEvents
$response = Get-PlugEventsUmbrellaEvent -Id $umbrella -StartDate $startdate -EndDate $enddate -Top $top

Write-Host "Retrieved $($response.Count) events."

if ($format -eq "CSV") {
    # Convert the response to CSV
    $response = $response | Select-Object @{Name = "Name"; Expression = { $_.toName } }, @{Name = "Subtitle"; Expression = { $_.toSubtitle } }, @{Name = "Date"; Expression = { $_.toEventReadableTime } }, @{Name = "Link"; Expression = { "https://www.plug.events/event/" + $_.toSlug } } | ConvertTo-Csv -Delimiter ";" | Out-String

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::OK
        ContentType = "text/csv"
        Headers     = @{'Content-Disposition' = 'attachment;filename=response.csv' }
        Body        = $response
    })
}

if ($format -eq "JSON") {
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $response
        })
}

# Disconnect from plug.events
Disconnect-PlugEvents