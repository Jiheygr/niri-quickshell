#!/usr/bin/env bash

set -e

# ==================================================================
#  script de instalación — Hyprland / Niri / KDE Plasma + apps y configs
#  Con TUI estilo "dank" usando gum (charmbracelet)
# ==================================================================

# -----------------------------
# 0. Parseo de argumentos
# -----------------------------
HYPRLAND_LUA_SRC=""
NIRI_KDL_SRC=""

usage() {
  cat <<EOF
Uso: sudo $(basename "$0") [opciones]

Opciones:
  --hyprland-lua <ruta>   Copia ese archivo como ~/.config/hypr/hyprland.lua
                          cuando se instale Hyprland "limpio" (sin respaldo)
  --niri-kdl <ruta>       Copia ese archivo como ~/.config/niri/config.kdl
                          cuando se instale Niri "limpio" (sin respaldo)
  -h, --help              Muestra esta ayuda
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --hyprland-lua)
    HYPRLAND_LUA_SRC="$2"
    shift 2
    ;;
  --niri-kdl)
    NIRI_KDL_SRC="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "❌ Opción desconocida: $1"
    usage
    exit 1
    ;;
  esac
done

if [[ -n "$HYPRLAND_LUA_SRC" && ! -f "$HYPRLAND_LUA_SRC" ]]; then
  echo "❌ No se encontró el archivo indicado en --hyprland-lua: $HYPRLAND_LUA_SRC"
  exit 1
fi

if [[ -n "$NIRI_KDL_SRC" && ! -f "$NIRI_KDL_SRC" ]]; then
  echo "❌ No se encontró el archivo indicado en --niri-kdl: $NIRI_KDL_SRC"
  exit 1
fi

# -----------------------------
# 0.1. Verificar root
# -----------------------------
if [[ $EUID -ne 0 ]]; then
  echo "❌ Este script debe ejecutarse con sudo."
  exit 1
fi

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
ZSHRC="$USER_HOME/.zshrc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/respaldo"

# Si vinieron con ruta relativa, resolverlas contra el directorio actual
if [[ -n "$HYPRLAND_LUA_SRC" ]]; then
  HYPRLAND_LUA_SRC="$(cd "$(dirname "$HYPRLAND_LUA_SRC")" && pwd)/$(basename "$HYPRLAND_LUA_SRC")"
fi
if [[ -n "$NIRI_KDL_SRC" ]]; then
  NIRI_KDL_SRC="$(cd "$(dirname "$NIRI_KDL_SRC")" && pwd)/$(basename "$NIRI_KDL_SRC")"
fi

# -----------------------------
# 0.1. Bootstrap de gum
# -----------------------------
if ! command -v gum &>/dev/null; then
  echo "📦 Instalando gum (TUI helper)..."
  pacman -S --noconfirm --needed gum >/dev/null 2>&1 || {
    echo "❌ No se pudo instalar gum. Revisa tu conexión o pacman.conf."
    exit 1
  }
fi

on_error() {
  local exit_code=$1
  local line_no=$2
  local failed_cmd=$3
  gum style --border rounded --border-foreground 196 --padding "1 3" --margin "1 0" \
    "❌ Falló un paso de la instalación" \
    "" \
    "Línea: $line_no" \
    "Comando: $failed_cmd" \
    "Código de salida: $exit_code" \
    "" \
    "Log completo: ${LOG_FILE:-"(aún no generado)"}"
  exit "$exit_code"
}
trap 'on_error $? $LINENO "$BASH_COMMAND"' ERR

export GUM_CHOOSE_CURSOR_FOREGROUND="25"
export GUM_CHOOSE_SELECTED_FOREGROUND="25"
export GUM_CONFIRM_PROMPT_FOREGROUND="25"
export GUM_SPIN_SPINNER_FOREGROUND="25"
export GUM_SPIN_SPINNER="dot"

banner() {
  gum style \
    --border rounded --border-foreground 25 \
    --padding "1 4" --margin "1 0" --align center \
    "🚀 Apps & Configuraciones Installer" "Chaotic-AUR · base-bar (Quickshell) · Dotfiles"
}

section() {
  gum style --foreground 25 --bold "▸ $1"
}

# -----------------------------
# Detección de consola básica (TTY sin terminal gráfica)
# -----------------------------
# En la consola cruda de Arch (antes de tener un WM/terminal gráfica) la
# fuente no tiene glifos para emoji ni para los bordes redondeados que usa
# gum, y su interfaz interactiva (bubbletea) puede directamente no
# renderizar bien ahí. Se detecta y se usa un menú numerado con `read`
# plano en su lugar, que siempre funciona en cualquier TTY.
IS_TTY_CONSOLE=false
[[ "$TERM" == "linux" ]] && IS_TTY_CONSOLE=true

# Saca los emoji conocidos que usa el script (lista fija, no rangos
# Unicode, para no depender de herramientas externas tipo perl/python).
strip_emoji() {
  sed -e 's/🔊//g; s/🤫//g; s/🌊//g; s/🌀//g; s/🔀//g; s/🟪//g; s/📦//g; s/✅//g; s/❌//g;
          s/🧹//g; s/📂//g; s/🎁//g; s/🔍//g; s/🖥️//g; s/📸//g; s/🎮//g;
          s/💬//g; s/🐚//g; s/🔐//g; s/🗂️//g; s/🎨//g; s/🐧//g; s/🔎//g' <<<"$1" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Selección de UNA opción. Usa gum en terminal gráfica, o un menú
# numerado con read en la consola básica.
ask_choice() {
  local header="$1"
  shift
  local opts=("$@")

  if ! $IS_TTY_CONSOLE; then
    gum choose --header "$header" "${opts[@]}"
    return
  fi

  {
    echo ""
    echo "== $(strip_emoji "$header") =="
    local i=1
    for o in "${opts[@]}"; do
      echo "  $i) $(strip_emoji "$o")"
      i=$((i + 1))
    done
  } >&2

  local n
  while true; do
    read -rp "Elegí un número [1-${#opts[@]}]: " n </dev/tty
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le "${#opts[@]}" ]; then
      echo "${opts[$((n - 1))]}"
      return
    fi
    echo "Opción inválida." >&2
  done
}

# Selección MÚLTIPLE (todas premarcadas por defecto). Usa gum en
# terminal gráfica, o un menú numerado en la consola básica donde se
# escriben los números a DESMARCAR.
ask_multi() {
  local header="$1"
  shift
  local opts=("$@")

  if ! $IS_TTY_CONSOLE; then
    local joined
    joined=$(
      IFS=,
      echo "${opts[*]}"
    )
    gum choose --no-limit --selected "$joined" --header "$header" "${opts[@]}"
    return
  fi

  {
    echo ""
    echo "== $(strip_emoji "$header") =="
    local i=1
    for o in "${opts[@]}"; do
      echo "  $i) $o"
      i=$((i + 1))
    done
    echo "  Todas están premarcadas. Escribí los NÚMEROS a DESMARCAR"
    echo "  separados por espacio (Enter vacío = dejarlas todas)."
  } >&2

  local input
  read -rp "Desmarcar: " input </dev/tty

  local exclude=()
  read -ra exclude <<<"$input"

  local i=1
  for o in "${opts[@]}"; do
    local skip=false
    for x in "${exclude[@]}"; do
      [[ "$x" == "$i" ]] && skip=true
    done
    $skip || echo "$o"
    i=$((i + 1))
  done
}

# Confirmación sí/no. Usa gum en terminal gráfica, o [s/N] con read en
# la consola básica.
ask_confirm() {
  local question="$1"
  if ! $IS_TTY_CONSOLE; then
    gum confirm "$question"
    return
  fi
  local ans
  read -rp "$(strip_emoji "$question") [s/N]: " ans </dev/tty
  [[ "$ans" =~ ^[sSyY] ]]
}

# Entrada de texto libre (para resolución/refresh manual de monitor,
# por ejemplo). Usa "gum input" en terminal gráfica, o read en la
# consola básica.
ask_input() {
  local prompt="$1"
  local default="${2:-}"
  local ans
  if ! $IS_TTY_CONSOLE; then
    gum input --placeholder "$default" --prompt "$(strip_emoji "$prompt"): "
    return
  fi
  if [[ -n "$default" ]]; then
    read -rp "$(strip_emoji "$prompt") [$default]: " ans </dev/tty
    echo "${ans:-$default}"
  else
    read -rp "$(strip_emoji "$prompt"): " ans </dev/tty
    echo "$ans"
  fi
}

# -----------------------------
# Detección y selección de monitores vía EDID
# -----------------------------
# DETECTED_MONITORS: array de "conector|resolución|refresh|escala"
# (ej: "DP-1|2560x1440|144.00|1"). Se lee directo de /sys/class/drm, así
# que funciona aunque todavía no haya compositor corriendo.
DETECTED_MONITORS=()

detect_monitors() {
  section "🔎 Detectando monitores conectados..."
  pacman -Sy --noconfirm --needed edid-decode >/dev/null 2>&1 || true

  local status_path
  for status_path in /sys/class/drm/card*-*/status; do
    [[ -f "$status_path" ]] || continue

    local drm_path conn status edid_path info res refresh
    drm_path=$(dirname "$status_path")
    conn=$(basename "$drm_path" | sed -E 's/^card[0-9]+-//')  # DP-1, HDMI-A-1, eDP-1...
    status=$(cat "$status_path" 2>/dev/null)
    [[ "$status" == "connected" ]] || continue

    edid_path="$drm_path/edid"
    res=""
    refresh=""

    # Reintenta un par de veces con una pequeña espera: en GPUs NVIDIA
    # (sobre todo con el panel cableado a la dGPU) el EDID a veces no
    # queda cacheado en sysfs hasta un instante después del boot.
    local attempt
    for attempt in 1 2 3; do
      if [[ -s "$edid_path" ]]; then
        break
      fi
      sleep 1
    done

    if [[ -s "$edid_path" ]]; then
      info=$(edid-decode "$edid_path" 2>/dev/null)
      res=$(grep -A2 "Detailed Timing Descriptors" <<<"$info" | grep -oE '[0-9]{3,4}x[0-9]{3,4}' | head -1)
      [[ -z "$res" ]] && res=$(grep -oE '[0-9]{3,4}x[0-9]{3,4}' <<<"$info" | sort -u | tail -1)
      refresh=$(grep -oE '[0-9]{2,3}\.[0-9]{2} Hz' <<<"$info" | sort -u | tail -1 | grep -oE '^[0-9.]+')
    fi

    if [[ -n "$res" ]]; then
      gum style --foreground 82 "  ✅ $conn detectado: ${res} @ ${refresh:-60.00}Hz"
      DETECTED_MONITORS+=("${conn}|${res}|${refresh:-60.00}|1")
    else
      gum style --foreground 244 "  ⚠️ $conn conectado pero no se pudo leer el EDID (normal en GPUs NVIDIA antes de que corra un compositor) — vas a poder configurarlo manualmente"
      DETECTED_MONITORS+=("${conn}|||1")
    fi
  done

  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    gum style --foreground 196 "  ⚠️ No se detectó ningún monitor conectado — se usará auto-detect del compositor."
  fi
}

# Devuelve, uno por línea, los modos "AnchoxAlto@Hz" que el EDID de ese
# conector reporta realmente soportar (no solo el preferido). Sirve
# para que el usuario elija un valor exacto en vez de escribir un Hz
# "a ciegas" que el compositor después ignora por no coincidir con
# ningún modo real (ej. escribir 144 cuando el panel reporta 143.98).
get_edid_modes() {
  local conn="$1"
  local edid_path=""
  local d
  for d in /sys/class/drm/card*-"${conn}"/edid; do
    [[ -s "$d" ]] && edid_path="$d" && break
  done
  [[ -z "$edid_path" ]] && return

  local info
  info=$(edid-decode "$edid_path" 2>/dev/null)
  grep -E '[0-9]{3,4}x[0-9]{3,4}.*[0-9]{2,3}\.[0-9]{2,3} ?Hz' <<<"$info" | while read -r line; do
    local res hz
    res=$(grep -oE '[0-9]{3,4}x[0-9]{3,4}' <<<"$line" | head -1)
    hz=$(grep -oE '[0-9]{2,3}\.[0-9]{2,3}' <<<"$line" | head -1)
    [[ -n "$res" && -n "$hz" ]] && echo "${res}@${hz}"
  done | awk '!seen[$0]++'
}

# Paso interactivo: para cada monitor detectado, preguntar si se usa lo
# detectado, se ingresa manualmente, o se deja en auto-detect (sin
# forzar nada). Modifica DETECTED_MONITORS in-place.
choose_monitor_settings() {
  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    return
  fi

  section "🖥️  Configuración de monitor(es)"
  local i
  for i in "${!DETECTED_MONITORS[@]}"; do
    local conn res refresh scale
    IFS='|' read -r conn res refresh scale <<<"${DETECTED_MONITORS[$i]}"

    local detected_label
    if [[ -n "$res" ]]; then
      detected_label="✅ Usar lo detectado (${res}@${refresh}Hz)"
    else
      detected_label="✅ Usar lo detectado (no se pudo leer resolución)"
    fi

    local choice
    choice=$(ask_choice "Monitor ${conn} — ¿qué configuración querés usar?" \
      "$detected_label" \
      "✏️  Elegir resolución/refresh manualmente" \
      "🤖 Dejar en auto-detect (sin forzar nada)")

    case "$choice" in
    *"manualmente"*)
      local new_res new_refresh new_scale
      local -a modes
      mapfile -t modes < <(get_edid_modes "$conn")

      if [[ ${#modes[@]} -gt 0 ]]; then
        local mode_opts=("${modes[@]}" "✏️  Ingresar otro valor a mano")
        local mode_choice
        mode_choice=$(ask_choice "Modos reales que reporta ${conn} — elegí uno:" "${mode_opts[@]}")
        if [[ "$mode_choice" == "✏️  Ingresar otro valor a mano" ]]; then
          new_res=$(ask_input "Resolución para ${conn} (formato AnchoxAlto, ej: 1920x1080)" "$res")
          new_refresh=$(ask_input "Refresh rate para ${conn} en Hz (ej: 60.00)" "${refresh:-60.00}")
        else
          new_res="${mode_choice%@*}"
          new_refresh="${mode_choice#*@}"
        fi
      else
        gum style --foreground 244 "  ⚠️ No se pudo leer la lista de modos del EDID para ${conn} — ingresá el valor a mano."
        new_res=$(ask_input "Resolución para ${conn} (formato AnchoxAlto, ej: 1920x1080)" "$res")
        new_refresh=$(ask_input "Refresh rate para ${conn} en Hz (ej: 60.00)" "${refresh:-60.00}")
      fi

      new_scale=$(ask_input "Escala para ${conn} (ej: 1, 1.5, 2)" "${scale:-1}")
      DETECTED_MONITORS[$i]="${conn}|${new_res}|${new_refresh}|${new_scale}"
      gum style --foreground 82 "  ✅ ${conn} → ${new_res}@${new_refresh}Hz, escala ${new_scale}"
      ;;
    *"auto-detect"*)
      DETECTED_MONITORS[$i]="${conn}|||${scale:-1}"
      gum style --foreground 244 "  🤖 ${conn} → sin forzar (auto-detect del compositor)"
      ;;
    *)
      gum style --foreground 82 "  ✅ ${conn} → se usa lo detectado"
      ;;
    esac
  done
}

# Genera el bloque hl.monitor({...}) de Hyprland (sintaxis real del
# hyprland.lua) para cada monitor detectado, y lo devuelve por stdout
# (para reemplazar el marcador AUTO_MONITOR_BLOCK).
generate_hypr_monitor_block() {
  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    cat <<'EOF'
hl.monitor({
	output = "",
	mode = "preferred",
	position = "auto",
	scale = 1.0,
})
EOF
    return
  fi
  local m conn res refresh scale
  for m in "${DETECTED_MONITORS[@]}"; do
    IFS='|' read -r conn res refresh scale <<<"$m"
    if [[ -n "$res" ]]; then
      cat <<EOF
hl.monitor({
	output = "${conn}",
	mode = "${res}@${refresh}",
	position = "auto",
	scale = ${scale:-1.0},
})
EOF
    else
      cat <<EOF
hl.monitor({
	output = "${conn}",
	mode = "preferred",
	position = "auto",
	scale = ${scale:-1.0},
})
EOF
    fi
  done
}

# Genera el/los bloque(s) "output" de Niri (sintaxis KDL) para el
# conector detectado y los devuelve por stdout (para reemplazar el
# marcador AUTO_MONITOR_BLOCK dentro del config.kdl).
generate_niri_output_block() {
  if [[ ${#DETECTED_MONITORS[@]} -eq 0 ]]; then
    echo "// No se detectó ningún monitor — usando auto-detect de niri por defecto"
    return
  fi
  local m conn res refresh scale
  for m in "${DETECTED_MONITORS[@]}"; do
    IFS='|' read -r conn res refresh scale <<<"$m"
    echo "output \"${conn}\" {"
    [[ -n "$res" ]] && echo "    mode \"${res}@${refresh}\""
    echo "    scale ${scale:-1}"
    echo "}"
  done
}

# -----------------------------
# 0.2. Selección de modo
# -----------------------------
clear
banner

MODE=$(ask_choice "Elige el modo de instalación:" \
  "🔊 Interactivo (sudo, con confirmaciones)" \
  "🤫 Silencioso (automático, sin pausas)")

case "$MODE" in
*Silencioso*) SILENT=true ;;
*) SILENT=false ;;
esac

LOG_FILE="/tmp/instalar_hyprland_$(date +%s).log"
: >"$LOG_FILE"

if $SILENT; then
  gum style --foreground 244 "Modo silencioso: sin pausas ni confirmaciones. Verás la salida de cada paso en pantalla y también en: $LOG_FILE"
else
  gum style --foreground 244 "Modo interactivo: se pedirá confirmación en pasos clave. Verás la salida de cada paso en pantalla y también en: $LOG_FILE"
fi
sleep 1

# -----------------------------
# 0.2.1. ¿Sos el dueño del repo o alguien probando el script?
# -----------------------------
# Controla dos cosas: (1) si los respaldos de apps se restauran TODOS
# automáticamente sin preguntar app por app (dueño) o si se pregunta
# limpio/restaurar por cada una (cualquier otra persona); y (2) si los
# binds de mouse de keyd (específicos de TU hardware) se aplican solos
# o se ofrecen como opcionales.
OWNER_CHOICE=$(ask_choice "¿Quién está corriendo este instalador?" \
  "👤 Soy yo (el dueño del repo) — restaurar todos mis respaldos automático" \
  "🌍 Soy otra persona probando el script — preguntame app por app")

case "$OWNER_CHOICE" in
*"Soy yo"*) OWNER_MODE=true ;;
*) OWNER_MODE=false ;;
esac
if $OWNER_MODE; then
  gum style --foreground 244 "Modo dueño: respaldos se restauran todos por defecto."
else
  gum style --foreground 244 "Modo invitado: se va a preguntar limpio/restaurar app por app."
fi
sleep 1

# -----------------------------
# 0.3. Selección de compositor
# -----------------------------
COMP=$(ask_choice "¿Qué querés instalar?" \
  "🌊 Hyprland (window manager + apps y configuraciones)" \
  "🌀 Niri (window manager + apps y configuraciones)" \
  "🔀 Ambos (Hyprland + Niri + apps y configuraciones)" \
  "🟪 KDE Plasma (escritorio completo)" \
  "📦 Solo apps y configuraciones (sin window manager)")

INSTALL_KDE=false
INSTALL_HYPRLAND=false
INSTALL_NIRI=false
case "$COMP" in
*Ambos*)
  INSTALL_HYPRLAND=true
  INSTALL_NIRI=true
  ;;
*Hyprland*)
  INSTALL_HYPRLAND=true
  INSTALL_NIRI=false
  ;;
*Niri*)
  INSTALL_HYPRLAND=false
  INSTALL_NIRI=true
  ;;
*"KDE Plasma"*)
  INSTALL_HYPRLAND=false
  INSTALL_NIRI=false
  INSTALL_KDE=true
  ;;
*"Solo apps"*)
  INSTALL_HYPRLAND=false
  INSTALL_NIRI=false
  ;;
*)
  # No debería pasar nunca, pero si $COMP vino vacío o no matchea
  # ninguna opción, cortamos con un error BIEN visible (echo directo,
  # no solo gum) en vez de seguir en silencio con un valor por defecto
  # que puede confundir sobre qué se está instalando.
  echo "❌ No se reconoció la selección del window manager: '$COMP'" >&2
  echo "   Volvé a correr el script y probá de nuevo." >&2
  exit 1
  ;;
esac

if $INSTALL_KDE; then
  gum style --foreground 244 "Instalación de KDE Plasma, más apps y configuraciones."
elif $INSTALL_HYPRLAND && $INSTALL_NIRI; then
  gum style --foreground 244 "Instalación de window manager: Hyprland + Niri, más apps y configuraciones."
elif $INSTALL_HYPRLAND; then
  gum style --foreground 244 "Instalación de window manager: Hyprland, más apps y configuraciones."
elif $INSTALL_NIRI; then
  gum style --foreground 244 "Instalación de window manager: Niri, más apps y configuraciones."
else
  gum style --foreground 244 "Sin window manager — solo apps y configuraciones."
fi
sleep 1

# -----------------------------
# 0.4.1. Configuración de monitor(es) — paso obligatorio
# -----------------------------
# Se hace acá, antes de elegir apps (todo/por categorías), porque el
# monitor es parte de la config base del compositor, no una app extra.
if $INSTALL_HYPRLAND || $INSTALL_NIRI; then
  detect_monitors
  choose_monitor_settings
fi

# -----------------------------
# 0.5. base-bar (Quickshell) — automático con Niri (sin preguntar)
# -----------------------------
INSTALL_BASEBAR=false

if $INSTALL_KDE; then
  gum style --foreground 244 "base-bar (Quickshell) es para Niri — se omite con KDE Plasma."
elif $INSTALL_HYPRLAND && ! $INSTALL_NIRI; then
  gum style --foreground 244 "base-bar (Quickshell) por ahora solo está integrada para Niri — se omite con Hyprland."
elif $INSTALL_NIRI; then
  INSTALL_BASEBAR=true
  gum style --foreground 244 "base-bar (Quickshell) se instala automáticamente, limpio (elegiste Niri)."
fi

# -----------------------------
# 0.5.1. Selección de restauración de respaldo
# -----------------------------
RESTORE_HYPR_CONFIG=false
RESTORE_NIRI_CONFIG=false
RESTORE_KDE_CONFIG=false

if $INSTALL_KDE; then
  if $OWNER_MODE && [ -d "$BACKUP_DIR/kde" ]; then
    RESTORE_KDE_CONFIG=true
  elif ! $OWNER_MODE; then
    KDE_RESTORE_CHOICE=$(ask_choice "KDE Plasma: ¿limpio o restaurar desde respaldo/kde?" \
      "🧹 Limpio" \
      "📂 Restaurar respaldo/kde")
    case "$KDE_RESTORE_CHOICE" in
    *Restaurar*) RESTORE_KDE_CONFIG=true ;;
    *) RESTORE_KDE_CONFIG=false ;;
    esac
  fi
fi

# Hyprland/Niri: igual que cualquier otra app, solo se pregunta si
# existe respaldo/hypr o respaldo/niri (y solo en modo invitado — en
# modo dueño se restaura directo sin preguntar). Si no existe, es
# limpio directo (y ahí --hyprland-lua/--niri-kdl sí se aplican, ver
# sección 10.1).
if $INSTALL_HYPRLAND && [ -d "$BACKUP_DIR/hypr" ]; then
  if $OWNER_MODE; then
    RESTORE_HYPR_CONFIG=true
  else
    HYPR_RESTORE_CHOICE=$(ask_choice "Hyprland: ¿limpio o restaurar desde respaldo/hypr?" \
      "🧹 Limpio" \
      "📂 Restaurar respaldo/hypr")
    case "$HYPR_RESTORE_CHOICE" in
    *Restaurar*) RESTORE_HYPR_CONFIG=true ;;
    *) RESTORE_HYPR_CONFIG=false ;;
    esac
  fi
fi

if $INSTALL_NIRI && [ -d "$BACKUP_DIR/niri" ]; then
  if $OWNER_MODE; then
    RESTORE_NIRI_CONFIG=true
  else
    NIRI_RESTORE_CHOICE=$(ask_choice "Niri: ¿limpio o restaurar desde respaldo/niri?" \
      "🧹 Limpio" \
      "📂 Restaurar respaldo/niri")
    case "$NIRI_RESTORE_CHOICE" in
    *Restaurar*) RESTORE_NIRI_CONFIG=true ;;
    *) RESTORE_NIRI_CONFIG=false ;;
    esac
  fi
fi

# -----------------------------
# 0.8. Categorías de apps — una por una, con detección de instalado
# -----------------------------
# Siempre se recorre categoría por categoría (sin atajo de "instalar
# todo"), cada una en su propia pantalla. Antes de cada categoría se
# avisa qué de eso ya está instalado.
INSTALL_CAT_PAMAC=false
INSTALL_CAT_HOWDY=false

# Muestra qué paquetes de una lista ya están instalados, si hay alguno.
show_already_installed() {
  local already=()
  for p in "$@"; do
    pacman -Qq "$p" &>/dev/null && already+=("$p")
  done
  if [[ ${#already[@]} -gt 0 ]]; then
    gum style --foreground 82 "  ✔ Ya instalado: $(
      IFS=', '
      echo "${already[*]}"
    )"
  fi
}

# Selecciona apps individuales dentro de una categoría. Recibe el
# título y la lista de paquetes; deja el resultado en SEL_RESULT.
pick_apps_in_category() {
  local title="$1"
  shift
  local all_pkgs=("$@")
  show_already_installed "${all_pkgs[@]}"
  # shellcheck disable=SC2207
  SEL_RESULT=($(ask_multi \
    "$title — desmarcá lo que NO quieras (espacio, enter para confirmar):" \
    "${all_pkgs[@]}"))
}

# -----------------------------
# Instalación limpia vs. restaurar respaldo, POR APP
# -----------------------------
# Para cada paquete elegido (en cualquier categoría), si existe
# respaldo/<paquete> se pregunta si querés instalación limpia (config
# de ejemplo del paquete) o restaurar tu respaldo para esa app puntual.
# APP_RESTORE_CHOICE: mapa "nombre_carpeta" -> "clean" | "restore".
declare -A APP_RESTORE_CHOICE

ask_app_restore_choices() {
  local pkg
  for pkg in "$@"; do
    [[ -d "$BACKUP_DIR/$pkg" ]] || continue
    [[ -n "${APP_RESTORE_CHOICE[$pkg]:-}" ]] && continue  # ya preguntado

    if $OWNER_MODE; then
      APP_RESTORE_CHOICE[$pkg]="restore"
      continue
    fi

    local choice
    choice=$(ask_choice "📂 ${pkg}: encontré respaldo/${pkg} — ¿qué querés usar?" \
      "🧹 Limpio (config de ejemplo del paquete)" \
      "📂 Restaurar respaldo/${pkg}")
    case "$choice" in
    *Restaurar*) APP_RESTORE_CHOICE[$pkg]="restore" ;;
    *) APP_RESTORE_CHOICE[$pkg]="clean" ;;
    esac
  done
}

SEL_DESKTOP=()
SEL_CAPTURE=()
SEL_GAMING=()
SEL_APPS=()
SEL_TERMINAL=()
SEL_SNAPSHOTS=()

DESKTOP_ALL=(libappindicator-gtk3 nwg-drawer nwg-look papirus-icon-theme swaybg swaync
  thunar tumbler ffmpegthumbnailer wl-clip-persist wl-clipboard cliphist
  adw-gtk-theme qt6ct-kde gsettings-qt6)
CAPTURE_ALL=(grim slurp gpu-screen-recorder cava mpvpaper)
GAMING_ALL=(wine-staging winetricks protontricks protonplus mangojuice steam gamemode gamescope vulkan-tools)

# Base original tuya + extras que se agregaron después para hacer el
# script más "universal" (editores, etc.). En OWNER_MODE se omiten los
# extras — solo se instala lo que ya tenías. En modo invitado se
# ofrecen ambos.
APPS_ALL_BASE=(telegram-desktop discord helium-browser-bin proton-vpn-gtk-app localsend
  mission-center fastfetch gnome-firmware gearlever chafa xarchiver)
APPS_ALL_EXTRA=(visual-studio-code-bin vscodium-bin sublime-text-4 geany kate)

TERMINAL_ALL_BASE=(neovim neovim-qt fzf jq eza yazi)
TERMINAL_ALL_EXTRA=(vim micro helix emacs-nox)

if $OWNER_MODE; then
  APPS_ALL=("${APPS_ALL_BASE[@]}")
  TERMINAL_ALL=("${TERMINAL_ALL_BASE[@]}")
else
  APPS_ALL=("${APPS_ALL_BASE[@]}" "${APPS_ALL_EXTRA[@]}")
  TERMINAL_ALL=("${TERMINAL_ALL_BASE[@]}" "${TERMINAL_ALL_EXTRA[@]}")
fi

SNAPSHOTS_ALL=(btrfs-assistant btrfs-progs snapper snap-pac)

# Emulador de terminal — pregunta de opción única, no checklist (solo
# se instala UNO). kitty queda como opción, ya no viene fijo/obligado.
TERMINAL_EMU_CHOICE=$(ask_choice "🖥️  ¿Qué emulador de terminal querés instalar?" \
  "kitty" "alacritty" "foot" "wezterm")
SEL_TERMINAL_EMU="$TERMINAL_EMU_CHOICE"
gum style --foreground 82 "  ✅ Emulador de terminal: $SEL_TERMINAL_EMU"

# Gestor de paquetes gráfico. Octopi es un agregado nuevo (no estaba en
# tu setup original) — en OWNER_MODE ni se ofrece como opción.
INSTALL_CAT_PAMAC=false
INSTALL_CAT_OCTOPI=false
if $OWNER_MODE; then
  show_already_installed pamac-aur
  PKG_MANAGER_CHOICE=$(ask_choice "📦 ¿Instalar el gestor de paquetes gráfico (pamac)?" "✅ Sí" "❌ No")
  grep -q "Sí" <<<"$PKG_MANAGER_CHOICE" && INSTALL_CAT_PAMAC=true
else
  show_already_installed pamac-aur octopi
  PKG_MANAGER_CHOICE=$(ask_choice "📦 ¿Qué gestor de paquetes gráfico querés instalar?" \
    "Pamac" "Octopi" "Ninguno")
  case "$PKG_MANAGER_CHOICE" in
  Pamac) INSTALL_CAT_PAMAC=true ;;
  Octopi) INSTALL_CAT_OCTOPI=true ;;
  esac
fi

pick_apps_in_category "🖥️  Utilidades de escritorio" "${DESKTOP_ALL[@]}"
SEL_DESKTOP=("${SEL_RESULT[@]}")

pick_apps_in_category "📸 Capturas y grabación" "${CAPTURE_ALL[@]}"
SEL_CAPTURE=("${SEL_RESULT[@]}")

pick_apps_in_category "🎮 Gaming" "${GAMING_ALL[@]}"
SEL_GAMING=("${SEL_RESULT[@]}")

pick_apps_in_category "💬 Apps y comunicación" "${APPS_ALL[@]}"
SEL_APPS=("${SEL_RESULT[@]}")

pick_apps_in_category "🐚 Terminal avanzada" "${TERMINAL_ALL[@]}"
SEL_TERMINAL=("${SEL_RESULT[@]}")

# Autenticación facial (un solo paquete → sí/no, no picker)
show_already_installed howdy-git
HOWDY_CHOICE=$(ask_choice "🔐 ¿Instalar autenticación facial (howdy)?" "✅ Sí" "❌ No")
grep -q "Sí" <<<"$HOWDY_CHOICE" && INSTALL_CAT_HOWDY=true

pick_apps_in_category "🗂️  Snapshots BTRFS" "${SNAPSHOTS_ALL[@]}"
SEL_SNAPSHOTS=("${SEL_RESULT[@]}")

# Ahora que ya sabemos TODO lo que se va a instalar, preguntamos
# limpio/restaurar por cada app elegida que tenga respaldo propio.
section "📂 Instalación limpia vs. respaldo, por app"
ask_app_restore_choices "$SEL_TERMINAL_EMU" \
  "${SEL_DESKTOP[@]}" "${SEL_CAPTURE[@]}" "${SEL_GAMING[@]}" \
  "${SEL_APPS[@]}" "${SEL_TERMINAL[@]}" "${SEL_SNAPSHOTS[@]}"

# Helpers de ejecución
# -----------------------------

run_step() {
  local desc="$1"
  shift
  section "$desc"
  "$@" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló: $desc" "Ver detalle en: $LOG_FILE"
    exit "$rc"
  fi
}

confirm_step() {
  local question="$1"
  if $SILENT; then
    return 0
  fi
  ask_confirm "$question"
}

log_or_show() {
  if $SILENT; then
    "$@" >>"$LOG_FILE" 2>&1
  else
    "$@"
  fi
}

# Instala una lista de paquetes con pacman mostrando una barra de progreso
# real con porcentaje (parseando las líneas "(n/total) installing ...").
# Toda la salida cruda igual queda guardada en $LOG_FILE por si falla algo.
run_pacman_progress() {
  local desc="$1"
  shift
  section "$desc"

  local tmp_out
  tmp_out=$(mktemp)
  local total_pkgs=$#

  # Antes usábamos stdbuf + captura por archivo normal, pero pacman
  # detecta que no hay una terminal real y deja de reescribir su barra
  # en vivo — solo imprime una línea por paquete cuando termina. Por eso
  # la barra "saltaba" en vez de ir fluida. Con `script` le damos una
  # pseudo-terminal real: pacman usa su barra nativa con \r y % interno
  # de cada paquete, y de ahí sacamos el progreso real.
  local pkg_args=()
  for p in "$@"; do pkg_args+=("$(printf '%q' "$p")"); done
  script -qefc "pacman -S --noconfirm --needed ${pkg_args[*]}" "$tmp_out" >/dev/null 2>&1 &
  local pid=$!

  local bar_len=30 cur=0 tot=$total_pkgs pkg="" pct=0 filled=0 last=""
  local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' spin_i=0 spin_phase_msg="" subpct=0

  while kill -0 "$pid" 2>/dev/null; do
    # El archivo tiene \r (actualizaciones en vivo) en vez de \n, y como
    # ahora pacman cree que tiene una terminal real, también mete
    # códigos de color ANSI antes de "(n/total)" — hay que sacarlos
    # antes de parsear, si no la línea no matchea y las variables
    # quedan vacías (causaba "printf: : invalid number").
    last=$(tr '\r' '\n' <"$tmp_out" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' | \
      grep -E '\([0-9]+/[0-9]+\) (installing|upgrading|reinstalling)' | tail -1)
    if [[ -n "$last" ]]; then
      cur=$(grep -oE '^\([0-9]+' <<<"$last" | tr -d '(')
      tot=$(grep -oE '^\([0-9]+/[0-9]+\)' <<<"$last" | grep -oE '/[0-9]+' | tr -d '/')
      pkg=$(sed -E 's#^\([0-9]+/[0-9]+\) [a-z]+ ([^ ]+).*#\1#' <<<"$last")
      subpct=$(grep -oE '[0-9]+%' <<<"$last" | tail -1 | tr -d '%')
      # Blindaje: si por algún motivo alguna quedó vacía, usar 0 en vez
      # de dejar que printf reviente con "invalid number".
      [[ -z "$subpct" ]] && subpct=0
      [[ -z "$cur" ]] && cur=1
      [[ -z "$tot" || "$tot" -eq 0 ]] && tot=$total_pkgs
      [[ -z "$pkg" ]] && pkg="..."
      pct=$(( ((cur - 1) * 100 + subpct) / tot ))
      [[ $pct -gt 100 ]] && pct=100
      [[ $pct -lt 0 ]] && pct=0
      filled=$((pct * bar_len / 100))
      printf "\r  \033[34m[%s%s]\033[0m %3d%%  (%d/%d) %-40s" \
        "$(printf '█%.0s' $(seq 1 "$filled" 2>/dev/null))" \
        "$(printf '░%.0s' $(seq 1 $((bar_len - filled)) 2>/dev/null))" \
        "$pct" "$cur" "$tot" "$pkg"
    else
      # Todavía no hay nada que contar — pacman sigue resolviendo
      # dependencias, sincronizando bases de datos o descargando.
      # Spinner para que se vea movimiento real desde el arranque.
      spin_phase_msg=$(tr '\r' '\n' <"$tmp_out" 2>/dev/null | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tail -1 | \
        grep -oE 'downloading\.\.\.|Synchronizing package databases\.\.\.|resolving dependencies\.\.\.|looking for conflicting packages\.\.\.|Retrieving packages\.\.\.' | tail -1)
      [[ -z "$spin_phase_msg" ]] && spin_phase_msg="preparando..."
      spin_i=$(((spin_i + 1) % ${#spin_chars}))
      printf "\r  \033[34m%s\033[0m %-50s" "${spin_chars:$spin_i:1}" "$spin_phase_msg"
    fi
    sleep 0.1
  done

  local rc=0
  wait "$pid" || rc=$?
  [[ -z "$tot" || "$tot" -eq 0 ]] && tot=$total_pkgs
  printf "\r  \033[34m[%s]\033[0m %3d%%  (%d/%d) %-40s\n" \
    "$(printf '█%.0s' $(seq 1 "$bar_len"))" 100 "$tot" "$tot" "listo"

  tr '\r' '\n' <"$tmp_out" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g' >>"$LOG_FILE" 2>/dev/null

  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló: $desc" "Ver detalle en: $LOG_FILE"
    rm -f "$tmp_out"
    exit "$rc"
  fi

  rm -f "$tmp_out"
  gum style --foreground 82 "✅ $desc"
}

# -----------------------------
# 0.9. Resumen de lo que se va a instalar
# -----------------------------
SUMMARY_LINES=()

if $INSTALL_KDE; then
  SUMMARY_LINES+=("🟪 Escritorio: KDE Plasma")
  if $RESTORE_KDE_CONFIG; then
    SUMMARY_LINES+=("   • KDE: restaurar respaldo/kde")
  else
    SUMMARY_LINES+=("   • KDE: limpio")
  fi
elif $INSTALL_HYPRLAND && $INSTALL_NIRI; then
  SUMMARY_LINES+=("🌊🌀 Window manager: Hyprland + Niri")
elif $INSTALL_HYPRLAND; then
  SUMMARY_LINES+=("🌊 Window manager: Hyprland")
elif $INSTALL_NIRI; then
  SUMMARY_LINES+=("🌀 Window manager: Niri")
else
  SUMMARY_LINES+=("📦 Sin window manager (solo apps y configuraciones)")
fi

if $INSTALL_HYPRLAND; then
  if $RESTORE_HYPR_CONFIG; then
    SUMMARY_LINES+=("   • Hyprland: restaurar respaldo/hypr")
  elif [[ -n "$HYPRLAND_LUA_SRC" ]]; then
    SUMMARY_LINES+=("   • Hyprland: limpio, con hyprland.lua de --hyprland-lua")
  else
    SUMMARY_LINES+=("   • Hyprland: limpio (config de ejemplo del paquete)")
  fi
fi

if $INSTALL_NIRI; then
  if $RESTORE_NIRI_CONFIG; then
    SUMMARY_LINES+=("   • Niri: restaurar respaldo/niri")
  elif [[ -n "$NIRI_KDL_SRC" ]]; then
    SUMMARY_LINES+=("   • Niri: limpio, con config.kdl de --niri-kdl")
  else
    SUMMARY_LINES+=("   • Niri: limpio (config por defecto del paquete)")
  fi
fi

if $INSTALL_BASEBAR; then
  SUMMARY_LINES+=("🎨 base-bar (Quickshell): sí — kitty, nwg-drawer, neovim, matugen")
fi

SUMMARY_LINES+=("🖥️  Terminal: $SEL_TERMINAL_EMU")

CAT_SUMMARY=()
$INSTALL_CAT_PAMAC && CAT_SUMMARY+=("pamac")
$INSTALL_CAT_OCTOPI && CAT_SUMMARY+=("octopi")
[[ ${#SEL_DESKTOP[@]} -gt 0 ]] && CAT_SUMMARY+=("escritorio (${#SEL_DESKTOP[@]})")
[[ ${#SEL_CAPTURE[@]} -gt 0 ]] && CAT_SUMMARY+=("capturas (${#SEL_CAPTURE[@]})")
[[ ${#SEL_GAMING[@]} -gt 0 ]] && CAT_SUMMARY+=("gaming (${#SEL_GAMING[@]})")
[[ ${#SEL_APPS[@]} -gt 0 ]] && CAT_SUMMARY+=("apps/comunicación (${#SEL_APPS[@]})")
[[ ${#SEL_TERMINAL[@]} -gt 0 ]] && CAT_SUMMARY+=("terminal (${#SEL_TERMINAL[@]})")
$INSTALL_CAT_HOWDY && CAT_SUMMARY+=("howdy")
[[ ${#SEL_SNAPSHOTS[@]} -gt 0 ]] && CAT_SUMMARY+=("snapshots (${#SEL_SNAPSHOTS[@]})")
if [[ ${#CAT_SUMMARY[@]} -eq 0 ]]; then
  SUMMARY_LINES+=("📦 Apps: ninguna categoría extra elegida")
else
  SUMMARY_LINES+=("📦 Apps: $(
    IFS=,
    echo "${CAT_SUMMARY[*]}"
  )")
  fi

gum style --border rounded --border-foreground 25 --padding "1 3" --margin "1 0" \
  "📋 RESUMEN DE INSTALACIÓN" "" "${SUMMARY_LINES[@]}"

if ! $SILENT; then
  ask_confirm "¿Continuar con la instalación?" || {
    echo "Cancelado."
    exit 0
  }
fi

section "Iniciando la instalación de apps, configuraciones y el window manager seleccionado (si corresponde)..."

# -----------------------------
# 1. Importar las llaves GPG
# -----------------------------
run_step "🔑 Importando la llave de Chaotic-AUR..." bash -c 'pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && pacman-key --lsign-key 3056513887B78AEB'

# -----------------------------
# 2. Instalar Keyring y Mirrorlist
# -----------------------------
run_step "📥 Instalando chaotic-keyring y chaotic-mirrorlist..." pacman -U --noconfirm \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

# -----------------------------
# 3. Añadir repo a pacman.conf
# -----------------------------
CONF="/etc/pacman.conf"
REPO="\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist"

if ! grep -q "\[chaotic-aur\]" "$CONF"; then
  if confirm_step "¿Añadir el repositorio [chaotic-aur] a $CONF?"; then
    echo -e "$REPO" >>"$CONF"
    section "✅ Repo añadido a pacman.conf"
  else
    gum style --foreground 196 "⏭️  Repo NO añadido (elegido por el usuario). El script puede fallar más adelante."
  fi
else
  gum style --foreground 244 "⚠️ Chaotic-AUR ya está en pacman.conf"
fi
# -----------------------------
# 4. Sincronizar y actualizar
# -----------------------------
run_step "🔄 Actualizando bases de datos y sistema..." pacman -Syyu --noconfirm

# -----------------------------
# 5. Instalar apps, configuraciones y el window manager seleccionado (si corresponde)
# -----------------------------
PACMAN_PKGS=(
  # Audio (PipeWire + WirePlumber, el stack estándar actual)
  pipewire
  pipewire-alsa
  pipewire-pulse
  pipewire-jack
  wireplumber
  # Básicos de escritorio (necesarios para cualquier sesión gráfica)
  keyd
  brightnessctl
  pavucontrol
  xdg-desktop-portal
  polkit-gnome
  sddm
  xorg-server
  xorg-xhost
  xorg-xinit
  avahi
  firewalld
  os-prober
  imagemagick
  python
  git
  wget
  xdg-user-dirs
  jq
  pacman-contrib
)

if $INSTALL_HYPRLAND; then
  PACMAN_PKGS+=(
    hyprcursor
    hyprgraphics
    hypridle
    hyprland
    hyprland-guiutils
    hyprland-protocols
    hyprland-qt-support
    hyprlang
    hyprsunset
    xdg-desktop-portal-hyprland
  )
fi

if $INSTALL_NIRI; then
  PACMAN_PKGS+=(
    niri
    xwayland-satellite
    xdg-desktop-portal-gnome
    # base-bar: barra propia en Quickshell (reemplaza a Noctalia)
    quickshell
    qt6-declarative
    qt6-svg
    qt6-wayland
    kitty
    nwg-drawer
    neovim
    matugen
    upower
    lm_sensors
    grim
    slurp
    swaybg
    curl
    gnupg
    git
  )
fi

if $INSTALL_KDE; then
  PACMAN_PKGS+=(
    plasma-desktop
    plasma-nm
    plasma-pa
    plasma-systemmonitor
    kscreen
    powerdevil
    sddm-kcm
    dolphin
    konsole
    kate
    spectacle
    xdg-desktop-portal-kde
    print-manager
  )
fi

$INSTALL_CAT_PAMAC && PACMAN_PKGS+=(pamac)
$INSTALL_CAT_OCTOPI && PACMAN_PKGS+=(octopi)

PACMAN_PKGS+=("$SEL_TERMINAL_EMU")

[[ ${#SEL_DESKTOP[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_DESKTOP[@]}")
[[ ${#SEL_CAPTURE[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_CAPTURE[@]}")
[[ ${#SEL_GAMING[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_GAMING[@]}")
[[ ${#SEL_APPS[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_APPS[@]}")
[[ ${#SEL_TERMINAL[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_TERMINAL[@]}")

$INSTALL_CAT_HOWDY && PACMAN_PKGS+=(howdy-git)

[[ ${#SEL_SNAPSHOTS[@]} -gt 0 ]] && PACMAN_PKGS+=("${SEL_SNAPSHOTS[@]}")

# Filtra paquetes que no existen en ningún repo sincronizado (oficial o
# chaotic-aur) ANTES de instalar. Un solo nombre inválido en el lote
# hace que pacman aborte TODA la transacción, no solo ese paquete — así
# que en vez de dejar que tumbe todo, lo avisamos y seguimos con el
# resto. (Paquetes solo-AUR sin build en chaotic-aur, como suele pasar
# con algunos "-bin" por temas de licencia, caen acá.)
UNAVAILABLE_PKGS=()
AVAILABLE_PKGS=()
for pkg in "${PACMAN_PKGS[@]}"; do
  if pacman -Si "$pkg" &>/dev/null; then
    AVAILABLE_PKGS+=("$pkg")
  else
    UNAVAILABLE_PKGS+=("$pkg")
  fi
done
PACMAN_PKGS=("${AVAILABLE_PKGS[@]}")

if [[ ${#UNAVAILABLE_PKGS[@]} -gt 0 ]]; then
  gum style --foreground 196 "⚠️ No se encontraron en ningún repo sincronizado (se omiten, no bloquean el resto): $(
    IFS=', '
    echo "${UNAVAILABLE_PKGS[*]}"
  )"
  gum style --foreground 244 "   Si alguno lo necesitás igual, probá instalarlo aparte con un AUR helper (yay/paru) después."
fi

run_pacman_progress "🖥️ Instalando apps, configuraciones y utilidades (${#PACMAN_PKGS[@]} paquetes)..." \
  "${PACMAN_PKGS[@]}"

gum style --foreground 82 "✅ Paquetes instalados correctamente."

# -----------------------------
# 5.0.1. Aplicar tema por defecto (Papirus + adw-gtk3-dark + qt6ct)
# -----------------------------
# Instalar los paquetes de tema no alcanza si nadie le dice a GTK/Qt
# que los use. Esto corre ANTES de restaurar respaldo/ (sección 10), a
# propósito: si tenés respaldo/qt6ct, respaldo/gtk-3.0, etc., esos van
# a pisar lo que se escribe acá — esto es solo el fallback razonable
# para instalación limpia, no toca lo tuyo si existe.
section "🎨 Aplicando tema por defecto (Papirus + adw-gtk3-dark + qt6ct)..."

# GTK3 / GTK4
if pacman -Qq papirus-icon-theme &>/dev/null && pacman -Qq adw-gtk-theme &>/dev/null; then
  for gtkver in gtk-3.0 gtk-4.0; do
    GTK_CONF_DIR="$USER_HOME/.config/$gtkver"
    sudo -u "$REAL_USER" mkdir -p "$GTK_CONF_DIR"
    cat >"$GTK_CONF_DIR/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-icon-theme-name=Papirus-Dark
gtk-application-prefer-dark-theme=1
EOF
    chown "$REAL_USER:$REAL_USER" "$GTK_CONF_DIR/settings.ini"
  done

  # dconf, para las apps GTK que leen gsettings en vez de settings.ini.
  # Ojo: en este punto de la instalación no hay sesión D-Bus activa
  # (recién se está bootstrapeando el sistema), así que "dconf write"
  # va a fallar con un error de dbus-launch de forma esperada. Con
  # "|| true" evitamos que ese fallo aborte TODO el script (el trap de
  # errores lo tomaría como fatal si no). settings.ini ya cubre la
  # mayoría de las apps GTK igual; esto es solo un extra best-effort.
  if command -v dconf &>/dev/null; then
    sudo -u "$REAL_USER" dbus-run-session -- dconf write /org/gnome/desktop/interface/gtk-theme "'adw-gtk3-dark'" 2>>"$LOG_FILE" || true
    sudo -u "$REAL_USER" dbus-run-session -- dconf write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'" 2>>"$LOG_FILE" || true
    sudo -u "$REAL_USER" dbus-run-session -- dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'" 2>>"$LOG_FILE" || true
  fi

  gum style --foreground 82 "✅ GTK3/GTK4: Papirus-Dark + adw-gtk3-dark aplicados."
else
  gum style --foreground 244 "⏭️  Papirus/adw-gtk-theme no están instalados (no se eligieron en 'Utilidades de escritorio') — se omite el tema GTK."
fi

# Qt6 (vía qt6ct-kde — la variante con parches KDE que pide Noctalia
# para que apps KDE como Dolphin lean bien el color scheme; qt6ct a
# secas puede mostrar colores incorrectos en esas apps).
if pacman -Qq qt6ct-kde &>/dev/null || pacman -Qq qt6ct &>/dev/null; then
  QT6CT_DIR="$USER_HOME/.config/qt6ct"
  sudo -u "$REAL_USER" mkdir -p "$QT6CT_DIR"
  cat >"$QT6CT_DIR/qt6ct.conf" <<'EOF'
[Appearance]
icon_theme=Papirus-Dark

[Interface]
activate_item_on_single_click=1
EOF
  chown -R "$REAL_USER:$REAL_USER" "$QT6CT_DIR"
  gum style --foreground 82 "✅ qt6ct: icon_theme=Papirus-Dark aplicado."
else
  gum style --foreground 244 "⏭️  qt6ct/qt6ct-kde no está instalado (no se eligió en 'Utilidades de escritorio') — se omite el tema Qt."
fi

# -----------------------------
# 5.1. Configurar Snapper automáticamente (BTRFS)
# -----------------------------
# Solo tiene sentido si se eligió instalar snapper y el filesystem raíz
# es BTRFS (create-config falla si no lo es).
SNAPPER_CONFIGURED=false
if command -v snapper &>/dev/null; then
  ROOT_FSTYPE=$(findmnt -n -o FSTYPE / 2>/dev/null)
  if [[ "$ROOT_FSTYPE" == "btrfs" ]]; then
    section "🗂️  Configurando Snapper..."

    if [ ! -f /etc/snapper/configs/root ]; then
      snapper -c root create-config / >>"$LOG_FILE" 2>&1
      gum style --foreground 82 "✅ Config 'root' de snapper creada."
    else
      gum style --foreground 244 "⚠️ Config 'root' de snapper ya existía, se ajustan sus valores."
    fi

    # Ajusta los valores conocidos sin pisar el resto del archivo (que
    # create-config ya llena con comentarios/defaults del paquete).
    apply_snapper_setting() {
      local file="$1" key="$2" value="$3"
      if grep -q "^${key}=" "$file"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$file"
      else
        echo "${key}=\"${value}\"" >>"$file"
      fi
    }

    SNAPPER_ROOT_CONF="/etc/snapper/configs/root"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "SPACE_LIMIT" "0.5"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "FREE_LIMIT" "0.2"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "SYNC_ACL" "no"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "BACKGROUND_COMPARISON" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_CLEANUP" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_MIN_AGE" "3600"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_LIMIT" "30"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "NUMBER_LIMIT_IMPORTANT" "10"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_CREATE" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_CLEANUP" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_MIN_AGE" "3600"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_HOURLY" "8"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_DAILY" "7"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_WEEKLY" "4"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_MONTHLY" "3"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_QUARTERLY" "0"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "TIMELINE_LIMIT_YEARLY" "0"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "EMPTY_PRE_POST_CLEANUP" "yes"
    apply_snapper_setting "$SNAPPER_ROOT_CONF" "EMPTY_PRE_POST_MIN_AGE" "3600"

    # /home solo si es su propio subvolumen BTRFS (si comparte el mismo
    # subvolumen que /, snapper create-config para home fallaría o
    # duplicaría snapshots innecesariamente).
    HOME_FSTYPE=$(findmnt -n -o FSTYPE /home 2>/dev/null)
    if [[ "$HOME_FSTYPE" == "btrfs" ]] && [ ! -f /etc/snapper/configs/home ]; then
      snapper -c home create-config /home >>"$LOG_FILE" 2>&1
      gum style --foreground 82 "✅ Config 'home' de snapper creada (con los defaults del paquete)."
    fi

    log_or_show systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || true
    SNAPPER_CONFIGURED=true
    gum style --foreground 82 "✅ Snapper configurado y timers habilitados."
  else
    gum style --foreground 244 "⚠️ Filesystem raíz no es BTRFS ($ROOT_FSTYPE) — se omite configuración de Snapper."
  fi
fi

# -----------------------------
# 6. Función auxiliar para instalar paquetes AUR sin helper
# -----------------------------
run_step "📦 Instalando base-devel y git..." pacman -S --noconfirm --needed base-devel git

SUDOERS_TMP="/etc/sudoers.d/99-aur-install"
echo "$REAL_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDOERS_TMP"
chmod 440 "$SUDOERS_TMP"

install_aur_manual() {
  local aur_url="$1"
  local pkg_name="$2"
  local tmp_dir
  tmp_dir=$(mktemp -d)
  chown "$REAL_USER:$REAL_USER" "$tmp_dir"

  local script
  script="sudo -u '$REAL_USER' git clone '$aur_url' '$tmp_dir/$pkg_name' && sudo -u '$REAL_USER' bash -c \"cd '$tmp_dir/$pkg_name' && makepkg -si --noconfirm\""

  section "📦 Instalando $pkg_name desde AUR (sin helper)..."
  bash -c "$script" 2>&1 | tee -a "$LOG_FILE"
  local rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló instalando $pkg_name" "Ver detalle en: $LOG_FILE"
    exit "$rc"
  fi

  rm -rf "$tmp_dir"
  gum style --foreground 82 "✅ $pkg_name instalado correctamente."
}

# -----------------------------
# 6.2. base-bar — barra propia en Quickshell + Helium + config de Niri
# -----------------------------
# Los paquetes (quickshell, kitty, nwg-drawer, neovim, matugen, upower,
# lm_sensors) ya se instalaron vía PACMAN_PKGS. Acá se arma la config
# QML/KDL/matugen y se instala Helium desde su tarball oficial (sin
# AUR), corriendo todo como REAL_USER porque este script principal
# corre con sudo.
if $INSTALL_BASEBAR; then
  section "🎨 Configurando base-bar (Quickshell)..."

  BASEBAR_CONFIG_DIR="$USER_HOME/.config/quickshell/base-bar"
  BASEBAR_COMMON_DIR="$BASEBAR_CONFIG_DIR/Common"
  MATUGEN_DIR="$USER_HOME/.config/matugen"
  MATUGEN_TEMPLATES_DIR="$MATUGEN_DIR/templates"
  QS_STATE_DIR="$USER_HOME/.local/state/quickshell/generated"

  sudo -u "$REAL_USER" mkdir -p "$BASEBAR_CONFIG_DIR" "$BASEBAR_COMMON_DIR" \
    "$MATUGEN_TEMPLATES_DIR" "$QS_STATE_DIR"

  # --- Plantilla + config de matugen ---
  sudo -u "$REAL_USER" tee "$MATUGEN_TEMPLATES_DIR/quickshell-colors.json" >/dev/null <<'EOF'
{
    "background": "{{colors.background.default.hex}}",
    "on_background": "{{colors.on_background.default.hex}}",
    "surface": "{{colors.surface.default.hex}}",
    "surface_variant": "{{colors.surface_variant.default.hex}}",
    "primary": "{{colors.primary.default.hex}}",
    "on_primary": "{{colors.on_primary.default.hex}}",
    "secondary": "{{colors.secondary.default.hex}}",
    "on_secondary": "{{colors.on_secondary.default.hex}}",
    "error": "{{colors.error.default.hex}}",
    "outline": "{{colors.outline.default.hex}}"
}
EOF

  sudo -u "$REAL_USER" tee "$MATUGEN_DIR/config.toml" >/dev/null <<EOF
[config]
mode = "dark"

[templates.quickshell]
input_path = "$MATUGEN_TEMPLATES_DIR/quickshell-colors.json"
output_path = "$QS_STATE_DIR/colors.json"
EOF

  sudo -u "$REAL_USER" tee "$MATUGEN_DIR/aplicar-wallpaper.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Uso: aplicar-wallpaper.sh /ruta/a/wallpaper.jpg
set -euo pipefail
if [[ $# -ne 1 ]]; then
    echo "Uso: $0 /ruta/a/wallpaper.jpg" >&2
    exit 1
fi
matugen image "$1"
pkill swaybg 2>/dev/null || true
swaybg -i "$1" -m fill &
EOF
  chmod +x "$MATUGEN_DIR/aplicar-wallpaper.sh"

  # --- Colors.qml: singleton reactivo (FileView + watchChanges) ---
  sudo -u "$REAL_USER" tee "$BASEBAR_COMMON_DIR/Colors.qml" >/dev/null <<'EOF'
pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property color background: "#1e1e2e"
    property color textOnBackground: "#cdd6f4"
    property color surface: "#313244"
    property color surfaceVariant: "#45475a"
    property color primary: "#89b4fa"
    property color textOnPrimary: "#1e1e2e"
    property color secondary: "#f5c2e7"
    property color textOnSecondary: "#1e1e2e"
    property color error: "#f38ba8"
    property color outline: "#6c7086"

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()

        // text() no es una property real, pero se puede "atar" a una
        // property normal y se re-evalúa sola gracias a su notify
        // signal interno (patrón documentado por Quickshell).
        property string rawJson: text()
        onRawJsonChanged: parseColors()

        function parseColors() {
            try {
                var c = JSON.parse(rawJson)
                if (c.background) root.background = c.background
                if (c.on_background) root.textOnBackground = c.on_background
                if (c.surface) root.surface = c.surface
                if (c.surface_variant) root.surfaceVariant = c.surface_variant
                if (c.primary) root.primary = c.primary
                if (c.on_primary) root.textOnPrimary = c.on_primary
                if (c.secondary) root.secondary = c.secondary
                if (c.on_secondary) root.textOnSecondary = c.on_secondary
                if (c.error) root.error = c.error
                if (c.outline) root.outline = c.outline
            } catch (e) {
                console.warn("Colors.qml: no se pudo parsear colors.json, usando paleta por defecto:", e)
            }
        }
    }
}
EOF

  # --- shell.qml: barra con estructura start/center/end ---
  sudo -u "$REAL_USER" tee "$BASEBAR_CONFIG_DIR/shell.qml" >/dev/null <<'EOF'
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import qs.Common

ShellRoot {
    property var workspaces: []
    property string netText: "N/A"
    property real cpuPct: 0
    property real ramPct: 0
    property string tempText: "N/A"
    property string gpuText: ""
    property string volText: "N/A"

    readonly property var battery: UPower.displayDevice

    Process {
        id: workspacesProc
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { workspaces = JSON.parse(text) } catch (e) { workspaces = [] }
            }
        }
    }

    Process {
        id: netProc
        command: ["sh", "-c", "ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}'"]
        stdout: StdioCollector {
            onStreamFinished: { var t = text.trim(); netText = t.length > 0 ? t : "sin red" }
        }
    }

    Process {
        id: cpuProc
        command: ["sh", "-c", "top -bn1 | grep '%Cpu' | awk '{print 100-$8}'"]
        stdout: StdioCollector {
            onStreamFinished: { var v = parseFloat(text.trim()); if (!isNaN(v)) cpuPct = v }
        }
    }

    Process {
        id: ramProc
        command: ["sh", "-c", "free | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'"]
        stdout: StdioCollector {
            onStreamFinished: { var v = parseFloat(text.trim()); if (!isNaN(v)) ramPct = v }
        }
    }

    Process {
        id: tempProc
        command: ["sh", "-c", "sensors 2>/dev/null | grep -m1 -oE '[+-][0-9]+\\.[0-9]°C' | head -c 4"]
        stdout: StdioCollector {
            onStreamFinished: { var t = text.trim(); tempText = t.length > 0 ? (t + "°C") : "N/A" }
        }
    }

    Process {
        id: gpuProc
        command: ["sh", "-c", "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { var t = text.trim(); gpuText = t.length > 0 ? ("GPU " + t + "%") : "" }
        }
    }

    Process {
        id: volProc
        command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf \"%.0f\", $2*100}'"]
        stdout: StdioCollector {
            onStreamFinished: { var v = parseFloat(text.trim()); volText = !isNaN(v) ? (v + "%") : "N/A" }
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
            cpuProc.running = true
            ramProc.running = true
            tempProc.running = true
            gpuProc.running = true
            volProc.running = true
        }
    }

    Process {
        id: launcherProc
        // toggle-drawer.sh se autogestiona: si no hay instancia
        // residente de nwg-drawer la arranca oculta, si ya existe le
        // manda la señal de toggle. No requiere spawn-at-startup en
        // config.kdl, ni relanzar el programa en cada clic.
        command: ["__USER_HOME__/.local/bin/toggle-drawer.sh"]
    }

    Process {
        id: switchProc
        property int targetIdx: 1
        command: ["niri", "msg", "action", "focus-workspace", String(targetIdx)]
        function runWith(idx) { targetIdx = idx; running = true }
    }

    component StatChip: Rectangle {
        property string label: ""
        implicitWidth: chipText.implicitWidth + 16
        implicitHeight: 22
        radius: height / 2
        color: Colors.surface

        Text {
            id: chipText
            anchors.centerIn: parent
            text: label
            color: Colors.textOnBackground
            font.pixelSize: 11
        }
    }

    PanelWindow {
        anchors { top: true; left: true; right: true }
        implicitHeight: 34
        color: Colors.background

        Item {
            id: clockTimer
            property var now: new Date()
            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: clockTimer.now = new Date()
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            RowLayout {
                spacing: 6

                Rectangle {
                    width: 26; height: 22; radius: 6
                    color: launcherArea.containsMouse ? Colors.surface : "transparent"
                    Text { anchors.centerIn: parent; text: "󰀻"; color: Colors.textOnBackground; font.pixelSize: 14 }
                    MouseArea {
                        id: launcherArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: launcherProc.running = true
                    }
                }

                Repeater {
                    model: workspaces
                    delegate: Rectangle {
                        width: 20; height: 20; radius: 10
                        color: modelData.is_focused ? Colors.primary : Colors.surface
                        Text {
                            anchors.centerIn: parent
                            text: modelData.idx !== undefined ? modelData.idx : ""
                            color: modelData.is_focused ? Colors.textOnPrimary : Colors.textOnBackground
                            font.pixelSize: 11
                        }
                        MouseArea { anchors.fill: parent; onClicked: switchProc.runWith(modelData.idx) }
                    }
                }

                StatChip { label: "CPU " + Math.round(cpuPct) + "%" }
                StatChip { label: tempText; visible: tempText !== "N/A" }
                StatChip { label: gpuText; visible: gpuText !== "" }
                StatChip { label: "RAM " + Math.round(ramPct) + "%" }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 10
                Text {
                    text: Qt.formatDateTime(clockTimer.now, "hh:mm:ss")
                    color: Colors.textOnBackground
                    font.bold: true
                    font.pixelSize: 13
                }
                Text {
                    text: Qt.formatDateTime(clockTimer.now, "ddd d MMM")
                    color: Colors.outline
                    font.pixelSize: 12
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 6

                StatChip { label: "🌐 " + netText }
                StatChip { label: "🔊 " + volText }

                // Bluetooth: toggle real vía BlueZ (Quickshell.Bluetooth)
                StatChip {
                    visible: Bluetooth.defaultAdapter !== null
                    label: {
                        var a = Bluetooth.defaultAdapter
                        if (!a) return ""
                        return a.enabled ? "󰂯" : "󰂲"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            var a = Bluetooth.defaultAdapter
                            if (a) a.enabled = !a.enabled
                        }
                    }
                }

                // Bandeja del sistema: ítems reales vía StatusNotifierItem
                RowLayout {
                    spacing: 4
                    Repeater {
                        model: SystemTray.items
                        delegate: Rectangle {
                            width: 20; height: 20; radius: 4
                            color: trayItemArea.containsMouse ? Colors.surface : "transparent"

                            Image {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                source: modelData.icon
                                smooth: true
                            }

                            MouseArea {
                                id: trayItemArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton && !modelData.onlyMenu) {
                                        modelData.display(null, 0, 0)
                                    } else {
                                        modelData.activate()
                                    }
                                }
                            }
                        }
                    }
                }

                StatChip {
                    visible: battery && battery.isLaptopBattery
                    label: {
                        if (!battery || !battery.isLaptopBattery) return ""
                        var pct = Math.round((battery.percentage ?? 0) * 100)
                        var charging = battery.state === UPowerDeviceState.Charging
                        return (charging ? "⚡ " : "🔋 ") + pct + "%"
                    }
                }

                Rectangle {
                    width: 26; height: 22; radius: 6
                    color: sessionArea.containsMouse ? Colors.surface : "transparent"
                    Text { anchors.centerIn: parent; text: "⏻"; color: Colors.error; font.pixelSize: 13 }
                    MouseArea {
                        id: sessionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sessionProc.running = true
                    }
                }

                Process {
                    id: sessionProc
                    command: ["sh", "-c", "command -v wlogout >/dev/null && wlogout || niri msg action quit"]
                }
            }
        }
    }
}
EOF

  # Ruta absoluta hardcodeada -- no depender de Quickshell.env("HOME") en
  # runtime, porque cuando qs arranca vía spawn-at-startup de Niri (en
  # vez de a mano desde una terminal) el entorno puede no traer HOME
  # seteado igual que en una sesión de shell interactiva, y el botón del
  # lanzador queda roto en silencio después de reiniciar sesión.
  sed -i "s#__USER_HOME__#$USER_HOME#g" "$BASEBAR_CONFIG_DIR/shell.qml"

  chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/quickshell" "$MATUGEN_DIR" "$USER_HOME/.local/state/quickshell"
  # --- toggle-drawer.sh: gestiona nwg-drawer solo, sin tocar config.kdl ---
  # Si no hay una instancia residente corriendo, la lanza (-r, en 2do
  # plano, oculta). Si ya está corriendo, le manda la señal de toggle
  # (SIGUSR1) para mostrarla/ocultarla. Así el botón de la barra y
  # cualquier bind solo necesitan llamar a este script, siempre.
  sudo -u "$REAL_USER" mkdir -p "$USER_HOME/.local/bin"
  sudo -u "$REAL_USER" tee "$USER_HOME/.local/bin/toggle-drawer.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
# flock evita que dos clics casi simultáneos (o un doble-disparo del
# MouseArea) corran este script al mismo tiempo -- sin esto, dos
# ejecuciones en paralelo pueden ver "nwg-drawer no está corriendo"
# ambas a la vez y lanzar dos instancias residentes, rompiendo el
# toggle (pkill -USR1 le pega a las dos y queda en estado inconsistente).
exec 200>/tmp/toggle-drawer.lock
flock -n 200 || exit 0

if pgrep -x nwg-drawer >/dev/null; then
    pkill -USR1 nwg-drawer
else
    nwg-drawer -r &
    disown
fi
EOF
  chmod +x "$USER_HOME/.local/bin/toggle-drawer.sh"
  chown "$REAL_USER:$REAL_USER" "$USER_HOME/.local/bin/toggle-drawer.sh"
  gum style --foreground 82 "✅ toggle-drawer.sh creado en $USER_HOME/.local/bin (lanza o esconde nwg-drawer solo)"

  gum style --foreground 82 "✅ base-bar configurada en $BASEBAR_CONFIG_DIR (lanzar con: qs -c base-bar)"

  # --- HyprQuickPaper: selector visual de wallpapers (Quickshell) ---
  # Repo: https://github.com/iamsurjog/hyprquickpaper -- shell aparte de
  # Quickshell (no vive dentro de base-bar), pensado para lanzarse con un
  # bind. Usamos Mod+W, que quedó libre al quitar el picker de mpvpaper
  # de Noctalia. commands.sh se reescribe para: 1) aplicar el wallpaper
  # con swaybg (sin AUR, sin swww) y 2) disparar matugen para recolorear
  # base-bar -- así un solo picker cubre las dos cosas.
  section "🖼️  Instalando HyprQuickPaper (selector de wallpapers)..."

  HQP_DIR="$USER_HOME/.config/quickshell/hyprquickpaper"
  WALLPAPER_DIR="$USER_HOME/Pictures/Wallpapers"
  HQP_CACHE_DIR="$USER_HOME/.cache/quickshell/thumbs"

  sudo -u "$REAL_USER" mkdir -p "$WALLPAPER_DIR" "$HQP_CACHE_DIR"

  if [ -d "$HQP_DIR/.git" ]; then
    gum style --foreground 244 "⏭️  HyprQuickPaper ya está clonado en $HQP_DIR — se omite (corré 'git pull' ahí a mano si querés actualizarlo)."
  else
    rm -rf "$HQP_DIR"
    sudo -u "$REAL_USER" git clone --depth 1 https://github.com/iamsurjog/hyprquickpaper "$HQP_DIR" >>"$LOG_FILE" 2>&1

    sudo -u "$REAL_USER" tee "$HQP_DIR/config.json" >/dev/null <<EOF
{
    "wallpaper_path": "$WALLPAPER_DIR/",
    "cache_path": "$HQP_CACHE_DIR/",
    "number_of_pictures": 7,
    "border_color": "#89b4fa",
    "cache_batch_size": 8
}
EOF

    sudo -u "$REAL_USER" tee "$HQP_DIR/commands.sh" >/dev/null <<'EOF'
#!/usr/bin/env bash
# Se llama con la ruta del wallpaper elegido como $1.
# 1) lo aplica con swaybg (sin transición suave -- swww requiere AUR,
#    y explícitamente no lo estamos usando en este setup)
# 2) dispara matugen para recolorear base-bar a partir de esa imagen
pkill swaybg 2>/dev/null || true
swaybg -i "$1" -m fill &
"$HOME/.config/matugen/aplicar-wallpaper.sh" "$1" >/dev/null 2>&1 &
EOF
    chmod +x "$HQP_DIR/commands.sh"

    chown -R "$REAL_USER:$REAL_USER" "$HQP_DIR" "$WALLPAPER_DIR" "$HQP_CACHE_DIR"
    gum style --foreground 82 "✅ HyprQuickPaper instalado en $HQP_DIR (wallpapers: $WALLPAPER_DIR)"
    if [ -z "$(ls -A "$WALLPAPER_DIR" 2>/dev/null)" ]; then
      gum style --foreground 244 "   ⚠️ $WALLPAPER_DIR está vacía todavía — poné imágenes ahí antes de abrir el picker (Mod+W)."
    fi
  fi

  # --- Helium Browser: tarball oficial + verificación GPG, sin AUR ---
  # Si ya tienes helium-browser-bin instalado (por ejemplo vía
  # Chaotic-AUR, como en tu install.sh anterior), NO se reinstala por
  # tarball -- evita terminar con dos Heliums en paralelo (/opt/helium
  # vs /opt/helium-browser-bin). Tus binds existentes que apuntan a
  # /opt/helium-browser-bin/helium-wrapper siguen intactos.
  if pacman -Qi helium-browser-bin &>/dev/null; then
    gum style --foreground 244 "⏭️  helium-browser-bin ya está instalado (Chaotic-AUR) — se omite la instalación por tarball para no duplicar."
  else
  section "🌐 Instalando Helium Browser (tarball oficial, con verificación GPG)..."

  HELIUM_OPT_DIR="/opt/helium"
  HELIUM_TMP="$(mktemp -d)"

  HELIUM_TARBALL_URL="$(curl -fsSL https://api.github.com/repos/imputnet/helium-linux/releases/latest \
    | grep -o '"browser_download_url": *"[^"]*x86_64_linux\.tar\.xz"' \
    | grep -o 'https://[^"]*')"

  if [[ -z "$HELIUM_TARBALL_URL" ]]; then
    gum style --foreground 196 "⚠️ No se pudo determinar la URL del tarball de Helium. Se omite su instalación."
  else
    curl -fsSL -o "$HELIUM_TMP/helium.tar.xz" "$HELIUM_TARBALL_URL"

    HELIUM_ASC_URL="${HELIUM_TARBALL_URL}.asc"
    HELIUM_GPG_HOME="$HELIUM_TMP/gnupg"
    mkdir -p "$HELIUM_GPG_HOME"
    chmod 700 "$HELIUM_GPG_HOME"

    if curl -fsSL -o "$HELIUM_TMP/helium.tar.xz.asc" "$HELIUM_ASC_URL"; then
      curl -fsSL https://raw.githubusercontent.com/imputnet/helium-linux/main/pubkey.asc \
        | gpg --homedir "$HELIUM_GPG_HOME" --import >/dev/null 2>&1

      if gpg --homedir "$HELIUM_GPG_HOME" --verify "$HELIUM_TMP/helium.tar.xz.asc" "$HELIUM_TMP/helium.tar.xz" 2>/dev/null; then
        gum style --foreground 82 "✅ Firma GPG de Helium verificada correctamente."

        mkdir -p "$HELIUM_TMP/extracted"
        tar -xf "$HELIUM_TMP/helium.tar.xz" -C "$HELIUM_TMP/extracted"
        HELIUM_SRC_DIR="$(find "$HELIUM_TMP/extracted" -maxdepth 1 -mindepth 1 -type d | head -n1)"

        rm -rf "$HELIUM_OPT_DIR"
        mkdir -p "$HELIUM_OPT_DIR"
        cp -r "$HELIUM_SRC_DIR"/. "$HELIUM_OPT_DIR"/

        HELIUM_BIN="$(find "$HELIUM_OPT_DIR" -maxdepth 1 -type f -iname 'helium*' ! -name '*.so*' | head -n1)"
        [[ -z "$HELIUM_BIN" ]] && HELIUM_BIN="$HELIUM_OPT_DIR/chrome"
        chmod +x "$HELIUM_BIN"

        tee /usr/local/bin/helium-browser >/dev/null <<EOF2
#!/usr/bin/env bash
exec "$HELIUM_BIN" --ozone-platform=wayland --enable-features=WaylandWindowDecorations "\$@"
EOF2
        chmod +x /usr/local/bin/helium-browser

        HELIUM_ICON="$(find "$HELIUM_OPT_DIR" -iname 'product_logo*256*.png' -o -iname 'icon*.png' | head -n1)"
        cat <<EOF3 >/usr/share/applications/helium-browser.desktop
[Desktop Entry]
Name=Helium
Comment=Navegador basado en Chromium sin Google (Helium)
Exec=/usr/local/bin/helium-browser %U
Terminal=false
Type=Application
Icon=${HELIUM_ICON:-web-browser}
Categories=Network;WebBrowser;
EOF3

        gum style --foreground 82 "✅ Helium instalado (comando: helium-browser)"
      else
        gum style --foreground 196 "❌ La firma GPG del tarball de Helium no es válida. Se omite su instalación por seguridad."
      fi
    else
      gum style --foreground 196 "⚠️ No se encontró archivo .asc para verificar la firma. Se omite Helium por seguridad."
    fi
  fi
  rm -rf "$HELIUM_TMP"
  fi
fi

# -----------------------------
# 7. Instalar tema SilentSDDM
# -----------------------------
section "🎨 Instalando tema SilentSDDM..."

OTHER_DMS=(gdm lightdm ly lxdm xdm entrance nodm)
for dm in "${OTHER_DMS[@]}"; do
  if systemctl is-enabled "$dm" &>/dev/null; then
    if confirm_step "Display manager '$dm' detectado y activo. ¿Deshabilitarlo?"; then
      systemctl disable "$dm" >>"$LOG_FILE" 2>&1 || true
      gum style --foreground 82 "✅ $dm deshabilitado."
    else
      gum style --foreground 196 "⏭️  $dm NO deshabilitado. Puede haber conflicto con SDDM."
    fi
  fi
done

run_step "📥 Instalando dependencias del tema (qt6-svg, qt6-virtualkeyboard, qt6-multimedia-ffmpeg)..." \
  pacman -S --noconfirm --needed qt6-svg qt6-virtualkeyboard qt6-multimedia-ffmpeg

install_aur_manual "https://aur.archlinux.org/redhat-fonts.git" "redhat-fonts"
install_aur_manual "https://aur.archlinux.org/sddm-silent-theme.git" "sddm-silent-theme"

# -----------------------------
# 7.2. HyprMod / NiriMod (GUIs para editar la config de Hyprland/Niri)
# -----------------------------
# Ambos son apps GTK4/libadwaita en desarrollo activo, no empaquetadas en
# los repos oficiales todavía. hyprmod sí está en el AUR (paquete normal);
# nirimod solo existe como nirimod-git.
if $INSTALL_HYPRLAND || $INSTALL_NIRI; then
  run_step "📥 Instalando dependencias de HyprMod/NiriMod (GTK4, libadwaita)..." \
    pacman -S --noconfirm --needed gtk4 libadwaita python-gobject python-cairo
fi

if $INSTALL_HYPRLAND; then
  # hyprmod depende de 5 paquetes que TAMBIÉN son solo-AUR
  # (python-hyprland-config/monitors/schema/socket/state). makepkg -si
  # no resuelve dependencias AUR-sobre-AUR solo — por eso fallaba con
  # "no puede resolver dependencias". Hay que construirlos manualmente
  # primero, en orden (los de más bajo nivel primero).
  install_aur_manual "https://aur.archlinux.org/python-hyprland-schema.git" "python-hyprland-schema"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-socket.git" "python-hyprland-socket"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-state.git" "python-hyprland-state"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-monitors.git" "python-hyprland-monitors"
  install_aur_manual "https://aur.archlinux.org/python-hyprland-config.git" "python-hyprland-config"
  install_aur_manual "https://aur.archlinux.org/hyprmod.git" "hyprmod"
fi

if $INSTALL_NIRI; then
  install_aur_manual "https://aur.archlinux.org/nirimod-git.git" "nirimod-git"
fi

SDDM_CONF="/etc/sddm.conf"

cat >"$SDDM_CONF" <<'EOF'
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=QML2_IMPORT_PATH=/usr/share/sddm/themes/silent/components/,QT_IM_MODULE=qtvirtualkeyboard

[Theme]
Current=silent
EOF

gum style --foreground 82 "✅ Tema SilentSDDM instalado y configurado."

rm -f "$SUDOERS_TMP"
gum style --foreground 244 "🔒 Regla temporal de sudoers eliminada."

# -----------------------------
# 7.1. Configurar portal XDG para niri
# -----------------------------
# Niri no trae su propio backend de portal (a diferencia de Hyprland con
# xdg-desktop-portal-hyprland). Le indicamos que use el backend de GNOME
# solo cuando la sesión activa sea "niri" (XDG_CURRENT_DESKTOP=niri),
# así no interfiere con el portal que ya usa Hyprland.
if $INSTALL_NIRI; then
  section "🌀 Configurando xdg-desktop-portal para la sesión de niri..."

  NIRI_PORTAL_DIR="$USER_HOME/.config/xdg-desktop-portal"
  mkdir -p "$NIRI_PORTAL_DIR"

  cat >"$NIRI_PORTAL_DIR/niri-portals.conf" <<'EOF'
[preferred]
default=gnome
org.freedesktop.impl.portal.Access=gnome
org.freedesktop.impl.portal.FileChooser=gnome
org.freedesktop.impl.portal.Screenshot=gnome
org.freedesktop.impl.portal.Screencast=gnome
EOF

  chown -R "$REAL_USER:$REAL_USER" "$NIRI_PORTAL_DIR"
  gum style --foreground 82 "✅ $NIRI_PORTAL_DIR/niri-portals.conf creado."
fi

# -----------------------------
# 8. Habilitar servicios
# -----------------------------
section "🔥 Habilitando servicios del sistema..."

log_or_show systemctl enable --now firewalld
log_or_show systemctl enable --now avahi-daemon
log_or_show systemctl enable sddm

if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --add-port=53317/udp --permanent &>/dev/null
  firewall-cmd --reload &>/dev/null
fi

if command -v ufw &>/dev/null; then
  ufw allow 53317/udp &>/dev/null
fi

# Audio (PipeWire suele activarse solo por socket activation al
# instalarse, pero lo forzamos para no depender de que el preset ande)
sudo -u "$REAL_USER" systemctl --user enable --now pipewire pipewire-pulse wireplumber &>/dev/null || true

if $INSTALL_HYPRLAND; then
  sudo -u "$REAL_USER" systemctl --user restart xdg-desktop-portal-hyprland.service xdg-desktop-portal.service &>/dev/null || true
fi

gum style --foreground 82 "✅ Servicios habilitados."

# -----------------------------
# 9. Instalar Zsh y Oh My Zsh
# -----------------------------
run_pacman_progress "🐚 Instalando Zsh y plugins..." \
  zsh eza zsh-autocomplete zsh-autosuggestions zsh-history-substring-search zsh-syntax-highlighting

if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
  ohmyzsh_script="sudo -u '$REAL_USER' RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)\""
  section "👤 Instalando Oh My Zsh para $REAL_USER..."
  bash -c "$ohmyzsh_script" 2>&1 | tee -a "$LOG_FILE"
  rc=${PIPESTATUS[0]}
  if [[ $rc -ne 0 ]]; then
    gum style --border rounded --border-foreground 196 --padding "1 3" \
      "❌ Falló instalando Oh My Zsh" "Ver detalle en: $LOG_FILE"
    exit "$rc"
  fi
else
  gum style --foreground 244 "⚠️ Oh My Zsh ya está instalado"
fi

ZSHRC_BACKUP="$SCRIPT_DIR/respaldo/.zshrc"

if [ -f "$ZSHRC_BACKUP" ]; then
  cp "$ZSHRC_BACKUP" "$ZSHRC"
  gum style --foreground 82 "✅ .zshrc restaurado desde respaldo"
else
  gum style --foreground 244 "⚠️ No se encontró .zshrc en respaldo — generando uno por defecto (no depende del repo)"

  # $ZSHRC en este punto es el generado por el instalador de Oh My Zsh.
  # Ajustamos tema y plugins ahí mismo (sed) en vez de pisar todo el
  # archivo, para no perder lo que Oh My Zsh ya dejó configurado.
  if [ -f "$ZSHRC" ]; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="geoffgarside"/' "$ZSHRC"
    sed -i 's/^plugins=(.*/plugins=(git sudo)/' "$ZSHRC"
  fi

  CUSTOM_BLOCK_MARK="### CUSTOM PLUGINS ###"
  if ! grep -qF "$CUSTOM_BLOCK_MARK" "$ZSHRC" 2>/dev/null; then
    cat >>"$ZSHRC" <<'EOF'

# Preferred editor for local and remote sessions
export EDITOR=nvim

### CUSTOM PLUGINS ###
source /usr/share/zsh/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh

# Better ls
alias ls='eza -a --icons=always'
alias y='yazi'
alias icat="kitten icat"
alias svim='sudo nvim "+set number"'
### END CUSTOM PLUGINS ###

export QT_QPA_PLATFORMTHEME=qt6ct

# apps
fastfetch
EOF
    gum style --foreground 82 "✅ .zshrc por defecto generado (tema, plugins, alias svim y más)"
  else
    gum style --foreground 244 "⚠️ El bloque custom ya existía en .zshrc, no se duplicó"
  fi
fi

chown "$REAL_USER:$REAL_USER" "$ZSHRC"
chsh -s /bin/zsh "$REAL_USER"
gum style --foreground 82 "✅ Shell cambiado a Zsh para $REAL_USER"

# -----------------------------
# 9.1. Configurar keyd
# -----------------------------
APPLY_KEYD_CONFIG=false
if $OWNER_MODE; then
  APPLY_KEYD_CONFIG=true
else
  KEYD_CHOICE=$(ask_choice "⌨️  keyd trae remapeos de botones de mouse pensados para el hardware específico del dueño (IDs de dispositivo fijos) — ¿igual querés aplicarlos?" \
    "❌ No, omitir (keyd queda instalado, sin config custom)" \
    "⚠️  Sí, aplicar igual (puede no corresponder a tu mouse/teclado)")
  case "$KEYD_CHOICE" in
  *"Sí"*) APPLY_KEYD_CONFIG=true ;;
  *) APPLY_KEYD_CONFIG=false ;;
  esac
fi

if $APPLY_KEYD_CONFIG; then
  section "⌨️  Configurando keyd..."

  mkdir -p /etc/keyd

  cat >/etc/keyd/default.conf <<'EOF'
# keyd config
# /etc/keyd/default.conf
[ids]
0461:4ec0:8e43ae64
[main]
mouse2 = M-f
[ids]
0fac:1ade:d2b36ae6
[main]
mouse1 = print
EOF

  log_or_show systemctl enable --now keyd
  gum style --foreground 82 "✅ keyd configurado y habilitado."
else
  gum style --foreground 244 "⏭️  keyd: config de mouse omitida. Para armar la tuya, corré 'sudo keyd list-ids' y editá /etc/keyd/default.conf a mano."
fi

# -----------------------------
# 9.2. Ignorar touchpad del control DualSense/PS4 como dispositivo
#       de input (evita que libinput lo trate como touchpad real)
# -----------------------------
APPLY_DUALSENSE_RULE=false
if $OWNER_MODE; then
  APPLY_DUALSENSE_RULE=true
else
  DUALSENSE_CHOICE=$(ask_choice "🎮 ¿Tenés un control DualSense/PS4 y querés que se ignore su touchpad como dispositivo de input?" \
    "❌ No" \
    "✅ Sí")
  case "$DUALSENSE_CHOICE" in
  *"Sí"*) APPLY_DUALSENSE_RULE=true ;;
  *) APPLY_DUALSENSE_RULE=false ;;
  esac
fi

if $APPLY_DUALSENSE_RULE; then
  section "🎮 Configurando regla udev para ignorar touchpad de DualSense/PS4..."
  mkdir -p /etc/udev/rules.d
  cat >/etc/udev/rules.d/99-ignore-dualsense-touchpad.rules <<'EOF'
ATTRS{name}=="DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
ATTRS{name}=="Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
EOF
  udevadm control --reload-rules 2>/dev/null || true
  gum style --foreground 82 "✅ Regla udev creada — libinput va a ignorar el touchpad del control (aplica igual en Hyprland y Niri, es a nivel de kernel/libinput)."
fi

# -----------------------------
# 10. Restaurar configuraciones desde respaldo
# -----------------------------
section "📂 Restaurando configuraciones desde $SCRIPT_DIR/respaldo..."


# Generar las carpetas de usuario estándar (Pictures, Videos, Documents,
# etc.) ANTES de restaurar — así "Pictures" existe en el idioma/nombre
# correcto y no queda mal puesta o duplicada.
sudo -u "$REAL_USER" xdg-user-dirs-update &>/dev/null || true

BACKUP_DIR="$SCRIPT_DIR/respaldo"
CONFIG_DIR="$USER_HOME/.config"

if [ ! -d "$BACKUP_DIR" ]; then
  gum style --foreground 244 "⚠️  No se encontró la carpeta $BACKUP_DIR — omitiendo restauración."
else
  mkdir -p "$CONFIG_DIR"

  for SRC in "$BACKUP_DIR"/*/; do
    [ -d "$SRC" ] || continue
    folder=$(basename "$SRC")

    if [ "$folder" = "scripts" ]; then
      cp -r "$SRC"/. /usr/local/bin/
      chmod +x /usr/local/bin/*
      gum style --foreground 82 "  ✅ scripts → /usr/local/bin/"

      # Si snapper quedó configurado y el script de entradas de boot
      # está entre los que se acaban de copiar, armamos el hook de
      # pacman para que se regeneren solas en cada transacción.
      if $SNAPPER_CONFIGURED && command -v arch-snapper-boot-entries &>/dev/null; then
        SNAPPER_HOOK_DIR="/etc/pacman.d/hooks"
        mkdir -p "$SNAPPER_HOOK_DIR"
        cat >"$SNAPPER_HOOK_DIR/95-snapper-boot-entries.hook" <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Actualizando entradas de arranque de snapshots (snapper)...
When = PostTransaction
Exec = /usr/bin/env bash -c 'command -v arch-snapper-boot-entries >/dev/null && arch-snapper-boot-entries || true'
EOF
        gum style --foreground 82 "  ✅ Hook de pacman creado: las entradas de boot se regeneran solas en cada transacción."
      elif $SNAPPER_CONFIGURED; then
        gum style --foreground 244 "  ⚠️ Snapper está configurado pero no se encontró arch-snapper-boot-entries en /usr/local/bin — revisá que esté en respaldo/scripts/."
      fi

      continue
    fi

    # Carpeta de imágenes/wallpapers: va a la carpeta REAL de Imágenes
    # del usuario (respetando xdg-user-dirs, con fallback a ~/Pictures),
    # no a ~/.config — así sirve para wallpapers y fotos, no configs.
    case "$folder" in
    Pictures | pictures | Imagenes | imagenes | Imágenes | wallpapers | Wallpapers)
      PICTURES_DIR=$(sudo -u "$REAL_USER" xdg-user-dir PICTURES 2>/dev/null)
      [ -z "$PICTURES_DIR" ] && PICTURES_DIR="$USER_HOME/Pictures"
      mkdir -p "$PICTURES_DIR"
      cp -r "$SRC"/. "$PICTURES_DIR"/
      chown -R "$REAL_USER:$REAL_USER" "$PICTURES_DIR"
      gum style --foreground 82 "  ✅ $folder → $PICTURES_DIR/ (wallpapers y fotos)"
      continue
      ;;
    esac

    # Carpeta especial: unidades systemd de usuario (services/timers),
    # que NO van a ~/.config/<folder> tal cual sino a
    # ~/.config/systemd/user/, y además hay que habilitarlas.
    if [ "$folder" = "systemd-user" ]; then
      USER_SYSTEMD_DIR="$CONFIG_DIR/systemd/user"
      sudo -u "$REAL_USER" mkdir -p "$USER_SYSTEMD_DIR"
      cp "$SRC"/. "$USER_SYSTEMD_DIR"/ -r 2>/dev/null
      shopt -s nullglob
      cp "$SRC"*.service "$SRC"*.timer "$USER_SYSTEMD_DIR"/ 2>/dev/null || true
      shopt -u nullglob
      chown -R "$REAL_USER:$REAL_USER" "$USER_SYSTEMD_DIR"
      gum style --foreground 82 "  ✅ systemd-user → $USER_SYSTEMD_DIR/"

      # "systemctl --user" necesita una instancia de systemd de usuario
      # corriendo, que normalmente arranca recién con el primer login
      # gráfico — que en este punto de la instalación todavía no pasó.
      # loginctl enable-linger la arranca sin necesitar login, y de paso
      # hace que los timers (como el de chequear actualizaciones) sigan
      # corriendo aunque el usuario no tenga sesión iniciada.
      loginctl enable-linger "$REAL_USER" 2>>"$LOG_FILE" || true
      sleep 2

      sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
        systemctl --user daemon-reload || true

      shopt -s nullglob
      for timer_file in "$USER_SYSTEMD_DIR"/*.timer; do
        timer_name=$(basename "$timer_file")
        sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
          systemctl --user enable --now "$timer_name" && \
          gum style --foreground 82 "  ✅ $timer_name activado." || \
          gum style --foreground 244 "  ⚠️  No se pudo activar $timer_name."
      done
      shopt -u nullglob
      continue
    fi

    # Respetar qué se eligió instalar. Antes esto solo miraba
    # RESTORE_*_CONFIG (limpio/respaldo), pero eso ya no alcanza: si no
    # elegiste ese compositor, su carpeta de respaldo no debe copiarse
    # NUNCA, sin importar el valor de RESTORE_*_CONFIG.
    if [ "$folder" = "hypr" ] && ! $INSTALL_HYPRLAND; then
      gum style --foreground 244 "  ⏭️  hypr → omitido (no elegiste instalar Hyprland)"
      continue
    fi
    if [ "$folder" = "niri" ] && ! $INSTALL_NIRI; then
      gum style --foreground 244 "  ⏭️  niri → omitido (no elegiste instalar Niri)"
      continue
    fi
    if [ "$folder" = "kde" ] && ! $INSTALL_KDE; then
      gum style --foreground 244 "  ⏭️  kde → omitido (no elegiste instalar KDE)"
      continue
    fi

    if [ "$folder" = "hypr" ] && ! $RESTORE_HYPR_CONFIG; then
      gum style --foreground 244 "  ⏭️  hypr → omitido (se pidió Hyprland limpio)"
      continue
    fi
    if [ "$folder" = "niri" ] && ! $RESTORE_NIRI_CONFIG; then
      gum style --foreground 244 "  ⏭️  niri → omitido (se pidió Niri limpio)"
      continue
    fi
    if [ "$folder" = "kde" ] && ! $RESTORE_KDE_CONFIG; then
      gum style --foreground 244 "  ⏭️  kde → omitido (se pidió KDE limpio)"
      continue
    fi

    # Cualquier otra carpeta de app (no hypr/niri/kde, que ya se
    # manejaron arriba): respeta la elección limpio/restaurar hecha
    # en la sección 0.8 para esa app puntual, si se preguntó.
    # Excepción: carpetas de theming puro (qt6ct, gtk-3.0, gtk-4.0) se
    # restauran SIEMPRE, en los dos modos — no tienen nada personal.
    if [ "$folder" != "hypr" ] && [ "$folder" != "niri" ] && [ "$folder" != "kde" ] \
      && [ "$folder" != "qt6ct" ] && [ "$folder" != "gtk-3.0" ] && [ "$folder" != "gtk-4.0" ]; then
      if [[ "${APP_RESTORE_CHOICE[$folder]:-}" == "clean" ]]; then
        gum style --foreground 244 "  ⏭️  $folder → omitido (se pidió instalación limpia para esa app)"
        continue
      fi
    fi

    DEST="$CONFIG_DIR/$folder"
    rm -rf "$DEST"
    cp -r "$SRC" "$DEST"
    chown -R "$REAL_USER:$REAL_USER" "$DEST"
    gum style --foreground 82 "  ✅ $folder → $CONFIG_DIR/"
  done

  if [ -f "$BACKUP_DIR/howdy-config.ini" ]; then
    mkdir -p /etc/howdy
    cp "$BACKUP_DIR/howdy-config.ini" /etc/howdy/config.ini
    gum style --foreground 82 "  ✅ /etc/howdy/config.ini restaurado."
  else
    gum style --foreground 244 "  ⚠️  howdy-config.ini no encontrado en respaldo, omitiendo."
  fi

  restore_pam() {
    local src="$1"
    local dest="$2"
    if [ -f "$BACKUP_DIR/$src" ]; then
      cp "$BACKUP_DIR/$src" "$dest"
      gum style --foreground 82 "  ✅ $dest restaurado."
    else
      gum style --foreground 244 "  ⚠️  $src no encontrado en respaldo, omitiendo."
    fi
  }

  restore_pam "pam-sudo" "/etc/pam.d/sudo"
  restore_pam "pam-sddm" "/etc/pam.d/sddm"
  restore_pam "pam-polkit" "/etc/pam.d/polkit-gnome-authentication-agent-1"

  gum style --foreground 82 "✅ Configuraciones restauradas correctamente."
fi

# -----------------------------
# 10.0.2. Script "fix-monitor-config" — ajuste fino post-login
# -----------------------------
# Ni edid-decode ni ningún parseo pre-boot del EDID va a coincidir
# nunca con precisión exacta al valor que el compositor calcula
# internamente (cada uno redondea distinto el mismo timing: Niri daba
# 360.041, Hyprland 360.04 para el mismo panel). La única fuente
# confiable es preguntarle al compositor una vez que ya está corriendo.
# Este script hace eso y reescribe la config con el valor exacto.
if $INSTALL_HYPRLAND || $INSTALL_NIRI; then
  cat >/usr/local/bin/fix-monitor-config <<'FIXEOF'
#!/usr/bin/env bash
# Corré esto UNA VEZ después de tu primer login gráfico (Hyprland o
# Niri ya tienen que estar corriendo). Pregunta al compositor los
# valores exactos de refresh que aceptó para tus monitores, y
# reescribe hyprland.lua / config.kdl con esos valores precisos.
set -e

if command -v hyprctl &>/dev/null && [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
  HYPR_CONF="$HOME/.config/hypr/hyprland.lua"
  echo "🔎 Consultando hyprctl monitors..."
  hyprctl monitors -j | jq -c '.[]' | while read -r mon; do
    name=$(jq -r '.name' <<<"$mon")
    width=$(jq -r '.width' <<<"$mon")
    height=$(jq -r '.height' <<<"$mon")
    hz=$(jq -r '.refreshRate' <<<"$mon")
    newmode="${width}x${height}@${hz}"
    echo "  → ${name}: ${newmode}"
    awk -v conn="$name" -v newmode="$newmode" '
      /hl\.monitor\(\{/ { inblock=1; cur="" }
      inblock && match($0, /output = "([^"]*)"/, arr) { cur = arr[1] }
      inblock && cur == conn && /mode = "/ {
        sub(/mode = "[^"]*"/, "mode = \"" newmode "\"")
      }
      /\}\)/ { inblock=0 }
      { print }
    ' "$HYPR_CONF" >"${HYPR_CONF}.tmp" && mv "${HYPR_CONF}.tmp" "$HYPR_CONF"
  done
  echo "✅ hyprland.lua actualizado. Recargá con: hyprctl reload"
fi

if command -v niri &>/dev/null && [ -f "$HOME/.config/niri/config.kdl" ]; then
  NIRI_CONF="$HOME/.config/niri/config.kdl"
  echo "🔎 Consultando niri msg outputs..."
  niri msg --json outputs | jq -r 'to_entries[] | "\(.key)|\(.value.modes[.value.current_mode].width)x\(.value.modes[.value.current_mode].height)|\(.value.modes[.value.current_mode].refresh_rate)"' | \
  while IFS='|' read -r name res mhz; do
    hz=$(awk -v m="$mhz" 'BEGIN{printf "%.3f", m/1000}')
    newmode="${res}@${hz}"
    echo "  → ${name}: ${newmode}"
    awk -v conn="$name" -v newmode="$newmode" '
      $0 ~ ("output \"" conn "\"") { inblock=1 }
      inblock && /mode "/ { sub(/mode "[^"]*"/, "mode \"" newmode "\"") }
      inblock && /^}/ { inblock=0 }
      { print }
    ' "$NIRI_CONF" >"${NIRI_CONF}.tmp" && mv "${NIRI_CONF}.tmp" "$NIRI_CONF"
  done
  echo "✅ config.kdl actualizado. Recargá con: niri msg action load-config-file (o reiniciá la sesión)"
fi
FIXEOF
  chmod +x /usr/local/bin/fix-monitor-config
  gum style --foreground 82 "✅ Script /usr/local/bin/fix-monitor-config creado (correr una vez después del primer login gráfico)."
fi

# -----------------------------
# 10.1. Aplicar hyprland.lua / niri config.kdl — SOLO en instalación
#       limpia (sin respaldo). Igual copia TODO el contenido de
#       respaldo/hypr o respaldo/niri (scripts, assets, etc.) — lo
#       único que cambia en "limpio" es que el archivo principal
#       (hyprland.lua / config.kdl) se reemplaza por el que se pasó
#       con --hyprland-lua/--niri-kdl, en vez de usar el que trae el
#       propio respaldo.
# -----------------------------
if $INSTALL_HYPRLAND && ! $RESTORE_HYPR_CONFIG; then
  HYPR_DEST_DIR="$CONFIG_DIR/hypr"
  if [ -d "$BACKUP_DIR/hypr" ]; then
    rm -rf "$HYPR_DEST_DIR"
    cp -r "$BACKUP_DIR/hypr" "$HYPR_DEST_DIR"
    gum style --foreground 82 "✅ hypr → contenido de respaldo/hypr copiado (scripts/assets incluidos)"
  else
    mkdir -p "$HYPR_DEST_DIR"
  fi

  if [[ -n "$HYPRLAND_LUA_SRC" ]]; then
    section "🌙 Hyprland limpio: reemplazando hyprland.lua por el provisto en --hyprland-lua..."
    cp "$HYPRLAND_LUA_SRC" "$HYPR_DEST_DIR/hyprland.lua"
    gum style --foreground 82 "✅ $HYPR_DEST_DIR/hyprland.lua actualizado desde $HYPRLAND_LUA_SRC"
  elif [ ! -f "$HYPR_DEST_DIR/hyprland.lua" ]; then
    gum style --foreground 244 "⚠️  Hyprland limpio sin --hyprland-lua ni hyprland.lua en respaldo/hypr — se usa la config de ejemplo que trae el paquete."
  fi

  chown -R "$REAL_USER:$REAL_USER" "$HYPR_DEST_DIR"
elif [[ -n "$HYPRLAND_LUA_SRC" ]]; then
  gum style --foreground 244 "⚠️  Se pasó --hyprland-lua pero se restauró respaldo/hypr — se omite para no pisarlo."
fi

if $INSTALL_NIRI && ! $RESTORE_NIRI_CONFIG; then
  NIRI_DEST_DIR="$CONFIG_DIR/niri"
  if [ -d "$BACKUP_DIR/niri" ]; then
    rm -rf "$NIRI_DEST_DIR"
    cp -r "$BACKUP_DIR/niri" "$NIRI_DEST_DIR"
    gum style --foreground 82 "✅ niri → contenido de respaldo/niri copiado (scripts/assets incluidos)"
  else
    mkdir -p "$NIRI_DEST_DIR"
  fi

  if [[ -n "$NIRI_KDL_SRC" ]]; then
    section "🌙 Niri limpio: reemplazando config.kdl por el provisto en --niri-kdl..."
    cp "$NIRI_KDL_SRC" "$NIRI_DEST_DIR/config.kdl"
    gum style --foreground 82 "✅ $NIRI_DEST_DIR/config.kdl actualizado desde $NIRI_KDL_SRC"
  elif [ ! -f "$NIRI_DEST_DIR/config.kdl" ]; then
    gum style --foreground 244 "⚠️  Niri limpio sin --niri-kdl ni config.kdl en respaldo/niri — se usa la config por defecto que trae el paquete."
  fi

  chown -R "$REAL_USER:$REAL_USER" "$NIRI_DEST_DIR"
elif [[ -n "$NIRI_KDL_SRC" ]]; then
  gum style --foreground 244 "⚠️  Se pasó --niri-kdl pero se restauró respaldo/niri — se omite para no pisarlo."
fi

# -----------------------------
# 10.1.1. base-bar: enganchar autostart + binds en config.kdl final
# -----------------------------
# Sin importar de dónde vino el config.kdl final (limpio, --niri-kdl o
# respaldo/niri), si base-bar se instaló, garantizamos que quede
# lanzada al iniciar sesión y que Mod+B abra Helium. Es idempotente:
# si ya están esas líneas, no las duplica.
if $INSTALL_BASEBAR; then
  NIRI_CONF_FOR_BASEBAR="$USER_HOME/.config/niri/config.kdl"
  if [ -f "$NIRI_CONF_FOR_BASEBAR" ]; then
    if ! grep -q 'qs.*base-bar' "$NIRI_CONF_FOR_BASEBAR"; then
      # Se usa spawn-sh-at-startup con un pequeño delay (en vez de
      # spawn-at-startup directo) porque lanzar qs demasiado temprano,
      # antes de que Niri termine de inicializar layer-shell/input,
      # puede dejar la barra visible pero sin recibir clics -- carrera
      # de arranque típica en Wayland. 2s alcanza de sobra.
      if grep -q 'spawn-at-startup' "$NIRI_CONF_FOR_BASEBAR"; then
        sed -i '0,/spawn-at-startup/s//spawn-sh-at-startup "sleep 2 \&\& qs -c base-bar"\nspawn-at-startup/' "$NIRI_CONF_FOR_BASEBAR"
      else
        printf '\nspawn-sh-at-startup "sleep 2 && qs -c base-bar"\n' >>"$NIRI_CONF_FOR_BASEBAR"
      fi
      gum style --foreground 82 "✅ base-bar: autostart agregado a $NIRI_CONF_FOR_BASEBAR (con delay de 2s)"
    fi

    if ! grep -q 'helium-browser' "$NIRI_CONF_FOR_BASEBAR"; then
      if grep -q '^binds {' "$NIRI_CONF_FOR_BASEBAR"; then
        sed -i '/^binds {/a\    Mod+B { spawn "helium-browser"; }' "$NIRI_CONF_FOR_BASEBAR"
      else
        printf '\nbinds {\n    Mod+B { spawn "helium-browser"; }\n}\n' >>"$NIRI_CONF_FOR_BASEBAR"
      fi
      gum style --foreground 82 "✅ base-bar: bind Mod+B (Helium) agregado a $NIRI_CONF_FOR_BASEBAR"
    fi

    if ! grep -q 'hyprquickpaper' "$NIRI_CONF_FOR_BASEBAR"; then
      if grep -q '^binds {' "$NIRI_CONF_FOR_BASEBAR"; then
        sed -i '/^binds {/a\    Mod+W { spawn "quickshell" "-c" "hyprquickpaper"; }' "$NIRI_CONF_FOR_BASEBAR"
      else
        printf '\nbinds {\n    Mod+W { spawn "quickshell" "-c" "hyprquickpaper"; }\n}\n' >>"$NIRI_CONF_FOR_BASEBAR"
      fi
      gum style --foreground 82 "✅ base-bar: bind Mod+W (HyprQuickPaper) agregado a $NIRI_CONF_FOR_BASEBAR"
    fi

    chown "$REAL_USER:$REAL_USER" "$NIRI_CONF_FOR_BASEBAR"
  fi
fi

# -----------------------------
# 10.2. Aplicar monitor detectado — SIEMPRE AL FINAL
# -----------------------------
# Se hace acá, después de que hypr/niri/apps/scripts ya terminaron de
# copiarse (limpio o restaurado), para que ninguna copia posterior
# pueda pisar el bloque de monitor. Busca el marcador AUTO_MONITOR_BLOCK
# en el archivo final (venga de --hyprland-lua/--niri-kdl o del
# respaldo restaurado) y lo reemplaza con lo detectado/elegido.
section "🖥️  Aplicando configuración de monitor final..."

HYPR_FINAL_CONF="$CONFIG_DIR/hypr/hyprland.lua"
if $INSTALL_HYPRLAND && [ -f "$HYPR_FINAL_CONF" ] && grep -q "AUTO_MONITOR_BLOCK" "$HYPR_FINAL_CONF"; then
  HYPR_MONITOR_BLOCK=$(generate_hypr_monitor_block)
  awk -v block="$HYPR_MONITOR_BLOCK" '
    /AUTO_MONITOR_BLOCK/ { print block; next }
    { print }
  ' "$HYPR_FINAL_CONF" >"${HYPR_FINAL_CONF}.tmp"
  mv "${HYPR_FINAL_CONF}.tmp" "$HYPR_FINAL_CONF"
  chown "$REAL_USER:$REAL_USER" "$HYPR_FINAL_CONF"
  gum style --foreground 82 "✅ Monitor(es) aplicado(s) a $HYPR_FINAL_CONF"
fi

NIRI_FINAL_CONF="$CONFIG_DIR/niri/config.kdl"
if $INSTALL_NIRI && [ -f "$NIRI_FINAL_CONF" ] && grep -q "AUTO_MONITOR_BLOCK" "$NIRI_FINAL_CONF"; then
  NIRI_MONITOR_BLOCK=$(generate_niri_output_block)
  awk -v block="$NIRI_MONITOR_BLOCK" '
    /AUTO_MONITOR_BLOCK/ { print block; next }
    { print }
  ' "$NIRI_FINAL_CONF" >"${NIRI_FINAL_CONF}.tmp"
  mv "${NIRI_FINAL_CONF}.tmp" "$NIRI_FINAL_CONF"
  chown "$REAL_USER:$REAL_USER" "$NIRI_FINAL_CONF"
  gum style --foreground 82 "✅ Monitor(es) aplicado(s) a $NIRI_FINAL_CONF"
fi

# -----------------------------
# 10.3. Aplicar el emulador de terminal elegido — también al final
# -----------------------------
# Mismo motivo que el monitor: se hace después de que todo terminó de
# copiarse, para que no lo pise una restauración posterior. Reemplaza
# el marcador AUTO_TERMINAL_EMULATOR por el terminal elegido en la
# sección 0.8 ($SEL_TERMINAL_EMU).
# Ojo: los flags "--class" y "-e" que usan estos binds son de kitty;
# alacritty los soporta igual, pero foot usa "-a" en vez de "--class" y
# wezterm tiene su propia sintaxis (wezterm start --class ... -- cmd).
# Si elegiste foot/wezterm, revisá esos binds a mano después.
if [ -f "$HYPR_FINAL_CONF" ] && grep -q "AUTO_TERMINAL_EMULATOR" "$HYPR_FINAL_CONF"; then
  sed -i "s/AUTO_TERMINAL_EMULATOR/${SEL_TERMINAL_EMU}/g" "$HYPR_FINAL_CONF"
  chown "$REAL_USER:$REAL_USER" "$HYPR_FINAL_CONF"
  gum style --foreground 82 "✅ Terminal ($SEL_TERMINAL_EMU) aplicado a $HYPR_FINAL_CONF"
fi
if [ -f "$NIRI_FINAL_CONF" ] && grep -q "AUTO_TERMINAL_EMULATOR" "$NIRI_FINAL_CONF"; then
  sed -i "s/AUTO_TERMINAL_EMULATOR/${SEL_TERMINAL_EMU}/g" "$NIRI_FINAL_CONF"
  chown "$REAL_USER:$REAL_USER" "$NIRI_FINAL_CONF"
  gum style --foreground 82 "✅ Terminal ($SEL_TERMINAL_EMU) aplicado a $NIRI_FINAL_CONF"
fi

# -----------------------------
# 12. Notas post-instalación
# -----------------------------
gum style --border rounded --border-foreground 25 --padding "1 3" --margin "1 0" "$(
  cat <<'EOF'
🎉 Instalación completada. Notas importantes:

🔵 os-prober (arranque dual con GRUB, si aplica):
   /etc/default/grub → GRUB_DISABLE_OS_PROBER=false
   Luego: grub-mkconfig -o /boot/grub/grub.cfg

🔵 Snapper:
   Configurado automáticamente si el filesystem raíz es BTRFS (config
   'root' con tus valores, timers de timeline/cleanup habilitados). No
   hace falta correrlo a mano.

🔵 SDDM y SilentSDDM se activarán en el próximo arranque.
EOF
)"

if $SILENT; then
  gum style --foreground 244 "🔁 Reiniciando en 10 segundos... (Ctrl+C para cancelar)"
  sleep 10
  reboot
else
  if confirm_step "¿Reiniciar el sistema ahora?"; then
    reboot
  else
    gum style --foreground 244 "Reinicio pospuesto. Ejecuta 'reboot' cuando quieras aplicar todos los cambios."
  fi
fi
