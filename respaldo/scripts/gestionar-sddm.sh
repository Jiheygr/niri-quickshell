#!/usr/bin/env bash
#
# gestionar-sddm.sh — Herramienta todo-en-uno para gestionar el tema SilentSDDM
#
# Subcomandos:
#   list                        Lista los presets disponibles en configs/
#   current                     Muestra el preset actualmente activo
#   set <preset>                Cambia el preset activo (ej: rei, ken, nord)
#   test [debug]                Prueba el tema sin reiniciar (./test.sh del tema)
#   update                      Reinstala/actualiza sddm-silent-theme vía paru
#   backup                      Guarda metadata.desktop actual en ~/respaldo/sddm/
#   avatar <usuario> <imagen>   Cambia el avatar de un usuario
#   background <archivo> [destino]
#                                Cambia el fondo (imagen/video). destino: login|lock|both
#   pick | (sin argumentos)     Selector interactivo con fzf + preview (requiere chafa)
#                                ESC en la lista de archivos = volver al menú principal
#
# Requiere para el preview: chafa (sudo pacman -S chafa)
# Requiere para thumbnails de video: ffmpeg
#
# Uso: gestionar-sddm.sh <subcomando> [args]

set -e

green='\033[0;32m'
red='\033[0;31m'
bred='\033[1;31m'
cyan='\033[0;36m'
grey='\033[2;37m'
reset='\033[0m'

THEME_DIR="/usr/share/sddm/themes/silent"
BACKGROUNDS_DIR="$THEME_DIR/backgrounds"
VALID_BG_EXT="jpg|jpeg|png|avi|mp4|mov|mkv|m4v|webm"

REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(eval echo "~$REAL_USER")
BACKUP_DIR="$USER_HOME/respaldo/sddm"
THUMB_CACHE="$USER_HOME/.cache/sddm-fzf-thumbs"

# Carpeta de Imágenes real del usuario (respeta xdg-user-dirs, con
# fallback a ~/Pictures) — misma convención que usa install.sh, así
# funciona con cualquier usuario, no solo en esta máquina.
PICTURES_DIR=$(sudo -u "$REAL_USER" xdg-user-dir PICTURES 2>/dev/null)
[[ -z "$PICTURES_DIR" ]] && PICTURES_DIR="$USER_HOME/Pictures"

# Carpetas de origen para el selector fzf
WALLPAPER_DIR="$PICTURES_DIR/Wallpapers"
AVATAR_DIR="$PICTURES_DIR/avatar"

BACK_LABEL="⬅️  Volver al menú principal"

require_theme_installed() {
  if [[ ! -d "$THEME_DIR" ]]; then
    echo -e "${bred}❌ El tema SilentSDDM no está instalado en ${THEME_DIR}${reset}"
    echo -e "   Instálalo con: ${cyan}paru -S sddm-silent-theme${reset}"
    exit 1
  fi
}

get_active_conf_path() {
  local rel
  rel=$(awk -F '=' '/^ConfigFile=/ {print $2}' "$THEME_DIR/metadata.desktop")
  echo "$THEME_DIR/$rel"
}

set_conf_option() {
  local file="$1" section="$2" key="$3" value="$4"
  local tmp
  tmp=$(mktemp)

  sudo cat "$file" | awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN { in_section=0; found_section=0; replaced=0 }
    /^\[.*\]$/ {
      if (in_section && !replaced) {
        print key " = \"" value "\""
        replaced=1
      }
      cur = substr($0, 2, length($0)-2)
      in_section = (cur == section)
      if (in_section) found_section=1
      print
      next
    }
    {
      if (in_section && $0 ~ "^[ \t]*" key "[ \t]*=") {
        print key " = \"" value "\""
        replaced=1
        next
      }
      print
    }
    END {
      if (in_section && !replaced) {
        print key " = \"" value "\""
      }
      if (!found_section) {
        print ""
        print "[" section "]"
        print key " = \"" value "\""
      }
    }
  ' > "$tmp"

  sudo cp "$tmp" "$file"
  rm -f "$tmp"
}

cmd_list() {
  require_theme_installed
  echo -e "${grey}Presets disponibles:${reset}"
  ls "$THEME_DIR/configs" | sed 's/\.conf$//' | sed 's/^/  • /'
}

cmd_current() {
  require_theme_installed
  current=$(awk -F '=' '/^ConfigFile=/ {print $2}' "$THEME_DIR/metadata.desktop" | sed 's|configs/||; s|\.conf$||')
  echo -e "${green}Preset activo:${reset} ${current}"
}

cmd_set() {
  require_theme_installed
  local preset="$1"

  if [[ -z "$preset" ]]; then
    echo -e "${red}❌ Debes indicar un preset. Ej: $0 set ken${reset}"
    cmd_list
    exit 1
  fi

  if [[ ! -f "$THEME_DIR/configs/${preset}.conf" ]]; then
    echo -e "${red}❌ El preset '${preset}' no existe.${reset}"
    cmd_list
    exit 1
  fi

  echo -e "${grey}Cambiando preset a '${preset}'...${reset}"
  sudo sed -i "s|^ConfigFile=.*|ConfigFile=configs/${preset}.conf|" "$THEME_DIR/metadata.desktop"
  echo -e "${green}✅ Preset cambiado a: ${preset}${reset}"
  echo -e "${cyan}   Prueba con: $0 test${reset}"
}

cmd_test() {
  require_theme_installed
  cd "$THEME_DIR"
  if [[ "$1" =~ ^(debug|-debug|--debug|-d)$ ]]; then
    sudo ./test.sh debug
  else
    echo -e "${grey}Probando tema (Ctrl+C para salir)...${reset}"
    sudo ./test.sh
  fi
}

cmd_update() {
  echo -e "${grey}Actualizando sddm-silent-theme vía paru...${reset}"
  sudo -u "$REAL_USER" paru -S --noconfirm sddm-silent-theme
  echo -e "${green}✅ Tema actualizado.${reset}"
}

cmd_backup() {
  require_theme_installed
  mkdir -p "$BACKUP_DIR"
  cp "$THEME_DIR/metadata.desktop" "$BACKUP_DIR/metadata.desktop"
  chown -R "$REAL_USER:$REAL_USER" "$BACKUP_DIR" 2>/dev/null || true
  echo -e "${green}✅ Backup de metadata.desktop guardado en ${BACKUP_DIR}${reset}"
}

cmd_avatar() {
  require_theme_installed

  local username image

  if [[ $# -eq 1 ]]; then
    username="$REAL_USER"
    image="$1"
  elif [[ $# -eq 2 ]]; then
    username="$1"
    image="$2"
  else
    echo -e "${red}❌ Uso: $0 avatar [usuario] <ruta_imagen>${reset}"
    exit 1
  fi

  if [[ ! -f "$image" ]]; then
    echo -e "${red}❌ Archivo de imagen no encontrado: ${image}${reset}"
    exit 1
  fi

  if [[ ! -x "$THEME_DIR/change_avatar.sh" ]]; then
    echo -e "${red}❌ No se encontró change_avatar.sh en ${THEME_DIR}${reset}"
    exit 1
  fi

  cd "$THEME_DIR"
  sudo ./change_avatar.sh "$username" "$image"
}

cmd_background() {
  require_theme_installed
  local src="$1"
  local target="${2:-both}"

  if [[ -z "$src" ]]; then
    echo -e "${red}❌ Uso: $0 background <archivo> [login|lock|both]${reset}"
    exit 1
  fi

  if [[ ! -f "$src" ]]; then
    echo -e "${red}❌ Archivo no encontrado: ${src}${reset}"
    exit 1
  fi

  local ext="${src##*.}"
  ext="${ext,,}"
  if [[ ! "$ext" =~ ^(${VALID_BG_EXT})$ ]]; then
    echo -e "${red}❌ Formato no soportado: .${ext}${reset}"
    echo -e "   Soportados: jpg, jpeg, png, avi, mp4, mov, mkv, m4v, webm (NO .gif)"
    exit 1
  fi

  local filename
  filename=$(basename "$src")

  echo -e "${grey}Copiando '${filename}' a ${BACKGROUNDS_DIR}/...${reset}"
  sudo mkdir -p "$BACKGROUNDS_DIR"
  sudo cp -f "$src" "$BACKGROUNDS_DIR/$filename"

  local conf_path
  conf_path=$(get_active_conf_path)

  if [[ "$target" == "login" || "$target" == "both" ]]; then
    set_conf_option "$conf_path" "LoginScreen" "background" "$filename"
    echo -e "${green}✅ Fondo de LoginScreen actualizado.${reset}"
  fi

  if [[ "$target" == "lock" || "$target" == "both" ]]; then
    set_conf_option "$conf_path" "LockScreen" "background" "$filename"
    echo -e "${green}✅ Fondo de LockScreen actualizado.${reset}"
  fi

  if [[ "$ext" =~ ^(mp4|avi|mov|mkv|m4v|webm)$ ]]; then
    echo -e "${cyan}ℹ️  Es un video. Considera generar un placeholder con ffmpeg:${reset}"
    echo -e "   ${grey}ffmpeg -i \"$BACKGROUNDS_DIR/$filename\" -vframes 1 \"$BACKGROUNDS_DIR/${filename%.*}_placeholder.jpg\"${reset}"
    echo -e "   ${grey}y luego setear animated-background-placeholder en [General] del .conf${reset}"
  fi

  echo -e "${cyan}   Prueba con: $0 test${reset}"
}

# Genera el comando de preview para fzf usando chafa (funciona en cualquier shell/terminal
# que soporte color truecolor; en kitty además puede usar el protocolo de gráficos nativo).
# $1 = directorio base de los archivos listados (solo se muestran basenames en fzf)
build_preview_cmd() {
  local dir="$1"
  mkdir -p "$THUMB_CACHE"
  cat <<PREVIEW
sel={}
if [[ "\$sel" == "$BACK_LABEL" ]]; then
  echo "Volver al menú principal"
  exit 0
fi
f="$dir/\$sel"
ext="\${f##*.}"
ext=\$(printf '%s' "\$ext" | tr '[:upper:]' '[:lower:]')
if [[ "\$ext" = "mp4" || "\$ext" = "mov" || "\$ext" = "mkv" || "\$ext" = "m4v" || "\$ext" = "webm" || "\$ext" = "avi" ]]; then
  thumb="$THUMB_CACHE/\$sel.jpg"
  if [[ ! -f "\$thumb" ]] && command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -ss 00:00:01 -i "\$f" -vframes 1 -q:v 3 "\$thumb" >/dev/null 2>&1
  fi
  [[ -f "\$thumb" ]] && f="\$thumb"
fi
if command -v chafa >/dev/null 2>&1; then
  cols="\${FZF_PREVIEW_COLUMNS:-80}"
  lines="\${FZF_PREVIEW_LINES:-24}"
  chafa --size="\${cols}x\${lines}" "\$f"
else
  echo "chafa no está instalado (sudo pacman -S chafa)"
  echo ""
  file -b "\$f" 2>/dev/null
fi
PREVIEW
}

# Selector fzf para una carpeta de archivos (wallpapers o avatares).
# $2 = "wallpaper" (imagen o video) | "avatar" (solo imagen)
# Devuelve por stdout: nombre de archivo elegido, o "$BACK_LABEL", o vacío si se canceló.
select_file() {
  local dir="$1" filetype="$2" prompt="$3"
  local preview_cmd
  preview_cmd=$(build_preview_cmd "$dir")

  local files
  if [[ "$filetype" == "wallpaper" ]]; then
    files=$(find "$dir" -maxdepth 1 -type f \( \
        -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mkv" -o -iname "*.m4v" \
        -o -iname "*.webm" -o -iname "*.avi" \
        -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
      \) -printf "%f\n" | sort)
  else
    files=$(find "$dir" -maxdepth 1 -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \
      \) -printf "%f\n" | sort)
  fi

  { echo "$BACK_LABEL"; printf '%s\n' "$files"; } | \
    fzf --prompt="$prompt > " --height=90% --border --reverse \
        --header="ESC o '$BACK_LABEL' = volver" \
        --preview="$preview_cmd" --preview-window=right:60% || true
}

cmd_pick() {
  require_theme_installed

  if ! command -v fzf >/dev/null 2>&1; then
    echo -e "${red}❌ fzf no está instalado.${reset}"
    exit 1
  fi

  if ! command -v chafa >/dev/null 2>&1; then
    echo -e "${cyan}ℹ️  chafa no está instalado, el preview de imágenes no funcionará.${reset}"
    echo -e "   Instálalo con: sudo pacman -S chafa"
  fi

  while true; do
    local choice
    choice=$(printf "🖼️  Wallpaper (fondo animado)\n👤  Avatar\n🚪  Salir" | \
      fzf --prompt="¿Qué quieres cambiar? > " --height=10 --border --reverse || true)

    case "$choice" in
      *Wallpaper*)
        if [[ ! -d "$WALLPAPER_DIR" ]]; then
          echo -e "${red}❌ No existe la carpeta: $WALLPAPER_DIR${reset}"
          continue
        fi
        local file
        file=$(select_file "$WALLPAPER_DIR" "wallpaper" "Wallpaper")

        if [[ -z "$file" || "$file" == "$BACK_LABEL" ]]; then
          continue
        fi

        echo -e "${cyan}Aplicando wallpaper: ${file}...${reset}"
        cmd_background "$WALLPAPER_DIR/$file"
        echo -e "${green}✅ Listo.${reset}"
        read -n 1 -s -r -p "Presiona cualquier tecla para continuar..."
        ;;

      *Avatar*)
        if [[ ! -d "$AVATAR_DIR" ]]; then
          echo -e "${red}❌ No existe la carpeta: $AVATAR_DIR${reset}"
          continue
        fi
        local file
        file=$(select_file "$AVATAR_DIR" "avatar" "Avatar")

        if [[ -z "$file" || "$file" == "$BACK_LABEL" ]]; then
          continue
        fi

        echo -e "${cyan}Aplicando avatar: ${file}...${reset}"
        cmd_avatar "$AVATAR_DIR/$file"
        echo -e "${green}✅ Listo.${reset}"
        read -n 1 -s -r -p "Presiona cualquier tecla para continuar..."
        ;;

      *)
        # Salir, o ESC/cancelado en el menú principal
        break
        ;;
    esac
  done
}

case "$1" in
  list)       cmd_list ;;
  current)    cmd_current ;;
  set)        cmd_set "$2" ;;
  test)       cmd_test "$2" ;;
  update)     cmd_update ;;
  backup)     cmd_backup ;;
  avatar)     shift; cmd_avatar "$@" ;;
  background) shift; cmd_background "$@" ;;
  pick)       cmd_pick ;;
  "")         cmd_pick ;;
  *)
    echo -e "${cyan}Uso:${reset} $0 {list|current|set <preset>|test [debug]|update|backup|avatar [usuario] <imagen>|background <archivo> [login|lock|both]|pick}"
    exit 1
    ;;
esac
