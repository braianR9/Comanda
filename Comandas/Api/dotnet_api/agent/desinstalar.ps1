# Quita el agente de impresión de Foco. Ejecutar como administrador.
$tarea = 'Foco - Agente de impresion'
Stop-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $tarea -Confirm:$false -ErrorAction SilentlyContinue
Get-Process BarIceCreamShop.Api -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -Recurse -Force 'C:\FocoAgente' -ErrorAction SilentlyContinue
Write-Host 'Agente desinstalado.'
Read-Host 'Enter para cerrar'
