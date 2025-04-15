Clear-Host
$currentPorts = @()
$wsl_ip = ""
function Reset-State {
    Invoke-Expression "netsh interface portproxy reset" | out-null
    Invoke-Expression "netsh advfirewall firewall delete rule name='WSL Port Proxy'" | out-null
    $currentPorts = @()
    $wsl_ip = ""
}

Reset-State

function Delete-Port-Proxy($port) {
    Write-Output "removing portproxy $port"
    Invoke-Expression "netsh interface portproxy delete v4tov4 listenport=$port" | out-null
    Invoke-Expression "netsh advfirewall firewall del rule name='WSL Port Proxy' protocol=TCP localport=$port" | out-null
}

function Add-Port-Proxy($port, $dstAddr, $dstPort){
    Invoke-Expression "netsh interface portproxy delete v4tov4 listenport=$port" | out-null
    Invoke-Expression "netsh advfirewall firewall del rule name='WSL Port Proxy' protocol=TCP localport=$port" | out-null
    Write-Output "adding portproxy: $port -> $dstPort"
    Invoke-Expression "netsh interface portproxy add v4tov4 listenport=$port connectaddress=$dstAddr connectport=$dstPort" | out-null
    Invoke-Expression "netsh advfirewall firewall add rule name='WSL Port Proxy' dir=in action=allow protocol=TCP localport=$port" | out-null
}

while ($true) {

    $wsl_running = (wsl -l --running | Where-Object { $_.Replace("`0", "") -match 'Default' } | Measure-Object -Line | Select-Object -expand Lines)
    if ($wsl_running -eq 0 -and $currentPorts.Length -gt 0) {
        Reset-State
    }
    elseif ($wsl_running -eq 1) {
        if ($wsl_ip.Length -eq 0) {
            $wsl_ip = wsl -u root -e sh -c "ip -o -4 addr list eth0 | awk '{print `$4}' | cut -d/ -f1"
            Write-Output $wsl_ip
        }
        if ($wsl_ip.Length -ne 0) {
            $newPorts = @()
            $netstat = wsl -u root -e sh -c 'netstat -tpln'
            # parse netstat into array
            foreach ($line in $netstat) {
                if ($line.StartsWith("tcp")) {
                    $values = $line -split '\s+'
                    foreach ($value in $values) {
                        if ($value.Contains(":")) {
                            $split = ($value -split ':')
                            $port = $split[$split.Length - 1] -as [int]
                            if ($port -ge 22 -and $port -le 65535 -and !$newPorts.Contains($port)) {
                                $newPorts += $port
                            }
                        }
                    }
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
                        Add-Port-Proxy $listenPort $wsl_ip $newPort
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
            Write-Warning "WSL IP is empty..."
        }
    }

    Start-Sleep -Milliseconds 5000
}
