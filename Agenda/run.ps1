using namespace System.Net

param($Request, $TriggerMetadata)

# ---------------------------------------------------------------------------
# Parse POST JSON body
# ---------------------------------------------------------------------------
try {
    $body = $Request.Body | ConvertFrom-Json -ErrorAction Stop
} catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'Request body must be valid JSON.'
    })
    return
}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------
$email     = $body.Email
$removeKey = $body.RemoveKey
$umbrella  = $body.Umbrella
$weeksRaw  = $body.Weeks
$latRaw    = $body.Lat
$lonRaw    = $body.Lon

if (-not $email -or -not $removeKey -or -not $umbrella -or -not $weeksRaw) {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = 'Missing required parameter(s): Email, RemoveKey, Umbrella, Weeks.'
    })
    return
}

try { $weeks = [int]$weeksRaw }
catch {
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body       = "'Weeks' must be a valid integer."
    })
    return
}

$lat = $null; $lon = $null
if ($latRaw) { try { $lat = [double]$latRaw } catch { } }
if ($lonRaw) { try { $lon = [double]$lonRaw } catch { } }
$hasLocation = ($null -ne $lat -and $null -ne $lon)

# ---------------------------------------------------------------------------
# Date range — end = today + (weeks * 7) + 1 day for overlap
# Example: today = 14 jul, weeks = 1  →  endDate = 22 jul
# ---------------------------------------------------------------------------
$startDate = (Get-Date).Date
$endDate   = $startDate.AddDays($weeks * 7 + 1)

Write-Host "Agenda | umbrella=$umbrella weeks=$weeks start=$($startDate.ToString('yyyy-MM-dd')) end=$($endDate.ToString('yyyy-MM-dd')) hasLocation=$hasLocation"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# plug.events timestamps are yyyyMMddHHmm strings (e.g. "202607141930")
function ConvertTo-PlugDateTime([string]$ts) {
    if (-not $ts) { return $null }
    try {
        return [DateTime]::ParseExact(
            $ts.PadRight(12, '0').Substring(0, 12),
            'yyyyMMddHHmm',
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    } catch {
        try { return [DateTime]$ts } catch { return $null }
    }
}

# Dutch short date — "ma 13 jul 2026"
function Format-DutchDate([DateTime]$dt) {
    $days   = @('zo', 'ma', 'di', 'wo', 'do', 'vr', 'za')
    $months = @($null, 'jan', 'feb', 'mrt', 'apr', 'mei', 'jun',
                'jul', 'aug', 'sep', 'okt', 'nov', 'dec')
    "$($days[[int]$dt.DayOfWeek]) $($dt.Day) $($months[$dt.Month]) $($dt.Year)"
}

# ---------------------------------------------------------------------------
# Fetch events
# ---------------------------------------------------------------------------
Connect-PlugEvents

$rawEvents = Get-PlugEventsUmbrellaEvent -Id $umbrella -StartDate $startDate -EndDate $endDate
Write-Host "Raw events returned: $($rawEvents.Count)"

# Expand recurring events (toSegments) into individual occurrences
$occurrences = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($evt in $rawEvents) {
    if ($evt.toSegments -and $evt.toSegments.Count -gt 0) {
        # Recurring event — each segment is one occurrence
        foreach ($seg in $evt.toSegments) {
            $tsVal = if ($seg.PSObject.Properties['toEventStartTime']) { $seg.toEventStartTime }
                     elseif ($seg.PSObject.Properties['startTime'])    { $seg.startTime }
                     else                                              { $null }
            $dt = ConvertTo-PlugDateTime ([string]$tsVal)
            if ($null -ne $dt -and $dt -ge $startDate -and $dt -le $endDate) {
                $occurrences.Add([PSCustomObject]@{
                    Slug      = $evt.toSlug
                    Name      = $evt.toName
                    StartTime = $dt
                })
            }
        }
    } else {
        $dt = ConvertTo-PlugDateTime ([string]$evt.toEventStartTime)
        if ($null -ne $dt) {
            $occurrences.Add([PSCustomObject]@{
                Slug      = $evt.toSlug
                Name      = $evt.toName
                StartTime = $dt
            })
        }
    }
}

$sorted = @($occurrences | Sort-Object StartTime)
Write-Host "Occurrences after expansion: $($sorted.Count)"

# ---------------------------------------------------------------------------
# Build table rows and collect Geoapify map markers
# ---------------------------------------------------------------------------
$geoapifyKey = $env:GEOAPIFY_API_KEY
$rowBuffer   = [System.Text.StringBuilder]::new()
$markerList  = [System.Collections.Generic.List[string]]::new()

foreach ($occ in $sorted) {
    Write-Host "Fetching details for '$($occ.Slug)'"
    $d = Get-PlugEventsEventView -Id $occ.Slug

    $city   = $d.venueLocale.name6
    $evtLat = $d.venueLocale.minlat
    $evtLon = $d.venueLocale.minlon

    # Price — try ticketTypes first, fall back to top-level price fields
    $priceDisplay = '—'
    if ($d.ticketTypes -and $d.ticketTypes.Count -gt 0) {
        $prices = @($d.ticketTypes |
            Where-Object { $null -ne $_.price } |
            Select-Object -ExpandProperty price)
        if ($prices.Count -gt 0) {
            $minPrice     = ($prices | Measure-Object -Minimum).Minimum
            $priceDisplay = ([double]$minPrice).ToString('€0.00')
        }
    } elseif ($null -ne $d.minPrice) {
        $priceDisplay = ([double]$d.minPrice).ToString('€0.00')
    } elseif ($null -ne $d.price) {
        $priceDisplay = ([double]$d.price).ToString('€0.00')
    }

    $dateStr  = Format-DutchDate $occ.StartTime
    $nameEnc  = [System.Net.WebUtility]::HtmlEncode($occ.Name)
    $cityEnc  = [System.Net.WebUtility]::HtmlEncode([string]$city)
    $eventUrl = "https://www.plug.events/event/$($occ.Slug)"

    # Optional distance column
    $distTd = ''
    if ($hasLocation -and $evtLat -and $evtLon) {
        try {
            $dist = Find-GeoCodeDistance `
                -OriginLatitude       $lat `
                -OriginLongitude      $lon `
                -DestinationLatitude  ([double]$evtLat) `
                -DestinationLongitude ([double]$evtLon) `
                -Provider             OSM
            $km     = [math]::Round($dist.Distance.Kilometers, 0)
            $distTd = "        <td>$km km</td>`n"
        } catch {
            $distTd = "        <td>—</td>`n"
        }
    }

    [void]$rowBuffer.Append(@"
      <tr>
        <td><a href="$eventUrl">$nameEnc</a></td>
        <td>$dateStr</td>
        <td>$cityEnc</td>
        <td>$priceDisplay</td>
$($distTd)      </tr>
"@)

    if ($evtLat -and $evtLon) {
        $markerList.Add("lonlat:$evtLon,$evtLat")
    }
}

Disconnect-PlugEvents

# ---------------------------------------------------------------------------
# Geoapify static map — embedded as base64 so the email has no external links
# ---------------------------------------------------------------------------
$mapHtml = '<p><em>Geen kaart beschikbaar.</em></p>'
if ($markerList.Count -gt 0 -and $geoapifyKey) {
    $markerStr = $markerList -join '|'
    $mapUrl    = "https://maps.geoapify.com/v1/staticmap?style=osm-bright" +
                 "&width=750&height=900&center=lonlat:5.289222,52.160197&zoom=7.049" +
                 "&marker=$markerStr&apiKey=$geoapifyKey"
    try {
        $imgBytes = (Invoke-WebRequest -Uri $mapUrl -UseBasicParsing).Content
        $b64      = [Convert]::ToBase64String($imgBytes)
        $mapHtml  = "<img src=`"data:image/png;base64,$b64`" alt=`"Kaart met evenementen`" style=`"max-width:100%;height:auto;display:block;`" />"
    } catch {
        Write-Warning "Failed to generate map: $_"
    }
}

# ---------------------------------------------------------------------------
# Unsubscribe link — base64url (RFC 4648 §5) encoded email
# ---------------------------------------------------------------------------
$emailB64 = ([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($email))) `
              -replace '\+', '-' -replace '/', '_' -replace '=', ''
$unsubUrl = "https://plugeventstools.balfolkworkshop.com/pages/unsubscribe.html?id=$emailB64&RemoveKey=$removeKey"

# ---------------------------------------------------------------------------
# Compose HTML body
# ---------------------------------------------------------------------------
$distTh = if ($hasLocation) { '        <th>Afstand</th>' + [Environment]::NewLine } else { '' }

$htmlBody = @"
<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8" />
  <style>
    body  { font-family: Arial, sans-serif; font-size: 14px; color: #222; margin: 20px; }
    table { border-collapse: collapse; width: 100%; margin: 12px 0; }
    th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; vertical-align: top; }
    th { background-color: #f5f5f5; font-weight: bold; }
    a  { color: #0072c6; text-decoration: none; }
    a:hover { text-decoration: underline; }
  </style>
</head>
<body>
  <p>Beste,</p>
  <p>Hier vind je de evenementen voor <strong>$umbrella</strong> voor de komende <strong>$weeks</strong> weken:</p>

  <table>
    <thead>
      <tr>
        <th>Evenement</th>
        <th>Datum</th>
        <th>Locatie</th>
        <th>Prijs</th>
$($distTh)      </tr>
    </thead>
    <tbody>
$($rowBuffer.ToString())    </tbody>
  </table>

  <p>Hier kan je een kaart vinden met daarop alle evenementen:</p>
  $mapHtml

  <p>Als je wilt afmelden voor deze email klik dan op de volgende link:<br />
  <a href="$unsubUrl">Afmelden</a></p>
</body>
</html>
"@

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode  = [HttpStatusCode]::OK
    ContentType = 'text/html; charset=utf-8'
    Body        = $htmlBody
})
