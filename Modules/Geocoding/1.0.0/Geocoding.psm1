function ConvertFrom-GeoAzureMapsDistanceOutput {
    <#
    .SYNOPSIS
        Convert route output from Azure Maps to uniform output format.

    .DESCRIPTION
        Convert route directions output from Azure Maps to the uniform distance
        output format used by Find-GeoCodeDistance.

    .PARAMETER Resource
        The raw response object returned by Find-GeoCodeDistanceAzureMaps.

    .EXAMPLE
        Convert the output

        PS> ConvertFrom-GeoAzureMapsDistanceOutput -Resource $output
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The product is called like this.')]

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object] $Resource
    )

    Write-Debug "[AzureMaps] convert distance output"

    $summary   = $Resource.routes[0].summary
    $delaySecs = $summary.trafficDelayInSeconds

    $trafficDelay = if ($null -ne $delaySecs -and $delaySecs -gt 0) {
        [TimeSpan]::FromSeconds($delaySecs)
    }
    else {
        $null
    }

    return [PSCustomObject]@{
        "Distance"     = [PSCustomObject]@{
            "Meters" = $summary.lengthInMeters
        }
        "Duration"     = [TimeSpan]::FromSeconds($summary.travelTimeInSeconds)
        "TrafficDelay" = $trafficDelay
    }
}

function ConvertFrom-GeoAzureMapsOutput {
    <#
    .SYNOPSIS
        Convert output from Azure Maps to uniform output format.

    .DESCRIPTION
        Convert output from Azure Maps to uniform output format.

    .PARAMETER Resource
        The output from Azure Maps

    .EXAMPLE
        Convert the output

        PS> ConvertFrom-GeoAzureMapsOutput -Resource $output
    #>

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object] $Resource
    )

    Write-Debug "[AzureMaps] convert output"

    return [PSCustomObject]@{
        "Coordinates" = [PSCustomObject]@{
            "Latitude"  = $Resource.geometry.coordinates[1]
            "Longitude" = $Resource.geometry.coordinates[0]
        }
        "Address"     = [PSCustomObject]@{
            "Street Address" = if($Resource.properties.address.addressLine){$Resource.properties.address.addressLine}else{$null}
            "Locality"       = if($Resource.properties.address.locality){$Resource.properties.address.locality}else{$null}
            "Region"         = if($Resource.properties.address.adminDistricts){$Resource.properties.address.adminDistricts[0].shortName}else{$null}
            "Postal Code"    = if($Resource.properties.address.postalCode){$Resource.properties.address.postalCode}else{$null}
            "Country"        = if($Resource.properties.address.countryRegion.name){$Resource.properties.address.countryRegion.name}else{$null}
        }
        "Boundingbox" = [PSCustomObject]@{
            "South Latitude" = $Resource.bbox[1]
            "West Longitude" = $Resource.bbox[0]
            "North Latitude" = $Resource.bbox[3]
            "East Longitude" = $Resource.bbox[2]
        }
    }
}


function ConvertFrom-GeoGoogleMapsDistanceOutput {
    <#
    .SYNOPSIS
        Convert distance output from Google Maps to uniform output format.

    .DESCRIPTION
        Convert distance matrix output from Google Maps to the uniform distance
        output format used by Find-GeoCodeDistance.

    .PARAMETER Resource
        The raw response object returned by Find-GeoCodeDistanceGoogleMaps.

    .EXAMPLE
        Convert the output

        PS> ConvertFrom-GeoGoogleMapsDistanceOutput -Resource $output
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The product is called like this.')]

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object] $Resource
    )

    Write-Debug "[GoogleMaps] convert distance output"

    $element  = $Resource.rows[0].elements[0]
    $baseSecs = $element.duration.value

    if ($element.duration_in_traffic) {
        $totalSecs    = $element.duration_in_traffic.value
        # Clamp to zero — negative delay (faster with traffic) is reported as no delay.
        $delaySecs    = [Math]::Max(0, $totalSecs - $baseSecs)
        # Always return a TimeSpan when traffic data was returned, even for zero delay.
        # A null TrafficDelay means "no traffic data", a zero TimeSpan means "no extra delay".
        $trafficDelay = [TimeSpan]::FromSeconds($delaySecs)
    }
    else {
        $totalSecs    = $baseSecs
        $trafficDelay = $null
    }

    return [PSCustomObject]@{
        "Distance"     = [PSCustomObject]@{
            "Meters" = $element.distance.value
        }
        "Duration"     = [TimeSpan]::FromSeconds($totalSecs)
        "TrafficDelay" = $trafficDelay
    }
}

function ConvertFrom-GeoGoogleMapsOutput {
    <#
    .SYNOPSIS
        Convert output from Google Maps to uniform output format.

    .DESCRIPTION
        Convert output from Google Maps to uniform output format.

    .PARAMETER Resource
        The output from Google Maps

    .EXAMPLE
        Convert the output

        PS> ConvertFrom-GeoGoogleMapsOutput -Resource $output
    #>

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object] $Resource
    )

    Write-Debug "[GoogleMaps] convert output"

    return [PSCustomObject]@{
        "Coordinates" = [PSCustomObject]@{
            "Latitude"  = $Resource.geometry.location.lat
            "Longitude" = $Resource.geometry.location.lng
        }
        "Address"     = [PSCustomObject]@{
            "Street Address" = ($Resource.address_components | Where-Object {$_.types -like "*route*"}).long_name + " " + ($Resource.address_components | Where-Object {$_.types -like "*street_number*"}).long_name
            "Locality"       = ($Resource.address_components | Where-Object {$_.types -like "*locality*"}).long_name
            "Region"         = ($Resource.address_components | Where-Object {$_.types -like "*administrative_area_level_1*"}).long_name
            "Postal Code"    = ($Resource.address_components | Where-Object {$_.types -like "*postal_code*"}).long_name
            "Country"        = ($Resource.address_components | Where-Object {$_.types -like "*country*"}).long_name
        }
        "Boundingbox" = [PSCustomObject]@{
            "South Latitude" = $Resource.geometry.viewport.southwest.lat
            "West Longitude" = $Resource.geometry.viewport.southwest.lng
            "North Latitude" = $Resource.geometry.viewport.northeast.lat
            "East Longitude" = $Resource.geometry.viewport.northeast.lng
        }
    }
}


function ConvertFrom-GeoNominatimOutput {
    <#
    .SYNOPSIS
        Convert output from Open Street Maps to uniform output format.

    .DESCRIPTION
        Convert output from Open Street Maps to uniform output format.

    .PARAMETER Resource
        The output from Open Street Maps

    .EXAMPLE
        Convert the output

        PS> ConvertFrom-GeoNominatimOutput -Resource $output
    #>

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object] $Resource
    )

    Write-Debug "[OpenStreetMaps] convert output"

    return [PSCustomObject]@{
        "Coordinates" = [PSCustomObject]@{
            "Latitude"  = $Resource.lat
            "Longitude" = $Resource.lon
        }
        "Address"     = [PSCustomObject]@{
            "Street Address" = $Resource.address.road + " " + $Resource.address.house_number
            "Locality"       = $Resource.address.city
            "Region"         = $Resource.address.state
            "Postal Code"    = $Resource.address.postcode
            "Country"        = $Resource.address.country
        }
        "Boundingbox" = [PSCustomObject]@{
            "South Latitude" = $Resource.boundingbox[0]
            "West Longitude" = $Resource.boundingbox[2]
            "North Latitude" = $Resource.boundingbox[1]
            "East Longitude" = $Resource.boundingbox[3]
        }
    }
}


function ConvertFrom-GeoOsrmDistanceOutput {
    <#
    .SYNOPSIS
        Convert route output from OSRM to uniform output format.

    .DESCRIPTION
        Convert route output from OSRM (Open Source Routing Machine) to the
        uniform distance output format used by Find-GeoCodeDistance.

    .PARAMETER Resource
        The raw response object returned by Find-GeoCodeDistanceOsrm.

    .EXAMPLE
        Convert the output

        PS> ConvertFrom-GeoOsrmDistanceOutput -Resource $output
    #>

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Object] $Resource
    )

    Write-Debug "[OSRM] convert distance output"

    $route = $Resource.routes[0]

    return [PSCustomObject]@{
        "Distance"     = [PSCustomObject]@{
            "Meters" = [Math]::Round($route.distance, 0)
        }
        "Duration"     = [TimeSpan]::FromSeconds([Math]::Round($route.duration, 0))
        "TrafficDelay" = $null
    }
}

function Find-GeoCodeDistanceAzureMaps {
    <#
    .SYNOPSIS
        Calculate the route distance between two coordinates using Azure Maps.

    .DESCRIPTION
        Uses the Azure Maps Route Directions API to retrieve route distance and
        duration between an origin and a destination. Azure Maps includes live
        traffic data by default for car routing.

    .PARAMETER OriginLatitude
        The latitude of the origin point.

    .PARAMETER OriginLongitude
        The longitude of the origin point.

    .PARAMETER DestinationLatitude
        The latitude of the destination point.

    .PARAMETER DestinationLongitude
        The longitude of the destination point.

    .PARAMETER ApiKey
        Azure Maps subscription key.

    .PARAMETER TravelMode
        The travel mode. Accepts Driving or Walking. Defaults to Driving.

    .PARAMETER DepartureTime
        Optional departure time as a DateTime for route planning.

    .PARAMETER ArrivalTime
        Optional desired arrival time as a DateTime. Only valid for Driving mode.

    .EXAMPLE
        Calculate driving distance

        PS> Find-GeoCodeDistanceAzureMaps -OriginLatitude 52.30 -OriginLongitude 4.75 -DestinationLatitude 53.56 -DestinationLongitude 9.92 -ApiKey "KEY"
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The product is called like this.')]

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Double] $OriginLatitude,

        [Parameter(Mandatory = $true, Position = 2)]
        [Double] $OriginLongitude,

        [Parameter(Mandatory = $true, Position = 3)]
        [Double] $DestinationLatitude,

        [Parameter(Mandatory = $true, Position = 4)]
        [Double] $DestinationLongitude,

        [Parameter(Mandatory = $true, Position = 5)]
        [String] $ApiKey,

        [Parameter(Mandatory = $false, Position = 6)]
        [ValidateSet('Driving', 'Walking')]
        [String] $TravelMode = 'Driving',

        [Parameter(Mandatory = $false)]
        [DateTime] $DepartureTime,

        [Parameter(Mandatory = $false)]
        [DateTime] $ArrivalTime
    )

    $mode = switch ($TravelMode) {
        'Driving' { 'car'        }
        'Walking' { 'pedestrian' }
    }

    $uri = "https://atlas.microsoft.com/route/directions/json?api-version=1.0&subscription-key=$ApiKey&query=$OriginLatitude,$OriginLongitude`:$DestinationLatitude,$DestinationLongitude&travelMode=$mode"

    if ($DepartureTime) {
        $formatted = $DepartureTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
        $uri += "&departAt=$([System.Web.HttpUtility]::UrlEncode($formatted))"
    }
    if ($ArrivalTime) {
        $formatted = $ArrivalTime.ToString("yyyy-MM-ddTHH:mm:sszzz")
        $uri += "&arriveAt=$([System.Web.HttpUtility]::UrlEncode($formatted))"
    }

    Write-Debug "[AzureMaps] Call uri: $uri"
    return Invoke-RestMethod -Uri $uri -Method GET
}

function Find-GeoCodeDistanceGoogleMaps {
    <#
    .SYNOPSIS
        Calculate the route distance between two coordinates using Google Maps.

    .DESCRIPTION
        Uses the Google Maps Distance Matrix API to retrieve route distance and
        duration between an origin and a destination.

    .PARAMETER OriginLatitude
        The latitude of the origin point.

    .PARAMETER OriginLongitude
        The longitude of the origin point.

    .PARAMETER DestinationLatitude
        The latitude of the destination point.

    .PARAMETER DestinationLongitude
        The longitude of the destination point.

    .PARAMETER ApiKey
        Google Maps API key.

    .PARAMETER TravelMode
        The travel mode. Accepts Driving, Walking or Transit. Defaults to Driving.

    .PARAMETER DepartureTime
        Optional departure time as a DateTime. For Driving mode this also enables
        traffic-aware routing.

    .PARAMETER ArrivalTime
        Optional arrival time as a DateTime. Only valid for Transit mode.

    .PARAMETER TrafficAware
        When set, requests real-time traffic data for Driving mode by setting the
        departure time to now if no explicit DepartureTime was provided.

    .EXAMPLE
        Calculate driving distance with traffic

        PS> Find-GeoCodeDistanceGoogleMaps -OriginLatitude 52.30 -OriginLongitude 4.75 -DestinationLatitude 53.56 -DestinationLongitude 9.92 -ApiKey "KEY" -TrafficAware
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'The product is called like this.')]

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Double] $OriginLatitude,

        [Parameter(Mandatory = $true, Position = 2)]
        [Double] $OriginLongitude,

        [Parameter(Mandatory = $true, Position = 3)]
        [Double] $DestinationLatitude,

        [Parameter(Mandatory = $true, Position = 4)]
        [Double] $DestinationLongitude,

        [Parameter(Mandatory = $true, Position = 5)]
        [String] $ApiKey,

        [Parameter(Mandatory = $false, Position = 6)]
        [ValidateSet('Driving', 'Walking', 'Transit')]
        [String] $TravelMode = 'Driving',

        [Parameter(Mandatory = $false)]
        [DateTime] $DepartureTime,

        [Parameter(Mandatory = $false)]
        [DateTime] $ArrivalTime,

        [Parameter(Mandatory = $false)]
        [Switch] $TrafficAware
    )

    $mode = switch ($TravelMode) {
        'Driving' { 'driving' }
        'Walking' { 'walking' }
        'Transit' { 'transit' }
    }

    $uri = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=$OriginLatitude,$OriginLongitude&destinations=$DestinationLatitude,$DestinationLongitude&mode=$mode&key=$ApiKey"

    if ($TravelMode -eq 'Driving' -and $TrafficAware -and -not $DepartureTime) {
        $uri += "&departure_time=now"
    }
    elseif ($DepartureTime) {
        $epoch = [System.DateTimeOffset]::new($DepartureTime).ToUnixTimeSeconds()
        $uri += "&departure_time=$epoch"
    }
    elseif ($ArrivalTime) {
        $epoch = [System.DateTimeOffset]::new($ArrivalTime).ToUnixTimeSeconds()
        $uri += "&arrival_time=$epoch"
    }

    Write-Debug "[GoogleMaps] Call uri: $uri"
    return Invoke-RestMethod -Uri $uri -Method GET
}

function Find-GeoCodeDistanceOsrm {
    <#
    .SYNOPSIS
        Calculate the route distance between two coordinates using OSRM.

    .DESCRIPTION
        Uses the Open Source Routing Machine (OSRM) HTTP API to retrieve route
        distance and duration between an origin and a destination.

    .PARAMETER OriginLatitude
        The latitude of the origin point.

    .PARAMETER OriginLongitude
        The longitude of the origin point.

    .PARAMETER DestinationLatitude
        The latitude of the destination point.

    .PARAMETER DestinationLongitude
        The longitude of the destination point.

    .PARAMETER TravelMode
        The travel mode. Accepts Driving or Walking. Defaults to Driving.

    .PARAMETER Server
        The base URL of the OSRM server. Defaults to the public demo server
        at http://router.project-osrm.org.

    .EXAMPLE
        Calculate driving distance

        PS> Find-GeoCodeDistanceOsrm -OriginLatitude 52.30 -OriginLongitude 4.75 -DestinationLatitude 53.56 -DestinationLongitude 9.92
    #>

    [CmdLetBinding()]
    [OutputType([Object])]

    Param (
        [Parameter(Mandatory = $true, Position = 1)]
        [Double] $OriginLatitude,

        [Parameter(Mandatory = $true, Position = 2)]
        [Double] $OriginLongitude,

        [Parameter(Mandatory = $true, Position = 3)]
        [Double] $DestinationLatitude,

        [Parameter(Mandatory = $true, Position = 4)]
        [Double] $DestinationLongitude,

        [Parameter(Mandatory = $false, Position = 5)]
        [ValidateSet('Driving', 'Walking')]
        [String] $TravelMode = 'Driving',

        [Parameter(Mandatory = $false, Position = 6)]
        [String] $Server = 'http://router.project-osrm.org'
    )

    $routeProfile = switch ($TravelMode) {
        'Driving' { 'driving' }
        'Walking' { 'foot'    }
    }

    $coordinates = "$OriginLongitude,$OriginLatitude;$DestinationLongitude,$DestinationLatitude"
    $uri = "$($Server.TrimEnd('/'))/route/v1/$routeProfile/$($coordinates)?overview=false"

    Write-Debug "[OSRM] Call uri: $uri"
    return Invoke-RestMethod -Uri $uri -Method GET
}

function Find-GeoCodeLocationAzureMaps {
    <#
    .SYNOPSIS
        Find a geographical location based on a query or coordinates in Azure Maps.

    .DESCRIPTION
        Find a geographical location based on a query or coordinates in Azure Maps.

    .PARAMETER Query
        A textual query for the location, this is what you would normally enter in the search bar for the map service. Can't be used together with Lat/Long.

    .PARAMETER Latitude
        The latitude as a float. Can't be used together with Query.

    .PARAMETER Longitude
        The longitude as a float. Can't be used together with Query.

    .PARAMETER Apikey
        Apikey from Azure

    .PARAMETER Limit
        Limits the amount of results being returned.

    .EXAMPLE
        Find based on query

        PS> Find-GeoCodeLocationAzureMaps -Query "Microsoft Building 92, NE 36th St, Redmond, WA 98052, United States" -Apikey <YOUR API KEY>
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='The product is called like this.')]

    [CmdLetBinding()]
    [OutputType([System.Object[]])]

    Param (
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Query')]
        [String] $Query,

        [Alias("Lat")]
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Lon/Lat')]
        [Single] $Latitude,

        [Alias("Lon")]
        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = 'Lon/Lat')]
        [Single] $Longitude,

        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $true, Position = 3, ParameterSetName = 'Lon/Lat')]
        [String] $ApiKey,

        [Parameter(Mandatory = $false, Position = 3, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 4, ParameterSetName = 'Lon/Lat')]
        [Int32] $Limit
    )

    switch($PsCmdlet.ParameterSetName) {
        "Query" {
            Write-Debug "Q"
            $uri = "https://atlas.microsoft.com/geocode?api-version=2025-01-01&query=$([System.Web.HttpUtility]::UrlEncode($Query))&subscription-key=$ApiKey"

            if($Limit) {
                $uri += "&top=$Limit"
            }
        }

        "Lon/Lat" {
            $uri = "https://atlas.microsoft.com/reverseGeocode?api-version=2025-01-01&coordinates=$($Latitude),$($Longitude)&subscription-key=$ApiKey"
        }
    }

    Write-Debug "[AzureMaps] Call uri: $uri"
    return Invoke-RestMethod -Uri $uri -Method GET
}

function Find-GeoCodeLocationGoogleMaps {
    <#
    .SYNOPSIS
        Find a geographical location based on a query or coordinates in Google Maps.

    .DESCRIPTION
        Find a geographical location based on a query or coordinates in Google Maps.

    .PARAMETER Query
        A textual query for the location, this is what you would normally enter in the search bar for the map service. Can't be used together with Lat/Long.

    .PARAMETER Latitude
        The latitude as a float. Can't be used together with Query.

    .PARAMETER Longitude
        The longitude as a float. Can't be used together with Query.

    .PARAMETER Apikey
        Apikey from Google

    .PARAMETER Language
        The language of the returned values can be changed based on the language. Use a country code which is accepted in the header Accept-Language (like "en-US").

    .EXAMPLE
        Find based on query

        PS> Find-GeoCodeLocationGooleMaps -Query "Microsoft Building 92, NE 36th St, Redmond, WA 98052, United States" -Apikey <YOUR API KEY>
    #>

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification='The product is called like this.')]

    [CmdLetBinding()]
    [OutputType([System.Object[]])]

    Param (
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Query')]
        [String] $Query,

        [Alias("Lat")]
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Lon/Lat')]
        [Single] $Latitude,

        [Alias("Lon")]
        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = 'Lon/Lat')]
        [Single] $Longitude,

        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $true, Position = 3, ParameterSetName = 'Lon/Lat')]
        [String] $ApiKey,

        [Parameter(Mandatory = $false, Position = 4, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 5, ParameterSetName = 'Lon/Lat')]
        [String] $Language = "en-US"
    )

    # Create the headers
    $headers = @{
        "accept-language" = $Language
    }

    switch($PsCmdlet.ParameterSetName) {
        "Query" {
            $uri = "https://maps.googleapis.com/maps/api/geocode/json?address=$([System.Web.HttpUtility]::UrlEncode($Query))&key=$ApiKey"
        }

        "Lon/Lat" {
            $uri = "https://maps.googleapis.com/maps/api/geocode/json?latlng=$($Latitude),$($Longitude)&key=$ApiKey"
        }
    }

    Write-Debug "[GoogleMaps] Call uri: $uri"
    return Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
}

function Find-GeoCodeLocationNominatim {
    <#
    .SYNOPSIS
        Find a geographical location based on a query or coordinates in Open Street Maps.

    .DESCRIPTION
        Find a geographical location based on a query or coordinates in Open Street Maps.

    .PARAMETER Query
        A textual query for the location, this is what you would normally enter in the search bar for the map service. Can't be used together with Lat/Long.

    .PARAMETER Latitude
        The latitude as a float. Can't be used together with Query.

    .PARAMETER Longitude
        The longitude as a float. Can't be used together with Query.

    .PARAMETER DetailedAddress
        Split the address info into seperate attributes in the output.

    .PARAMETER Limit
        Limits the amount of results being returned.

    .PARAMETER Language
        The language of the returned values can be changed based on the language. Use a country code which is accepted in the header Accept-Language (like "en-US").

    .EXAMPLE
        Find based on query

        PS> Find-GeoCodeLocationNominatim -Query "Microsoft Building 92, NE 36th St, Redmond, WA 98052, United States"
    #>

    [CmdLetBinding()]
    [OutputType([System.Object[]])]

    Param (
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Query')]
        [String] $Query,

        [Alias("Lat")]
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Lon/Lat')]
        [Single] $Latitude,

        [Alias("Lon")]
        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = 'Lon/Lat')]
        [Single] $Longitude,

        [Parameter(Mandatory = $false, Position = 2, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 3, ParameterSetName = 'Lon/Lat')]
        [Switch] $DetailedAddress,

        [Parameter(Mandatory = $false, Position = 3, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 4, ParameterSetName = 'Lon/Lat')]
        [Int32] $Limit,

        [Parameter(Mandatory = $false, Position = 4, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 5, ParameterSetName = 'Lon/Lat')]
        [String] $Language = "en-US"
    )

    # Create the headers
    $headers = @{
        "accept-language" = $Language
    }

    switch($PsCmdlet.ParameterSetName) {
        "Query" {
            $uri = "https://nominatim.openstreetmap.org/search?q=$([System.Web.HttpUtility]::UrlEncode($Query))&format=jsonv2"

            if($Limit) {
                $uri += "&limit=$Limit"
            }
        }

        "Lon/Lat" {
            $uri = "https://nominatim.openstreetmap.org/reverse?lat=$Latitude&lon=$Longitude&format=jsonv2"
        }
    }

    if($DetailedAddress) {
        $uri += "&addressdetails=1"
    }

    Write-Debug "[OpenStreetMaps] Call uri: $uri"
    return Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
}

function Find-GeoCodeDistance {
    <#
    .SYNOPSIS
        Calculate the route distance and travel time between two coordinates.

    .DESCRIPTION
        Calculates the driving or walking route distance and estimated travel
        time between an origin and a destination using latitude/longitude
        coordinates. Supports Open Street Maps (via OSRM), Google Maps and
        Azure Maps.

        Open Street Maps can be used without an API key. Google Maps and Azure
        Maps require an API key (-Apikey), which only appears as a parameter
        when a paid provider is selected.

        Transit mode is only available for Google Maps; providing it for any
        other provider raises an error. The ValidateSet for -TravelMode always
        shows all three options to keep the parameter discoverable, and the
        provider restriction is enforced at runtime.

        -TrafficAware only appears as a parameter when -Provider Google or
        -Provider Azure is selected, since those are the only providers that
        support live traffic data.

        -OsrmServer only appears when -Provider OSM or -Provider OpenStreetMaps
        is explicitly selected.

        -DepartureTime and -ArrivalTime are mutually exclusive parameter sets.
        Arrival time is only supported by Google Maps.

        Use -Unit to choose between Metric (meters, default) and Imperial (miles).
        Duration is returned as a TimeSpan, giving access to .TotalSeconds,
        .TotalMinutes, .TotalHours, .Hours, .Minutes, .Seconds and so on.
        TrafficDelay is also a TimeSpan when traffic data is available.

    .PARAMETER OriginLatitude
        The latitude of the origin point as a decimal number (e.g. 52.3037).

    .PARAMETER OriginLongitude
        The longitude of the origin point as a decimal number (e.g. 4.7500).

    .PARAMETER DestinationLatitude
        The latitude of the destination point as a decimal number.

    .PARAMETER DestinationLongitude
        The longitude of the destination point as a decimal number.

    .PARAMETER Provider
        The routing service to use. Accepts OpenStreetMaps, OSM, GoogleMaps,
        Google, AzureMaps or Azure. Defaults to OSM. The availability of
        Apikey, OsrmServer and TrafficAware all depend on the selected provider.

    .PARAMETER TravelMode
        The travel mode: Driving (default), Walking or Transit. Transit is only
        valid for Google Maps and raises an error for any other provider.

    .PARAMETER Unit
        Distance unit for the output. Accepts Metric (returns Distance.Meters,
        the default) or Imperial (returns Distance.Miles).

    .PARAMETER DepartureTime
        Optional departure time as a DateTime. Cannot be combined with
        -ArrivalTime. Not supported by Open Street Maps. For Google Maps Driving
        mode, providing a departure time also enables traffic-aware results.

    .PARAMETER ArrivalTime
        Optional desired arrival time as a DateTime. Cannot be combined with
        -DepartureTime. Only supported by Google Maps Transit mode.

    .PARAMETER Apikey
        API key for the selected provider. Only available (and required) when
        -Provider Google, GoogleMaps, Azure or AzureMaps is selected.

    .PARAMETER TrafficAware
        Requests real-time traffic data. Only available when -Provider Google or
        -Provider Azure is selected (this is a dynamic parameter). Only valid
        for Driving mode. For Google Maps this sets the departure time to now if
        no explicit -DepartureTime was provided. Azure Maps always includes live
        traffic for car routing regardless of this switch.

    .PARAMETER OsrmServer
        Base URL of the OSRM server. Only available when -Provider OSM or
        -Provider OpenStreetMaps is explicitly selected. Defaults to the public
        demo server at http://router.project-osrm.org.

    .EXAMPLE
        Calculate driving distance using Open Street Maps (no API key needed)

        PS> Find-GeoCodeDistance -OriginLatitude 52.3037 -OriginLongitude 4.7500 -DestinationLatitude 53.5614 -DestinationLongitude 9.9152

        Distance     : @{Meters=470426}
        Duration     : 05:05:48
        TrafficDelay :

    .EXAMPLE
        Calculate driving distance with live traffic using Google Maps

        PS> Find-GeoCodeDistance -OriginLatitude 52.3037 -OriginLongitude 4.7500 -DestinationLatitude 53.5614 -DestinationLongitude 9.9152 -Provider Google -Apikey "<KEY>" -TrafficAware

    .EXAMPLE
        Calculate distance in miles using Open Street Maps

        PS> Find-GeoCodeDistance -OriginLatitude 52.3037 -OriginLongitude 4.7500 -DestinationLatitude 53.5614 -DestinationLongitude 9.9152 -Unit Imperial

        Distance     : @{Miles=292.28}
        Duration     : 05:05:48
        TrafficDelay :

    .EXAMPLE
        Calculate transit distance using Google Maps with a target arrival time

        PS> Find-GeoCodeDistance -OriginLatitude 52.3037 -OriginLongitude 4.7500 -DestinationLatitude 53.5614 -DestinationLongitude 9.9152 -Provider Google -TravelMode Transit -ArrivalTime (Get-Date).AddHours(3) -Apikey "<KEY>"
    #>

    [CmdLetBinding(DefaultParameterSetName = 'Default')]
    [OutputType([System.Object[]])]

    Param (
        # Base parameters — no ParameterSetName so they work in all parameter sets.
        [Parameter(Mandatory = $true)]
        [Double] $OriginLatitude,

        [Parameter(Mandatory = $true)]
        [Double] $OriginLongitude,

        [Parameter(Mandatory = $true)]
        [Double] $DestinationLatitude,

        [Parameter(Mandatory = $true)]
        [Double] $DestinationLongitude,

        [Parameter(Mandatory = $false)]
        [ValidateSet('OpenStreetMaps', 'OSM', 'GoogleMaps', 'Google', 'AzureMaps', 'Azure')]
        [String] $Provider = 'OSM',

        # TravelMode is a static parameter so that help and tab-completion always
        # work. Transit is validated against the provider in Process{}.
        [Parameter(Mandatory = $false)]
        [ValidateSet('Driving', 'Walking', 'Transit')]
        [String] $TravelMode = 'Driving',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Metric', 'Imperial')]
        [String] $Unit = 'Metric',

        # DepartureTime and ArrivalTime are in separate parameter sets so
        # PowerShell itself prevents both from being specified simultaneously.
        [Parameter(Mandatory = $false, ParameterSetName = 'WithDepartureTime')]
        [DateTime] $DepartureTime,

        [Parameter(Mandatory = $false, ParameterSetName = 'WithArrivalTime')]
        [DateTime] $ArrivalTime
    )

    DynamicParam {
        $dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        # -Apikey: required for Google Maps and Azure Maps.
        if ($Provider -in 'GoogleMaps', 'Google', 'AzureMaps', 'Azure') {
            $akAttr = New-Object System.Management.Automation.ParameterAttribute
            $akAttr.Mandatory = $true
            $akCol  = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $akCol.Add($akAttr)
            $akParam = New-Object System.Management.Automation.RuntimeDefinedParameter('Apikey', [string], $akCol)
            $dictionary.Add('Apikey', $akParam)
        }

        # -TrafficAware: only available for providers that support traffic data.
        if ($Provider -in 'GoogleMaps', 'Google', 'AzureMaps', 'Azure') {
            $taAttr = New-Object System.Management.Automation.ParameterAttribute
            $taAttr.Mandatory = $false
            $taCol  = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $taCol.Add($taAttr)
            $taParam = New-Object System.Management.Automation.RuntimeDefinedParameter('TrafficAware', [switch], $taCol)
            $dictionary.Add('TrafficAware', $taParam)
        }

        # -OsrmServer: only available when OSM provider is explicitly selected.
        if ($Provider -in 'OSM', 'OpenStreetMaps') {
            $osAttr = New-Object System.Management.Automation.ParameterAttribute
            $osAttr.Mandatory = $false
            $osCol  = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $osCol.Add($osAttr)
            $osParam = New-Object System.Management.Automation.RuntimeDefinedParameter('OsrmServer', [string], $osCol)
            $dictionary.Add('OsrmServer', $osParam)
        }

        return $dictionary
    }

    Process {
        # Resolve dynamic-parameter values with their defaults.
        $trafficAware = [bool]$PSBoundParameters['TrafficAware']
        $osrmServer   = if ($PSBoundParameters.ContainsKey('OsrmServer')) { $PSBoundParameters['OsrmServer'] } else { 'http://router.project-osrm.org' }

        # Validate logical constraints.
        if ($TravelMode -eq 'Transit' -and $Provider -notin 'GoogleMaps', 'Google') {
            throw "Transit mode is only supported by Google Maps."
        }
        if ($trafficAware -and $TravelMode -ne 'Driving') {
            throw "TrafficAware is only supported for Driving mode."
        }
        if (($PSBoundParameters.ContainsKey('DepartureTime') -or $PSBoundParameters.ContainsKey('ArrivalTime')) -and $Provider -in 'OpenStreetMaps', 'OSM') {
            throw "DepartureTime and ArrivalTime are not supported by Open Street Maps."
        }
        if ($PSBoundParameters.ContainsKey('ArrivalTime') -and $Provider -notin 'GoogleMaps', 'Google') {
            throw "ArrivalTime is only supported by Google Maps."
        }

        # Invoke the appropriate provider and get the normalised result.
        $result = switch ($Provider) {
            { $_ -in 'OpenStreetMaps', 'OSM' } {
                Write-Debug "[OpenStreetMaps] start distance processing"
                Send-THEvent -ModuleName "Geocoding" -EventName "Find-GeoCodeDistance" -PropertiesHash @{ Provider = "OSM" }

                $splat = @{
                    OriginLatitude       = $OriginLatitude
                    OriginLongitude      = $OriginLongitude
                    DestinationLatitude  = $DestinationLatitude
                    DestinationLongitude = $DestinationLongitude
                    TravelMode           = $TravelMode
                    Server               = $osrmServer
                }
                ConvertFrom-GeoOsrmDistanceOutput -Resource (Find-GeoCodeDistanceOsrm @splat)
            }

            { $_ -in 'GoogleMaps', 'Google' } {
                Write-Debug "[GoogleMaps] start distance processing"
                Send-THEvent -ModuleName "Geocoding" -EventName "Find-GeoCodeDistance" -PropertiesHash @{ Provider = "Google" }

                $splat = @{
                    OriginLatitude       = $OriginLatitude
                    OriginLongitude      = $OriginLongitude
                    DestinationLatitude  = $DestinationLatitude
                    DestinationLongitude = $DestinationLongitude
                    ApiKey               = $PSBoundParameters['Apikey']
                    TravelMode           = $TravelMode
                    TrafficAware         = $trafficAware
                }
                if ($PSBoundParameters.ContainsKey('DepartureTime')) { $splat['DepartureTime'] = $DepartureTime }
                if ($PSBoundParameters.ContainsKey('ArrivalTime'))   { $splat['ArrivalTime']   = $ArrivalTime   }
                ConvertFrom-GeoGoogleMapsDistanceOutput -Resource (Find-GeoCodeDistanceGoogleMaps @splat)
            }

            { $_ -in 'AzureMaps', 'Azure' } {
                Write-Debug "[AzureMaps] start distance processing"
                Send-THEvent -ModuleName "Geocoding" -EventName "Find-GeoCodeDistance" -PropertiesHash @{ Provider = "Azure" }

                $splat = @{
                    OriginLatitude       = $OriginLatitude
                    OriginLongitude      = $OriginLongitude
                    DestinationLatitude  = $DestinationLatitude
                    DestinationLongitude = $DestinationLongitude
                    ApiKey               = $PSBoundParameters['Apikey']
                    TravelMode           = $TravelMode
                }
                if ($PSBoundParameters.ContainsKey('DepartureTime')) { $splat['DepartureTime'] = $DepartureTime }
                if ($PSBoundParameters.ContainsKey('ArrivalTime'))   { $splat['ArrivalTime']   = $ArrivalTime   }
                ConvertFrom-GeoAzureMapsDistanceOutput -Resource (Find-GeoCodeDistanceAzureMaps @splat)
            }
        }

        # Build the output object. TrafficDelay is only included when the provider
        # returned actual traffic data — a null value means no traffic data was
        # available (or requested), so the property is omitted entirely to keep
        # the output clean.
        $distanceObj = if ($Unit -eq 'Imperial') {
            [PSCustomObject]@{ "Miles" = [Math]::Round($result.Distance.Meters / 1609.344, 2) }
        }
        else {
            $result.Distance
        }

        if ($null -ne $result.TrafficDelay) {
            return [PSCustomObject]@{
                "Distance"     = $distanceObj
                "Duration"     = $result.Duration
                "TrafficDelay" = $result.TrafficDelay
            }
        }

        return [PSCustomObject]@{
            "Distance" = $distanceObj
            "Duration" = $result.Duration
        }
    }
}

function Find-GeoCodeLocation {
    <#
    .SYNOPSIS
        Find a geographical location based on a query or coordinates.

    .DESCRIPTION
        Find a geographical location based on a query or coordinates. It supports multiple providers being: Open Street Maps, Azure Maps and Google Maps.

    .PARAMETER Query
        A textual query for the location, this is what you would normally enter in the search bar for the map service. Can't be used together with Lat/Long.

    .PARAMETER Latitude
        The latitude as a float. Can't be used together with Query.

    .PARAMETER Longitude
        The longitude as a float. Can't be used together with Query.

    .PARAMETER Provider
        The service to use to find the location. It supports Open Street Maps (OSM), Azure Maps (Azure) and Google Maps (Google).
        To use Azure and Google an API key is required which needs to be requested via their service. Open Street Maps can be used without an API key.
        Default it will use Open Street Maps

    .PARAMETER Apikey
        Required when using Azure or Google. Needs to be entered as a string.

    .PARAMETER Limit
        Limits the amount of results being returned.

    .PARAMETER Language
        For Open Street Maps and Google the language of the returned values can be changed based on the language. Use a country code which is accepted in the header Accept-Language (like "en-US").

    .EXAMPLE
        Use OpenStreetMaps to query and return a single result

        PS> Find-GeoCodeLocation -Query "Microsoft Building 92, NE 36th St, Redmond, WA 98052, United States" -Provider OSM -Limit 1 | fl *

        Coordinates : @{Latitude=47.64249155; Longitude=-122.13692695171639}
        Address     : @{Street Address=Northeast 36th Street 15010; Locality=; Region=Washington; Postal Code=98052; Country=United States}
        Boundingbox : @{South Latitude=47.6413399; West Longitude=-122.1378316; North Latitude=47.6433901; East Longitude=-122.1365074}

    .EXAMPLE
        Use Google Maps to query and return a single result

        PS> Find-GeoCodeLocation -Query "Microsoft Building 92, NE 36th St, Redmond, WA 98052, United States" -Provider Google -Apikey <YOUR API KEY> -Limit 1 | fl *

        Coordinates : @{Latitude=47,6423109; Longitude=-122,1368406}
        Address     : @{Street Address=Northeast 36th Street 15010; Locality=Redmond; Region=Washington; Postal Code=System.Object[]; Country=United States}
        Boundingbox : @{South Latitude=47,6410083697085; West Longitude=-122,138480530292; North Latitude=47,6437063302915; East Longitude=-122,135782569708}

    .EXAMPLE
        Use Azure Maps to query and return a single result

        PS> Find-GeoCodeLocation -Query "Microsoft Building 92, NE 36th St, Redmond, WA 98052, United States" -Provider Azure -Apikey <YOUR API KEY> -Limit 1 | fl *

        Coordinates : @{Latitude=47,6423109; Longitude=-122,1368406}
        Address     : @{Street Address=Northeast 36th Street 15010; Locality=Redmond; Region=Washington; Postal Code=System.Object[]; Country=United States}
        Boundingbox : @{South Latitude=47,6410083697085; West Longitude=-122,138480530292; North Latitude=47,6437063302915; East Longitude=-122,135782569708}


    .EXAMPLE
        Use OpenStreetMaps to lookup coordinates and return a single result

        PS> Find-GeoCodeLocation -Latitude 38.75408328 -Longitude -78.13476563 -Provider OSM -Limit 1 | fl *

        Coordinates : @{Latitude=38.75186724786314; Longitude=-78.13181680294852}
        Address     : @{Street Address=Fodderstack Road ; Locality=; Region=Virginia; Postal Code=22747; Country=United States}
        Boundingbox : @{South Latitude=38.7196074; West Longitude=-78.1576132; North Latitude=38.7593864; East Longitude=-78.1236110}

    .EXAMPLE
        Use Google Maps to lookup coordinates and return a single result

        PS> Find-GeoCodeLocation -Latitude 38.75408328 -Longitude -78.13476563 -Provider Google -Apikey <YOUR API KEY> -Limit 1 | fl *

        Coordinates : @{Latitude=38,75408; Longitude=-78,13477}
        Address     : @{Street Address= ; Locality=Flint Hill; Region=Virginia; Postal Code=; Country=United States}
        Boundingbox : @{South Latitude=38,7527135197085; West Longitude=-78,1361614802915; North Latitude=38,7554114802915; East Longitude=-78,1334635197085 }

    .EXAMPLE
        Use Azure Maps to lookup coordinates and return a single result

        PS> Find-GeoCodeLocation -Latitude 38.75408328 -Longitude -78.13476563 -Provider Azure -Apikey <YOUR API KEY> -Limit 1 | fl *

        Coordinates : @{Latitude=38,75408; Longitude=-78,13477}
        Address     : @{Street Address= ; Locality=Flint Hill; Region=Virginia; Postal Code=; Country=United States}
        Boundingbox : @{South Latitude=38,7527135197085; West Longitude=-78,1361614802915; North Latitude=38,7554114802915; East Longitude=-78,1334635197085 }


    .NOTES
        Open Street Maps: https://nominatim.org/release-docs/latest/api/Overview/
        Google Maps: https://developers.google.com/maps/documentation/geocoding
        Azure Maps: https://learn.microsoft.com/en-us/azure/azure-maps/about-azure-maps
    #>

    [CmdLetBinding()]
    [OutputType([System.Object[]])]

    Param (
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Query')]
        [String] $Query,

        [Alias("Lat")]
        [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'Lon/Lat')]
        [Single] $Latitude,

        [Alias("Lon")]
        [Parameter(Mandatory = $true, Position = 2, ParameterSetName = 'Lon/Lat')]
        [Single] $Longitude,

        [ValidateSet('OpenStreetMaps', 'OSM', 'GoogleMaps', 'Google', "Azure", "AzureMaps")]
        [Parameter(Mandatory = $false, Position = 2, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 3, ParameterSetName = 'Lon/Lat')]
        [String] $Provider = "OpenStreetMaps",

        [Parameter(Mandatory = $false, Position = 3, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 4, ParameterSetName = 'Lon/Lat')]
        [Int32] $Limit,

        [Parameter(Mandatory = $false, Position = 4, ParameterSetName = 'Query')]
        [Parameter(Mandatory = $false, Position = 5, ParameterSetName = 'Lon/Lat')]
        [String] $Language = "en-US"
    )

    DynamicParam {
        if($Provider -in 'GoogleMaps', 'Google', "Azure", "AzureMaps") {
            $attribute = New-Object System.Management.Automation.ParameterAttribute
            $attribute.Mandatory = $true

            $collection = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $collection.Add($attribute)

            $param = New-Object System.Management.Automation.RuntimeDefinedParameter('Apikey', [string], $collection)
            $dictionary = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $dictionary.Add('Apikey', $param)

            return $dictionary
        }
    }

    Process {
        # do actions for the right provider
        switch ($Provider) {
            { $_ -in "OpenStreetMaps", "OSM" } {
                Write-Debug "[OpenStreetMaps] start processing"
                Send-THEvent -ModuleName "Geocoding" -EventName "Find-GeoCodeLocation" -PropertiesHash @{Provider = "OSM" }

                # Create the parameters
                $splat = $PSBoundParameters
                $null = $splat.Remove("Provider")
                $splat.add("DetailedAddress",$true)

                # Query the provider for the results
                $res = Find-GeoCodeLocationNominatim @splat

                # Format the results in a uniform format
                $res = @($res | ForEach-Object {ConvertFrom-GeoNominatimOutput -Resource $_})

                # Return result
                return $res
            }

            { $_ -in "AzureMaps", "Azure" } {
                Write-Debug "[AzureMaps] start processing"
                Send-THEvent -ModuleName "Geocoding" -EventName "Find-GeoCodeLocation" -PropertiesHash @{Provider = "Azure" }

                # Create the parameters
                $splat = $PSBoundParameters
                $null = $splat.Remove("Provider")
                $null = $splat.Remove("Language")

                # Query the provider for the results
                $res = (Find-GeoCodeLocationAzureMaps @splat).features

                # Format the results in a uniform format
                $res = @($res | ForEach-Object {ConvertFrom-GeoAzureMapsOutput -Resource $_})

                # Return result
                return $res
            }

            { $_ -in "GoogleMaps", "Google" } {
                Write-Debug "[GoogleMaps] start processing"
                Send-THEvent -ModuleName "Geocoding" -EventName "Find-GeoCodeLocation" -PropertiesHash @{Provider = "Google" }

                # Create the parameters
                $splat = $PSBoundParameters
                $null = $splat.Remove("Provider")
                $null = $splat.Remove("Limit")

                # Query the provider for the results
                $res = (Find-GeoCodeLocationGoogleMaps @splat).results

                if($Limit) {
                    $res = $res | Select-Object -First $Limit
                }

                # Format the results in a uniform format
                $res = @($res | ForEach-Object {ConvertFrom-GeoGoogleMapsOutput -Resource $_})

                # Return result
                return $res
            }
        }
    }
}

# Create env variables
$Env:GEOCODING_TELEMETRY_OPTIN = (-not $Evn:POWERSHELL_TELEMETRY_OPTOUT) # use the invert of default powershell telemetry setting

# Set up the telemetry
Initialize-THTelemetry -ModuleName "Geocoding"
Set-THTelemetryConfiguration -ModuleName "Geocoding" -OptInVariableName "GEOCODING_TELEMETRY_OPTIN" -StripPersonallyIdentifiableInformation $true -Confirm:$false
Add-THAppInsightsConnectionString -ModuleName "Geocoding" -ConnectionString "InstrumentationKey=df9757a1-873b-41c6-b4a2-2b93d15c9fb1;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"

# Create a message about the telemetry
Write-Information ("Telemetry for Geocoding module is $(if([string] $Env:GEOCODING_TELEMETRY_OPTIN -in ("no","false","0")){"NOT "})enabled. Change the behavior by setting the value of "+ '$Env:GEOCODING_TELEMETRY_OPTIN') -InformationAction Continue

# Send a metric for the installation of the module
Send-THEvent -ModuleName "Geocoding" -EventName "Import Module Geocoding"