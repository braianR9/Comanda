#!/bin/bash
# Quita el agente de impresión de Foco de esta Mac (doble clic).
LABEL="net.focobr.agente"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/FocoAgente"
echo "Agente desinstalado."
read -r -p "Enter para cerrar"
