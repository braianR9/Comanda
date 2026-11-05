# Quita el agente de impresión de Foco. Se ejecuta desde desinstalar.cmd.
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}
$tarea = 'Foco - Agente de impresion'
Stop-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $tarea -Confirm:$false -ErrorAction SilentlyContinue
Get-Process FocoAgente, BarIceCreamShop.Api -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
Set-Location $env:TEMP
Remove-Item -Recurse -Force 'C:\FocoAgente' -ErrorAction SilentlyContinue
Write-Host 'Agente desinstalado.'
Read-Host 'Enter para cerrar'
