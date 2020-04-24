function Invoke-PortCheck {
    [cmdletbinding()]
    param(
        $Target,
        $Port,
        $Timeout=500
    )
    $Connected = $false
    $TcpClient = New-Object System.Net.Sockets.TcpClient
    Write-Verbose "Attempting to connect to target '$Target' on port'$Port'..."
    $null = $TcpClient.BeginConnect($Target, $Port, $null, $null)
    if ($TcpClient.Connected) {
        Write-Verbose "Connected!"
        $Connected = $true
    }
    else {
        Write-Verbose "Not connected, but retrying..."
        Start-Sleep -Milliseconds $Timeout
        if ($TcpClient.Connected) {
            $Connected = $true
            Write-Verbose "Connected!"
        }
        else {
            Write-Verbose "Failed to connect."
        }
    }
    $null = $TcpClient.Close()
    return $Connected
}
