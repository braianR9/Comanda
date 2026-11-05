# Instala el agente de impresión de Foco en la PC Windows del local (donde están las impresoras).
# Se ejecuta desde instalar.cmd (doble clic). Copia todo a C:\FocoAgente y lo deja
# arrancando solo con Windows (tarea programada como SYSTEM).
$ErrorActionPreference = 'Stop'
$destino = 'C:\FocoAgente'
$tarea = 'Foco - Agente de impresion'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
    Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Write-Host ''
Write-Host 'Agente de impresión de Foco'
Write-Host '---------------------------'
$clave = (Read-Host 'Pegá la clave del agente (la generás en Foco > Impresoras) y apretá Enter').Trim()
if (-not $clave) {
    Write-Host 'No ingresaste la clave. No se instaló nada.'
    Read-Host 'Enter para cerrar'
    exit 1
}
$apiUrl = (Get-Content (Join-Path $PSScriptRoot 'agente.json') -Raw | ConvertFrom-Json).apiUrl

# Reemplaza cualquier versión anterior (incluida la que se conectaba directo a la base).
Stop-ScheduledTask -TaskName $tarea -ErrorAction SilentlyContinue
Get-Process FocoAgente, BarIceCreamShop.Api -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 1
Remove-Item -Recurse -Force $destino -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $destino | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'FocoAgente.exe'), (Join-Path $PSScriptRoot 'desinstalar.*') -Destination $destino -Force
Get-ChildItem $destino | Unblock-File
@{ apiUrl = $apiUrl; clave = $clave } | ConvertTo-Json | Set-Content -Path (Join-Path $destino 'agente.json') -Encoding UTF8

$accion = New-ScheduledTaskAction -Execute 'cmd.exe' -WorkingDirectory $destino `
    -Argument "/c FocoAgente.exe >> `"$destino\agente.log`" 2>&1"
$disparador = New-ScheduledTaskTrigger -AtStartup
$usuario = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$opciones = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $tarea -Action $accion -Trigger $disparador -Principal $usuario -Settings $opciones -Force | Out-Null
Start-ScheduledTask -TaskName $tarea

Write-Host ''
Write-Host 'Listo: el agente quedó instalado en' $destino 'y arranca solo con Windows.'
Write-Host ''
Write-Host 'Impresoras de esta PC. En Foco, el "Nombre de la cola" de cada impresora'
Write-Host 'tiene que ser igual a uno de estos nombres:'
Get-Printer | Select-Object -ExpandProperty Name | ForEach-Object { Write-Host '  -' $_ }
Write-Host ''
Write-Host "Registro del agente: $destino\agente.log"
Read-Host 'Enter para cerrar'
