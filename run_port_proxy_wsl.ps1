$portProxyScript = '"$HOME\port_proxy_wsl.ps1"'
$portProxyRun = "powershell -WindowStyle hidden -file $($portProxyScript)"

Invoke-Expression $portProxyRun