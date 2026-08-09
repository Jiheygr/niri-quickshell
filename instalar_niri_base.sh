#!/usr/bin/env bash
# instalar_niri_base.sh
# Instalación base de Niri para pruebas en VM
#   - Terminal: kitty (en vez de alacritty)
#   - Lanzador: nwg-drawer (en vez de fuzzel/wofi)
#   - Barra: quickshell (en vez de waybar)
#
# Uso: bash instalar_niri_base.sh

set -euo pipefail

# ------------------------------------------------------------------
# 0. Comprobaciones previas
# ------------------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    echo "No ejecutes este script como root. Usa tu usuario normal (con sudo disponible)." >&2
    exit 1
fi

if ! command -v pacman &>/dev/null; then
    echo "Este script es solo para sistemas basados en Arch Linux." >&2
    exit 1
fi

echo "==> Actualizando sistema..."
sudo pacman -Syu --noconfirm

# ------------------------------------------------------------------
# 1. Paquetes base
# ------------------------------------------------------------------
PKGS=(
    niri              # compositor Wayland
    kitty             # terminal
    nwg-drawer        # lanzador de apps
    quickshell        # barra / shell (reemplaza waybar)
    qt6-declarative
    qt6-svg
    qt6-wayland
    polkit-gnome      # agente de autenticación gráfico
    xdg-desktop-portal
    xdg-desktop-portal-gnome
    xdg-utils
    wl-clipboard
    grim              # captura de pantalla
    slurp             # selección de área
    swaybg            # fondo de pantalla estático (opcional)
)

echo "==> Instalando paquetes: ${PKGS[*]}"
sudo pacman -S --needed --noconfirm "${PKGS[@]}"

# ------------------------------------------------------------------
# 2. Estructura de configuración
# ------------------------------------------------------------------
CONFIG_DIR="$HOME/.config"
NIRI_DIR="$CONFIG_DIR/niri"
QS_DIR="$CONFIG_DIR/quickshell/base-bar"

mkdir -p "$NIRI_DIR"
mkdir -p "$QS_DIR"

# ------------------------------------------------------------------
# 3. config.kdl de Niri
# ------------------------------------------------------------------
if [[ -f "$NIRI_DIR/config.kdl" ]]; then
    cp "$NIRI_DIR/config.kdl" "$NIRI_DIR/config.kdl.bak.$(date +%s)"
    echo "==> Config existente respaldado."
fi

cat > "$NIRI_DIR/config.kdl" <<'EOF'
// Config base de Niri generada por instalar_niri_base.sh

input {
    keyboard {
        xkb {
            layout "us"
        }
    }
    touchpad {
        tap
        natural-scroll
    }
}

output "Virtual-1" {
    // Ajusta el nombre real del output con: niri msg outputs
    mode "1920x1080@60.000"
    scale 1.0
}

environment {
    TERMINAL "kitty"
}

spawn-at-startup "qs" "-c" "base-bar"
spawn-at-startup "polkit-gnome-authentication-agent-1"

layout {
    gaps 8
    center-focused-column "never"

    preset-column-widths {
        proportion 0.33333
        proportion 0.5
        proportion 0.66667
    }

    default-column-width { proportion 0.5; }

    focus-ring {
        width 2
    }
}

binds {
    // Terminal
    Mod+Return { spawn "kitty"; }
    Mod+T { spawn "kitty"; }

    // Lanzador de apps
    Mod+D { spawn "nwg-drawer" "-r"; }

    // Cerrar ventana
    Mod+Q { close-window; }

    // Navegación de columnas/ventanas
    Mod+Left  { focus-column-left; }
    Mod+Right { focus-column-right; }
    Mod+Down  { focus-window-down; }
    Mod+Up    { focus-window-up; }

    Mod+Shift+Left  { move-column-left; }
    Mod+Shift+Right { move-column-right; }

    // Pantalla completa / maximizar
    Mod+F { maximize-column; }
    Mod+Shift+F { fullscreen-window; }

    // Captura de pantalla
    Print { spawn "sh" "-c" "grim -g \"$(slurp)\" - | wl-copy"; }

    // Salir de Niri
    Mod+Shift+E { quit; }

    // Cambiar de workspace
    Mod+1 { focus-workspace 1; }
    Mod+2 { focus-workspace 2; }
    Mod+3 { focus-workspace 3; }
    Mod+4 { focus-workspace 4; }
}
EOF

echo "==> config.kdl escrito en $NIRI_DIR/config.kdl"
echo "    Recuerda ajustar el nombre del output con: niri msg outputs"

# ------------------------------------------------------------------
# 4. Barra mínima en Quickshell
# ------------------------------------------------------------------
cat > "$QS_DIR/shell.qml" <<'EOF'
import Quickshell
import QtQuick
import QtQuick.Layouts

ShellRoot {
    PanelWindow {
        anchors {
            top: true
            left: true
            right: true
        }
        height: 32
        color: "#1e1e2e"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            Text {
                text: "niri"
                color: "#cdd6f4"
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            Text {
                id: clock
                color: "#cdd6f4"
                text: Qt.formatDateTime(new Date(), "yyyy-MM-dd  hh:mm:ss")

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: clock.text = Qt.formatDateTime(new Date(), "yyyy-MM-dd  hh:mm:ss")
                }
            }
        }
    }
}
EOF

echo "==> Barra base de Quickshell escrita en $QS_DIR/shell.qml"

# ------------------------------------------------------------------
# 5. Sesión gráfica (por si usas un display manager)
# ------------------------------------------------------------------
SESSION_FILE="/usr/share/wayland-sessions/niri.desktop"
if [[ ! -f "$SESSION_FILE" ]]; then
    echo "==> Aviso: no se encontró $SESSION_FILE. Niri debería crear su propia entrada de sesión al instalarse."
fi

echo
echo "==> Instalación completa."
echo "    - Terminal:  kitty      (Mod+Return / Mod+T)"
echo "    - Lanzador:  nwg-drawer (Mod+D)"
echo "    - Barra:     quickshell (autolanzada al iniciar Niri)"
echo
echo "Para probar sin reiniciar sesión (dentro de la VM con TTY o sesión anidada):"
echo "    niri-session"
echo
echo "Revisa el nombre real de tu output con 'niri msg outputs' y ajústalo en config.kdl si no es Virtual-1."
