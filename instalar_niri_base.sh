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
    neovim            # editor
    curl              # descarga de tarballs
    gnupg             # verificación de firmas
    upower            # servicio de batería para Quickshell.Services.UPower
)

echo "==> Instalando paquetes: ${PKGS[*]}"
sudo pacman -S --needed --noconfirm "${PKGS[@]}"

# ------------------------------------------------------------------
# 1b. Helium Browser (tarball oficial, sin AUR)
# ------------------------------------------------------------------
echo "==> Instalando Helium Browser (tarball oficial de GitHub, sin AUR)..."

HELIUM_OPT_DIR="/opt/helium"
HELIUM_TMP="$(mktemp -d)"

# Obtiene la URL del tarball x86_64 de la última release estable
HELIUM_TARBALL_URL="$(curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*x86_64_linux\.tar\.xz"' \
    | grep -o 'https://[^"]*')"

if [[ -z "$HELIUM_TARBALL_URL" ]]; then
    echo "ADVERTENCIA: no se pudo determinar la URL del tarball de Helium. Omitiendo su instalación." >&2
else
    echo "==> Descargando: $HELIUM_TARBALL_URL"
    curl -fsSL -o "$HELIUM_TMP/helium.tar.xz" "$HELIUM_TARBALL_URL"

    # ---- Verificación de firma GPG ----
    HELIUM_ASC_URL="${HELIUM_TARBALL_URL}.asc"
    HELIUM_GPG_HOME="$HELIUM_TMP/gnupg"
    mkdir -p "$HELIUM_GPG_HOME"
    chmod 700 "$HELIUM_GPG_HOME"

    echo "==> Descargando firma: $HELIUM_ASC_URL"
    if curl -fsSL -o "$HELIUM_TMP/helium.tar.xz.asc" "$HELIUM_ASC_URL"; then
        echo "==> Importando clave pública de Helium (351601AD01D6378E)..."
        curl -fsSL https://raw.githubusercontent.com/imputnet/helium-linux/main/pubkey.asc \
            | gpg --homedir "$HELIUM_GPG_HOME" --import

        echo "==> Verificando firma del tarball..."
        if gpg --homedir "$HELIUM_GPG_HOME" --verify "$HELIUM_TMP/helium.tar.xz.asc" "$HELIUM_TMP/helium.tar.xz"; then
            echo "==> Firma verificada correctamente."
        else
            echo "ERROR: la firma GPG del tarball de Helium no es válida. Abortando instalación de Helium." >&2
            rm -rf "$HELIUM_TMP"
            HELIUM_TARBALL_URL=""
        fi
    else
        echo "ADVERTENCIA: no se encontró archivo .asc para verificar la firma. Se omite verificación e instalación de Helium por seguridad." >&2
        HELIUM_TARBALL_URL=""
    fi
fi

if [[ -n "$HELIUM_TARBALL_URL" ]]; then
    mkdir -p "$HELIUM_TMP/extracted"
    tar -xf "$HELIUM_TMP/helium.tar.xz" -C "$HELIUM_TMP/extracted"

    # El tarball trae una carpeta interna (p.ej. helium-0.15.1.1-x86_64_linux/)
    HELIUM_SRC_DIR="$(find "$HELIUM_TMP/extracted" -maxdepth 1 -mindepth 1 -type d | head -n1)"

    sudo rm -rf "$HELIUM_OPT_DIR"
    sudo mkdir -p "$HELIUM_OPT_DIR"
    sudo cp -r "$HELIUM_SRC_DIR"/. "$HELIUM_OPT_DIR"/

    # Detecta el binario principal dentro del paquete
    HELIUM_BIN="$(find "$HELIUM_OPT_DIR" -maxdepth 1 -type f -iname 'helium*' ! -name '*.so*' | head -n1)"
    if [[ -z "$HELIUM_BIN" ]]; then
        HELIUM_BIN="$HELIUM_OPT_DIR/chrome"
    fi
    sudo chmod +x "$HELIUM_BIN"

    # Wrapper para forzar backend nativo de Wayland (Niri no tiene X11/XWayland)
    sudo tee /usr/local/bin/helium-browser >/dev/null <<EOF3
#!/usr/bin/env bash
exec "$HELIUM_BIN" --ozone-platform=wayland --enable-features=WaylandWindowDecorations "\$@"
EOF3
    sudo chmod +x /usr/local/bin/helium-browser

    # Icono y entrada .desktop
    HELIUM_ICON="$(find "$HELIUM_OPT_DIR" -iname 'product_logo*256*.png' -o -iname 'icon*.png' | head -n1)"
    sudo mkdir -p /usr/share/applications
    cat <<EOF2 | sudo tee /usr/share/applications/helium-browser.desktop >/dev/null
[Desktop Entry]
Name=Helium
Comment=Navegador basado en Chromium sin Google (Helium)
Exec=/usr/local/bin/helium-browser %U
Terminal=false
Type=Application
Icon=${HELIUM_ICON:-web-browser}
Categories=Network;WebBrowser;
EOF2

    echo "==> Helium instalado en $HELIUM_OPT_DIR (comando: helium-browser)"
fi

rm -rf "$HELIUM_TMP"

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
spawn-at-startup "swaybg" "-c" "#1e1e2e"

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

    // Navegador
    Mod+B { spawn "helium-browser"; }

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
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

ShellRoot {
    // ----------------------------------------------------------------
    // Estado: workspaces de Niri (poll, no hay socket de eventos simple
    // aún expuesto por Niri para IPC directo desde QML) y red (poll ligero).
    // La batería usa UPower nativo -- reactivo, sin polling.
    // ----------------------------------------------------------------
    property var workspaces: []
    property string netText: "N/A"

    readonly property var battery: UPower.displayDevice

    Process {
        id: workspacesProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    workspaces = JSON.parse(text)
                } catch (e) {
                    workspaces = []
                }
            }
        }
    }

    Process {
        id: netProc
        command: ["sh", "-c", "ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = text.trim()
                netText = t.length > 0 ? t : "sin red"
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            workspacesProc.running = true
            netProc.running = true
        }
    }

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
            spacing: 16

            // Lanzador
            Rectangle {
                width: 28
                height: 24
                radius: 4
                color: launcherArea.containsMouse ? "#313244" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰀻"
                    color: "#cdd6f4"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: launcherArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: launcherProc.running = true
                }
            }

            Process {
                id: launcherProc
                command: ["nwg-drawer", "-r"]
            }

            // Workspaces
            RowLayout {
                spacing: 6

                Repeater {
                    model: workspaces
                    delegate: Rectangle {
                        width: 20
                        height: 20
                        radius: 4
                        color: modelData.is_focused ? "#89b4fa" : "#313244"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.idx !== undefined ? modelData.idx : ""
                            color: modelData.is_focused ? "#1e1e2e" : "#cdd6f4"
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: switchProc.runWith(modelData.idx)
                        }
                    }
                }
            }

            Process {
                id: switchProc
                property int targetIdx: 1
                command: ["niri", "msg", "action", "focus-workspace", String(targetIdx)]
                function runWith(idx) {
                    targetIdx = idx
                    running = true
                }
            }

            Text {
                text: "niri"
                color: "#6c7086"
                font.bold: true
            }

            Item { Layout.fillWidth: true }

            // Red
            Text {
                text: "🌐 " + netText
                color: "#cdd6f4"
                font.pixelSize: 12
            }

            // Batería (UPower nativo, reactivo -- ver mixer/volume-osd
            // de quickshell-examples para el mismo patrón con Pipewire)
            Text {
                visible: battery && battery.isLaptopBattery
                text: {
                    if (!battery || !battery.isLaptopBattery) return ""
                    var pct = Math.round((battery.percentage ?? 0) * 100)
                    var charging = battery.state === UPowerDeviceState.Charging
                    return (charging ? "⚡ " : "🔋 ") + pct + "%"
                }
                color: "#cdd6f4"
                font.pixelSize: 12
            }

            // Reloj
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
echo "    - Terminal:  kitty            (Mod+Return / Mod+T)"
echo "    - Lanzador:  nwg-drawer       (Mod+D)"
echo "    - Navegador: helium-browser   (Mod+B)"
echo "    - Editor:    neovim (nvim)"
echo "    - Barra:     quickshell       (autolanzada al iniciar Niri)"
echo
echo "Para probar sin reiniciar sesión (dentro de la VM con TTY o sesión anidada):"
echo "    niri-session"
echo
echo "Revisa el nombre real de tu output con 'niri msg outputs' y ajústalo en config.kdl si no es Virtual-1."
