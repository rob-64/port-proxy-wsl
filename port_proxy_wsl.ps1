param (
    [int]$t = 15,       # default to 15
    [switch]$v
)

function Log-Verbose {
    param (
        [string]$Message
    )
    if ($v) {
        Write-Host "[VERBOSE] $Message"
    }
}

Clear-Host
$currentPorts = @()
$wslEth0 = ""

function Reset-State {
    Log-Verbose "clearing all port proxies..."
    Invoke-Expression "netsh interface portproxy reset" | out-null
    Invoke-Expression "netsh advfirewall firewall delete rule name='WSL Port Proxy'" | out-null
    $currentPorts = @()
    $wslEth0 = ""
}

Reset-State

function Delete-Port-Proxy($port) {
    Log-Verbose "removing port proxy $port"
    Invoke-Expression "netsh interface portproxy delete v4tov4 listenport=$port" | out-null
    Invoke-Expression "netsh advfirewall firewall del rule name='WSL Port Proxy' protocol=TCP localport=$port" | out-null
}

function Add-Port-Proxy($port, $dstAddr, $dstPort){
    Invoke-Expression "netsh interface portproxy delete v4tov4 listenport=$port" | out-null
    Invoke-Expression "netsh advfirewall firewall del rule name='WSL Port Proxy' protocol=TCP localport=$port" | out-null
    Log-Verbose "adding port proxy: $port -> $dstPort"
    Invoke-Expression "netsh interface portproxy add v4tov4 listenport=$port connectaddress=$dstAddr connectport=$dstPort" | out-null
    Invoke-Expression "netsh advfirewall firewall add rule name='WSL Port Proxy' dir=in action=allow protocol=TCP localport=$port" | out-null
}

while ($true) {

    $wslRunning = (wsl -l --running | Where-Object { $_.Replace("`0", "") -match 'Default' } | Measure-Object -Line | Select-Object -expand Lines)
    Log-Verbose "wsl running: $wslRunning"
    if ($wslRunning -eq 0) {
        Reset-State
    }
    elseif ($wslRunning -eq 1) {
        if ($wslEth0.Length -eq 0) {
            $wslEth0 = wsl -u root -e sh -c "ip -o -4 addr list eth0 | awk '{print `$4}' | cut -d/ -f1"
            Log-Verbose $wslEth0
        }
        if ($wslEth0.Length -ne 0) {
            $newPorts = @()
            $localPorts = wsl -u root -e sh -c "ss -ltn | tail -n +2 | awk '{print `$4}' | awk -F':' '{print `$NF}' | sort -n | uniq"
            # Log-Verbose $localPorts
            foreach ($port in $localPorts) {
                if ($port -ge 22 -and $port -le 65535 -and !$newPorts.Contains($port)) {
                    $newPorts += $port
                }
            }
            $updatedPorts = $false
            # sometimes we get an empty array
            if ($newPorts.Length -gt 0 -Or $newPorts.Length -ne $currentPorts.Length) {
                # remove old ports
                For ($i = 0; $i -lt $currentPorts.Length; $i++) {
                    $currentPort = $currentPorts[$i]
                    if (!$newPorts.Contains($currentPort)) {
                        $listenPort = $currentPort
                        # always forward 443 -> 8443
                        if ($listenPort -eq 8443) {
                            $listenPort = 443
                        }
                        Delete-Port-Proxy $listenPort
                        $updatedPorts = $true
                    }
                }
                # forward new ports
                For ($i = 0; $i -lt $newPorts.Length; $i++) {
                    $newPort = $newPorts[$i]
                    $listenPort = $newPort
                    # always forward 443 -> 8443
                    if ($listenPort -eq 8443) {
                        $listenPort = 443
                    }
                    # always forward 80 -> 8000
                    if ($listenPort -eq 8000) {
                        $listenPort = 80
                    }
                    if (!$currentPorts.Contains($newPort)) {
                        Add-Port-Proxy $listenPort $wslEth0 $newPort
                        $updatedPorts = $true
                    }
                }
                if ($updatedPorts -eq $true) {
                    # set currentPorts
                    $currentPorts = $newPorts
                }
            }
            # Clear-Host
            # Invoke-Expression "netsh interface portproxy show v4tov4"
        }
        else {
            Log-Verbose "WSL IP is empty..."
        }
    }

    Start-Sleep -Seconds $t
}
