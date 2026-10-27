# Instala el agente de impresión de Foco en la PC Windows del local (donde están las impresoras USB).
# Uso: clic derecho > "Ejecutar con PowerShell" como administrador, desde la carpeta descomprimida.
# Copia todo a C:\FocoAgente y lo deja arrancando solo con Windows (tarea programada como SYSTEM).
$ErrorActionPreference = 'Stop'
$destino = 'C:\FocoAgente'
$tarea = 'Foco - Agente de impresion'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Stop-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue
Get-Process BarIceCreamShop.Api -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force -Path $destino | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot '*') -Destination $destino -Recurse -Force

$accion = New-ScheduledTaskAction -Execute 'cmd.exe' -WorkingDirectory $destino `
    -Argument "/c BarIceCreamShop.Api.exe >> `"$destino\agente.log`" 2>&1"
$disparador = New-ScheduledTaskTrigger -AtStartup
$usuario = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $tarea -Action $accion -Trigger $disparador -Principal $usuario -Settings $opciones -Force | Out-Null
Start-ScheduledTask -TaskName $tarea

Write-Host ''
Write-Host 'Agente instalado en' $destino
Write-Host 'Impresoras de Windows (el "Nombre de la cola" en Foco tiene que coincidir exacto):'
Get-Printer | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host '  -' $_ }
Write-Host ''
Write-Host "Registro: $destino\agente.log"
Read-Host 'Enter para cerrar'
