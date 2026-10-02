#!/bin/bash
set -euo pipefail

# autoXRAY minimal fork by ChatGPT for David
# v11: add profile-update-interval=3 and append reminder clone profile.
# Only VLESS RAW REALITY VISION + simple named subscription pages + nginx-based link tracking.

GRN='\033[1;32m'
RED='\033[1;31m'
YEL='\033[1;33m'
BLU='\033[1;34m'
NC='\033[0m'

PROJECT_NAME="vpn-cluster.skam"
APP_DIR="/etc/vpn-cluster"
BACKUP_DIR="/root/vpn-cluster-backups"
XRAY_DIR="/usr/local/etc/xray"
CERT_DIR="/var/lib/xray/cert"
CORE_DIR_NAME="_core"
LOG_FILE="/var/log/nginx/vpn-cluster-access.log"
BRANDING_FILE="$APP_DIR/branding.conf"

[[ $EUID -eq 0 ]] || { echo -e "${RED}❌ скрипту нужны root права${NC}"; exit 1; }

cmd="install"
DOMAIN=""
USERNAME=""

case "${1:-}" in
  install)
    cmd="install"; DOMAIN="${2:-}" ;;
  adduser|deluser|listusers|sync|backup|stats|webfix|brand|serverfix|catalog)
    cmd="$1"; DOMAIN="${2:-}"; USERNAME="${3:-}" ;;
  help|-h|--help|"")
    cat <<EOF
Использование:
  $0 install DOMAIN              полная установка / переустановка
  $0 DOMAIN                      то же самое, короткая форма
  $0 adduser DOMAIN username     создать именную подписку
  $0 deluser DOMAIN username     удалить именную подписку
  $0 listusers DOMAIN            показать пользователей
  $0 sync DOMAIN                 пересоздать именные ссылки из текущего конфига
  $0 stats DOMAIN [username]      статистика переходов и скачиваний подписок
  $0 webfix DOMAIN               обновить дизайн/страницы/подписки без перегенерации Xray
  $0 brand DOMAIN                показать файл настройки дизайна и контента
  $0 backup DOMAIN               сделать резервную копию

Пример:
  $0 install vpn.example.com
  $0 adduser vpn.example.com mama
  $0 deluser vpn.example.com mama
  $0 stats vpn.example.com
  $0 stats vpn.example.com mama
EOF
    exit 0 ;;
  *)
    cmd="install"; DOMAIN="$1" ;;
esac

if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}❌ Ошибка: домен не задан.${NC}"
  exit 1
fi

WEB_PATH="/var/www/$DOMAIN"
CORE_PATH="$WEB_PATH/$CORE_DIR_NAME"
USERS_FILE="$APP_DIR/users.txt"
ENV_FILE="$APP_DIR/current.env"

validate_username() {
  local u="$1"
  [[ "$u" =~ ^[A-Za-z0-9_-]{2,32}$ ]]
}

write_default_branding() {
  mkdir -p "$APP_DIR"
  if [[ -f "$BRANDING_FILE" ]]; then return 0; fi
  cat > "$BRANDING_FILE" <<'EOF'
# /etc/vpn-cluster/branding.conf
# Этот файл можно менять в любой момент. После изменения запустите:
#   sudo ./autoXRAY_davida_custom.sh webfix vpn.example.com
# Xray, ключи и Reality-конфиг при этом не трогаются.

SUBSCRIPTION_NAME="vpn-cluster.skam"
SERVER_FLAG="🇫🇮"
PAGE_TITLE="Личный доступ к vpn-cluster.skam"
PAGE_HELLO="Привет! Это твоя персональная страница для подключения."
PAGE_SUBTITLE="Нажми основную кнопку, чтобы добавить подписку в HAPP, или скопируй ссылку вручную."
WARNING_TEXT="Пожалуйста, не пересылай эту ссылку. Если она окажется у других людей, доступ может быть ограничен или отключён. Для друга лучше попросить отдельную персональную ссылку."
ROUTING_NOTE="Просьба: в клиенте включай маршрутизацию только для нужных приложений и сайтов, а не для всего интернета, если тебе не нужен полный туннель. Так соединение обычно стабильнее и быстрее."
FOOTER_TEXT="Если что-то не работает — напиши мне, я создам новую ссылку или помогу настроить приложение."

# Цвета фона/свечения. Можно менять на любые hex-цвета.
ACCENT_A="#7dd3fc"
ACCENT_B="#c084fc"
ACCENT_C="#86efac"

# Ссылки на приложения. APK/EXE ведут сразу на загрузку, без GitHub-интерфейса.
HAPP_ANDROID_URL="https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk"
HAPP_IOS_URL="https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973"
HAPP_WINDOWS_URL="https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe"
AMNEZIA_ANDROID_URL="https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.0.5/AmneziaVPN_5.0.0.5_android9%2B_arm64-v8a.apk"
AMNEZIA_IOS_URL="https://apps.apple.com/app/defaultvpn/id6744725017"
AMNEZIA_WINDOWS_URL="https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.0.5/AmneziaVPN_5.0.0.5_windows_x64.exe"
V2RAYTUN_ANDROID_URL="https://play.google.com/store/apps/details?id=com.v2raytun.android"
V2RAYTUN_IOS_URL="https://apps.apple.com/ru/app/v2ray-vpn-client/id6752994543"
# Ссылки оплаты по СБП. Их можно заменить в branding.conf без изменения шаблона.
DONATE_SBER_URL=""
DONATE_TBANK_URL=""
AMNEZIA_ESTONIA_URL="vpn://YOUR_AMNEZIA_PROFILE_KEY"
EOF
}

load_branding() {
  SUBSCRIPTION_NAME="$PROJECT_NAME"
  SERVER_FLAG="🇫🇮"
  PAGE_TITLE="Личный доступ к $PROJECT_NAME"
  PAGE_HELLO="Привет! Это твоя персональная страница для подключения."
  PAGE_SUBTITLE="Нажми основную кнопку, чтобы добавить подписку в HAPP, или скопируй ссылку вручную."
  WARNING_TEXT="Пожалуйста, не пересылай эту ссылку. Если она окажется у других людей, доступ может быть ограничен или отключён. Для друга лучше попросить отдельную персональную ссылку."
  ROUTING_NOTE="Просьба: в клиенте включай маршрутизацию только для нужных приложений и сайтов, а не для всего интернета, если тебе не нужен полный туннель. Так соединение обычно стабильнее и быстрее."
  FOOTER_TEXT="Если что-то не работает — напиши мне, я создам новую ссылку или помогу настроить приложение."
  ACCENT_A="#7dd3fc"
  ACCENT_B="#c084fc"
  ACCENT_C="#86efac"
  HAPP_COLOR_PROFILE="base64:eyJiYWNrZ3JvdW5kR3JhZGllbnRSb3RhdGlvbkFuZ2xlIjozOCwic2VydmVyUm93QmFja2dyb3VuZENvbG9yIjoiIzExMUIzNUM5Iiwic3Vic0hlYWRlckNvbG9yIjoiIzE4MjY0QUZGIiwicHJvZmlsZVdlYlBhZ2VJY29uQ29sb3IiOiIjQTVCNEZDRkYiLCJzZWxlY3RlZFNlcnZlclJvd0NvbG9yIjoiIzI1M0I3MkU2IiwiZGlzY2xvc3VyZWFkZXJTdWJIZWFkZXJUZXh0Q29sb3IiOiIjQThCNkQ2RkYiLCJidXR0b25UZXh0Q29sb3IiOiIjMDgxMTFGRkYiLCJidXR0b25UaW1lckNvbG9yIjoiI0RDRTdGRkZGIiwic3Vic2NyaXB0aW9uSW5mb0JhY2tncm91bmRDb2xvciI6IiMxMTFDMzhGRiIsImJhY2tncm91bmRDb2xvcnMiOlsiIzBCMTAyMEZGIiwiIzE0MUMzQUZGIiwiIzIyMjg1QkZGIiwiIzNCMkI3M0ZGIl0sImJhY2tncm91bmRHcmFkaWVudENvbG9ySW50ZW5zaXR5IjowLjg1LCJhZGRpdGlvbmFsT3B0aW9uc0J1dHRvbkNvbG9yIjoiI0M3RDJGRUZGIiwiYnV0dG9uSW1hZ2VUeXBlIjoibGlnaHQiLCJzZXJ2ZXJSb3dTdWJUaXRsZVRleHRDb2xvciI6IiNBOEI2RDZGRiIsInN1cHBvcnRJY29uQ29sb3IiOiIjRjlBOEQ0RkYiLCJ0b3BCYXJCdXR0b25zQ29sb3IiOiIjRjhGQUZDRkYiLCJzdWJzY3JpcHRpb25UcmFmZmljQmFja2dyb3VuZENvbG9yIjoiIzFFMkI1MkZGIiwic3ViSGVhZGVyQnV0dG9uQ29sb3IiOiIjQzdEMkZFRkYiLCJidXR0b25Db2xvciI6IiNBN0YzRDBGRiIsInBvd2VySWNvbkNvbG9yIjoiIzE3MjU1NEZGIiwic3Vic2NyaXB0aW9uSW5mb1RleHRDb2xvciI6IiNGOEZBRkNGRiIsInNlcnZlclJvd1RpdGxlVGV4dENvbG9yIjoiI0Y4RkFGQ0ZGIiwiYmFja2dyb3VuZEltYWdlVHlwZSI6InN5c3RlbSIsImVsaXBzZUNvbG9ycyI6WyIjMjJEM0VFQTYiLCIjQTc4QkZBQTYiLCIjRjQ3MkI2QTYiXSwic2VydmVyUm93Q2hldnJvbkNvbG9yIjoiI0NCRDVFMUZGIiwic2V0dGluZ3NDb250cm9sc1RpbnRDb2xvciI6IiNBNzhCRkFGRiJ9"
  HAPP_ANDROID_URL="https://github.com/Happ-proxy/happ-android/releases/latest/download/Happ.apk"
  HAPP_IOS_URL="https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973"
  HAPP_WINDOWS_URL="https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe"
  AMNEZIA_ANDROID_URL="https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.0.5/AmneziaVPN_5.0.0.5_android9%2B_arm64-v8a.apk"
  AMNEZIA_IOS_URL="https://apps.apple.com/app/defaultvpn/id6744725017"
  AMNEZIA_WINDOWS_URL="https://github.com/amnezia-vpn/amnezia-client/releases/download/5.0.0.5/AmneziaVPN_5.0.0.5_windows_x64.exe"
  V2RAYTUN_ANDROID_URL="https://play.google.com/store/apps/details?id=com.v2raytun.android"
  V2RAYTUN_IOS_URL="https://apps.apple.com/ru/app/v2ray-vpn-client/id6752994543"
  DONATE_SBER_URL=""
  DONATE_TBANK_URL=""
  AMNEZIA_ESTONIA_URL="${AMNEZIA_ESTONIA_URL:-}"
  if [[ -f "$BRANDING_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$BRANDING_FILE"
  fi
  if [[ -f "${SERVER_CATALOG_FILE:-$APP_DIR/servers.conf}" ]]; then
    # shellcheck disable=SC1090
    source "${SERVER_CATALOG_FILE:-$APP_DIR/servers.conf}"
  fi
}

write_default_servers() {
  local file="${SERVER_CATALOG_FILE:-$APP_DIR/servers.conf}"
  [[ -f "$file" ]] && return 0
  cat > "$file" <<EOF
# Central Amnezia profiles. Replace values here, then run: $0 webfix $DOMAIN
AMNEZIA_ESTONIA_URL="$AMNEZIA_ESTONIA_URL"
EOF
  chmod 600 "$file"
}

write_server_catalog() {
  load_branding
  python3 - <<'PY'
import json
import os
from pathlib import Path
nodes = []
try:
    nodes = json.loads(Path("/etc/vpn-cluster/nodes.json").read_text(encoding="utf-8"))
except:
    pass

servers = []
for n in nodes:
    if n.get("amnezia_url"):
        servers.append({
            "id": n["id"],
            "name": n["name"],
            "flag": n["name"].split(" ")[0] if " " in n["name"] else "🌐",
            "protocol": "AmneziaVPN",
            "url": n["amnezia_url"]
        })

out = {
    "version": 2,
    "apps": {
        "android": os.environ.get("AMNEZIA_ANDROID_URL", ""),
        "ios": os.environ.get("AMNEZIA_IOS_URL", ""),
        "windows": os.environ.get("AMNEZIA_WINDOWS_URL", "")
    },
    "servers": servers
}
Path(os.environ.get("WEB_PATH", "/var/www/vpn-ch.example.com") + "/servers.json").write_text(json.dumps(out, ensure_ascii=False))
PY
  chmod 644 "$WEB_PATH/servers.json"
}

ensure_dirs() {
  mkdir -p "$APP_DIR" "$BACKUP_DIR" "$WEB_PATH" "$CORE_PATH" "$CERT_DIR" "$XRAY_DIR"
  touch "$USERS_FILE"
  write_default_branding
  load_branding
  write_default_servers
}

show_branding() {
  ensure_dirs
  echo -e "${YEL}Файл дизайна и контента:${NC} $BRANDING_FILE"
  echo ""
  sed 's/^/  /' "$BRANDING_FILE"
  echo ""
  echo -e "${YEL}После редактирования применить для всех пользователей:${NC}"
  echo "  $0 webfix $DOMAIN"
  echo "  $0 brand $DOMAIN"
}

make_backup() {
  ensure_dirs
  local ts archive
  ts="$(date +%Y%m%d-%H%M%S)"
  archive="$BACKUP_DIR/${DOMAIN}-${ts}.tar.gz"
  tar -czf "$archive" \
    --ignore-failed-read \
    "$APP_DIR" \
    "$WEB_PATH" \
    "$XRAY_DIR/config.json" \
    "$CERT_DIR" 2>/dev/null || true
  echo -e "${GRN}✅ Бекап создан:${NC} $archive"
}

write_landing_page() {
  local username="$1"
  local nnect_dir="$WEB_PATH/nnect"
  
  local user_uuid=""
  if [[ -f "$ETC_DIR/users.json" ]]; then
    user_uuid=$(jq -r --arg u "$username" '.[$u] // empty' "$ETC_DIR/users.json")
  fi
  local sub_filename="$username.json"
  if [[ -n "$user_uuid" ]]; then
    sub_filename="${username}_${user_uuid}.json"
  fi
  
  local sub_url="https://$DOMAIN/sub/$sub_filename"
  local happ_add_url="happ://add/$sub_url"
  local page_file="$nnect_dir/$username.html"

  load_branding

  if [[ -e "$nnect_dir" && ! -d "$nnect_dir" ]]; then
    mv "$nnect_dir" "$nnect_dir.bak-$(date +%Y%m%d-%H%M%S)"
  fi
  mkdir -p "$nnect_dir"

  : <<'OLDER_TEMPLATE'
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>__TITLE__</title>
<meta name="robots" content="noindex,nofollow">
<script src="https://cdn.tailwindcss.com"></script>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css">
<style>
:root{color-scheme:light}
*{box-sizing:border-box}
html{min-height:100%;scroll-behavior:smooth}
body{min-height:100vh;margin:0;overflow-x:hidden;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#0f172a;background:#475569}
body:before{content:"";position:fixed;inset:0;z-index:-2;background:radial-gradient(circle at 50% -12%,rgba(226,232,240,.68),transparent 42%),radial-gradient(circle at 0% 30%,rgba(148,163,184,.34),transparent 36%),linear-gradient(160deg,#64748b 0%,#475569 53%,#334155 100%)}
body:after{content:"";position:fixed;inset:0;z-index:-1;pointer-events:none;background:radial-gradient(ellipse at center,transparent 35%,rgba(15,23,42,.32) 100%)}
.grain{position:fixed;inset:-18%;z-index:50;pointer-events:none;opacity:.04;mix-blend-mode:overlay;background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 180 180' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='noise'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.82' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23noise)' opacity='1'/%3E%3C/svg%3E");background-size:180px 180px;animation:grain .45s steps(4) infinite}
@keyframes grain{0%{transform:translate(0,0)}25%{transform:translate(-2%,1%)}50%{transform:translate(1%,-2%)}75%{transform:translate(2%,2%)}100%{transform:translate(0,0)}}
.glass{background:rgba(255,255,255,.45);backdrop-filter:blur(26px) saturate(.9);-webkit-backdrop-filter:blur(26px) saturate(.9);box-shadow:0 26px 60px rgba(15,23,42,.22),0 8px 18px rgba(15,23,42,.12)}
.glass-soft{background:rgba(255,255,255,.27);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px)}
.btn-primary{background:linear-gradient(135deg,#4338ca,#312e81);color:#fff;box-shadow:0 16px 28px rgba(49,46,129,.32),inset 0 1px rgba(255,255,255,.22);transition:transform .2s ease,box-shadow .2s ease,filter .2s ease}
.btn-primary:hover{transform:translateY(-2px);filter:saturate(1.08);box-shadow:0 20px 34px rgba(49,46,129,.4),inset 0 1px rgba(255,255,255,.25)}
.btn-primary:active{transform:translateY(0)}
.btn-secondary{background:rgba(255,255,255,.36);color:#1e293b;box-shadow:0 8px 16px rgba(15,23,42,.1);transition:transform .2s ease,background .2s ease}
.btn-secondary:hover{transform:translateY(-1px);background:rgba(255,255,255,.55)}
.focus-ring:focus-visible{outline:3px solid rgba(67,56,202,.5);outline-offset:3px}
.toast{opacity:0;transform:translate(-50%,12px);pointer-events:none;transition:opacity .2s ease,transform .2s ease}
.toast.show{opacity:1;transform:translate(-50%,0)}
details>summary{list-style:none;cursor:pointer}
details>summary::-webkit-details-marker{display:none}
details[open] .chevron{transform:rotate(180deg)}
.chevron{transition:transform .2s ease}
@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}.grain,.btn-primary,.btn-secondary,.toast,.chevron{animation:none;transition:none}}
</style>
</head>
<body>
<div class="grain" aria-hidden="true"></div>
<main class="relative mx-auto max-w-5xl px-4 py-5 sm:px-6 sm:py-8 lg:py-10">
  <header class="mb-5 flex items-center justify-between gap-3 sm:mb-7">
    <div class="flex items-center gap-2 text-sm font-semibold tracking-tight text-white/95">
      <span class="grid h-9 w-9 place-items-center rounded-2xl bg-white/35 text-indigo-900 shadow-lg shadow-slate-900/10"><i class="fa-solid fa-shield-halved" aria-hidden="true"></i></span>
      <span>vpn-cluster<span class="text-indigo-200">.skam</span></span>
    </div>
    <span class="inline-flex items-center gap-2 rounded-full bg-white/28 px-3 py-1.5 text-[11px] font-semibold uppercase tracking-[.12em] text-white/90 shadow-sm">
      <span>__SERVER_FLAG__</span><span>личная страница</span>
    </span>
  </header>

  <section class="glass relative isolate overflow-hidden rounded-[2rem] p-6 sm:p-9">
    <div class="pointer-events-none absolute -right-24 -top-28 h-72 w-72 rounded-full bg-indigo-400/20 blur-3xl"></div>
    <div class="pointer-events-none absolute -bottom-36 left-1/3 h-64 w-64 rounded-full bg-sky-200/25 blur-3xl"></div>
    <div class="relative grid items-center gap-7 lg:grid-cols-[1fr_auto]">
      <div>
        <div class="mb-4 inline-flex items-center gap-2 rounded-full bg-white/35 px-3 py-1.5 text-xs font-semibold text-indigo-950/80">
          <i class="fa-solid fa-lock text-indigo-700" aria-hidden="true"></i>
          <span>Твой личный доступ</span>
        </div>
        <h1 class="max-w-2xl text-4xl font-extrabold tracking-[-.055em] text-slate-900 sm:text-6xl">Привет, <span class="text-indigo-800">__USERNAME__</span></h1>
        <p class="mt-4 max-w-2xl text-base leading-7 text-slate-700 sm:text-lg">Подключение к интернету без лишних настроек. Выбери приложение ниже — всё остальное уже подготовлено.</p>
        <div class="mt-6 flex flex-wrap gap-2 text-xs font-semibold text-slate-700">
          <span class="inline-flex items-center gap-2 rounded-full bg-white/38 px-3 py-2"><i class="fa-solid fa-circle-check text-emerald-700" aria-hidden="true"></i>Готово к подключению</span>
          <span class="inline-flex items-center gap-2 rounded-full bg-white/38 px-3 py-2"><i class="fa-solid fa-user-shield text-indigo-700" aria-hidden="true"></i>Ссылка только для тебя</span>
        </div>
      </div>
      <div class="hidden h-32 w-32 place-items-center rounded-[2rem] bg-white/32 shadow-inner shadow-white/30 lg:grid">
        <i class="fa-solid fa-wand-magic-sparkles text-5xl text-indigo-800/80" aria-hidden="true"></i>
      </div>
    </div>
  </section>

  <section class="mt-5 grid gap-5 lg:grid-cols-[1.12fr_.88fr]">
    <article class="glass rounded-[1.75rem] p-5 sm:p-7">
      <div class="flex items-center justify-between gap-3">
        <span class="text-xs font-bold uppercase tracking-[.16em] text-slate-600">01 · Основной способ</span>
        <span class="rounded-full bg-indigo-900 px-3 py-1.5 text-[11px] font-bold text-white shadow-lg shadow-indigo-900/20"><i class="fa-solid fa-star mr-1" aria-hidden="true"></i>Проще всего</span>
      </div>
      <div class="mt-6 flex items-start gap-4">
        <span class="grid h-12 w-12 shrink-0 place-items-center rounded-2xl bg-indigo-900 text-xl text-white shadow-lg shadow-indigo-900/25"><i class="fa-solid fa-bolt" aria-hidden="true"></i></span>
        <div><h2 class="text-3xl font-extrabold tracking-tight text-slate-900">HAPP</h2><p class="mt-1 text-sm font-medium text-slate-600">Один клик — и подписка добавится сама.</p></div>
      </div>
      <p class="mt-5 max-w-xl text-sm leading-6 text-slate-700">Нажми большую кнопку. Если приложение ещё не установлено, сначала выбери своё устройство.</p>
      <a class="btn-primary focus-ring mt-6 flex min-h-14 items-center justify-between gap-4 rounded-2xl px-5 py-4 text-base font-extrabold" href="__HAPP_ADD_URL__">
        <span class="inline-flex items-center gap-3"><i class="fa-solid fa-circle-plus text-lg" aria-hidden="true"></i>Добавить в HAPP</span><i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i>
      </a>
      <div class="mt-5">
        <p class="mb-2 text-xs font-bold uppercase tracking-[.13em] text-slate-600">Скачать HAPP</p>
        <div class="flex flex-wrap gap-2">
          <a class="btn-secondary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-bold" target="_blank" rel="noopener" href="__HAPP_ANDROID_URL__"><i class="fa-brands fa-android text-base text-emerald-700" aria-hidden="true"></i>Android</a>
          <a class="btn-secondary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-bold" target="_blank" rel="noopener" href="__HAPP_IOS_URL__"><i class="fa-brands fa-apple text-base" aria-hidden="true"></i>iPhone</a>
          <a class="btn-secondary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-bold" target="_blank" rel="noopener" href="__HAPP_WINDOWS_URL__"><i class="fa-brands fa-windows text-base text-sky-700" aria-hidden="true"></i>Windows</a>
        </div>
      </div>
    </article>

    <aside class="glass-soft rounded-[1.75rem] p-5 shadow-[0_20px_45px_rgba(15,23,42,.16)] sm:p-7">
      <div class="flex items-center justify-between gap-3">
        <span class="text-xs font-bold uppercase tracking-[.16em] text-slate-600">Твоя ссылка</span>
        <i class="fa-solid fa-link text-indigo-800" aria-hidden="true"></i>
      </div>
      <h2 class="mt-5 text-2xl font-extrabold tracking-tight text-slate-900">Сохрани на всякий случай</h2>
      <p class="mt-3 text-sm leading-6 text-slate-700">Она уже добавлена в кнопку выше. Здесь её можно скопировать, если понадобится открыть HAPP вручную.</p>
      <button id="copy-sub" class="btn-secondary focus-ring mt-5 inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl px-4 py-3 text-sm font-extrabold" type="button"><i class="fa-regular fa-copy" aria-hidden="true"></i>Скопировать ссылку</button>
      <details class="mt-4 rounded-2xl bg-white/28 p-3">
        <summary class="focus-ring flex items-center justify-between gap-3 rounded-xl px-1 py-1 text-xs font-bold text-slate-700"><span>Показать ссылку вручную</span><i class="chevron fa-solid fa-chevron-down text-indigo-800" aria-hidden="true"></i></summary>
        <code id="sub" class="mt-3 block break-all rounded-xl bg-slate-900/75 p-3 text-[11px] leading-5 text-slate-100">__SUB_URL__</code>
      </details>
    </aside>
  </section>

  <section class="glass mt-5 rounded-[1.75rem] p-5 sm:p-7">
    <div class="flex flex-wrap items-start justify-between gap-4">
      <div>
        <span class="text-xs font-bold uppercase tracking-[.16em] text-slate-600">02 · Запасной вариант</span>
        <h2 class="mt-3 text-3xl font-extrabold tracking-tight text-slate-900">AmneziaVPN</h2>
        <p class="mt-2 max-w-2xl text-sm leading-6 text-slate-700">Если HAPP не открылся, выбери страну и нажми «Открыть». Приложение установит готовое подключение.</p>
      </div>
      <span class="inline-flex items-center gap-2 rounded-full bg-white/35 px-3 py-2 text-xs font-semibold text-slate-700"><i class="fa-solid fa-life-ring text-indigo-700" aria-hidden="true"></i>Резервный путь</span>
    </div>
    <div id="amnezia-list" class="mt-6 grid gap-3 md:grid-cols-2"><div class="rounded-2xl bg-white/28 p-4 text-sm text-slate-600"><i class="fa-solid fa-spinner fa-spin mr-2 text-indigo-700" aria-hidden="true"></i>Загружаем варианты…</div></div>
    <div class="mt-5 flex flex-wrap gap-2">
      <a id="amz-android" class="btn-secondary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-bold" target="_blank" rel="noopener"><i class="fa-brands fa-android text-base text-emerald-700" aria-hidden="true"></i>Amnezia для Android</a>
      <a id="amz-ios" class="btn-secondary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-bold" target="_blank" rel="noopener"><i class="fa-brands fa-apple text-base" aria-hidden="true"></i>Amnezia для iPhone</a>
    </div>
  </section>

  <section class="mt-5 grid gap-5 md:grid-cols-2">
    <details class="glass rounded-[1.75rem] p-5 sm:p-7">
      <summary class="focus-ring flex items-center justify-between gap-4 rounded-xl text-slate-900"><span class="inline-flex items-center gap-3 text-lg font-extrabold"><span class="grid h-10 w-10 place-items-center rounded-xl bg-white/40 text-indigo-800"><i class="fa-solid fa-list-check" aria-hidden="true"></i></span>Как подключиться</span><i class="chevron fa-solid fa-chevron-down text-indigo-800" aria-hidden="true"></i></summary>
      <ol class="mt-5 space-y-3 text-sm leading-6 text-slate-700">
        <li class="flex gap-3"><span class="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-indigo-900 text-xs font-bold text-white">1</span><span>Установи HAPP на своём устройстве.</span></li>
        <li class="flex gap-3"><span class="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-indigo-900 text-xs font-bold text-white">2</span><span>Нажми «Добавить в HAPP» выше.</span></li>
        <li class="flex gap-3"><span class="grid h-6 w-6 shrink-0 place-items-center rounded-full bg-indigo-900 text-xs font-bold text-white">3</span><span>Разреши добавление и включи соединение.</span></li>
      </ol>
    </details>
    <div class="glass-soft rounded-[1.75rem] p-5 sm:p-7">
      <div class="flex items-center gap-3 text-lg font-extrabold text-slate-900"><span class="grid h-10 w-10 place-items-center rounded-xl bg-white/40 text-indigo-800"><i class="fa-solid fa-heart" aria-hidden="true"></i></span>Нужна помощь?</div>
      <p class="mt-4 text-sm leading-6 text-slate-700">__FOOTER_TEXT__</p>
      <div class="mt-4 rounded-2xl bg-white/28 p-3 text-xs leading-5 text-slate-700"><i class="fa-solid fa-lightbulb mr-2 text-amber-600" aria-hidden="true"></i>__ROUTING_NOTE__</div>
    </div>
  </section>

  <section class="glass mt-5 rounded-[1.75rem] p-5 sm:p-7">
    <div class="flex items-start gap-3">
      <span class="grid h-10 w-10 shrink-0 place-items-center rounded-xl bg-rose-100/60 text-rose-700"><i class="fa-solid fa-user-lock" aria-hidden="true"></i></span>
      <div><h2 class="text-lg font-extrabold text-slate-900">Ссылка личная</h2><p class="mt-2 text-sm leading-6 text-slate-700">__WARNING_TEXT__</p></div>
    </div>
  </section>

  <footer class="px-1 py-7 text-center text-xs font-medium text-white/70">
    <span>vpn-cluster.skam</span><span class="mx-2 text-white/40">·</span><span>страница доступа для __USERNAME__</span>
  </footer>
</main>
<div id="toast" class="toast fixed bottom-6 left-1/2 z-[60] rounded-full bg-slate-950/90 px-4 py-2.5 text-sm font-bold text-white shadow-2xl" role="status" aria-live="polite">Скопировано</div>
<script>
const toast=document.getElementById("toast");
function showToast(message){toast.textContent=message;toast.classList.add("show");window.clearTimeout(window.__toastTimer);window.__toastTimer=window.setTimeout(()=>toast.classList.remove("show"),1800)}
async function copyText(value,message){try{if(navigator.clipboard&&window.isSecureContext){await navigator.clipboard.writeText(value)}else{const area=document.createElement("textarea");area.value=value;area.style.position="fixed";area.style.opacity="0";document.body.appendChild(area);area.focus();area.select();document.execCommand("copy");area.remove()}showToast(message||"Скопировано")}catch(_){showToast("Не получилось скопировать")}}
document.getElementById("copy-sub").addEventListener("click",()=>copyText(document.getElementById("sub").textContent.trim(),"Ссылка скопирована"));
function makeServerCard(server){
  const card=document.createElement("article");card.className="rounded-2xl bg-white/28 p-4 shadow-sm shadow-slate-900/10";
  const row=document.createElement("div");row.className="flex flex-wrap items-center justify-between gap-3";
  const title=document.createElement("div");title.className="flex min-w-0 items-center gap-3";
  const flag=document.createElement("span");flag.className="text-2xl";flag.textContent=server.flag||"🌐";
  const text=document.createElement("div");const name=document.createElement("div");name.className="font-extrabold text-slate-900";name.textContent=server.name||"Сервер";
  const protocol=document.createElement("div");protocol.className="mt-1 text-xs font-medium text-slate-600";protocol.textContent=server.protocol||"Готовое подключение";
  text.append(name,protocol);title.append(flag,text);
  const actions=document.createElement("div");actions.className="flex shrink-0 gap-2";
  const open=document.createElement("a");open.className="btn-primary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-extrabold";open.href=server.url||"#";open.textContent="Открыть ";const openIcon=document.createElement("i");openIcon.className="fa-solid fa-arrow-up-right-from-square";openIcon.setAttribute("aria-hidden","true");open.append(openIcon);
  const copy=document.createElement("button");copy.className="btn-secondary focus-ring inline-flex items-center gap-2 rounded-xl px-3 py-2.5 text-xs font-extrabold";copy.type="button";copy.textContent="Копировать";const copyIcon=document.createElement("i");copyIcon.className="fa-regular fa-copy";copyIcon.setAttribute("aria-hidden","true");copy.prepend(copyIcon);copy.addEventListener("click",()=>copyText(server.url||"","Ключ скопирован"));
  actions.append(open,copy);row.append(title,actions);card.append(row);return card
}
async function loadAmnezia(){
  const list=document.getElementById("amnezia-list");
  try{const response=await fetch("/servers.json?v="+Date.now(),{cache:"no-store"});if(!response.ok)throw new Error("catalog");const data=await response.json();document.getElementById("amz-android").href=(data.apps&&data.apps.android)||"#";document.getElementById("amz-ios").href=(data.apps&&data.apps.ios)||"#";list.replaceChildren(...(data.servers||[]).map(makeServerCard));if(!list.children.length)throw new Error("empty")}catch(_){list.innerHTML='<div class="rounded-2xl bg-white/28 p-4 text-sm text-slate-600"><i class="fa-solid fa-circle-exclamation mr-2 text-rose-700" aria-hidden="true"></i>Варианты временно недоступны. Обнови страницу чуть позже.</div>'}
}
loadAmnezia();
</script>
</body>
</html>
OLDER_TEMPLATE
  cat > "$page_file" <<'HTML_TEMPLATE'
<!DOCTYPE html>
<html lang="ru" style="--hue: 271.3;"><head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8">

<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
<title>__USERNAME__ // Персональный доступ</title>
<meta name="theme-color" content="#05070d">

<!-- Google Fonts: Bebas Neue, Inter, JetBrains Mono -->
<link rel="preconnect" href="https://fonts.googleapis.com/">
<link rel="preconnect" href="https://fonts.gstatic.com/" crossorigin="">
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Inter:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">

<style>
  :root {
    --hue: 175;
    --bg-base: #04060b;
    --ink-pure: #ffffff;
    --ink-high: rgba(240, 246, 255, 0.90);
    --ink-mid: rgba(195, 212, 235, 0.55);
    --ink-dim: rgba(160, 185, 215, 0.35);
    --line: rgba(255, 255, 255, 0.08);
    --line-hover: rgba(255, 255, 255, 0.18);

    --accent: hsla(var(--hue), 75%, 60%, 1);
    --accent-glow: hsla(var(--hue), 80%, 55%, 0.15);
    --accent-subtle: hsla(var(--hue), 70%, 50%, 0.08);

    --font-display: 'Bebas Neue', 'Inter', -apple-system, sans-serif;
    --font-ui: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    --font-mono: 'JetBrains Mono', 'Cascadia Code', Consolas, monospace;

    --ease-out: cubic-bezier(0.16, 1, 0.3, 1);
  }

  *, *::before, *::after {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }

  html {
    scroll-behavior: smooth;
    color-scheme: dark;
  }

  html, body {
    touch-action: manipulation;
    -webkit-text-size-adjust: 100%;
  }

  input, button {
    touch-action: manipulation;
  }

  body {
    background-color: var(--bg-base);
    color: var(--ink-high);
    font-family: var(--font-ui);
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    min-height: 100vh;
    min-height: 100svh;
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    position: relative;
    overflow-x: hidden;
    width: 100%;
    padding: 0;
  }

  /* Fullscreen GPU WebGL Aurora */
  #aurora {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    z-index: 0;
    pointer-events: none;
    background: #04060b;
    /* Bring the luminous horizon a little closer to the action area. */
    transform: translateY(3.5vh) scale(1.08);
    transform-origin: center center;
    filter: brightness(1.45) saturate(1.12);
  }

  /* Edge vignette: preserves the centre while letting the frame fall into night. */
  .vignette {
    position: fixed;
    inset: 0;
    z-index: 1;
    pointer-events: none;
    background:
      radial-gradient(circle at 50% 42%, transparent 54%, rgba(1, 3, 6, 0.16) 100%),
      linear-gradient(180deg,
        rgba(2, 4, 8, 0.10) 0%,
        transparent 25%,
          rgba(1, 3, 8, 0.09) 58%,
        rgba(0, 0, 0, 0.72) 100%);
  }

  /* Luminous atmospheric bottom gradient — soft ambient light dispersing upward */
  .atmo-bottom {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    height: 66%;
    z-index: 1;
    pointer-events: none;
    background:
      /* Soft radiant mist rising from bottom */
      linear-gradient(0deg,
        hsla(var(--hue), 55%, 30%, 0.28) 0%,
        hsla(var(--hue), 45%, 22%, 0.16) 35%,
        hsla(var(--hue), 35%, 15%, 0.06) 65%,
        transparent 100%
      ),
      /* Center soft illuminated bloom */
      radial-gradient(ellipse 120% 70% at 50% 100%,
        hsla(var(--hue), 70%, 52%, 0.22) 0%,
        hsla(calc(var(--hue) + 30), 60%, 42%, 0.13) 40%,
        transparent 75%
      );
    filter: blur(22px);
    transform: translateY(20px) scale(1.05);
  }

  /* Wide glowing atmospheric light wash */
  .atmo-wash {
    position: fixed;
    left: -20%;
    right: -20%;
    bottom: -15%;
    height: 58%;
    z-index: 1;
    pointer-events: none;
    border-radius: 50% 50% 0 0;
    background: radial-gradient(
      ellipse 90% 90% at 50% 100%,
      hsla(var(--hue), 80%, 62%, 0.18) 0%,
      hsla(var(--hue), 60%, 45%, 0.12) 35%,
      hsla(calc(var(--hue) - 25), 50%, 35%, 0.06) 65%,
      transparent 85%
    );
    filter: blur(108px);
  }

  /* Lower-depth veil: keeps the aurora soft and distant below the actions. */
  .lower-haze {
    position: fixed;
    left: -4%;
    right: -4%;
    bottom: -4%;
    height: 56%;
    z-index: 1;
    pointer-events: none;
    background: linear-gradient(180deg, transparent 0%, rgba(2, 5, 13, 0.06) 24%, rgba(5, 8, 22, 0.24) 100%);
    -webkit-backdrop-filter: blur(26px) saturate(118%);
    backdrop-filter: blur(26px) saturate(118%);
    -webkit-mask-image: linear-gradient(180deg, transparent 0%, #000 34%, #000 100%);
    mask-image: linear-gradient(180deg, transparent 0%, #000 34%, #000 100%);
  }

  /* Final black falloff: it sits above atmospheric colour, below the interface. */
  .bottom-fade {
    position: fixed;
    inset: 0;
    z-index: 1;
    pointer-events: none;
    background: linear-gradient(180deg,
      transparent 0%,
      transparent 46%,
      rgba(0, 0, 0, 0.10) 61%,
      rgba(0, 0, 0, 0.48) 82%,
      rgba(0, 0, 0, 0.92) 100%);
  }

  /* Animated film grain — canvas overlay */
  #grain {
    position: fixed;
    inset: 0;
    z-index: 3;
    pointer-events: none;
    width: 100vw;
    height: 100vh;
    opacity: 0.058;
    mix-blend-mode: soft-light;
    animation: grain-flicker 180ms steps(2, end) infinite;
  }

  @keyframes grain-flicker {
    0%, 100% { opacity: 0.065; }
    50% { opacity: 0.088; }
  }

  /* Floating light orbs at bottom — animated soft spots */
  .light-orbs {
    position: fixed;
    inset: 0;
    z-index: 1;
    pointer-events: none;
    overflow: hidden;
  }

  .light-orb {
    position: absolute;
    border-radius: 50%;
    filter: blur(80px);
    will-change: transform, opacity;
  }

  .light-orb:nth-child(1) {
    width: 380px;
    height: 380px;
    bottom: -6%;
    left: 10%;
    background: hsla(var(--hue), 55%, 52%, 0.22);
    animation: orb-drift-1 7s ease-in-out infinite;
  }

  .light-orb:nth-child(2) {
    width: 320px;
    height: 320px;
    bottom: -4%;
    right: 5%;
    background: hsla(calc(var(--hue) + 30), 50%, 54%, 0.17);
    animation: orb-drift-2 9s ease-in-out infinite;
  }

  .light-orb:nth-child(3) {
    width: 460px;
    height: 460px;
    bottom: -10%;
    left: 30%;
    background: hsla(calc(var(--hue) - 20), 45%, 58%, 0.15);
    animation: orb-drift-3 11s ease-in-out infinite;
  }

  .light-orb:nth-child(4) {
    width: 240px;
    height: 240px;
    bottom: 4%;
    left: 60%;
    background: hsla(var(--hue), 55%, 62%, 0.12);
    animation: orb-drift-4 8s ease-in-out infinite;
  }

  .light-orb:nth-child(5) {
    width: 340px;
    height: 340px;
    bottom: -5%;
    left: -5%;
    background: hsla(calc(var(--hue) + 60), 45%, 52%, 0.14);
    animation: orb-drift-5 10s ease-in-out infinite;
  }

  @keyframes orb-drift-1 {
    0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.14; }
    33% { transform: translate(30px, -20px) scale(1.15); opacity: 0.18; }
    66% { transform: translate(-15px, -35px) scale(0.9); opacity: 0.11; }
  }

  @keyframes orb-drift-2 {
    0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.10; }
    40% { transform: translate(-25px, -30px) scale(1.2); opacity: 0.15; }
    70% { transform: translate(20px, -15px) scale(0.85); opacity: 0.08; }
  }

  @keyframes orb-drift-3 {
    0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.08; }
    30% { transform: translate(20px, -40px) scale(1.1); opacity: 0.13; }
    60% { transform: translate(-30px, -20px) scale(1.2); opacity: 0.10; }
  }

  @keyframes orb-drift-4 {
    0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.07; }
    50% { transform: translate(-20px, -25px) scale(1.3); opacity: 0.12; }
  }

  @keyframes orb-drift-5 {
    0%, 100% { transform: translate(0, 0) scale(1); opacity: 0.09; }
    35% { transform: translate(35px, -30px) scale(1.15); opacity: 0.14; }
    65% { transform: translate(10px, -45px) scale(0.95); opacity: 0.07; }
  }

  /* Central content — symmetrical, balanced vertically */
  main {
    transition: filter 300ms ease, opacity 300ms ease;
  }
  main.locked {
    filter: blur(24px);
    opacity: 0.15;
    pointer-events: none;
  }

  /* PIN GATE OVERLAY */
  .pin-gate-overlay {
    position: fixed;
    inset: 0;
    z-index: 99;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
    background: rgba(4, 6, 11, 0.84);
    backdrop-filter: blur(28px);
    transition: opacity 300ms var(--ease-out), visibility 300ms var(--ease-out);
  }
  .pin-gate-overlay.unlocked {
    opacity: 0;
    pointer-events: none;
    visibility: hidden;
  }
  .pin-gate-card {
    width: min(400px, 100%);
    padding: 32px 24px;
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 8px;
    background: rgba(18, 28, 44, 0.82);
    backdrop-filter: blur(16px);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.8), inset 0 1px rgba(255, 255, 255, 0.15);
    text-align: center;
    position: relative;
  }
  .pin-gate-kicker {
    font-family: var(--font-mono);
    font-size: 0.58rem;
    letter-spacing: 0.32em;
    text-transform: uppercase;
    color: var(--ink-dim);
    margin-bottom: 8px;
  }
  .pin-gate-title {
    font-family: var(--font-display);
    font-size: 2.4rem;
    letter-spacing: 0.05em;
    color: #ffffff;
    line-height: 1.1;
    margin-bottom: 6px;
    background: linear-gradient(180deg, #ffffff 0%, hsla(var(--hue), 60%, 88%, 0.9) 100%);
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.12em;
  }
  .pin-gate-desc {
    font-family: var(--font-ui);
    font-size: 0.84rem;
    color: var(--ink-mid);
    line-height: 1.45;
    margin-bottom: 20px;
  }
  .pin-input-wrap {
    position: relative;
    margin-bottom: 12px;
  }
  .pin-input {
    width: 100%;
    padding: 12px 14px;
    font-family: var(--font-mono);
    font-size: 16px !important;
    touch-action: manipulation;
    -webkit-appearance: none;
    letter-spacing: 0.15em;
    text-align: center;
    color: #ffffff;
    background: rgba(24, 38, 58, 0.65);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    outline: none;
    transition: border-color 0.2s var(--ease-out);
  }
  .pin-input:focus {
    border-color: var(--accent);
    box-shadow: 0 0 12px var(--accent-glow);
  }
  .pin-submit {
    width: 100%;
    padding: 12px;
    font-family: var(--font-ui);
    font-size: 0.76rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #ffffff;
    background: rgba(22, 45, 72, 0.85);
    border: 1px solid hsla(var(--hue), 75%, 55%, 0.5);
    border-radius: 4px;
    cursor: pointer;
    box-shadow: 0 0 18px hsla(var(--hue), 70%, 50%, 0.2);
    transition: all 0.2s var(--ease-out);
  }
  .pin-submit:hover {
    background: rgba(28, 56, 90, 0.95);
    border-color: var(--accent);
    box-shadow: 0 0 24px var(--accent-glow);
  }
  .pin-error {
    font-family: var(--font-ui);
    color: #f87171;
    font-size: 0.78rem;
    margin-bottom: 10px;
    font-weight: 500;
  }
  .pin-gate-help {
    font-family: var(--font-ui);
    margin-top: 18px;
    font-size: 0.72rem;
    color: var(--ink-dim);
  }
  .pin-gate-help a {
    color: var(--accent);
    text-decoration: none;
    border-bottom: 1px dashed var(--accent);
  }

  main {
    position: relative;
    z-index: 2;
    width: 100%;
    max-width: 460px;
    margin: 0 auto;
    display: grid;
    grid-template-columns: minmax(0, 460px);
    grid-template-rows: 62svh auto 1fr;
    justify-content: center;
    align-content: start;
    text-align: center;
    padding: 0 16px 32px;
    min-height: 100vh;
    min-height: 100svh;
    justify-content: center;
    overflow: visible;
  }

  /* Tiny kicker label */
  .kicker {
    font-family: var(--font-mono);
    font-size: 0.58rem;
    letter-spacing: 0.32em;
    text-transform: uppercase;
    color: rgba(193, 218, 242, 0.62);
    margin-bottom: 12px;
    text-shadow: 0 0 12px hsla(var(--hue), 70%, 62%, 0.28);
  }

  /* Keeps even long names geometrically centred when they exceed the column. */
  .identity {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    align-self: center;
    text-align: center;
  }

  .control-stack {
    width: 100%;
    align-self: start;
  }

  /* MONUMENTAL name — the hero element */
  .name-wrap {
    margin-bottom: 0;
    cursor: default;
    user-select: none;
    width: max-content;
    max-width: none;
    overflow: visible;
  }

  .name {
    font-family: var(--font-display);
    font-size: clamp(4.5rem, 12vw, 7rem);
    font-weight: 400;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    line-height: 0.88;
    background: linear-gradient(180deg,
      #ffffff 0%,
      rgba(255, 255, 255, 0.95) 50%,
      hsla(var(--hue), 60%, 88%, 0.8) 75%,
      hsla(var(--hue), 50%, 70%, 0.4) 100%);
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
    filter:
      drop-shadow(0 0 12px rgba(255, 255, 255, 0.20))
      drop-shadow(0 0 30px hsla(var(--hue), 70%, 65%, 0.42))
      drop-shadow(0 0 60px hsla(var(--hue), 60%, 55%, 0.20))
      drop-shadow(0 8px 24px rgba(0, 0, 0, 0.4));
    white-space: nowrap;
    word-break: normal;
  }

  /* Compact action buttons — thin, editorial, lightened */
  .actions-row {
    display: flex;
    gap: 6px;
    width: 100%;
    margin-bottom: 12px;
  }

  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 10px 8px;
    font-family: var(--font-ui);
    font-size: 0.69rem;
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    text-decoration: none;
    color: var(--ink-high);
    background: linear-gradient(135deg,
      hsla(var(--hue), 70%, 52%, 0.22) 0%,
      rgba(22, 40, 66, 0.76) 58%,
      rgba(13, 23, 40, 0.86) 100%);
    border: 1px solid hsla(var(--hue), 65%, 62%, 0.34);
    border-radius: 4px;
    cursor: pointer;
    backdrop-filter: blur(8px);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.16),
      0 0 18px hsla(var(--hue), 78%, 54%, 0.13),
      0 8px 22px rgba(0, 0, 0, 0.18);
    transition: all 0.25s var(--ease-out);
    white-space: nowrap;
  }

  #downloadBtn { flex: 1; min-width: 0; }
  #openSubBtn { flex: 1; min-width: 0; }

  .btn:hover {
    color: var(--ink-pure);
    background: linear-gradient(135deg,
      hsla(var(--hue), 75%, 58%, 0.34) 0%,
      rgba(34, 58, 92, 0.84) 100%);
    border-color: hsla(var(--hue), 78%, 68%, 0.65);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.25),
      0 0 28px hsla(var(--hue), 82%, 58%, 0.32),
      0 10px 26px rgba(0, 0, 0, 0.24);
    transform: translateY(-1px);
  }

  .btn:active {
    transform: translateY(0);
  }

  .btn.primary {
    color: #ffffff;
    background: linear-gradient(135deg,
      hsla(var(--hue), 82%, 55%, 0.42) 0%,
      hsla(calc(var(--hue) + 18), 66%, 40%, 0.42) 48%,
      rgba(20, 37, 76, 0.88) 100%);
    border-color: hsla(var(--hue), 82%, 64%, 0.66);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.25),
      0 0 24px hsla(var(--hue), 82%, 56%, 0.34),
      0 10px 26px rgba(0, 0, 0, 0.22);
  }

  .btn.primary:hover {
    background: rgba(28, 56, 90, 0.8);
    border-color: var(--accent);
    box-shadow: 0 0 24px var(--accent-glow);
  }

  .btn svg {
    width: 13px;
    height: 13px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linecap: round;
    stroke-linejoin: round;
    flex-shrink: 0;
    opacity: 0.7;
  }

  .badge-tag {
    font-family: var(--font-mono);
    font-size: 0.55rem;
    padding: 0px 4px;
    border-radius: 2px;
    background: rgba(255, 255, 255, 0.06);
    color: var(--ink-dim);
    margin-left: 1px;
    letter-spacing: 0.05em;
  }

  /* Config line — minimal, lightened */
  .config-panel {
    width: 100%;
    padding: 9px 12px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 14px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 4px;
    background: rgba(24, 38, 58, 0.48);
    backdrop-filter: blur(8px);
    transition: border-color 0.25s var(--ease-out);
  }

  .config-panel:hover {
    border-color: rgba(255, 255, 255, 0.26);
  }

  .config-code {
    flex: 1;
    min-width: 0;
    font-family: var(--font-mono);
    font-size: 0.68rem;
    letter-spacing: 0.01em;
    color: hsla(var(--hue), 65%, 68%, 0.95);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    text-align: left;
    user-select: all;
  }

  .btn-copy {
    flex-shrink: 0;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    padding: 6px 11px;
    font-family: var(--font-ui);
    font-size: 0.66rem;
    font-weight: 500;
    letter-spacing: 0.04em;
    color: var(--ink-high);
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 3px;
    cursor: pointer;
    transition: all 0.2s var(--ease-out);
  }

  .btn-copy:hover {
    color: #ffffff;
    background: rgba(255, 255, 255, 0.15);
    border-color: rgba(255, 255, 255, 0.3);
  }

  .btn-copy.done {
    color: var(--accent);
    border-color: hsla(var(--hue), 60%, 50%, 0.3);
  }

  /* Password Bar directly under subscription link */
  .pwd-panel {
    width: 100%;
    padding: 7px 12px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 14px;
    border: 1px solid rgba(255, 255, 255, 0.14);
    border-radius: 4px;
    background: rgba(24, 38, 58, 0.48);
    backdrop-filter: blur(8px);
    transition: border-color 0.25s var(--ease-out);
  }
  .pwd-panel:hover {
    border-color: rgba(255, 255, 255, 0.26);
  }
  .pwd-left {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .pwd-tag {
    font-family: var(--font-ui);
    font-size: 0.64rem;
    font-weight: 500;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--ink-mid);
    white-space: nowrap;
  }
  .pwd-code {
    font-family: var(--font-mono);
    font-size: 0.76rem;
    font-weight: 600;
    letter-spacing: 0.14em;
    color: #ffffff;
    background: rgba(255, 255, 255, 0.07);
    padding: 2px 7px;
    border-radius: 3px;
    border: 1px solid rgba(255, 255, 255, 0.12);
  }
  .pwd-eye-btn {
    background: none;
    border: none;
    color: var(--ink-dim);
    cursor: pointer;
    padding: 3px 5px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 3px;
    transition: color 0.2s ease;
  }
  .pwd-eye-btn:hover {
    color: var(--ink-pure);
  }
  .pwd-edit-btn {
    flex-shrink: 0;
  }

  /* Guide Modal & Sections */
  .guide-card {
    position: relative;
    width: min(560px, 94vw);
    max-height: 86vh;
    overflow-y: auto;
    padding: 28px 22px;
    background: rgba(16, 26, 42, 0.94);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 8px;
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.85);
    text-align: left;
    scrollbar-width: thin;
    scrollbar-color: rgba(255, 255, 255, 0.25) transparent;
  }
  .guide-card::-webkit-scrollbar {
    width: 6px;
  }
  .guide-card::-webkit-scrollbar-thumb {
    background: rgba(255, 255, 255, 0.25);
    border-radius: 3px;
  }
  .guide-card h2 {
    font-family: var(--font-ui);
    font-size: 1.35rem;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: #ffffff;
    margin-bottom: 4px;
  }
  .guide-card .guide-sub {
    font-family: var(--font-ui);
    font-size: 0.78rem;
    color: var(--ink-mid);
    margin-bottom: 20px;
    line-height: 1.4;
  }
  .guide-section {
    margin-bottom: 18px;
    padding-bottom: 16px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  }
  .guide-section:last-child {
    margin-bottom: 0;
    padding-bottom: 0;
    border-bottom: none;
  }
  .guide-sec-title {
    display: flex;
    align-items: center;
    gap: 8px;
    font-family: var(--font-ui);
    font-size: 0.88rem;
    font-weight: 600;
    color: #ffffff;
    margin-bottom: 8px;
  }
  .guide-sec-title svg {
    width: 15px;
    height: 15px;
    stroke: var(--accent);
    fill: none;
    stroke-width: 2;
    flex-shrink: 0;
  }
  .guide-text {
    font-family: var(--font-ui);
    font-size: 0.78rem;
    line-height: 1.55;
    color: var(--ink-high);
  }
  .guide-text p {
    margin-bottom: 8px;
  }
  .guide-text p:last-child {
    margin-bottom: 0;
  }
  .guide-text strong {
    color: #ffffff;
  }
  .guide-steps {
    list-style: none;
    padding: 0;
    margin: 8px 0;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .guide-step {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    font-size: 0.78rem;
    line-height: 1.45;
  }
  .step-num {
    flex-shrink: 0;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: hsla(var(--hue), 60%, 50%, 0.2);
    border: 1px solid hsla(var(--hue), 60%, 55%, 0.4);
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.66rem;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    margin-top: 1px;
  }
  .guide-servers-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 8px;
    margin-top: 8px;
  }
  @media (max-width: 480px) {
    .guide-servers-grid { grid-template-columns: 1fr; }
  }
  .server-item {
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 5px;
    padding: 8px 10px;
  }
  .server-item-header {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 0.76rem;
    font-weight: 600;
    color: #ffffff;
    margin-bottom: 3px;
  }
  .server-item-desc {
    font-size: 0.68rem;
    color: var(--ink-dim);
    line-height: 1.35;
  }
  .guide-img-slot {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    padding: 22px 16px;
    margin: 10px 0 12px;
    border: 1px dashed rgba(255, 255, 255, 0.20);
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.02);
    color: var(--ink-dim);
    font-size: 0.72rem;
    letter-spacing: 0.02em;
    text-align: center;
    transition: all 0.2s ease;
  }
  .guide-img-slot svg {
    opacity: 0.45;
  }
  .guide-img-slot:hover {
    border-color: var(--accent);
    background: hsla(var(--hue), 70%, 50%, 0.04);
    color: var(--ink-mid);
  }

  /* Support links — lightened */
  .support-row {
    display: flex;
    gap: 6px;
    width: 100%;
    margin-bottom: 24px;
  }

  .support-link {
    flex: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    padding: 9px 12px;
    background: linear-gradient(135deg,
      hsla(var(--hue), 52%, 44%, 0.16),
      rgba(17, 29, 47, 0.78));
    border: 1px solid hsla(var(--hue), 52%, 60%, 0.25);
    border-radius: 4px;
    text-decoration: none;
    cursor: pointer;
    font-family: inherit;
    font-size: 0.67rem;
    font-weight: 500;
    letter-spacing: 0.06em;
    color: var(--ink-high);
    transition: all 0.25s var(--ease-out);
    backdrop-filter: blur(6px);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.10), 0 0 14px hsla(var(--hue), 72%, 52%, 0.08);
  }

  .support-link svg {
    width: 12px;
    height: 12px;
    fill: none;
    stroke: currentColor;
    stroke-width: 1.6;
    opacity: 0.6;
  }

  
  .support-link.guide:hover {
    color: var(--accent);
    border-color: hsla(var(--hue), 70%, 55%, 0.45);
    box-shadow: 0 0 16px var(--accent-glow);
  }
  .support-link.tg:hover {
    color: #29a7ed;
    border-color: rgba(41, 167, 237, 0.3);
  }

  .support-link.max:hover {
    color: var(--accent);
    border-color: hsla(var(--hue), 60%, 50%, 0.3);
  }

  /* Footer */
  footer {
    font-family: var(--font-mono);
    font-size: 0.62rem;
    letter-spacing: 0.12em;
    color: var(--ink-dim);
    opacity: 0.7;
    transition: opacity 0.2s ease;
  }
  footer a {
    color: inherit;
    text-decoration: none;
    border-bottom: 1px dashed rgba(255, 255, 255, 0.18);
    padding-bottom: 1px;
    transition: all 0.2s var(--ease-out);
  }
  footer a:hover {
    color: var(--accent);
    border-color: var(--accent);
    opacity: 1;
  }

  /* Wide screens use the same two-zone hierarchy as mobile. */
  @media (min-width: 681px) {
    .vignette {
      background:
        /* Empty lateral fields deliberately recede into black. */
        linear-gradient(90deg,
          rgba(0, 0, 0, 0.44) 0%,
          rgba(0, 0, 0, 0.20) 13%,
          transparent 33%,
          transparent 67%,
          rgba(0, 0, 0, 0.20) 87%,
          rgba(0, 0, 0, 0.44) 100%),
        radial-gradient(ellipse 54% 78% at 50% 42%, transparent 42%, rgba(0, 0, 0, 0.14) 100%),
        linear-gradient(180deg,
          rgba(2, 4, 8, 0.12) 0%,
          transparent 22%,
          rgba(1, 3, 8, 0.22) 56%,
          rgba(0, 0, 0, 0.84) 100%);
    }
  }

  /* On panoramic screens the empty sides become a quiet, dim frame. */
  @media (min-aspect-ratio: 2/1) {
    .vignette {
      box-shadow:
        inset 250px 0 190px -120px rgba(0, 0, 0, 0.60),
        inset -250px 0 190px -120px rgba(0, 0, 0, 0.60);
    }
    .vignette::after {
      content: "";
      position: absolute;
      inset: 0;
      background:
        radial-gradient(ellipse 40% 62% at -8% 78%, hsla(var(--hue), 70%, 48%, 0.14), transparent 72%),
        radial-gradient(ellipse 40% 62% at 108% 78%, hsla(calc(var(--hue) + 24), 68%, 46%, 0.12), transparent 72%);
      filter: blur(24px);
      opacity: 0.8;
    }
  }


  /* MODAL DIALOGS */
  .modal[hidden] { display: none !important; }
  .modal {
    position: fixed;
    inset: 0;
    z-index: 95;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
    background: rgba(3, 5, 10, 0.78);
    backdrop-filter: blur(20px);
  }
  .modal-card {
    position: relative;
    width: min(420px, 100%);
    padding: 28px 22px;
    background: rgba(18, 28, 44, 0.90);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 6px;
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.85);
    text-align: left;
  }
  .modal-card h2 {
    font-family: var(--font-ui);
    font-size: 1.35rem;
    font-weight: 700;
    letter-spacing: -0.02em;
    color: #ffffff;
    margin-bottom: 6px;
  }
  .modal-card p {
    font-family: var(--font-ui);
    font-size: 0.80rem;
    color: var(--ink-mid);
    margin-bottom: 16px;
    line-height: 1.45;
  }
  .modal-card p {
    font-size: 0.82rem;
    color: var(--ink-mid);
    margin-bottom: 16px;
    line-height: 1.4;
  }
  .modal-close {
    position: absolute;
    top: 14px;
    right: 14px;
    background: transparent;
    border: none;
    color: var(--ink-dim);
    font-size: 1.4rem;
    cursor: pointer;
    line-height: 1;
  }
  .modal-close:hover { color: #ffffff; }

  /* Platform Selector List in Download Modal */
  .platform-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 6px;
  }
  .platform-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    background: rgba(255, 255, 255, 0.035);
    border: 1px solid rgba(255, 255, 255, 0.09);
    border-radius: 4px;
    text-decoration: none;
    color: inherit;
    transition: all 0.2s var(--ease-out);
    user-select: none;
  }
  .platform-item:hover {
    background: rgba(255, 255, 255, 0.08);
    border-color: var(--accent);
    box-shadow: 0 4px 18px var(--accent-glow);
    transform: translateY(-1px);
  }
  .platform-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.06);
    color: var(--accent);
    flex-shrink: 0;
  }
  .platform-info {
    flex: 1;
    min-width: 0;
  }
  .platform-name {
    font-size: 0.88rem;
    font-weight: 600;
    color: #ffffff;
    letter-spacing: 0.02em;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .platform-desc {
    font-size: 0.70rem;
    color: var(--ink-dim);
    margin-top: 1px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .platform-badge {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--accent);
    background: var(--accent-subtle);
    border: 1px solid rgba(255, 255, 255, 0.12);
    padding: 4px 8px;
    border-radius: 3px;
    flex-shrink: 0;
    letter-spacing: 0.04em;
  }
  .platform-item:hover .platform-badge {
    background: var(--accent);
    color: #04060b;
    border-color: var(--accent);
  }

  /* Password Form */
  .pin-input {
    width: 100%;
    padding: 10px 12px;
    font-family: var(--font-mono);
    font-size: 0.95rem;
    color: #ffffff;
    background: rgba(24, 38, 58, 0.65);
    border: 1px solid rgba(255, 255, 255, 0.18);
    border-radius: 4px;
    outline: none;
    transition: border-color 0.2s var(--ease-out);
  }
  .pin-input:focus {
    border-color: var(--accent);
    box-shadow: 0 0 12px var(--accent-glow);
  }
  .pin-submit {
    width: 100%;
    padding: 11px;
    font-family: var(--font-ui);
    font-size: 0.74rem;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: #ffffff;
    background: linear-gradient(135deg, hsla(var(--hue), 76%, 54%, 0.4), rgba(25, 50, 86, 0.86));
    border: 1px solid hsla(var(--hue), 75%, 55%, 0.5);
    border-radius: 4px;
    cursor: pointer;
    box-shadow: 0 0 18px hsla(var(--hue), 70%, 50%, 0.2);
    transition: all 0.2s var(--ease-out);
  }
  .pin-submit:hover {
    background: rgba(28, 56, 90, 0.95);
    border-color: var(--accent);
    box-shadow: 0 0 24px var(--accent-glow);
  }
  .pin-error {
    color: #f87171;
    font-size: 0.78rem;
    margin-bottom: 10px;
    font-weight: 500;
  }

  /* Toast Notification */
  .toast {
    position: fixed;
    bottom: 24px;
    left: 50%;
    transform: translate(-50%, 100px);
    opacity: 0;
    z-index: 100;
    padding: 10px 20px;
    background: rgba(18, 32, 50, 0.95);
    border: 1px solid var(--accent);
    border-radius: 4px;
    color: #ffffff;
    font-family: var(--font-ui);
    font-size: 0.76rem;
    font-weight: 500;
    letter-spacing: 0.04em;
    box-shadow: 0 8px 28px rgba(0, 0, 0, 0.6), 0 0 16px var(--accent-glow);
    pointer-events: none;
    transition: transform 0.25s var(--ease-out), opacity 0.25s var(--ease-out);
  }
  .toast.show {
    transform: translate(-50%, 0);
    opacity: 1;
  }

  /* Aurora Shader Tuner Modal & Trigger */
  footer {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    margin-top: 4px;
  }
  .tuner-trigger-btn {
    background: none;
    border: none;
    color: var(--ink-dim);
    font-family: inherit;
    font-size: 0.65rem;
    cursor: pointer;
    padding: 2px 4px;
    border-radius: 3px;
    opacity: 0.7;
    transition: all 0.2s ease;
  }
  .tuner-trigger-btn:hover {
    opacity: 1;
    color: var(--accent);
    text-shadow: 0 0 8px var(--accent-glow);
  }
  .tuner-modal {
    position: fixed;
    inset: 0;
    z-index: 9999;
    display: flex;
    align-items: flex-end;
    justify-content: flex-end;
    padding: 20px;
    pointer-events: none;
  }
  .tuner-modal[hidden] {
    display: none !important;
  }
  .tuner-card {
    pointer-events: auto;
    width: min(340px, 92vw);
    max-height: 80vh;
    overflow-y: auto;
    background: rgba(10, 16, 26, 0.92);
    backdrop-filter: blur(16px);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 8px;
    padding: 16px;
    box-shadow: 0 20px 50px rgba(0, 0, 0, 0.8), 0 0 20px rgba(0, 240, 255, 0.1);
    color: #e2e8f0;
    font-family: var(--font-ui);
    font-size: 0.75rem;
    scrollbar-width: thin;
  }
  .tuner-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 12px;
    padding-bottom: 8px;
    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
  }
  .tuner-title {
    font-weight: 700;
    font-size: 0.85rem;
    letter-spacing: 0.04em;
    color: #ffffff;
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .tuner-close-btn {
    background: none;
    border: none;
    color: var(--ink-dim);
    font-size: 1.2rem;
    cursor: pointer;
    padding: 0 4px;
    line-height: 1;
  }
  .tuner-close-btn:hover { color: #fff; }
  .tuner-row {
    margin-bottom: 10px;
  }
  .tuner-label-val {
    display: flex;
    justify-content: space-between;
    margin-bottom: 3px;
    font-size: 0.70rem;
    color: #94a3b8;
  }
  .tuner-slider {
    width: 100%;
    accent-color: #38bdf8;
    cursor: pointer;
    height: 4px;
  }
  .tuner-actions {
    display: flex;
    gap: 6px;
    margin-top: 14px;
  }
  .tuner-btn {
    flex: 1;
    padding: 6px 8px;
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 4px;
    color: #ffffff;
    font-size: 0.68rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .tuner-btn:hover {
    background: rgba(255, 255, 255, 0.16);
    border-color: #38bdf8;
  }
  .tuner-btn.copy {
    background: linear-gradient(135deg, rgba(56, 189, 248, 0.2), rgba(14, 165, 233, 0.4));
    border-color: rgba(56, 189, 248, 0.5);
  }

</style>
</head>
<body>

<!-- WebGL Aurora Borealis GPU Canvas -->
<canvas id="aurora" width="890" height="716"></canvas>
<div class="vignette"></div>
<div class="atmo-bottom"></div>
<div class="atmo-wash"></div>
<div class="lower-haze"></div>
<div class="bottom-fade"></div>

<!-- Floating light orbs at bottom -->
<div class="light-orbs">
  <div class="light-orb"></div>
  <div class="light-orb"></div>
  <div class="light-orb"></div>
  <div class="light-orb"></div>
  <div class="light-orb"></div>
</div>

<!-- Animated grain canvas -->
<div class="grain"></div>

<!-- PIN GATE OVERLAY -->
<div class="pin-gate-overlay" id="pinGateOverlay">
  <div class="pin-gate-card">
    <div class="pin-gate-kicker">Personal Access Gateway</div>
    <h2 class="pin-gate-title">__USERNAME__</h2>
    <p class="pin-gate-desc">Введите ваш персональный PIN или пароль для доступа к подписке:</p>
    <form id="pinGateForm">
      <div class="pin-input-wrap">
        <input type="password" id="pinGateInput" class="pin-input" placeholder="Пароль / PIN" autocomplete="current-password" inputmode="text" autocorrect="off" autocapitalize="off" spellcheck="false" required>
      </div>
      <div id="pinErrorBox" class="pin-error" style="display:none;">Неверный пароль. Попробуйте еще раз.</div>
      <button type="submit" class="pin-submit">Войти ↗</button>
    </form>
    <div class="pin-gate-help">
      Забыли пароль? Напишите <a href="https://t.me/your_support" target="_blank" rel="noopener">Давиду в Telegram</a> — он пришлёт ссылку для входа в 1 клик.
    </div>
  </div>
</div>

<!-- Main Centered Presentation -->
<main id="personalPage" class="locked" data-username="__USERNAME__" data-happ-android-url="__HAPP_ANDROID_URL__" data-telegram-url="https://t.me/your_support" data-max-url="https://max.ru/your_support">

  <div class="identity">
    <!-- Kicker -->
    <div class="kicker">Personal Gateway</div>

    <!-- MONUMENTAL USER NAME -->
    <div class="name-wrap" id="nameWrap">
      <h1 class="name" id="userName">__USERNAME__</h1>
    </div>
  </div>

  <div class="control-stack">
    <!-- Actions: Download Happ & Open Subscription -->
    <div class="actions-row">
      <button class="btn" id="downloadBtn" type="button">
        <svg viewBox="0 0 24 24">
          <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
          <polyline points="7 10 12 15 17 10"></polyline>
          <line x1="12" y1="15" x2="12" y2="3"></line>
        </svg>
        <span>Скачать Happ</span>
        <span class="badge-tag">OS ▾</span>
      </button>

      <a class="btn primary" id="openSubBtn" href="#" onclick="if(this.getAttribute('href')==='#'){showToast('Введите пароль для активации');return false;}">
        <svg viewBox="0 0 24 24">
          <polygon points="5 3 19 12 5 21 5 3"></polygon>
        </svg>
        <span>Открыть в Happ</span>
      </a>
    </div>

    <!-- Config Box with Copy -->
    <div class="config-panel">
      <div class="config-code" id="configText" style="letter-spacing:0.18em;opacity:0.6;">••••••••••••••••••••••••••••••••••••••••••••</div>
      <button class="btn-copy" id="copyBtn" type="button">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
          <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
        </svg>
        <span>Скопировать</span>
      </button>
    </div>

    <!-- Password Row directly below subscription link -->
    <div class="pwd-panel">
      <div class="pwd-left">
        <span class="pwd-tag">Пароль / PIN:</span>
        <span class="pwd-code" id="pwdDisplay">••••</span>
        <button class="pwd-eye-btn" id="pwdEyeBtn" type="button" aria-label="Скрыть/показать пароль" title="Скрыть/показать пароль">
          <svg id="eyeIconSvg" viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path>
            <circle cx="12" cy="12" r="3"></circle>
          </svg>
        </button>
      </div>
      <button class="btn-copy pwd-edit-btn" id="openPwdBtn" type="button">
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"></path>
          <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"></path>
        </svg>
        <span>Изменить</span>
      </button>
    </div>

    <!-- Support & Guide -->
    <div class="support-row">
      <button class="support-link guide" id="openGuideBtn" type="button">
        <svg viewBox="0 0 24 24">
          <path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"></path>
          <path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"></path>
        </svg>
        <span>Инструкция</span>
      </button>

      <a class="support-link tg" id="tgBtn" href="https://t.me/your_support" target="_blank" rel="noopener">
        <svg viewBox="0 0 24 24">
          <path d="M21.5 2L2 10.5L9.5 14L12 21.5L15.5 16.5L20 20L22 2.5L21.5 2Z"></path>
          <path d="M9.5 14L20 4.5"></path>
        </svg>
        <span>Telegram</span>
      </a>

      <a class="support-link max" id="maxBtn" href="https://max.ru/your_support" target="_blank" rel="noopener">
        <svg viewBox="0 0 24 24">
          <rect x="3" y="4" width="18" height="16" rx="4"></rect>
          <path d="M7 15V9l5 4 5-4v6"></path>
        </svg>
        <span>MAX</span>
      </a>
    </div>

    <footer>
      <a href="https://t.me/your_support" target="_blank" rel="noopener">@your_support</a>
      <button type="button" class="tuner-trigger-btn" id="openTunerBtn" title="Настройка северного сияния">✦</button>
    </footer>
  </div>

</main>

<!-- DOWNLOAD HAPP CLIENT MODAL -->
<div class="modal" id="downloadModal" hidden>
  <div class="modal-card">
    <button class="modal-close" id="closeDownloadBtn" aria-label="Закрыть">×</button>
    <h2>Скачать Happ</h2>
    <p>Прямые официальные ссылки на клиенты HAPP:</p>
    
    <div class="platform-list">
      <!-- Android -->
      <a class="platform-item" id="dlAndroid" href="__HAPP_ANDROID_URL__" target="_blank" rel="noopener" download>
        <div class="platform-icon">
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="5" y="10" width="14" height="11" rx="2"></rect>
            <path d="M8 10V6a4 4 0 0 1 8 0v4"></path>
            <line x1="9" y1="14" x2="9.01" y2="14"></line>
            <line x1="15" y1="14" x2="15.01" y2="14"></line>
          </svg>
        </div>
        <div class="platform-info">
          <div class="platform-name">Android</div>
          <div class="platform-desc">Прямой .apk файл последней версии (GitHub)</div>
        </div>
        <span class="platform-badge">.APK ▾</span>
      </a>

      <!-- iOS -->
      <a class="platform-item" id="dlIos" href="https://apps.apple.com/ru/app/happ-proxy-utility-plus/id6746188973" target="_blank" rel="noopener">
        <div class="platform-icon">
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M12 20.94c1.88-2.6 3.1-4.72 3.1-6.94a3.1 3.1 0 0 0-6.2 0c0 2.22 1.22 4.34 3.1 6.94z"></path>
            <path d="M12 2a5 5 0 0 0-5 5v3a5 5 0 0 0 10 0V7a5 5 0 0 0-5-5z"></path>
          </svg>
        </div>
        <div class="platform-info">
          <div class="platform-name">iPhone / iPad</div>
          <div class="platform-desc">Happ Proxy Utility Plus в App Store</div>
        </div>
        <span class="platform-badge">App Store ↗</span>
      </a>

      <!-- Windows -->
      <a class="platform-item" id="dlWindows" href="https://github.com/Happ-proxy/happ-desktop/releases/latest/download/setup-Happ.x64.exe" target="_blank" rel="noopener">
        <div class="platform-icon">
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="3" width="8" height="8"></rect>
            <rect x="13" y="3" width="8" height="8"></rect>
            <rect x="3" y="13" width="8" height="8"></rect>
            <rect x="13" y="13" width="8" height="8"></rect>
          </svg>
        </div>
        <div class="platform-info">
          <div class="platform-name">Windows</div>
          <div class="platform-desc">Официальный установщик (.exe)</div>
        </div>
        <span class="platform-badge">.EXE ▾</span>
      </a>
    </div>
  </div>
</div>


<!-- GUIDE / INSTRUCTIONS MODAL -->
<div class="modal" id="guideModal" hidden>
  <div class="guide-card">
    <button class="modal-close" id="closeGuideBtn" aria-label="Закрыть">×</button>
    <h2>Инструкция к подключению</h2>
    <div class="guide-sub">Полное руководство: о проекте, подключение, пароль, сервера и советы</div>

    <!-- 1. О проекте -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>
        <span>О проекте</span>
      </div>
      <div class="guide-text">
        <p><strong>Davida Core</strong> — это персональный, быстрый и защищенный сервис доступа без ограничений, логирования и рекламы. Он построен на базе современных протоколов <strong>Xray VLESS Reality</strong> и <strong>AmneziaWG</strong>, которые полностью маскируют трафик под обычный TLS/HTTPS веб-серфинг и не блокируются провайдерами.</p>
        <p>В подписку встроена <strong>умная маршрутизация</strong>: российские ресурсы (банки, Госуслуги, маркетплейсы, сервисы доставки) открываются напрямую на максимальной скорости вашего провайдера, а все международные ресурсы — через защищенный туннель.</p>
      </div>
    </div>

    <!-- 2. Скачивание и клиенты -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path><polyline points="7 10 12 15 17 10"></polyline><line x1="12" y1="15" x2="12" y2="3"></line></svg>
        <span>Скачивание клиентов</span>
      </div>
      <div class="guide-text">
        <p>Основное рекомендуемое приложение — <strong>HAPP</strong>. Оно идеально поддерживает нашу единую подписку, автоматическое разделение сайтов и моментальное переключение между серверами.</p>
        <ul class="guide-steps">
          <li class="guide-step">
            <span class="step-num">•</span>
            <span><strong>Android:</strong> прямой .apk файл последней версии (кнопка «Скачать Happ» на главной).</span>
          </li>
          <li class="guide-step">
            <span class="step-num">•</span>
            <span><strong>iPhone / iPad:</strong> приложение Happ Proxy Utility Plus в официальном App Store.</span>
          </li>
          <li class="guide-step">
            <span class="step-num">•</span>
            <span><strong>Windows / macOS:</strong> официальный установщик клиента для десктопа.</span>
          </li>
        </ul>
        <!-- Слот для скриншота: Выбор клиента -->
        <div class="guide-img-slot">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="18" height="18" rx="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>
          <span>[Место для скриншота: Установка приложения HAPP]</span>
        </div>
      </div>
    </div>

    <!-- 3. Подключение -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg>
        <span>Подключение за 1 клик</span>
      </div>
      <div class="guide-text">
        <ol class="guide-steps">
          <li class="guide-step">
            <span class="step-num">1</span>
            <span>Установите и откройте клиент <strong>HAPP</strong> на вашем устройстве.</span>
          </li>
          <li class="guide-step">
            <span class="step-num">2</span>
            <span>На этой странице нажмите яркую фиолетовую кнопку <strong>«Открыть в Happ»</strong>.</span>
          </li>
          <li class="guide-step">
            <span class="step-num">3</span>
            <span>Приложение откроется и предложит импортировать профиль — подтвердите добавление.</span>
          </li>
          <li class="guide-step">
            <span class="step-num">4</span>
            <span>Включите тумблер соединения. Готово!</span>
          </li>
        </ol>
        <p style="margin-top:8px;font-size:0.72rem;color:var(--ink-mid);"><em>Если ссылка не открылась автоматически: нажмите «Скопировать» на этой странице, затем в HAPP нажмите кнопку «+» в правом верхнем углу и выберите «Добавить из буфера» или по URL.</em></p>
        <!-- Слот для скриншота: Подключение в HAPP -->
        <div class="guide-img-slot">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="3" width="18" height="18" rx="2"></rect><circle cx="8.5" cy="8.5" r="1.5"></circle><polyline points="21 15 16 10 5 21"></polyline></svg>
          <span>[Место для скриншота: Добавление подписки и подключение]</span>
        </div>
      </div>
    </div>

    <!-- 4. Пароль / PIN -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>
        <span>Пароль / PIN-код</span>
      </div>
      <div class="guide-text">
        <p>Ваш персональный пароль отображается в плашке прямо под ссылкой на подписку. Иконка глаза позволяет скрыть или показать его.</p>
        <p>Этот PIN защищает ваши личные настройки. Вы можете сменить его в любой момент: нажмите кнопку <strong>«Изменить»</strong> рядом с паролем, введите текущий PIN и задайте новый (от 4 символов). Новый пароль сохранится в системе мгновенно.</p>
      </div>
    </div>

    <!-- 5. Сервера -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10"></circle><line x1="2" y1="12" x2="22" y2="12"></line><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path></svg>
        <span>Сервера и география</span>
      </div>
      <div class="guide-text">
        <p>В вашу единую подписку автоматически включены 3 независимых скоростных узла в Европе с распределением нагрузки:</p>
        <div class="guide-servers-grid">
          <div class="server-item">
            <div class="server-item-header">🇨🇭 Швейцария (Geneva)</div>
            <div class="server-item-desc">ЦОД Infomaniak Tier III+, максимальная конфиденциальность и скорость.</div>
          </div>
          <div class="server-item">
            <div class="server-item-header">🇪🇪 Эстония (Tallinn)</div>
            <div class="server-item-desc">Infonet DC / TLL-IX, минимальный пинг и стабильный канал.</div>
          </div>
          <div class="server-item">
            <div class="server-item-header">🇩🇪 Германия (Frankfurt)</div>
            <div class="server-item-desc">Крупнейший узел DE-CIX, идеален для стриминга, игр и высокой скорости.</div>
          </div>
        </div>
      </div>
    </div>

    <!-- 6. Советы и решение проблем -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3zM7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"></path></svg>
        <span>Советы и решение проблем</span>
      </div>
      <div class="guide-text">
        <ul class="guide-steps">
          <li class="guide-step">
            <span class="step-num">•</span>
            <span><strong>Если медленно работает:</strong> просто выберите другой сервер в списке HAPP (например, переключитесь со Швейцарии на Эстонию или Германию).</span>
          </li>
          <li class="guide-step">
            <span class="step-num">•</span>
            <span><strong>Автообновление:</strong> HAPP сам обновляет список серверов и свежие ключи раз в 24 часа. Чтобы обновить вручную — потяните список профилей вниз.</span>
          </li>
          <li class="guide-step">
            <span class="step-num">•</span>
            <span><strong>Безопасность:</strong> ваша ссылка на подписку является персональной. Не публикуйте её в открытых чатах.</span>
          </li>
        </ul>
      </div>
    </div>

    <!-- 7. Связь и помощь -->
    <div class="guide-section">
      <div class="guide-sec-title">
        <svg viewBox="0 0 24 24"><path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"></path></svg>
        <span>Связь и поддержка</span>
      </div>
      <div class="guide-text">
        <p>Если у вас возникли сложности с настройкой или недоступен нужный ресурс — напишите автору напрямую:</p>
        <p style="margin-top:6px;">
          ✈ <strong>Telegram:</strong> <a href="https://t.me/your_support" target="_blank" rel="noopener" style="color:var(--accent);text-decoration:none;border-bottom:1px dashed var(--accent);">@your_support</a><br>
          ✉ <strong>MAX:</strong> кнопка внизу главной страницы.
        </p>
      </div>
    </div>

  </div>
</div>

<!-- PASSWORD CHANGE MODAL -->
<div class="modal" id="pwdModal" hidden>
  <div class="modal-card">
    <button class="modal-close" id="closePwdBtn" aria-label="Закрыть">×</button>
    <h2>Смена пароля</h2>
    <p>Укажите текущий и новый персональный пароль / PIN:</p>
    <form id="changePwdForm">
      <div style="margin-bottom:10px;">
        <input type="password" id="curPwdInput" class="pin-input" placeholder="Текущий пароль" autocomplete="current-password" inputmode="text" autocorrect="off" autocapitalize="off" spellcheck="false" required>
      </div>
      <div style="margin-bottom:10px;">
        <input type="password" id="newPwdInput" class="pin-input" placeholder="Новый пароль (от 4 знаков)" minlength="4" autocomplete="new-password" inputmode="text" autocorrect="off" autocapitalize="off" spellcheck="false" required>
      </div>
      <div id="changePwdError" class="pin-error" style="display:none;"></div>
      <button type="submit" class="pin-submit" style="margin-top:6px;">Сохранить пароль ↗</button>
    </form>
  </div>
</div>

<!-- Toast notification -->
<div class="toast" id="toast"><span id="toastMsg">Готово</span></div>

<!-- AURORA SHADER TUNER MODAL -->
<div class="tuner-modal" id="tunerModal" hidden>
  <div class="tuner-card">
    <div class="tuner-header">
      <div class="tuner-title">✦ Aurora Engine Live Tuner</div>
      <button type="button" class="tuner-close-btn" id="closeTunerBtn">×</button>
    </div>

    <!-- Mode Selector: Both, Classic Only, Soft Only -->
    <div class="tuner-row">
      <div class="tuner-label-val"><span>Режим слоев:</span><span id="valMode">Оба слоя</span></div>
      <select id="tuneMode" style="width:100%;background:rgba(255,255,255,0.08);color:#fff;border:1px solid rgba(255,255,255,0.2);border-radius:4px;padding:4px;font-size:0.7rem;outline:none;">
        <option value="both">Оба (Мягкий фон + Четкий занавес)</option>
        <option value="classic">Только старый (Четкий занавес)</option>
        <option value="soft">Только новый (Мягкий растянутый)</option>
      </select>
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Резкость кромки (Edge Sharpness):</span><span id="valEdge">0.012</span></div>
      <input type="range" class="tuner-slider" id="tuneEdge" min="0.003" max="0.060" step="0.001" value="0.012">
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Октавы / Шум границы (Octaves):</span><span id="valOctaves">2 октавы (Мягко)</span></div>
      <input type="range" class="tuner-slider" id="tuneOctaves" min="1" max="4" step="1" value="2">
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Зубчатость / Пюре (Tooth Amp):</span><span id="valHarmonic">0.10</span></div>
      <input type="range" class="tuner-slider" id="tuneHarmonic" min="0.0" max="0.60" step="0.02" value="0.10">
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Яркость фона (Soft Background):</span><span id="valSoftBg">0.50</span></div>
      <input type="range" class="tuner-slider" id="tuneSoftBg" min="0.0" max="1.0" step="0.05" value="0.50">
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Яркость занавеса (Curtain Glow):</span><span id="valCurtain">0.85</span></div>
      <input type="range" class="tuner-slider" id="tuneCurtain" min="0.0" max="1.5" step="0.05" value="0.85">
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Яркость звезд (Stars Intensity):</span><span id="valStars">0.70</span></div>
      <input type="range" class="tuner-slider" id="tuneStars" min="0.0" max="1.2" step="0.05" value="0.70">
    </div>

    <div class="tuner-row">
      <div class="tuner-label-val"><span>Скорость движения (Speed):</span><span id="valSpeed">1.0x</span></div>
      <input type="range" class="tuner-slider" id="tuneSpeed" min="0.2" max="2.5" step="0.1" value="1.0">
    </div>

    <div class="tuner-actions">
      <button type="button" class="tuner-btn" id="resetTunerBtn">Сброс</button>
      <button type="button" class="tuner-btn copy" id="copyTunerBtn">Скопировать конфиг</button>
    </div>
  </div>
</div>


<script>
/* ======================================================
   НАСТРОЙКИ ПОДПИСКИ
   ====================================================== */
const CONFIG = {
  userName:  document.getElementById("personalPage").dataset.username,
  subscriptionUrl: "",
  happApkUrl: document.getElementById("personalPage").dataset.happAndroidUrl,
  telegramUrl: document.getElementById("personalPage").dataset.telegramUrl,
  maxUrl: document.getElementById("personalPage").dataset.maxUrl,
};

// Populate page: Heart ONLY for Nadzo, clean uppercase name for everyone else
const rawName = (CONFIG.userName || "").trim();
const isNadzo = rawName.toLowerCase() === "nadzo";
const displayName = isNadzo ? (rawName.toUpperCase() + " ❤️") : rawName.toUpperCase();
const userNameEl = document.getElementById("userName");
userNameEl.textContent = displayName;
document.title = displayName + " // Персональный доступ";
const tokenEl = document.getElementById("userToken");
if (tokenEl) tokenEl.textContent = CONFIG.userToken;
document.getElementById("configText").textContent = CONFIG.subscriptionUrl;

document.getElementById("downloadBtn").href = CONFIG.happApkUrl;
document.getElementById("openSubBtn").href = "happ://add/" + CONFIG.subscriptionUrl;
document.getElementById("tgBtn").href  = CONFIG.telegramUrl;
document.getElementById("maxBtn").href = CONFIG.maxUrl;

// Keep the mobile name monumental without wrapping long personal names.
function fitDisplayName() {
  if (!window.matchMedia("(max-width: 520px)").matches) {
    userNameEl.style.fontSize = "";
    return;
  }
  userNameEl.style.fontSize = "";
  const maxWidth = Math.max(220, window.innerWidth - 28);
  const measured = userNameEl.getBoundingClientRect().width;
  if (measured > maxWidth) {
    const size = parseFloat(getComputedStyle(userNameEl).fontSize);
    userNameEl.style.fontSize = `${Math.max(26, size * maxWidth / measured)}px`;
  }
}
requestAnimationFrame(fitDisplayName);
window.addEventListener("resize", fitDisplayName, { passive: true });
if (document.fonts && document.fonts.ready) document.fonts.ready.then(fitDisplayName);

// Copy config
const copyBtn = document.getElementById("copyBtn");
copyBtn.addEventListener("click", async () => {
  const currentText = (configText ? configText.textContent.trim() : "");
  if (!currentText || currentText.includes("••••")) {
    showToast("Введите пароль для доступа к ссылке");
    const pinIn = document.getElementById("pinGateInput");
    if (pinIn) pinIn.focus();
    return;
  }
  const text = CONFIG.subscriptionUrl;
  let ok = false;
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(text);
      ok = true;
    } else { throw new Error(); }
  } catch (_) {
    const ta = document.createElement("textarea");
    ta.value = text;
    ta.style.cssText = "position:fixed;opacity:0";
    document.body.appendChild(ta);
    ta.select();
    try { ok = document.execCommand("copy"); } catch (_) {}
    ta.remove();
  }

  const lbl = copyBtn.querySelector("span");
  if (lbl) lbl.textContent = ok ? "Готово ✓" : "Ошибка";
  copyBtn.classList.add("done");
  setTimeout(() => {
    if (lbl) lbl.textContent = "Скопировать";
    copyBtn.classList.remove("done");
  }, 2000);
});

/* ======================================================
   Северное сияние — WebGL GPU Шейдер
   С перспективным искажением (lens distortion)
   ====================================================== */
const canvas = document.getElementById("aurora");
const gl = canvas.getContext("webgl", { antialias: false, alpha: true, powerPreference: "high-performance" });

if (gl) {
  initWebGL(gl);
} else {
  canvas.remove();
}

function initWebGL(gl) {
  const VERT = `
    attribute vec2 aPos;
    void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
  `;

  const FRAG = `
    precision mediump float;
    uniform vec2  uRes;
    uniform float uTime;
    uniform float uHue;
    uniform vec2  uMouse;

    // Interactive Tuner Uniforms
    uniform float uEdge;      // edge sharpness window (default 0.012)
    uniform float uOctaves;   // 1.0 = smooth 2-octave, 2.0 = original 4-octave
    uniform float uHarmonic;  // high frequency secondary noise (0.0 to 0.4)
    uniform float uSoftBg;    // soft background brightness (0.0 to 1.0)
    uniform float uCurtain;   // crisp curtain brightness (0.0 to 1.5)
    uniform float uStars;     // starfield brightness (0.0 to 1.2)

    float hash21(vec2 p) {
      p = fract(p * vec2(233.34, 851.73));
      p += dot(p, p + 23.45);
      return fract(p.x * p.y);
    }

    float vnoise(vec2 p) {
      vec2 i = floor(p), f = fract(p);
      vec2 u = f * f * (3.0 - 2.0 * f);
      return mix(mix(hash21(i),               hash21(i + vec2(1.0, 0.0)), u.x),
                 mix(hash21(i + vec2(0.0,1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
    }

    // Standard 4-octave FBM for rocky terrain ridges
    float fbm(vec2 p) {
      float v = 0.0, a = 0.5;
      mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
      for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = m * p; a *= 0.5; }
      return v;
    }

    // Smooth 2-octave FBM for gentle wave contours
    float fbmCurtain(vec2 p) {
      float v = 0.0, a = 0.72;
      mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
      for (int i = 0; i < 2; i++) {
        v += a * vnoise(p);
        p = m * p;
        a *= 0.28;
      }
      return v;
    }

    // Dynamic FBM that blends between smooth (2 octaves) and textured (4 octaves)
    float fbmDynamic(vec2 p) {
      float vSmooth = fbmCurtain(p);
      float vDetail = fbm(p);
      return mix(vSmooth, vDetail, clamp(uOctaves - 1.0, 0.0, 1.0));
    }

    vec3 hueShift(vec3 c, float a) {
      const vec3 k = vec3(0.57735);
      float ca = cos(a), sa = sin(a);
      return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
    }

    /* Tunable aurora curtain layer with altitude coloring and magnetic rays */
    vec3 auroraLayer(vec2 uv, float base, float amp, float thick,
                     float speed, float seed, float parallax) {
      float x = uv.x + parallax;
      float t = uTime * speed;

      // Primary wave driven by dynamic octaves + adjustable high-frequency harmonic tooth
      float h = base
        + (fbmDynamic(vec2(x * 1.7 + t, seed)) - 0.5) * amp
        + (fbm(vec2(x * 4.5 - t * 0.7, seed * 2.7)) - 0.5) * amp * uHarmonic;

      float d    = uv.y - h;
      float up   = max(d, 0.0);
      // Interactive edge sharpness
      float mask = smoothstep(-uEdge, uEdge * 0.85, d);
      float fade = exp(-up * thick);

      // Vertical magnetic field lines move independently of the slower curtain drift.
      float rays = fbm(vec2(x * 11.0 + t * 0.55, up * 1.2 - t * 0.85 + seed * 3.0));
      rays = pow(max(rays - 0.13, 0.0) * 1.24, 2.0) * 1.06 + 0.19;

      float shimmer = 0.82 + 0.22 * vnoise(vec2(x * 8.0 + uTime * 0.72, seed * 5.3));
      float inten = min(mask * fade * rays * shimmer, 0.74);

      // Natural altitude coloring: emerald -> cyan -> violet
      float a    = clamp(up * 3.0, 0.0, 1.0);
      vec3 low   = vec3(0.055, 0.80, 0.43);
      vec3 mid   = vec3(0.06, 0.66, 0.76);
      vec3 high  = vec3(0.43, 0.25, 0.76);
      vec3 col   = mix(low, mid, smoothstep(0.0, 0.45, a));
      col        = mix(col, high, smoothstep(0.35, 1.0, a));

      return hueShift(col, uHue) * inten * uCurtain;
    }

    /* Soft diffused aurora stretched across the background */
    vec3 auroraSoftBackground(vec2 uv, float base, float amp, float thick,
                              float speed, float seed, float parallax) {
      float x = uv.x + parallax;
      float t = uTime * speed;

      float h = base
        + (fbm(vec2(x * 1.2 + t, seed)) - 0.5) * amp;

      float d    = uv.y - h;
      float up   = max(d, 0.0);
      float mask = smoothstep(-0.08, 0.06, d);
      float fade = exp(-up * thick);

      float rays = fbm(vec2(x * 7.0 + t * 0.35, up * 0.8 - t * 0.5 + seed * 2.0));
      rays = pow(max(rays - 0.10, 0.0) * 1.15, 1.6) * 0.9 + 0.2;

      float shimmer = 0.85 + 0.15 * vnoise(vec2(x * 4.0 + uTime * 0.4, seed * 3.0));
      float inten = min(mask * fade * rays * shimmer, 0.55);

      float a    = clamp(up * 2.2, 0.0, 1.0);
      vec3 low   = vec3(0.055, 0.75, 0.43);
      vec3 mid   = vec3(0.06, 0.60, 0.76);
      vec3 high  = vec3(0.43, 0.22, 0.76);
      vec3 col   = mix(low, mid, smoothstep(0.0, 0.5, a));
      col        = mix(col, high, smoothstep(0.4, 1.0, a));

      return hueShift(col, uHue) * inten * uSoftBg;
    }

    void main() {
      vec2 frag = gl_FragCoord.xy / uRes;
      float aspect = uRes.x / uRes.y;

      // ===== LENS DISTORTION / PERSPECTIVE =====
      vec2 centered = frag - 0.5;
      float r2 = dot(centered, centered);
      float distK1 = 0.18;
      float distK2 = 0.06;
      float distortion = 1.0 + distK1 * r2 + distK2 * r2 * r2;
      vec2 distorted = centered * distortion + 0.5;

      float perspTilt = 0.08;
      distorted.x = 0.5 + (distorted.x - 0.5) * (1.0 + perspTilt * (distorted.y - 0.3));

      vec2 uv = vec2(distorted.x * aspect, distorted.y);
      float t = uTime;

      // Deep polar sky gradient
      vec3 col = mix(vec3(0.012, 0.020, 0.038), vec3(0.002, 0.004, 0.009),
                     smoothstep(0.0, 0.85, distorted.y));

      // Twinkling star field across entire background
      {
        vec2 sp   = distorted * vec2(aspect, 1.0);
        vec2 cell = floor(sp * 95.0);
        vec2 f2   = fract(sp * 95.0);
        float h   = hash21(cell);
        vec2 spos = vec2(hash21(cell + 1.3), hash21(cell + 2.7)) * 0.8 + 0.1;
        float ds  = length(f2 - spos);
        float br  = smoothstep(0.07, 0.0, ds) * step(0.93, h);
        float tw  = 0.5 + 0.5 * sin(t * (0.3 + h * 1.4) + h * 40.0);
        col += vec3(0.75, 0.85, 1.0) * br * (0.25 + 0.75 * tw) * uStars;
      }

      float px = uMouse.x * 0.02;
      vec3 aur = vec3(0.0);

      // 1. Soft stretched background layer (растянуто по фону)
      aur += auroraSoftBackground(uv, 0.38, 0.18, 2.5, 0.018, 7.0, px * 0.4) * 0.55;
      aur += auroraSoftBackground(uv, 0.52, 0.22, 3.2, 0.028, 21.0, px * 0.8) * 0.50;

      // 2. Старый оригинальный эффект без модификаций (поверх)
      aur += auroraLayer(uv, 0.72, 0.20, 4.0, 0.026, 13.7, px * 0.55) * 0.82;
      aur += auroraLayer(uv, 0.60, 0.15, 5.5, 0.040,  0.0, px * 1.00) * 0.92;
      aur += auroraLayer(uv, 0.50, 0.11, 7.0, 0.058, 31.4, px * 1.60) * 0.56;
      col += aur;

      // Distant mountain ridge in haze
      float ridge2 = 0.20 + fbm(vec2(distorted.x * aspect * 2.2, 7.7)) * 0.10;
      float m2 = smoothstep(ridge2 + 0.004, ridge2 - 0.004, distorted.y);
      vec3 haze2 = mix(vec3(0.020, 0.030, 0.050), col, 0.35) + aur * 0.10;
      col = mix(col, haze2, m2 * 0.85);

      // Near mountain ridge silhouette
      float ridge1 = 0.05 + fbm(vec2(distorted.x * aspect * 2.6, 3.3)) * 0.13;
      float m1 = smoothstep(ridge1 + 0.004, ridge1 - 0.004, distorted.y);
      col = mix(col, vec3(0.008, 0.012, 0.020), m1);

      // Rim lighting on ridges from aurora
      float rimZone = smoothstep(ridge1 + 0.020, ridge1 + 0.002, distorted.y) * (1.0 - m1);
      col += hueShift(vec3(0.08, 0.55, 0.35), uHue) * rimZone * (0.20 + aur.g * 0.9);
      float rimZone2 = smoothstep(ridge2 + 0.016, ridge2 + 0.002, distorted.y) * (1.0 - m2) * (1.0 - m1);
      col += hueShift(vec3(0.06, 0.40, 0.30), uHue) * rimZone2 * 0.14;

      // Subtle soft glow at very bottom — atmospheric ground light
      float groundGlow = smoothstep(0.18, 0.0, distorted.y);
      col += hueShift(vec3(0.02, 0.08, 0.05), uHue) * groundGlow * 0.35;

      // Compress highlights before the browser's display conversion so bright
      // overlapping curtains keep their colour instead of clipping to neon.
      col = vec3(1.0) - exp(-max(col, 0.0) * 1.12);
      col = pow(col, vec3(0.94));
      gl_FragColor = vec4(col, 1.0);
    }
  `;

  function compile(type, src) {
    const s = gl.createShader(type);
    gl.shaderSource(s, src);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      console.error(gl.getShaderInfoLog(s));
      return null;
    }
    return s;
  }

  const vs = compile(gl.VERTEX_SHADER, VERT);
  const fs = compile(gl.FRAGMENT_SHADER, FRAG);
  if (!vs || !fs) { canvas.remove(); return; }

  const prog = gl.createProgram();
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  gl.useProgram(prog);

  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW);
  const aPos = gl.getAttribLocation(prog, "aPos");
  gl.enableVertexAttribArray(aPos);
  gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

  const uRes      = gl.getUniformLocation(prog, "uRes");
  const uTime     = gl.getUniformLocation(prog, "uTime");
  const uHue      = gl.getUniformLocation(prog, "uHue");
  const uMouse    = gl.getUniformLocation(prog, "uMouse");
  const uEdgeLoc  = gl.getUniformLocation(prog, "uEdge");
  const uOctLoc   = gl.getUniformLocation(prog, "uOctaves");
  const uHarmLoc  = gl.getUniformLocation(prog, "uHarmonic");
  const uSoftLoc  = gl.getUniformLocation(prog, "uSoftBg");
  const uCurtLoc  = gl.getUniformLocation(prog, "uCurtain");
  const uStarLoc  = gl.getUniformLocation(prog, "uStars");

  // Global settings synced with tuner controls (saved to localStorage)
  const savedParams = JSON.parse(localStorage.getItem("aurora_params") || "{}");
  window.AURORA_PARAMS = {
    mode: savedParams.mode || "both",
    edge: savedParams.edge !== undefined ? savedParams.edge : 0.012,
    octaves: savedParams.octaves !== undefined ? savedParams.octaves : 2,
    harmonic: savedParams.harmonic !== undefined ? savedParams.harmonic : 0.10,
    softBg: savedParams.softBg !== undefined ? savedParams.softBg : 0.50,
    curtain: savedParams.curtain !== undefined ? savedParams.curtain : 0.85,
    stars: savedParams.stars !== undefined ? savedParams.stars : 0.70,
    speed: savedParams.speed !== undefined ? savedParams.speed : 1.0
  };

  const isMobile = window.innerWidth < 768 || /Android|iPhone|iPad|iPod/i.test(navigator.userAgent);
  const scale = isMobile ? 0.50 : Math.min(window.devicePixelRatio || 1, 1.0) * 0.75;

  function resize() {
    canvas.width  = Math.max(2, Math.round(window.innerWidth  * scale));
    canvas.height = Math.max(2, Math.round(window.innerHeight * scale));
    gl.viewport(0, 0, canvas.width, canvas.height);
  }
  window.addEventListener("resize", resize, { passive: true });
  resize();

  let isInputActive = false;
  document.addEventListener("focusin", (e) => {
    if (e.target && (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA")) {
      isInputActive = true;
    }
  }, { passive: true });
  document.addEventListener("focusout", () => {
    isInputActive = false;
  }, { passive: true });

  let mx = 0, my = 0, mxS = 0, myS = 0;
  window.addEventListener("pointermove", e => {
    if (!isInputActive) {
      mx = (e.clientX / window.innerWidth)  * 2 - 1;
      my = (e.clientY / window.innerHeight) * 2 - 1;
    }
  }, { passive: true });

  let last = performance.now(), t = 0;
  let lastCssUpdate = 0;
  let lastRenderTime = 0;

  function frame(now) {
    // When typing digits, throttle RAF to 30fps to guarantee 0 input lag
    if (isInputActive && (now - lastRenderTime < 33)) {
      requestAnimationFrame(frame);
      return;
    }
    lastRenderTime = now;

    const dt = Math.min(now - last, 100);
    last = now;
    const p = window.AURORA_PARAMS;
    t += dt * (p.speed || 1.0);

    mxS += (mx - mxS) * 0.03;
    myS += (my - myS) * 0.03;

    // Organic hue drift: computed for GPU shader
    const hueVal = 165 + 75 * Math.sin(t * 0.00036) + 55 * Math.sin(t * 0.000135 + 2);
    
    // Only update root CSS property occasionally and NEVER while typing
    if (!isInputActive && (now - lastCssUpdate > 3000)) {
      document.documentElement.style.setProperty("--hue", hueVal.toFixed(0));
      lastCssUpdate = now;
    }

    gl.uniform2f(uRes, canvas.width, canvas.height);
    gl.uniform1f(uTime, t * 0.0065);
    gl.uniform1f(uHue, (hueVal - 190) * Math.PI / 180 * 0.9);
    gl.uniform2f(uMouse, mxS, myS);

    // Dynamic Tuner Uniforms
    let effSoft = p.softBg;
    let effCurt = p.curtain;
    if (p.mode === "classic") { effSoft = 0.0; effCurt = p.curtain || 1.0; }
    else if (p.mode === "soft") { effCurt = 0.0; effSoft = p.softBg || 0.8; }

    gl.uniform1f(uEdgeLoc, p.edge);
    gl.uniform1f(uOctLoc, p.octaves);
    gl.uniform1f(uHarmLoc, p.harmonic);
    gl.uniform1f(uSoftLoc, effSoft);
    gl.uniform1f(uCurtLoc, effCurt);
    gl.uniform1f(uStarLoc, p.stars);

    gl.drawArrays(gl.TRIANGLES, 0, 3);
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

/* Film grain is handled via hardware-accelerated CSS */
</script>



<script>

// Toast notification helper
const toast = document.getElementById("toast");
function showToast(msg) {
  const tMsg = document.getElementById("toastMsg");
  if (tMsg) tMsg.textContent = msg;
  if (toast) {
    toast.classList.add("show");
    clearTimeout(window._toastTimeout);
    window._toastTimeout = setTimeout(() => toast.classList.remove("show"), 2200);
  }
}

// Download Platform Modal Handlers
const downloadModal = document.getElementById("downloadModal");
const downloadBtn = document.getElementById("downloadBtn");
const closeDownloadBtn = document.getElementById("closeDownloadBtn");

if (downloadBtn && downloadModal) {
  downloadBtn.onclick = () => { downloadModal.hidden = false; };
}
if (closeDownloadBtn && downloadModal) {
  closeDownloadBtn.onclick = () => { downloadModal.hidden = true; };
}
if (downloadModal) {
  downloadModal.onclick = (e) => {
    if (e.target === downloadModal) downloadModal.hidden = true;
  };
}

// Password Change Modal Handlers
const pwdModal = document.getElementById("pwdModal");
const openPwdBtn = document.getElementById("openPwdBtn");
const closePwdBtn = document.getElementById("closePwdBtn");
const changePwdForm = document.getElementById("changePwdForm");
const changePwdError = document.getElementById("changePwdError");

if (openPwdBtn && pwdModal) {
  openPwdBtn.onclick = () => {
    if (changePwdError) changePwdError.style.display = "none";
    if (changePwdForm) changePwdForm.reset();
    pwdModal.hidden = false;
    const curIn = document.getElementById("curPwdInput");
    if (curIn) setTimeout(() => curIn.focus(), 80);
  };
}
if (closePwdBtn && pwdModal) {
  closePwdBtn.onclick = () => { pwdModal.hidden = true; };
}
if (pwdModal) {
  pwdModal.onclick = (e) => {
    if (e.target === pwdModal) pwdModal.hidden = true;
  };
}

if (changePwdForm) {
  changePwdForm.onsubmit = async (e) => {
    e.preventDefault();
    if (changePwdError) changePwdError.style.display = "none";
    const curPin = document.getElementById("curPwdInput").value.trim();
    const newPin = document.getElementById("newPwdInput").value.trim();
    if (!curPin || !newPin) return;

    try {
      const res = await fetch("/api/user/change_pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: CONFIG.userName, current_pin: curPin, new_pin: newPin })
      });
      const json = await res.json();
      if (res.ok && json.success) {
        localStorage.setItem("vpnadmin_pin_" + CONFIG.userName, newPin);
        currentStoredPin = newPin;
        if (pwdDisplay && pwdRevealed) pwdDisplay.textContent = newPin;
        if (document.getElementById("personalPage")) document.getElementById("personalPage").dataset.pin = newPin;
        pwdModal.hidden = true;
        showToast("Пароль успешно изменен!");
      } else {
        changePwdError.textContent = json.error || json.message || "Ошибка смены пароля";
        changePwdError.style.display = "block";
      }
    } catch(err) {
      changePwdError.textContent = "Ошибка связи при смене пароля";
      changePwdError.style.display = "block";
    }
  };
}


// ======================================================
// PIN PROTECTION GATE LOGIC
// ======================================================
const overlay = document.getElementById("pinGateOverlay");
const shell = document.getElementById("personalPage");
const pinInput = document.getElementById("pinGateInput");
const pinForm = document.getElementById("pinGateForm");
const pinError = document.getElementById("pinErrorBox");

function unlock(data) {
  if (overlay) overlay.classList.add("unlocked");
  if (shell) shell.classList.remove("locked");
  if (data && data.subscription_url) {
    CONFIG.subscriptionUrl = data.subscription_url;
    const configEl = document.getElementById("configText");
    if (configEl) {
      configEl.textContent = data.subscription_url;
      configEl.style.letterSpacing = "0.01em";
      configEl.style.opacity = "1";
    }
    const openBtn = document.getElementById("openSubBtn");
    if (openBtn) {
      openBtn.href = data.happ_add_url || ("happ://add/" + data.subscription_url);
    }
  }
  if (data && data.pin) {
    currentStoredPin = data.pin;
    if (pwdDisplay && pwdRevealed) pwdDisplay.textContent = data.pin;
  }
  if (typeof fitDisplayName === "function") fitDisplayName();
}

const urlParams = new URLSearchParams(window.location.search);
const urlPin = urlParams.get("pin") || urlParams.get("pass");

async function verifyPin(pin) {
  try {
    const res = await fetch("/api/auth/user", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ username: CONFIG.userName, pin: pin })
    });
    if (res.ok) {
      const data = await res.json();
      if (data && data.success) {
        localStorage.setItem("vpnadmin_pin_" + CONFIG.userName, pin);
        if (urlPin) {
          const cleanUrl = window.location.pathname;
          window.history.replaceState({}, document.title, cleanUrl);
        }
        unlock(data);
        return true;
      }
    }
  } catch(e) {}
  return false;
}

(async () => {
  // 1. Check Magic Link in URL: ?pin=...
  if (urlPin) {
    const ok = await verifyPin(urlPin);
    if (ok) return;
  }

  // 2. Check cached valid PIN in localStorage
  const cachedPin = localStorage.getItem("vpnadmin_pin_" + CONFIG.userName);
  if (cachedPin) {
    const ok = await verifyPin(cachedPin);
    if (ok) return;
  }

  // 3. Still locked: ensure overlay is visible and focus input
  if (shell) shell.classList.add("locked");
  if (overlay) overlay.classList.remove("unlocked");
  setTimeout(() => { if (pinInput) pinInput.focus(); }, 120);

  if (pinForm) {
    pinForm.onsubmit = async (e) => {
      e.preventDefault();
      if (pinError) pinError.style.display = "none";
      const pin = pinInput.value.trim();
      if (!pin) return;

      const submitBtn = pinForm.querySelector(".pin-submit");
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = "Проверка...";
      }

      const ok = await verifyPin(pin);
      if (!ok) {
        if (pinError) pinError.style.display = "block";
        if (pinInput) {
          pinInput.focus();
          pinInput.select();
        }
      }

      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = "Войти ↗";
      }
    };
  }
})();

// Guide Modal Handlers
const guideModal = document.getElementById("guideModal");
const openGuideBtn = document.getElementById("openGuideBtn");
const closeGuideBtn = document.getElementById("closeGuideBtn");

if (openGuideBtn && guideModal) {
  openGuideBtn.onclick = () => { guideModal.hidden = false; };
}
if (closeGuideBtn && guideModal) {
  closeGuideBtn.onclick = () => { guideModal.hidden = true; };
}
if (guideModal) {
  guideModal.onclick = (e) => {
    if (e.target === guideModal) guideModal.hidden = true;
  };
}

// Password Reveal/Mask Toggle Handler
let pwdRevealed = true;
const pwdDisplay = document.getElementById("pwdDisplay");
const pwdEyeBtn = document.getElementById("pwdEyeBtn");
const eyeIconSvg = document.getElementById("eyeIconSvg");
let currentStoredPin = document.getElementById("personalPage")?.dataset?.pin || (pwdDisplay ? pwdDisplay.textContent.trim() : "••••");

if (pwdEyeBtn && pwdDisplay) {
  pwdEyeBtn.onclick = () => {
    pwdRevealed = !pwdRevealed;
    if (pwdRevealed) {
      pwdDisplay.textContent = currentStoredPin;
      if (eyeIconSvg) {
        eyeIconSvg.innerHTML = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle>';
      }
    } else {
      pwdDisplay.textContent = "••••";
      if (eyeIconSvg) {
        eyeIconSvg.innerHTML = '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"></path><line x1="1" y1="1" x2="23" y2="23"></line>';
      }
    }
  };
}

// Update password display after successful change
// Aurora Tuner Modal & Live Control Handlers
const openTunerBtn = document.getElementById("openTunerBtn");
const closeTunerBtn = document.getElementById("closeTunerBtn");
const tunerModal = document.getElementById("tunerModal");

const tuneMode = document.getElementById("tuneMode");
const tuneEdge = document.getElementById("tuneEdge");
const tuneOctaves = document.getElementById("tuneOctaves");
const tuneHarmonic = document.getElementById("tuneHarmonic");
const tuneSoftBg = document.getElementById("tuneSoftBg");
const tuneCurtain = document.getElementById("tuneCurtain");
const tuneStars = document.getElementById("tuneStars");
const tuneSpeed = document.getElementById("tuneSpeed");

const valMode = document.getElementById("valMode");
const valEdge = document.getElementById("valEdge");
const valOctaves = document.getElementById("valOctaves");
const valHarmonic = document.getElementById("valHarmonic");
const valSoftBg = document.getElementById("valSoftBg");
const valCurtain = document.getElementById("valCurtain");
const valStars = document.getElementById("valStars");
const valSpeed = document.getElementById("valSpeed");

function syncTunerUI() {
  if (!window.AURORA_PARAMS) return;
  const p = window.AURORA_PARAMS;
  if (tuneMode) tuneMode.value = p.mode;
  if (tuneEdge) tuneEdge.value = p.edge;
  if (tuneOctaves) tuneOctaves.value = p.octaves;
  if (tuneHarmonic) tuneHarmonic.value = p.harmonic;
  if (tuneSoftBg) tuneSoftBg.value = p.softBg;
  if (tuneCurtain) tuneCurtain.value = p.curtain;
  if (tuneStars) tuneStars.value = p.stars;
  if (tuneSpeed) tuneSpeed.value = p.speed;

  if (valMode) valMode.textContent = p.mode === "both" ? "Оба слоя" : (p.mode === "classic" ? "Только старый" : "Только новый");
  if (valEdge) valEdge.textContent = Number(p.edge).toFixed(3);
  if (valOctaves) valOctaves.textContent = p.octaves == 1 ? "1 (Гладкая)" : (p.octaves == 2 ? "2 (Мягкая)" : `${p.octaves} (Детальная)`);
  if (valHarmonic) valHarmonic.textContent = Number(p.harmonic).toFixed(2);
  if (valSoftBg) valSoftBg.textContent = Number(p.softBg).toFixed(2);
  if (valCurtain) valCurtain.textContent = Number(p.curtain).toFixed(2);
  if (valStars) valStars.textContent = Number(p.stars).toFixed(2);
  if (valSpeed) valSpeed.textContent = Number(p.speed).toFixed(1) + "x";
}

function saveTunerParams() {
  if (!window.AURORA_PARAMS) return;
  localStorage.setItem("aurora_params", JSON.stringify(window.AURORA_PARAMS));
}

if (openTunerBtn && tunerModal) {
  openTunerBtn.onclick = (e) => {
    e.preventDefault();
    tunerModal.hidden = !tunerModal.hidden;
    if (!tunerModal.hidden) syncTunerUI();
  };
}
if (closeTunerBtn && tunerModal) {
  closeTunerBtn.onclick = () => { tunerModal.hidden = true; };
}

// Live Input Listeners
if (tuneMode) tuneMode.onchange = () => {
  window.AURORA_PARAMS.mode = tuneMode.value;
  syncTunerUI();
  saveTunerParams();
};
if (tuneEdge) tuneEdge.oninput = () => {
  window.AURORA_PARAMS.edge = parseFloat(tuneEdge.value);
  syncTunerUI();
  saveTunerParams();
};
if (tuneOctaves) tuneOctaves.oninput = () => {
  window.AURORA_PARAMS.octaves = parseFloat(tuneOctaves.value);
  syncTunerUI();
  saveTunerParams();
};
if (tuneHarmonic) tuneHarmonic.oninput = () => {
  window.AURORA_PARAMS.harmonic = parseFloat(tuneHarmonic.value);
  syncTunerUI();
  saveTunerParams();
};
if (tuneSoftBg) tuneSoftBg.oninput = () => {
  window.AURORA_PARAMS.softBg = parseFloat(tuneSoftBg.value);
  syncTunerUI();
  saveTunerParams();
};
if (tuneCurtain) tuneCurtain.oninput = () => {
  window.AURORA_PARAMS.curtain = parseFloat(tuneCurtain.value);
  syncTunerUI();
  saveTunerParams();
};
if (tuneStars) tuneStars.oninput = () => {
  window.AURORA_PARAMS.stars = parseFloat(tuneStars.value);
  syncTunerUI();
  saveTunerParams();
};
if (tuneSpeed) tuneSpeed.oninput = () => {
  window.AURORA_PARAMS.speed = parseFloat(tuneSpeed.value);
  syncTunerUI();
  saveTunerParams();
};

const resetTunerBtn = document.getElementById("resetTunerBtn");
if (resetTunerBtn) {
  resetTunerBtn.onclick = () => {
    window.AURORA_PARAMS = {
      mode: "both",
      edge: 0.012,
      octaves: 2,
      harmonic: 0.10,
      softBg: 0.50,
      curtain: 0.85,
      stars: 0.70,
      speed: 1.0
    };
    syncTunerUI();
    saveTunerParams();
    showToast("Параметры сброшены");
  };
}

const copyTunerBtn = document.getElementById("copyTunerBtn");
if (copyTunerBtn) {
  copyTunerBtn.onclick = async () => {
    const jsonStr = JSON.stringify(window.AURORA_PARAMS, null, 2);
    try {
      if (navigator.clipboard) await navigator.clipboard.writeText(jsonStr);
      showToast("Конфиг скопирован ✓");
    } catch (_) {
      showToast("Конфиг: " + jsonStr);
    }
  };
}

// Initial sync
setTimeout(syncTunerUI, 100);

// Global ESC key to close any modal
document.addEventListener("keydown", e => {
  if (e.key === "Escape") {
    if (downloadModal) downloadModal.hidden = true;
    
    if (pwdModal) pwdModal.hidden = true;
    if (guideModal) guideModal.hidden = true;
    if (tunerModal) tunerModal.hidden = true;
  }
});

</script>
</body></html>

HTML_TEMPLATE
  : <<'LEGACY_TEMPLATE'
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>__TITLE__</title>
<meta name="robots" content="noindex,nofollow">
<style>
:root{
  --bg:#05030b;
  --text:#f5f3ff;
  --muted:#b7aeda;
  --a:#a78bfa;
  --b:#22d3ee;
  --c:#f0abfc;
  --danger:#fb7185;
}
*{box-sizing:border-box}
html{min-height:100%;margin:0}
body{
  min-height:100%;
  margin:0;
  font-family:Inter,ui-sans-serif,system-ui,-apple-system,Segoe UI,Arial,sans-serif;
  background:var(--bg);
  color:var(--text);
  overflow-x:hidden;
  overflow-y:auto;
  -webkit-text-size-adjust:80%;
}

/* Base gradient depth */
body:before{
  content:"";
  position:fixed;
  inset:0;
  background:
    radial-gradient(circle at 50% 44%,rgba(167,139,250,.22),transparent 31%),
    radial-gradient(circle at 20% 80%,rgba(34,211,238,.12),transparent 28%),
    radial-gradient(circle at 82% 20%,rgba(240,171,252,.13),transparent 30%),
    radial-gradient(circle at 50% 110%,rgba(56,189,248,.10),transparent 34%),
    linear-gradient(180deg,#05030b,#03020a 72%,#010106);
  pointer-events:none;
}

/* Light animated grain */
body:after{
  content:"";
  position:fixed;
  inset:-18%;
  z-index:9;
  pointer-events:none;
  opacity:.81;
  mix-blend-mode:soft-light;
  background-image:url("data:image/svg+xml,%3Csvg viewBox='0 0 240 240' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.92' numOctaves='5' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='240' height='240' filter='url(%23n)' opacity='.9'/%3E%3C/svg%3E");
  background-size:240px 240px;
  animation:grain .42s steps(6) infinite, grainBreath 6s ease-in-out infinite;
}
@keyframes grain{
  0%{transform:translate(0,0)}
  12%{transform:translate(-3%,2%)}
  24%{transform:translate(4%,-3%)}
  36%{transform:translate(-2%,-4%)}
  48%{transform:translate(3%,4%)}
  60%{transform:translate(-5%,1%)}
  72%{transform:translate(5%,-2%)}
  84%{transform:translate(-1%,5%)}
  100%{transform:translate(0,0)}
}
@keyframes grainBreath{
  0%,100%{opacity:.075}
  45%{opacity:.125}
  50%{opacity:.14}
  55%{opacity:.105}
}

/* Aurora glow */
.aurora{
  position:fixed;
  inset:-22%;
  background:
    conic-gradient(from 190deg at 38% 52%, transparent 0 30%, rgba(34,211,238,.16) 39%, rgba(167,139,250,.22) 50%, transparent 66% 100%),
    conic-gradient(from 20deg at 72% 46%, transparent 0 36%, rgba(240,171,252,.15) 45%, rgba(34,211,238,.11) 57%, transparent 70% 100%);
  filter:blur(62px) saturate(1.28);
  animation:aurora 24s ease-in-out infinite alternate;
  opacity:.72;
  pointer-events:none;
}
@keyframes aurora{
  0%{transform:translate3d(-2%,1%,0) rotate(-5deg) scale(1.04)}
  100%{transform:translate3d(3%,-2%,0) rotate(8deg) scale(1.16)}
}

/* Particle canvases: no dotted grid, only chaotic tiny stars + soft particles */
#stars,#particles{
  position:fixed;
  inset:0;
  width:100%;
  height:100%;
  pointer-events:none;
  contain:strict;
}
#stars{z-index:1;opacity:.86}
#particles{z-index:1;opacity:.68}

/* Light scan lines */
.lines{
  position:fixed;
  inset:0;
  z-index:0;
  opacity:.25;
  background:
    linear-gradient(115deg,transparent 0 35%,rgba(255,255,255,.055) 35.2%,transparent 35.6%),
    linear-gradient(65deg,transparent 0 45%,rgba(34,211,238,.055) 45.2%,transparent 45.6%),
    linear-gradient(25deg,transparent 0 58%,rgba(240,171,252,.05) 58.2%,transparent 58.6%);
  animation:scan 18s ease-in-out infinite alternate;
  pointer-events:none;
}
@keyframes scan{
  from{transform:translateX(-2%)}
  to{transform:translateX(2%)}
}

/* Startup pulse */
.pulse{
  position:fixed;
  inset:0;
  z-index:2;
  pointer-events:none;
}
.pulse:before,
.pulse:after{
  content:"";
  position:absolute;
  left:50%;
  top:50%;
  width:80px;
  height:80px;
  border-radius:50%;
  transform:translate(-50%,-50%) scale(.2);
  border:1px solid rgba(165,243,252,.0);
  box-shadow:0 0 0 rgba(34,211,238,0);
  opacity:0;
}
.pulse:before{animation:startupPulse 4.2s cubic-bezier(.12,.9,.22,1) .35s 1 both}
.pulse:after{animation:startupPulse 4.9s cubic-bezier(.12,.9,.22,1) .75s 1 both}
@keyframes startupPulse{
  0%{opacity:0;transform:translate(-50%,-50%) scale(.15);border-color:rgba(165,243,252,.0);box-shadow:0 0 0 rgba(34,211,238,0)}
  18%{opacity:.72;border-color:rgba(165,243,252,.62);box-shadow:0 0 68px rgba(34,211,238,.30)}
  42%{opacity:.38;border-color:rgba(167,139,250,.38);box-shadow:0 0 120px rgba(167,139,250,.22)}
  100%{opacity:0;transform:translate(-50%,-50%) scale(16);border-color:rgba(167,139,250,.0);box-shadow:0 0 160px rgba(167,139,250,0)}
}

/* Orbit rings */
.orbit{
  position:fixed;
  inset:0;
  z-index:1;
  display:grid;
  place-items:center;
  filter:drop-shadow(0 0 34px rgba(167,139,250,.25));
  pointer-events:none;
  animation:orbitWake 4.6s cubic-bezier(.16,1,.3,1) .15s 1 both;
}
@keyframes orbitWake{
  0%{opacity:0;transform:scale(.90);filter:blur(10px) drop-shadow(0 0 0 rgba(34,211,238,0))}
  48%{opacity:.88;transform:scale(1.035);filter:blur(1px) drop-shadow(0 0 58px rgba(34,211,238,.26))}
  100%{opacity:1;transform:scale(1);filter:blur(0) drop-shadow(0 0 34px rgba(167,139,250,.25))}
}
.ring{
  position:absolute;
  border:1px solid rgba(255,255,255,.10);
  border-radius:50%;
  width:min(82vw,780px);
  aspect-ratio:1/1;
  animation:spin 34s linear infinite;
}
.ring:before{
  content:"";
  position:absolute;
  inset:-1px;
  border-radius:50%;
  background:conic-gradient(from 0deg,transparent,rgba(34,211,238,.30),transparent 18%,transparent 62%,rgba(240,171,252,.18),transparent);
  mask:radial-gradient(farthest-side,transparent calc(100% - 2px),#000 calc(100% - 1px));
  -webkit-mask:radial-gradient(farthest-side,transparent calc(100% - 2px),#000 calc(100% - 1px));
}
.ring:nth-child(2){width:min(62vw,590px);animation-duration:24s;animation-direction:reverse;transform:rotate(18deg)}
.ring:nth-child(3){width:min(42vw,410px);animation-duration:18s;transform:rotate(-25deg)}
.dot{
  position:absolute;
  width:13px;
  height:13px;
  border-radius:50%;
  background:#fff;
  box-shadow:0 0 25px #a5f3fc,0 0 60px rgba(167,139,250,.90);
}
.ring .dot{left:50%;top:-7px}
@keyframes spin{to{transform:rotate(360deg)}}

/* Main layout: scrollable and smaller */
.wrap{
  position:relative;
  z-index:3;
  min-height:100dvh;
  display:flex;
  align-items:center;
  justify-content:center;
  padding:clamp(14px,3.2vw,24px);
}
.panel{
  width:min(560px,100%);
  text-align:center;
  border-radius:28px;
  padding:clamp(20px,3.8vw,30px);
  border:1px solid rgba(255,255,255,.14);
  background:
    linear-gradient(180deg,rgba(255,255,255,.09),rgba(255,255,255,.035)),
    rgba(12,8,26,.66);
  backdrop-filter:blur(12px);
  -webkit-backdrop-filter:blur(12px);
  box-shadow:0 42px 110px rgba(0,0,0,.62),inset 0 0 0 1px rgba(255,255,255,.05),0 0 78px rgba(167,139,250,.13);
  position:relative;
  overflow:hidden;
  animation:panelIn 1.4s cubic-bezier(.16,1,.3,1) 3.55s both;
}
@keyframes panelIn{
  0%{opacity:0;transform:translateY(18px) scale(.975)}
  55%{opacity:.72;transform:translateY(6px) scale(.992)}
  100%{opacity:1;transform:translateY(0) scale(1)}
}
.panel:before{
  content:"";
  position:absolute;
  inset:-1px;
  border-radius:inherit;
  padding:1px;
  background:linear-gradient(135deg,rgba(34,211,238,.48),rgba(167,139,250,.28),rgba(240,171,252,.32),rgba(34,211,238,.15));
  mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);
  mask-composite:exclude;
  -webkit-mask-composite:xor;
  opacity:.64;
  pointer-events:none;
}
.panel:after{
  content:"";
  position:absolute;
  width:230px;
  height:230px;
  left:50%;
  top:-145px;
  transform:translateX(-50%);
  background:radial-gradient(circle,rgba(34,211,238,.15),transparent 70%);
  pointer-events:none;
}
.kicker{
  display:inline-flex;
  align-items:center;
  gap:8px;
  padding:7px 11px;
  border-radius:999px;
  border:1px solid rgba(255,255,255,.13);
  background:rgba(255,255,255,.055);
  color:#d8fbff;
  font-size:11px;
  letter-spacing:.13em;
  text-transform:uppercase;
  font-weight:800;
}
h1{
  font-size:clamp(38px,7vw,72px);
  line-height:1.02;
  margin:12px 0 8px;
  letter-spacing:-.07em;
  overflow:visible;
}
h1 .username{
  display:block;
  padding:0 .03em .14em;
  background:linear-gradient(90deg,#fff,#a5f3fc,#f5d0fe);
  color:transparent;
  -webkit-background-clip:text;
  background-clip:text;
  overflow:visible;
}
h1 .brandline{
  display:block;
  margin-top:4px;
  font-size:clamp(16px,3vw,25px);
  line-height:1.12;
  letter-spacing:-.03em;
  font-weight:750;
  color:rgba(245,243,255,.72);
}
p{
  color:var(--muted);
  line-height:1.52;
  margin:0 auto;
  max-width:500px;
  font-size:14px;
}
.warning,.routing{
  max-width:510px;
  margin:10px auto 0;
  border-radius:14px;
  padding:10px 12px;
  line-height:1.42;
  font-size:12.5px;
}
.warning{
  border:1px solid rgba(251,113,133,.20);
  background:linear-gradient(90deg,rgba(251,113,133,.11),rgba(255,255,255,.035));
  color:#ffd5de;
}
.routing{
  border:1px solid rgba(34,211,238,.16);
  background:rgba(34,211,238,.055);
  color:#c9f7ff;
}

.app-block{
  margin:14px auto 0;
  max-width:520px;
  padding:12px;
  border-radius:20px;
  background:rgba(255,255,255,.045);
  border:1px solid rgba(255,255,255,.10);
  text-align:left;
}
.app-head{
  display:flex;
  justify-content:space-between;
  align-items:center;
  gap:10px;
  margin-bottom:10px;
}
.app-title{
  font-size:13px;
  font-weight:850;
  letter-spacing:.04em;
  text-transform:uppercase;
  color:#edf7ff;
}
.app-note{
  color:rgba(219,234,254,.55);
  font-size:11px;
}
.big-action,.copy-action,.download-btn{
  text-decoration:none;
  color:var(--text);
  border-radius:15px;
  border:1px solid rgba(255,255,255,.14);
  transition:transform .22s ease,border-color .22s ease,box-shadow .22s ease,background .22s ease;
}
.big-action{
  display:flex;
  justify-content:center;
  align-items:center;
  min-height:46px;
  padding:12px 14px;
  font-size:14px;
  font-weight:900;
  background:linear-gradient(135deg,rgba(167,139,250,.42),rgba(34,211,238,.20));
  box-shadow:0 0 46px rgba(167,139,250,.18);
}
.big-action:hover,.copy-action:hover,.download-btn:hover{
  transform:translateY(-2px);
  border-color:rgba(255,255,255,.30);
  box-shadow:0 14px 42px rgba(0,0,0,.24);
}
.downloads{
  display:grid;
  grid-template-columns:repeat(3,1fr);
  gap:8px;
  margin-top:8px;
}
.download-btn{
  display:flex;
  justify-content:center;
  align-items:center;
  min-height:38px;
  padding:9px 8px;
  font-size:12px;
  background:rgba(255,255,255,.055);
}
.copy-action{
  display:flex;
  justify-content:center;
  align-items:center;
  max-width:520px;
  min-height:42px;
  margin:12px auto 0;
  padding:10px 14px;
  font-size:13px;
  font-weight:800;
  background:rgba(255,255,255,.06);
}
.footer{
  margin-top:13px;
  color:rgba(219,234,254,.42);
  font-size:11.5px;
}
.toast{
  position:fixed;
  left:50%;
  bottom:26px;
  transform:translateX(-50%) translateY(18px);
  opacity:0;
  z-index:30;
  pointer-events:none;
  background:rgba(10,8,26,.88);
  border:1px solid rgba(134,239,172,.28);
  color:#d8ffe3;
  padding:10px 14px;
  border-radius:999px;
  backdrop-filter:blur(16px);
  transition:.22s ease;
}
.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}
.mini{
  margin-top:9px;
  color:rgba(219,234,254,.30);
  font-size:10.5px;
  word-break:break-all;
}

@media(max-width:560px){
  .wrap{
    min-height:100dvh;
    display:flex;
    align-items:flex-start;
    justify-content:center;
    padding:12px;
    padding-top:max(12px,env(safe-area-inset-top));
    padding-bottom:max(18px,env(safe-area-inset-bottom));
  }
  .panel{
    width:100%;
    border-radius:24px;
    padding:18px 14px;
  }
  h1{
    font-size:clamp(34px,14vw,58px);
    line-height:1.03;
    margin-top:10px;
  }
  h1 .brandline{font-size:clamp(15px,5.2vw,22px)}
  p{font-size:13px;line-height:1.45}
  .warning,.routing{font-size:11.5px;padding:9px 10px}
  .app-block{padding:10px;border-radius:17px}
  .downloads{grid-template-columns:1fr 1fr 1fr;gap:7px}
  .download-btn{font-size:11.5px;min-height:36px;padding:8px 6px}
  .big-action{min-height:44px;font-size:13px}
  .ring{width:126vw}
  .ring:nth-child(2){width:94vw}
  .ring:nth-child(3){width:68vw}
}

@media(max-width:360px){
  .downloads{grid-template-columns:1fr}
}


write_happ_guide_page() {
  local guide_dir="$WEB_PATH/guide"
  local guide_file="$guide_dir/happ.html"
  load_branding
  mkdir -p "$guide_dir"
  export GUIDE_TITLE="$SUBSCRIPTION_NAME · инструкция HAPP"
  export GUIDE_HAPP_ANDROID_URL="$HAPP_ANDROID_URL"
  export GUIDE_HAPP_IOS_URL="$HAPP_IOS_URL"
  export GUIDE_HAPP_WINDOWS_URL="$HAPP_WINDOWS_URL"
  cat > "$guide_file" <<'GUIDE_TEMPLATE'
<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>__GUIDE_TITLE__</title><meta name="robots" content="noindex,nofollow"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@10..48,500;10..48,600;10..48,700&family=Geist:wght@400;500;600;700&display=swap" rel="stylesheet"><style>
:root{--paper:#fbfbf2;--surface:rgba(251,251,242,.82);--ink:#213a34;--muted:#5e6b66;--sage:#a8c4b4;--rosy:#847577;--dark:rgba(97,89,88,.2);--light:rgba(255,255,255,.72)}*{box-sizing:border-box}html{overflow-x:clip}body{margin:0;min-height:100vh;overflow-x:clip;background:radial-gradient(ellipse at 8% 4%,rgba(168,196,180,.5),transparent 34%),radial-gradient(ellipse at 92% 16%,rgba(183,210,220,.55),transparent 37%),linear-gradient(138deg,var(--paper),#e5e6e4 58%,#dfe6df);color:var(--ink);font-family:Geist,ui-sans-serif,system-ui,sans-serif}.wrap{max-width:760px;margin:0 auto;padding:24px 18px 36px}.back{display:inline-flex;align-items:center;min-height:44px;color:var(--rosy);font-size:13px;font-weight:700;text-decoration:none}.guide{margin-top:20px;padding:28px 22px;border-radius:22px;background:var(--surface);backdrop-filter:blur(40px);box-shadow:14px 18px 34px var(--dark),-10px -10px 24px var(--light);position:relative;overflow:hidden}.guide:after{content:"";position:absolute;inset:0;pointer-events:none;opacity:.04;mix-blend-mode:overlay;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}.eyebrow{margin:0;color:var(--rosy);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase}.guide h1{margin:10px 0 0;font-family:"Bricolage Grotesque",Geist,sans-serif;font-size:clamp(36px,8vw,58px);line-height:.98;letter-spacing:-.06em}.lead{max-width:560px;margin:15px 0 0;color:var(--muted);font-size:15px;line-height:1.55}.steps{display:grid;gap:20px;margin:28px 0 0;padding:0;list-style:none}.step{display:grid;grid-template-columns:40px 1fr;gap:13px}.number{display:grid;place-items:center;width:40px;height:40px;border-radius:13px;background:var(--sage);color:var(--ink);font-weight:800;box-shadow:5px 6px 12px rgba(97,89,88,.16),-4px -4px 9px rgba(255,255,255,.6)}.step h2{margin:2px 0 5px;font-family:"Bricolage Grotesque",Geist,sans-serif;font-size:22px;letter-spacing:-.03em}.step p{margin:0;color:var(--muted);font-size:14px;line-height:1.55}.shot{display:grid;place-items:center;min-height:110px;margin:12px 0 0;padding:16px;border-radius:14px;background:rgba(255,255,255,.42);color:var(--muted);font-size:12px;text-align:center}.links{display:flex;gap:9px;flex-wrap:wrap;margin-top:26px}.links a{display:inline-flex;align-items:center;min-height:44px;padding:0 14px;border-radius:13px;background:var(--ink);color:var(--paper);font-size:13px;font-weight:700;text-decoration:none;box-shadow:7px 9px 16px rgba(33,58,52,.24)}.links a.alt{background:rgba(255,255,255,.48);color:var(--ink);box-shadow:5px 6px 12px rgba(97,89,88,.14),-4px -4px 9px rgba(255,255,255,.6)}@media(max-width:520px){.guide{padding:23px 17px;border-radius:19px}.step{grid-template-columns:34px 1fr}.number{width:34px;height:34px;border-radius:11px}}
</style></head><body><div class="wrap"><a class="back" href="javascript:history.back()">← Назад к подключению</a><article class="guide"><p class="eyebrow">HAPP · пошагово</p><h1>Подключение за пару минут</h1><p class="lead">Установи приложение, добавь личную ссылку и включи соединение. Скриншоты добавим сюда, когда ты их пришлёшь.</p><ol class="steps"><li class="step"><span class="number">1</span><div><h2>Установи HAPP</h2><p>Открой магазин своего устройства и установи официальное приложение.</p><figure class="shot">Скриншот шага 1 появится здесь</figure></div></li><li class="step"><span class="number">2</span><div><h2>Вернись на эту страницу</h2><p>Нажми «Добавить в HAPP» на главной странице или скопируй ссылку вручную.</p><figure class="shot">Скриншот шага 2 появится здесь</figure></div></li><li class="step"><span class="number">3</span><div><h2>Разреши добавление</h2><p>В приложении подтверди импорт подписки, если появится запрос.</p><figure class="shot">Скриншот шага 3 появится здесь</figure></div></li><li class="step"><span class="number">4</span><div><h2>Включи соединение</h2><p>Выбери добавленный профиль и нажми кнопку подключения.</p><figure class="shot">Скриншот шага 4 появится здесь</figure></div></li></ol><div class="links"><a href="__GUIDE_HAPP_ANDROID_URL__" target="_blank" rel="noopener">Android</a><a href="__GUIDE_HAPP_IOS_URL__" target="_blank" rel="noopener">iPhone</a><a class="alt" href="__GUIDE_HAPP_WINDOWS_URL__" target="_blank" rel="noopener">Windows</a></div></article></div></body></html>
GUIDE_TEMPLATE
@media(max-width:560px){
  html,body{
    min-height:100%;
    overflow-x:hidden;
    overflow-y:auto;
  }
  body{
    position:relative;
  }
  .panel{
    margin:0 auto;
    max-width:100%;
  }
  #stars{
    opacity:.82;
  }
  #particles{
    opacity:.64;
  }
}

@media(prefers-reduced-motion:reduce){
  body:after,.aurora,.ring,.lines,.pulse:before,.pulse:after,.orbit,.panel{animation:none}
}
@import url('https://fonts.googleapis.com/css2?family=DM+Mono:wght@400;500&family=Manrope:wght@400;500;600;700;800&display=swap');
:root{--bg:#071114;--text:#f4f0e8;--muted:#9fb2ad;--a:#9ee7c2;--b:#f6c978;--c:#d4a8ff}
body{font-family:'Manrope',ui-sans-serif,sans-serif;background:#071114;color:var(--text)}
body:before{background:radial-gradient(circle at 8% 8%,rgba(158,231,194,.15),transparent 27%),radial-gradient(circle at 92% 22%,rgba(246,201,120,.13),transparent 28%),linear-gradient(145deg,#071114 0%,#10171a 55%,#090d10 100%)}
.aurora{background:conic-gradient(from 210deg at 30% 55%,transparent 0 28%,rgba(158,231,194,.14) 42%,rgba(212,168,255,.13) 53%,transparent 68%),conic-gradient(from 35deg at 78% 42%,transparent 0 35%,rgba(246,201,120,.13) 48%,transparent 70%);filter:blur(74px) saturate(.9);opacity:.7}
.orbit{opacity:.55;filter:none}.ring{border-color:rgba(244,240,232,.12);animation-duration:48s}.ring:nth-child(2){animation-duration:33s}.ring:nth-child(3){animation-duration:25s}.dot{width:8px;height:8px;box-shadow:0 0 18px #9ee7c2,0 0 38px rgba(158,231,194,.65)}
.panel{width:min(620px,100%);border-radius:34px;padding:clamp(24px,5vw,42px);background:rgba(9,20,22,.76);border:1px solid rgba(244,240,232,.15);box-shadow:0 35px 100px rgba(0,0,0,.48),inset 0 1px rgba(255,255,255,.08);animation:panelIn 1s cubic-bezier(.16,1,.3,1) .2s both}
.panel:before{background:linear-gradient(130deg,rgba(158,231,194,.48),rgba(246,201,120,.2),rgba(212,168,255,.26));opacity:.45}
.kicker{font-family:'DM Mono',monospace;letter-spacing:.08em;color:#c5e9d5;background:rgba(158,231,194,.07);border-color:rgba(158,231,194,.22)}
.server-choice{display:grid;grid-template-columns:1fr auto;gap:8px;width:100%;align-items:stretch}.server-link{min-width:0}.copy-key{border:1px solid rgba(244,240,232,.15);background:rgba(244,240,232,.06);color:#e5eee8;border-radius:12px;padding:0 12px;font:600 11px 'DM Mono',monospace;cursor:pointer;transition:.25s ease}.copy-key:hover{background:rgba(158,231,194,.14);border-color:rgba(158,231,194,.42);transform:translateY(-1px)}
</style>
</head>
<body>
<div class="aurora"></div>
<div class="lines"></div>
<div class="pulse"></div>
<canvas id="stars"></canvas>
<canvas id="particles"></canvas>

<div class="orbit">
  <div class="ring"><i class="dot"></i></div>
  <div class="ring"><i class="dot"></i></div>
  <div class="ring"><i class="dot"></i></div>
</div>

<main class="wrap">
  <section class="panel">
    <div class="kicker">__SERVER_FLAG__ private access · switzerland</div>

    <h1>
      <span class="username">__USERNAME__</span>
      <span class="brandline">by __SUBSCRIPTION_NAME__</span>
    </h1>

    <p>__PAGE_SUBTITLE__</p>

    <div class="warning">__WARNING_TEXT__</div>
    <div class="routing">__ROUTING_NOTE__</div>

    <div class="app-block">
      <div class="app-head">
        <div class="app-title">HAPP</div>
        <div class="app-note">Скачайте приложенте HAPP</div>
      </div>
      <a class="big-action" href="__HAPP_ADD_URL__">↪️ ДОБАВИТЬ В HAPP</a>
      <div class="downloads">
        <a class="download-btn" target="_blank" rel="noopener" href="__HAPP_ANDROID_URL__">📥 Android</a>
        <a class="download-btn" target="_blank" rel="noopener" href="__HAPP_IOS_URL__">📥 iOS</a>
        <a class="download-btn" target="_blank" rel="noopener" href="__HAPP_WINDOWS_URL__">📥 Windows</a>
      </div>
    </div>

    <div class="app-block">
      <div class="app-head">
        <div class="app-title">AmneziaVPN</div>
        <div class="app-note">Запасной способ подключения</div>
      </div>
      <div class="downloads" id="amnezia-list"><span class="app-note">Загрузка профилей…</span></div>
      <div class="downloads" style="margin-top:9px"><a class="download-btn" id="amz-android" target="_blank" rel="noopener">Android</a><a class="download-btn" id="amz-ios" target="_blank" rel="noopener">iOS</a></div>
      <div class="app-note" style="margin-top:9px">Открой кнопку на устройстве с установленной AmneziaVPN. Ключ можно добавить или скопировать вручную.</div>
    </div>

    <a class="copy-action" href="javascript:void(0)" onclick="copySub();return false;">📋 Скопировать ссылку подписки</a>

    <div class="mini" id="sub">__SUB_URL__</div>
    <div class="footer">__FOOTER_TEXT__</div>
  </section>
</main>
<div class="toast" id="toast">Ссылка скопирована</div>

<script>
function copySub(){
  const t=document.getElementById("sub").innerText;
  navigator.clipboard.writeText(t).then(()=>{
    const el=document.getElementById("toast");
    el.classList.add("show");
    setTimeout(()=>el.classList.remove("show"),1600);
  });
}
function showToast(message){
  const el=document.getElementById("toast"); el.textContent=message; el.classList.add("show");
  setTimeout(()=>el.classList.remove("show"),1600);
}

async function loadAmnezia(){
  const list=document.getElementById('amnezia-list');
  try{
    const response=await fetch('/servers.json?v='+Date.now(),{cache:'no-store'});
    if(!response.ok) throw new Error('catalog');
    const data=await response.json();
    document.getElementById('amz-android').href=data.apps.android;
    document.getElementById('amz-ios').href=data.apps.ios;
    list.innerHTML='';
    for(const server of (data.servers||[])){
      const group=document.createElement('div'); group.className='server-choice';
      const link=document.createElement('a'); link.className='download-btn server-link'; link.href=server.url;
      link.textContent=(server.flag||'')+' '+server.name; group.appendChild(link);
      const copy=document.createElement('button'); copy.className='copy-key'; copy.type='button'; copy.textContent='Копировать ключ';
      copy.addEventListener('click',()=>navigator.clipboard.writeText(server.url).then(()=>showToast('Ключ скопирован')));
      group.appendChild(copy); list.appendChild(group);
    }
    if(!list.children.length) throw new Error('empty');
  }catch(e){
    list.innerHTML='<span class="app-note">Профили временно недоступны — обновите страницу</span>';
  }
}
loadAmnezia();

const particleCanvas=document.getElementById('particles');
const particleCtx=particleCanvas.getContext('2d');
const starCanvas=document.getElementById('stars');
const starCtx=starCanvas.getContext('2d');
let w,h,dpr,pts=[],stars=[];

function resize(){
  dpr=Math.min(window.devicePixelRatio||1,2);
  w=particleCanvas.width=starCanvas.width=innerWidth*dpr;
  h=particleCanvas.height=starCanvas.height=innerHeight*dpr;
  particleCanvas.style.width=starCanvas.style.width=innerWidth+'px';
  particleCanvas.style.height=starCanvas.style.height=innerHeight+'px';

  const isMobile=innerWidth<620;
  const pCount=isMobile ? Math.max(95,Math.min(175,Math.floor(innerWidth/6))) : Math.max(120,Math.min(230,Math.floor(innerWidth/7)));
  pts=Array.from({length:pCount},()=>({
    x:Math.random()*w,
    y:Math.random()*h,
    r:(Math.random()*1.05+.22)*dpr,
    v:(Math.random()*0.24+.045)*dpr,
    a:Math.random()*Math.PI*2,
    hue:Math.random()
  }));

  const sCount=isMobile ? Math.max(220,Math.min(520,Math.floor(innerWidth*innerHeight/1250))) : Math.max(280,Math.min(760,Math.floor(innerWidth*innerHeight/1500)));
  stars=Array.from({length:sCount},()=>({
    x:Math.random()*w,
    y:Math.random()*h,
    r:(Math.random()*0.62+0.16)*dpr,
    a:Math.random()*Math.PI*2,
    speed:(Math.random()*0.0014+0.00045),
    drift:(Math.random()*0.018+0.006)*dpr,
    shade:Math.random()
  }));
}

function drawStars(t){
  starCtx.clearRect(0,0,w,h);
  for(const s of stars){
    const flicker=.22 + Math.max(0,Math.sin(t*s.speed+s.a))*0.68;
    const color=s.shade>.78
      ? `rgba(240,171,252,${flicker*.38})`
      : s.shade>.42
        ? `rgba(165,243,252,${flicker*.45})`
        : `rgba(255,255,255,${flicker*.50})`;
    s.y-=s.drift;
    s.x+=Math.sin(t*.00025+s.a)*0.05*dpr;
    if(s.y<-4*dpr){s.y=h+4*dpr;s.x=Math.random()*w}
    starCtx.beginPath();
    starCtx.fillStyle=color;
    starCtx.arc(s.x,s.y,s.r,0,Math.PI*2);
    starCtx.fill();
  }
}

function drawParticles(t){
  particleCtx.clearRect(0,0,w,h);
  for(const p of pts){
    p.y-=p.v;
    p.x+=Math.sin(t*.0007+p.a)*.18*dpr;
    if(p.y<-10*dpr){p.y=h+10*dpr;p.x=Math.random()*w}
    const alpha=.18 + Math.sin(t*.001 + p.a)*.08;
    const color = p.hue > .66
      ? `rgba(240,171,252,${alpha*.75})`
      : p.hue > .33
        ? `rgba(167,139,250,${alpha*.80})`
        : `rgba(165,243,252,${alpha})`;
    particleCtx.beginPath();
    particleCtx.fillStyle=color;
    particleCtx.shadowColor=color;
    particleCtx.shadowBlur=9*dpr;
    particleCtx.arc(p.x,p.y,p.r,0,Math.PI*2);
    particleCtx.fill();
    particleCtx.shadowBlur=0;
  }
}

let lastFrame=0;
function tick(t){
  if(t-lastFrame>33){
    drawStars(t);
    drawParticles(t);
    lastFrame=t;
  }
  requestAnimationFrame(tick);
}

let resizeTimer;
addEventListener('resize',()=>{
  clearTimeout(resizeTimer);
  resizeTimer=setTimeout(resize,120);
});
resize();
tick(0);
</script>
</body>
</html>
LEGACY_TEMPLATE

: <<'NESTED_GUIDE_DISABLED'
  local guide_dir="$WEB_PATH/guide"
  local guide_file="$guide_dir/happ.html"
  load_branding
  mkdir -p "$guide_dir"
  export GUIDE_TITLE="$SUBSCRIPTION_NAME · инструкция HAPP"
  export GUIDE_HAPP_ANDROID_URL="$HAPP_ANDROID_URL"
  export GUIDE_HAPP_IOS_URL="$HAPP_IOS_URL"
  export GUIDE_HAPP_WINDOWS_URL="$HAPP_WINDOWS_URL"
  cat > "$guide_file" <<'GUIDE_TEMPLATE'
<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>__GUIDE_TITLE__</title><meta name="robots" content="noindex,nofollow"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@10..48,500;10..48,600;10..48,700&family=Geist:wght@400;500;600;700&display=swap" rel="stylesheet"><style>
:root{--paper:#fbfbf2;--surface:rgba(251,251,242,.82);--ink:#213a34;--muted:#5e6b66;--sage:#a8c4b4;--rosy:#847577;--dark:rgba(97,89,88,.2);--light:rgba(255,255,255,.72)}*{box-sizing:border-box}html{overflow-x:clip}body{margin:0;min-height:100vh;overflow-x:clip;background:radial-gradient(ellipse at 8% 4%,rgba(168,196,180,.5),transparent 34%),radial-gradient(ellipse at 92% 16%,rgba(183,210,220,.55),transparent 37%),linear-gradient(138deg,var(--paper),#e5e6e4 58%,#dfe6df);color:var(--ink);font-family:Geist,ui-sans-serif,system-ui,sans-serif}.wrap{max-width:760px;margin:0 auto;padding:24px 18px 36px}.back{display:inline-flex;align-items:center;min-height:44px;color:var(--rosy);font-size:13px;font-weight:700;text-decoration:none}.guide{margin-top:20px;padding:28px 22px;border-radius:22px;background:var(--surface);backdrop-filter:blur(40px);box-shadow:14px 18px 34px var(--dark),-10px -10px 24px var(--light);position:relative;overflow:hidden}.guide:after{content:"";position:absolute;inset:0;pointer-events:none;opacity:.04;mix-blend-mode:overlay;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='140' height='140'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}.eyebrow{margin:0;color:var(--rosy);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase}.guide h1{margin:10px 0 0;font-family:"Bricolage Grotesque",Geist,sans-serif;font-size:clamp(36px,8vw,58px);line-height:.98;letter-spacing:-.06em}.lead{max-width:560px;margin:15px 0 0;color:var(--muted);font-size:15px;line-height:1.55}.steps{display:grid;gap:20px;margin:28px 0 0;padding:0;list-style:none}.step{display:grid;grid-template-columns:40px 1fr;gap:13px}.number{display:grid;place-items:center;width:40px;height:40px;border-radius:13px;background:var(--sage);color:var(--ink);font-weight:800;box-shadow:5px 6px 12px rgba(97,89,88,.16),-4px -4px 9px rgba(255,255,255,.6)}.step h2{margin:2px 0 5px;font-family:"Bricolage Grotesque",Geist,sans-serif;font-size:22px;letter-spacing:-.03em}.step p{margin:0;color:var(--muted);font-size:14px;line-height:1.55}.shot{display:grid;place-items:center;min-height:110px;margin:12px 0 0;padding:16px;border-radius:14px;background:rgba(255,255,255,.42);color:var(--muted);font-size:12px;text-align:center}.links{display:flex;gap:9px;flex-wrap:wrap;margin-top:26px}.links a{display:inline-flex;align-items:center;min-height:44px;padding:0 14px;border-radius:13px;background:var(--ink);color:var(--paper);font-size:13px;font-weight:700;text-decoration:none;box-shadow:7px 9px 16px rgba(33,58,52,.24)}.links a.alt{background:rgba(255,255,255,.48);color:var(--ink);box-shadow:5px 6px 12px rgba(97,89,88,.14),-4px -4px 9px rgba(255,255,255,.6)}@media(max-width:520px){.guide{padding:23px 17px;border-radius:19px}.step{grid-template-columns:34px 1fr}.number{width:34px;height:34px;border-radius:11px}}
</style></head><body><div class="wrap"><a class="back" href="javascript:history.back()">← Назад к подключению</a><article class="guide"><p class="eyebrow">HAPP · пошагово</p><h1>Подключение за пару минут</h1><p class="lead">Установи приложение, добавь личную ссылку и включи соединение. Скриншоты добавим сюда, когда ты их пришлёшь.</p><ol class="steps"><li class="step"><span class="number">1</span><div><h2>Установи HAPP</h2><p>Открой магазин своего устройства и установи официальное приложение.</p><figure class="shot">Скриншот шага 1 появится здесь</figure></div></li><li class="step"><span class="number">2</span><div><h2>Вернись на эту страницу</h2><p>Нажми «Добавить в HAPP» на главной странице или скопируй ссылку вручную.</p><figure class="shot">Скриншот шага 2 появится здесь</figure></div></li><li class="step"><span class="number">3</span><div><h2>Разреши добавление</h2><p>В приложении подтверди импорт подписки, если появится запрос.</p><figure class="shot">Скриншот шага 3 появится здесь</figure></div></li><li class="step"><span class="number">4</span><div><h2>Включи соединение</h2><p>Выбери добавленный профиль и нажми кнопку подключения.</p><figure class="shot">Скриншот шага 4 появится здесь</figure></div></li></ol><div class="links"><a href="__GUIDE_HAPP_ANDROID_URL__" target="_blank" rel="noopener">Android</a><a href="__GUIDE_HAPP_IOS_URL__" target="_blank" rel="noopener">iPhone</a><a class="alt" href="__GUIDE_HAPP_WINDOWS_URL__" target="_blank" rel="noopener">Windows</a></div></article></div></body></html>
GUIDE_TEMPLATE
  GUIDE_FILE="$guide_file" python3 - <<'PY'
from pathlib import Path
import html, os
p = Path(os.environ["GUIDE_FILE"])
s = p.read_text(encoding="utf-8")
for key, env in {
    "__GUIDE_TITLE__": "GUIDE_TITLE",
    "__GUIDE_HAPP_ANDROID_URL__": "GUIDE_HAPP_ANDROID_URL",
    "__GUIDE_HAPP_IOS_URL__": "GUIDE_HAPP_IOS_URL",
    "__GUIDE_HAPP_WINDOWS_URL__": "GUIDE_HAPP_WINDOWS_URL",
}.items():
    s = s.replace(key, html.escape(os.environ.get(env, "")))
p.write_text(s, encoding="utf-8")
PY
  chmod 644 "$guide_file"
}

NESTED_GUIDE_DISABLED
  local display_name="$username"
  [[ "$username" == "Nadzo" ]] && display_name="$username ❤️"
  [[ "$username" == "vika" ]] && display_name='⁎❁⁕❁※~(´◡`)~※❁⁕❁⁎'
  PAGE_TITLE_SAFE="$display_name · $SUBSCRIPTION_NAME"
  export PAGE_USERNAME="$display_name"
  export PAGE_TITLE_SAFE
  export PAGE_SUB_URL="$sub_url"
  export PAGE_HAPP_ADD_URL="$happ_add_url"
  export PAGE_SUBSCRIPTION_NAME="$SUBSCRIPTION_NAME"
  export PAGE_SERVER_FLAG="$SERVER_FLAG"
  export PAGE_SUBTITLE="$PAGE_SUBTITLE"
  export PAGE_WARNING_TEXT="$WARNING_TEXT"
  export PAGE_ROUTING_NOTE="$ROUTING_NOTE"
  export PAGE_FOOTER_TEXT="$FOOTER_TEXT"
  export PAGE_HAPP_ANDROID_URL="$HAPP_ANDROID_URL"
  export PAGE_HAPP_IOS_URL="$HAPP_IOS_URL"
  export PAGE_HAPP_WINDOWS_URL="$HAPP_WINDOWS_URL"
  export PAGE_AMNEZIA_ANDROID_URL="$AMNEZIA_ANDROID_URL"
  export PAGE_AMNEZIA_IOS_URL="$AMNEZIA_IOS_URL"
  export PAGE_AMNEZIA_WINDOWS_URL="$AMNEZIA_WINDOWS_URL"
  export PAGE_V2RAYTUN_ANDROID_URL="$V2RAYTUN_ANDROID_URL"
  export PAGE_V2RAYTUN_IOS_URL="$V2RAYTUN_IOS_URL"
  export PAGE_DONATE_SBER_URL="$DONATE_SBER_URL"
  export PAGE_DONATE_TBANK_URL="$DONATE_TBANK_URL"
  export PAGE_AMNEZIA_ESTONIA_URL="$AMNEZIA_ESTONIA_URL"

  python3 - "$page_file" <<'PY'
from pathlib import Path
import html
import os
import sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

repl = {
    "__TITLE__": html.escape(os.environ.get("PAGE_TITLE_SAFE", "")),
    "__USERNAME__": html.escape(os.environ.get("PAGE_USERNAME", "")),
    "__SUB_URL__": html.escape(os.environ.get("PAGE_SUB_URL", "")),
    "__HAPP_ADD_URL__": html.escape(os.environ.get("PAGE_HAPP_ADD_URL", "")),
    "__SUBSCRIPTION_NAME__": html.escape(os.environ.get("PAGE_SUBSCRIPTION_NAME", "")),
    "__SERVER_FLAG__": html.escape(os.environ.get("PAGE_SERVER_FLAG", "")),
    "__PAGE_SUBTITLE__": html.escape(os.environ.get("PAGE_SUBTITLE", "")),
    "__WARNING_TEXT__": html.escape(os.environ.get("PAGE_WARNING_TEXT", "")),
    "__ROUTING_NOTE__": html.escape(os.environ.get("PAGE_ROUTING_NOTE", "")),
    "__FOOTER_TEXT__": html.escape(os.environ.get("PAGE_FOOTER_TEXT", "")),
    "__HAPP_ANDROID_URL__": html.escape(os.environ.get("PAGE_HAPP_ANDROID_URL", "")),
    "__HAPP_IOS_URL__": html.escape(os.environ.get("PAGE_HAPP_IOS_URL", "")),
    "__HAPP_WINDOWS_URL__": html.escape(os.environ.get("PAGE_HAPP_WINDOWS_URL", "")),
    "__AMNEZIA_ANDROID_URL__": html.escape(os.environ.get("PAGE_AMNEZIA_ANDROID_URL", "")),
    "__AMNEZIA_IOS_URL__": html.escape(os.environ.get("PAGE_AMNEZIA_IOS_URL", "")),
    "__AMNEZIA_WINDOWS_URL__": html.escape(os.environ.get("PAGE_AMNEZIA_WINDOWS_URL", "")),
    "__V2RAYTUN_ANDROID_URL__": html.escape(os.environ.get("PAGE_V2RAYTUN_ANDROID_URL", "")),
    "__V2RAYTUN_IOS_URL__": html.escape(os.environ.get("PAGE_V2RAYTUN_IOS_URL", "")),
    "__DONATE_SBER_URL__": html.escape(os.environ.get("PAGE_DONATE_SBER_URL", "")),
    "__DONATE_TBANK_URL__": html.escape(os.environ.get("PAGE_DONATE_TBANK_URL", "")),
    "__AMNEZIA_ESTONIA_URL__": html.escape(os.environ.get("PAGE_AMNEZIA_ESTONIA_URL", "")),
}

for k, v in repl.items():
    s = s.replace(k, v)

p.write_text(s, encoding="utf-8")
PY
}



write_happ_guide_page() {
  local guide_dir="$WEB_PATH/guide" guide_file="$WEB_PATH/guide/happ.html"
  load_branding
  mkdir -p "$guide_dir"
  cat > "$guide_file" <<EOF
<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$SUBSCRIPTION_NAME · инструкция HAPP</title><meta name="robots" content="noindex,nofollow"><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@10..48,500;10..48,600;10..48,700&family=Geist:wght@400;500;600;700&display=swap" rel="stylesheet"><style>
:root{--paper:#fbfbf2;--surface:rgba(251,251,242,.84);--ink:#213a34;--muted:#5e6b66;--sage:#a8c4b4;--rosy:#847577;--dark:rgba(97,89,88,.2);--light:rgba(255,255,255,.72)}*{box-sizing:border-box}html{overflow-x:clip}body{margin:0;min-height:100vh;overflow-x:clip;background:radial-gradient(ellipse at 8% 4%,rgba(168,196,180,.5),transparent 34%),radial-gradient(ellipse at 92% 16%,rgba(183,210,220,.55),transparent 37%),linear-gradient(138deg,var(--paper),#e5e6e4 58%,#dfe6df);color:var(--ink);font-family:Geist,ui-sans-serif,system-ui,sans-serif}.wrap{max-width:760px;margin:0 auto;padding:24px 18px 36px}.back{display:inline-flex;align-items:center;min-height:44px;color:var(--rosy);font-size:13px;font-weight:700;text-decoration:none}.guide{margin-top:20px;padding:28px 22px;border-radius:22px;background:var(--surface);backdrop-filter:blur(40px);box-shadow:14px 18px 34px var(--dark),-10px -10px 24px var(--light);position:relative;overflow:hidden}.eyebrow{margin:0;color:var(--rosy);font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase}.guide h1{margin:10px 0 0;font-size:clamp(36px,8vw,58px);line-height:.98;letter-spacing:-.06em}.lead{margin:15px 0 0;color:var(--muted);font-size:15px;line-height:1.55}.steps{display:grid;gap:20px;margin:28px 0 0;padding:0;list-style:none}.step{display:grid;grid-template-columns:40px 1fr;gap:13px}.number{display:grid;place-items:center;width:40px;height:40px;border-radius:13px;background:var(--sage);color:var(--ink);font-weight:800;box-shadow:5px 6px 12px rgba(97,89,88,.16),-4px -4px 9px rgba(255,255,255,.6)}.step h2{margin:2px 0 5px;font-size:22px;letter-spacing:-.03em}.step p{margin:0;color:var(--muted);font-size:14px;line-height:1.55}.shot{display:grid;place-items:center;min-height:110px;margin:12px 0 0;padding:16px;border-radius:14px;background:rgba(255,255,255,.42);color:var(--muted);font-size:12px;text-align:center}.links{display:flex;gap:9px;flex-wrap:wrap;margin-top:26px}.links a{display:inline-flex;align-items:center;min-height:44px;padding:0 14px;border-radius:13px;background:var(--ink);color:var(--paper);font-size:13px;font-weight:700;text-decoration:none;box-shadow:7px 9px 16px rgba(33,58,52,.24)}.links a.alt{background:rgba(255,255,255,.48);color:var(--ink)}@media(max-width:520px){.guide{padding:23px 17px;border-radius:19px}.step{grid-template-columns:34px 1fr}.number{width:34px;height:34px;border-radius:11px}}
</style></head><body><div class="wrap"><a class="back" href="javascript:history.back()">← Назад к подключению</a><article class="guide"><p class="eyebrow">HAPP · пошагово</p><h1>Подключение за пару минут</h1><p class="lead">Установи приложение, добавь личную ссылку и включи соединение. Скриншоты добавим сюда, когда ты их пришлёшь.</p><ol class="steps"><li class="step"><span class="number">1</span><div><h2>Установи HAPP</h2><p>Открой магазин своего устройства и установи официальное приложение.</p><figure class="shot">Скриншот шага 1 появится здесь</figure></div></li><li class="step"><span class="number">2</span><div><h2>Вернись на эту страницу</h2><p>Нажми «Добавить в HAPP» на главной странице или скопируй ссылку вручную.</p><figure class="shot">Скриншот шага 2 появится здесь</figure></div></li><li class="step"><span class="number">3</span><div><h2>Разреши добавление</h2><p>В приложении подтверди импорт подписки, если появится запрос.</p><figure class="shot">Скриншот шага 3 появится здесь</figure></div></li><li class="step"><span class="number">4</span><div><h2>Включи соединение</h2><p>Выбери добавленный профиль и нажми кнопку подключения.</p><figure class="shot">Скриншот шага 4 появится здесь</figure></div></li></ol><div class="links"><a href="$HAPP_ANDROID_URL" target="_blank" rel="noopener">Android</a><a href="$HAPP_IOS_URL" target="_blank" rel="noopener">iPhone</a><a class="alt" href="$HAPP_WINDOWS_URL" target="_blank" rel="noopener">Windows</a></div></article></div></body></html>
EOF
  chmod 644 "$guide_file"
}

make_user_subscription() {
  local username="$1"
  local sub_dir="$WEB_PATH/sub"
  local reminder_remark user_uuid
  reminder_remark="Обнови подписку – нажать на 🔄 сверху"
  mkdir -p "$sub_dir"

  # Lookup personal UUID from users.json
  if [[ -f "$ETC_DIR/users.json" ]]; then
    user_uuid=$(jq -r --arg u "$username" '.[$u] // empty' "$ETC_DIR/users.json")
  fi
  if [[ -z "$user_uuid" ]]; then
    user_uuid=$(xray uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid)
    jq --arg u "$username" --arg id "$user_uuid" '.[$u] = $id' "$ETC_DIR/users.json" > /tmp/u.json && mv /tmp/u.json "$ETC_DIR/users.json"
  fi

  # Inject personal UUID and email into all profiles, preserving core remarks
  python3 -c "
import json
from pathlib import Path

sub_file = Path('$CORE_PATH/subscription.json')
data = json.loads(sub_file.read_text(encoding='utf-8'))

user_uuid = '$user_uuid'
uname = '$username'
reminder = '$reminder_remark'

if isinstance(data, list) and len(data) > 0:
    for idx, profile in enumerate(data):
        for out in profile.get('outbounds', []):
            if 'settings' in out and 'vnext' in out['settings']:
                for v in out['settings']['vnext']:
                    for u in v.get('users', []):
                        u['id'] = user_uuid
                        u['email'] = uname

    reminder_prof = json.loads(json.dumps(data[0]))
    reminder_prof['remarks'] = reminder
    data.append(reminder_prof)

output_data = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
if '$user_uuid':
    Path('$sub_dir/${username}_${user_uuid}.json').write_text(output_data, encoding='utf-8')
Path('$sub_dir/$username.json').write_text(output_data, encoding='utf-8')
"
}


sync_user() {
  local username="$1"
  local nnect_dir="$WEB_PATH/nnect"
  local sub_dir="$WEB_PATH/sub"
  if [[ -e "$nnect_dir" && ! -d "$nnect_dir" ]]; then mv "$nnect_dir" "$nnect_dir.bak-$(date +%Y%m%d-%H%M%S)"; fi
  if [[ -e "$sub_dir" && ! -d "$sub_dir" ]]; then mv "$sub_dir" "$sub_dir.bak-$(date +%Y%m%d-%H%M%S)"; fi
  mkdir -p "$nnect_dir" "$sub_dir"
  if [[ ! -f "$CORE_PATH/subscription.json" ]]; then
    echo -e "${RED}❌ Не найден базовый файл подписки: $CORE_PATH/subscription.json${NC}"
    exit 1
  fi
  make_user_subscription "$username"
  write_landing_page "$username"
}

sync_users() {
  ensure_dirs
  if [[ ! -s "$USERS_FILE" ]]; then
    echo -e "${YEL}Список пользователей пуст.${NC}"
    return 0
  fi
  while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    sync_user "$u"
  done < "$USERS_FILE"
  echo -e "${GRN}✅ Именные подписки синхронизированы.${NC}"
}

update_client_russian_routes() {
  local subscription="$CORE_PATH/subscription.json"
  [[ -f "$subscription" ]] || return 0

  SUBSCRIPTION="$subscription" python3 - <<'PY'
import json, os
from pathlib import Path

path = Path(os.environ["SUBSCRIPTION"])
data = json.loads(path.read_text(encoding="utf-8"))

domains = [
    "geosite:category-ru", "regexp:\\.ru$", "regexp:\\.рф$",
    "domain:yandex.ru", "domain:yandex.com", "domain:yastatic.net", "domain:yandex.net", "domain:ya.ru",
    "domain:vk.com", "domain:vk.ru", "domain:vkuseraudio.net", "domain:mail.ru", "domain:ok.ru", "domain:rutube.ru",
    "domain:gosuslugi.ru", "domain:mos.ru", "domain:nalog.gov.ru", "domain:customs.gov.ru",
    "domain:ozon.ru", "domain:wildberries.ru", "domain:wb.ru", "domain:avito.ru", "domain:youla.ru",
    "domain:sberbank.ru", "domain:sber.ru", "domain:tbank.ru", "domain:alfabank.ru", "domain:vtb.ru", "domain:psbank.ru",
    "domain:2gis.ru",
    "domain:kinopoisk.ru", "domain:ivi.ru", "domain:start.ru", "domain:smotrim.ru",
]
tag = "vpn-cluster-russian-direct"
telegram_tag = "vpn-cluster-telegram-proxy"
telegram_domains = [
    "domain:telegram.org", "domain:t.me", "domain:telegram.me",
    "domain:telegra.ph", "domain:cdn-telegram.org", "domain:telesco.pe",
]
dns_servers = ["https://cloudflare-dns.com/dns-query", "https://dns.google/dns-query"]

def update_config(cfg):
    if not isinstance(cfg, dict) or not isinstance(cfg.get("routing"), dict):
        return False
    rules = cfg["routing"].setdefault("rules", [])
    if not isinstance(rules, list):
        return False
    rules[:] = [r for r in rules if not (isinstance(r, dict) and r.get("ruleTag") in {tag, telegram_tag})]
    for rule in rules:
        if isinstance(rule, dict) and rule.get("outboundTag") == "direct" and isinstance(rule.get("domain"), list):
            rule["domain"] = [domain for domain in rule["domain"] if domain not in telegram_domains]
    if isinstance(cfg.get("dns"), dict):
        cfg["dns"]["servers"] = dns_servers
    telegram_rule = {"type": "field", "ruleTag": telegram_tag, "domain": telegram_domains, "outboundTag": "proxy"}
    rule = {"type": "field", "ruleTag": tag, "domain": domains,
            "ip": ["geoip:ru"], "outboundTag": "direct"}
    index = next((i for i, r in enumerate(rules)
                  if isinstance(r, dict) and r.get("outboundTag") in {"proxy", "warp", "warproxy", "warpcli"}), len(rules))
    rules.insert(index, telegram_rule)
    rules.insert(index + 1, rule)
    if isinstance(cfg.get("outbounds"), list) and not any(isinstance(o, dict) and o.get("tag") == "direct" for o in cfg["outbounds"]):
        cfg["outbounds"].append({"tag": "direct", "protocol": "freedom"})
    return True

changed = False
if isinstance(data, list):
    for config in data:
        changed = update_config(config) or changed
elif isinstance(data, dict):
    changed = update_config(data)
    for key in ("configs", "profiles", "items"):
        if isinstance(data.get(key), list):
            for config in data[key]:
                changed = update_config(config) or changed

if changed:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)
    print("client Russian routes updated")
else:
    print("no embedded routing config found")
PY
}

add_user() {
  local username="$1"
  ensure_dirs
  if ! validate_username "$username"; then
    echo -e "${RED}❌ username должен быть 2-32 символа: латиница, цифры, _ или -${NC}"
    exit 1
  fi
  grep -qxF "$username" "$USERS_FILE" || echo "$username" >> "$USERS_FILE"
  write_happ_guide_page
  sync_user "$username"
  echo -e "${GRN}✅ Пользователь добавлен:${NC} $username"
  echo -e "${BLU}Страница:${NC} https://$DOMAIN/nnect/$username.html"
  echo -e "${BLU}Подписка:${NC} https://$DOMAIN/sub/$username.json"
}

del_user() {
  local username="$1"
  ensure_dirs
  if ! validate_username "$username"; then
    echo -e "${RED}❌ Некорректный username.${NC}"
    exit 1
  fi
  grep -vxF "$username" "$USERS_FILE" > "$USERS_FILE.tmp" || true
  mv "$USERS_FILE.tmp" "$USERS_FILE"
  rm -f "$WEB_PATH/nnect/$username.html"
  rm -f "$WEB_PATH/sub/$username.json"
  rm -f "$WEB_PATH/sub/${username}_*.json"
  echo -e "${GRN}✅ Пользователь удалён:${NC} $username"
}

list_users() {
  ensure_dirs
  echo -e "${YEL}Пользователи $PROJECT_NAME:${NC}"
  if [[ ! -s "$USERS_FILE" ]]; then
    echo "  пока нет"
  else
    sed 's#^#  - #' "$USERS_FILE"
  fi
}

read_project_logs() {
  local f
  for f in "$LOG_FILE" "$LOG_FILE".*; do
    [[ -e "$f" ]] || continue
    case "$f" in
      *.gz) gzip -cd "$f" 2>/dev/null || true ;;
      *) cat "$f" 2>/dev/null || true ;;
    esac
  done
}

print_user_stats() {
  local username="$1"
  local page_path="/nnect/$username.html"
  local user_uuid=""
  if [[ -f "$ETC_DIR/users.json" ]]; then
    user_uuid=$(jq -r --arg u "$username" '.[$u] // empty' "$ETC_DIR/users.json")
  fi
  local sub_filename="$username.json"
  if [[ -n "$user_uuid" ]]; then
    sub_filename="${username}_${user_uuid}.json"
  fi
  local sub_path="/sub/$sub_filename"
  local tmp
  tmp="$(mktemp)"

  read_project_logs | awk -F'|' -v p="$page_path" -v s="$sub_path" '
    NF >= 6 && ($4 == p || $4 == p "/" || $4 == s) { print }
  ' > "$tmp"

  local page_views sub_downloads uniq_page_ips uniq_sub_ips last_seen
  page_views="$(awk -F'|' -v p="$page_path" '$4 == p || $4 == p "/" {c++} END{print c+0}' "$tmp")"
  sub_downloads="$(awk -F'|' -v s="$sub_path" '$4 == s && ($5 == 200 || $5 == 304) {c++} END{print c+0}' "$tmp")"
  uniq_page_ips="$(awk -F'|' -v p="$page_path" '($4 == p || $4 == p "/") && $2 != "" {print $2}' "$tmp" | sort -u | wc -l | tr -d ' ')"
  uniq_sub_ips="$(awk -F'|' -v s="$sub_path" '$4 == s && ($5 == 200 || $5 == 304) && $2 != "" {print $2}' "$tmp" | sort -u | wc -l | tr -d ' ')"
  last_seen="$(tail -n 1 "$tmp" | awk -F'|' '{print $1}')"
  [[ -n "$last_seen" ]] || last_seen="нет данных"

  echo -e "\n${YEL}$username${NC}"
  echo "  Страница открыта: $page_views"
  echo "  Уникальных IP страницы: $uniq_page_ips"
  echo "  Подписка скачана/обновлена: $sub_downloads"
  echo "  Уникальных IP подписки: $uniq_sub_ips"
  echo "  Последняя активность: $last_seen"

  if [[ "$uniq_sub_ips" -ge 2 ]]; then
    echo -e "  ${RED}⚠ Возможная пересылка: подписку скачивали с $uniq_sub_ips разных IP.${NC}"
  fi

  if [[ "$sub_downloads" -gt 0 ]]; then
    echo "  IP, которые забирали sub.json:"
    awk -F'|' -v s="$sub_path" '$4 == s && ($5 == 200 || $5 == 304) && $2 != "" {print $2}' "$tmp" | sort | uniq -c | sort -nr | head -n 10 | sed 's/^/    /'
    echo "  Устройства/User-Agent для sub.json:"
    awk -F'|' -v s="$sub_path" '$4 == s && ($5 == 200 || $5 == 304) {ua=$6; for(i=7;i<=NF;i++) ua=ua "|" $i; if(ua=="") ua="-"; print $2 " | " ua}' "$tmp" | sort | uniq -c | sort -nr | head -n 10 | sed 's/^/    /'
  fi

  rm -f "$tmp"
}

show_stats() {
  local username="${1:-}"
  ensure_dirs

  local log_files
  shopt -s nullglob
  log_files=("$LOG_FILE" "$LOG_FILE".*)
  shopt -u nullglob
  if [[ ${#log_files[@]} -eq 0 ]]; then
    echo -e "${YEL}Пока нет логов $LOG_FILE.${NC}"
    echo "Они появятся после первого открытия /nnect/username.html или скачивания /sub/username.json."
    return 0
  fi

  echo -e "${YEL}Статистика переходов $PROJECT_NAME${NC}"
  echo "Лог: $LOG_FILE"
  echo "Важно: разные IP не всегда означают слив. У человека может быть Wi-Fi + мобильная сеть, VPN или динамический IP."

  if [[ -n "$username" ]]; then
    if ! validate_username "$username"; then
      echo -e "${RED}❌ Некорректный username.${NC}"
      exit 1
    fi
    print_user_stats "$username"
  else
    if [[ ! -s "$USERS_FILE" ]]; then
      echo "Пользователей пока нет."
      return 0
    fi
    while IFS= read -r u; do
      [[ -z "$u" ]] && continue
      print_user_stats "$u"
    done < "$USERS_FILE"
  fi
}

write_root_page() {
  load_branding
  cat > "$WEB_PATH/index.html" <<EOF
<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>$SUBSCRIPTION_NAME</title><style>:root{--a:$ACCENT_A;--b:$ACCENT_B}body{margin:0;min-height:100vh;display:grid;place-items:center;background:radial-gradient(circle at 25% 25%,color-mix(in srgb,var(--a) 22%,transparent),transparent 30%),radial-gradient(circle at 75% 20%,color-mix(in srgb,var(--b) 18%,transparent),transparent 28%),#070912;color:#eef4ff;font-family:system-ui,sans-serif}.box{max-width:620px;margin:18px;padding:34px;border-radius:28px;background:rgba(255,255,255,.07);border:1px solid rgba(255,255,255,.13);box-shadow:0 0 90px color-mix(in srgb,var(--a) 16%,transparent);backdrop-filter:blur(16px)}h1{margin:0 0 12px;font-size:42px;letter-spacing:-.04em}p{color:#a7b3cf;line-height:1.6}.hint{padding:12px 14px;border-radius:16px;background:rgba(255,255,255,.06);color:#eaf2ff}</style></head><body><div class="box"><h1>$SUBSCRIPTION_NAME</h1><p>$PAGE_HELLO</p><p class="hint">Используйте личную ссылку формата <b>/nnect/username.html</b>. Если нужна новая ссылка — попросите владельца создать отдельный доступ.</p></div></body></html>
EOF
}


install_packages() {
  echo -e "${YEL}Обновление и установка пакетов...${NC}"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y curl jq dnsutils openssl nginx certbot wget tar gettext-base ca-certificates python3
  systemctl enable --now nginx
}

check_dns() {
  local local_ip dns_ip
  local_ip="$(hostname -I | awk '{print $1}')"
  dns_ip="$(dig +short "$DOMAIN" | grep '^[0-9]' | head -n1 || true)"
  if [[ -n "$dns_ip" && "$local_ip" != "$dns_ip" ]]; then
    echo -e "${RED}❌ IP сервера ($local_ip) не совпадает с A-записью $DOMAIN ($dns_ip).${NC}"
    echo -e "${YEL}Для нормальной установки A-запись домена должна указывать на $local_ip.${NC}"
    read -r -p "Продолжить на ваш страх и риск? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then exit 1; fi
  fi
}

enable_bbr() {
  if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q 'bbr'; then
    echo -e "${GRN}BBR уже активен.${NC}"
  else
    cat > /etc/sysctl.d/999-vpn-cluster.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system >/dev/null || true
    echo -e "${GRN}BBR включён.${NC}"
  fi

  cat > /etc/security/limits.d/99-vpn-cluster.conf <<EOF
*       soft    nofile  1048576
*       hard    nofile  1048576
root    soft    nofile  1048576
root    hard    nofile  1048576
EOF
  ulimit -n 65535 || true
}

install_xray() {
  echo -e "${YEL}Установка / обновление Xray-core...${NC}"
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
}

prepare_nginx_for_certbot() {
  local config_path="$1"
  mkdir -p /var/www/html
  cat > "$config_path" <<EOF
log_format vpn_davida '\$time_iso8601|\$remote_addr|\$request_method|\$uri|\$status|\$http_user_agent';

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    location / {
        return 200 '$PROJECT_NAME certbot ok';
        add_header Content-Type text/plain;
    }
}
EOF
  nginx -t
  systemctl reload nginx
}

get_nginx_config_path() {
  if [[ -f /etc/nginx/sites-enabled/default ]]; then
    echo "/etc/nginx/sites-enabled/default"
  elif [[ -f /etc/nginx/sites-available/default ]]; then
    echo "/etc/nginx/sites-available/default"
  elif [[ -d /etc/nginx/conf.d ]]; then
    echo "/etc/nginx/conf.d/default.conf"
  else
    echo -e "${RED}❌ Не найден путь для nginx-конфига.${NC}" >&2
    exit 1
  fi
}

issue_cert() {
  local config_path="$1"
  prepare_nginx_for_certbot "$config_path"
  certbot certonly --webroot -w /var/www/html \
    -d "$DOMAIN" \
    -m "mail@$DOMAIN" \
    --agree-tos --non-interactive \
    --deploy-hook "systemctl reload nginx; mkdir -p $CERT_DIR; cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem $CERT_DIR/fullchain.pem; cp /etc/letsencrypt/live/$DOMAIN/privkey.pem $CERT_DIR/privkey.pem; chmod 744 $CERT_DIR/fullchain.pem $CERT_DIR/privkey.pem; systemctl restart xray || true"

  cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$CERT_DIR/fullchain.pem"
  cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$CERT_DIR/privkey.pem"
  chmod 744 "$CERT_DIR/fullchain.pem" "$CERT_DIR/privkey.pem"
  echo -e "${GRN}✅ Сертификат получен и скопирован для Xray.${NC}"
}

write_nginx_config() {
  local config_path="$1"
  local title_b64 route_b64
  load_branding
  title_b64="$(printf '%s' "$SUBSCRIPTION_NAME" | base64 -w0)"
  route_b64="$(SUBSCRIPTION_NAME="$SUBSCRIPTION_NAME" python3 - <<'PY'
import base64
import json
import os

name = os.environ.get("SUBSCRIPTION_NAME", "vpn-cluster.skam")
routing = {
    "Name": name,
    "GlobalProxy": "true",
    "RouteOrder": "block-proxy-direct",
    "RemoteDNSType": "DoH",
    "RemoteDNSDomain": "https://dns.google/dns-query",
    "RemoteDNSIP": "8.8.4.4",
    "DomesticDNSType": "DoH",
    "DomesticDNSDomain": "https://cloudflare-dns.com/dns-query",
    "DomesticDNSIP": "1.1.1.1",
    "Geoipurl": "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat",
    "Geositeurl": "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat",
    "LastUpdated": "1775206108",
    "DnsHosts": {},
    "DirectSites": [
        "geosite:category-ru", "geosite:private",
        "regexp:\\.ru$", "regexp:\\.рф$",
        "domain:yandex.ru", "domain:yandex.com", "domain:yastatic.net", "domain:yandex.net", "domain:ya.ru",
        "domain:vk.com", "domain:vk.ru", "domain:vkuseraudio.net", "domain:mail.ru", "domain:ok.ru", "domain:rutube.ru",
        "domain:gosuslugi.ru", "domain:mos.ru", "domain:nalog.gov.ru",
        "domain:ozon.ru", "domain:wildberries.ru", "domain:wb.ru", "domain:avito.ru", "domain:youla.ru",
        "domain:sberbank.ru", "domain:sber.ru", "domain:tbank.ru", "domain:alfabank.ru", "domain:vtb.ru", "domain:psbank.ru",
        "domain:2gis.ru",
        "domain:kinopoisk.ru", "domain:ivi.ru", "domain:start.ru", "domain:smotrim.ru"
    ],
    "DirectIp": ["geoip:private", "geoip:ru"],
    "ProxySites": [
        "domain:telegram.org", "domain:t.me", "domain:telegram.me",
        "domain:telegra.ph", "domain:cdn-telegram.org", "domain:telesco.pe"
    ],
    "ProxyIp": [],
    "BlockSites": ["geosite:category-ads", "geosite:win-spy"],
    "BlockIp": [],
    "DomainStrategy": "IPIfNonMatch",
    "FakeDNS": "false",
    "UseChunkFiles": "false",
}
raw = json.dumps(routing, separators=(",", ":"), ensure_ascii=False).encode()
print(base64.b64encode(raw).decode())
PY
)"
  cat > "$config_path" <<EOF
log_format vpn_davida '\$time_iso8601|\$remote_addr|\$request_method|\$uri|\$status|\$http_user_agent';

server {
    listen 127.0.0.1:3333 ssl http2 proxy_protocol;
    server_name $DOMAIN;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    root $WEB_PATH;
    index index.html;
    access_log $LOG_FILE vpn_davida;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location ~ "^/\." { deny all; }

    # Старые ссылки оставляем как редиректы:
    # /nnect-alice          -> /nnect/david.html
    # /nnect-alice/sub.json -> /sub/alice.json
    location ~ ^/nnect-([A-Za-z0-9_-]+)/?$ { return 301 /nnect/\$1.html; }
    location ~ ^/nnect-([A-Za-z0-9_-]+)/sub\.json$ { return 301 /sub/\$1.json; }

    # Без расширений тоже не ломаем: просто перенаправляем на явные .html/.json.
    location ~ ^/nnect/([A-Za-z0-9_-]+)$ { return 301 /nnect/\$1.html; }
    location ~ ^/sub/([A-Za-z0-9_-]+)$ { return 301 /sub/\$1.json; }

    location ~ ^/nnect/[A-Za-z0-9_-]+\.html$ {
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;
        try_files \$uri =404;
    }

    location ~ ^/sub/[A-Za-z0-9_-]+\.json$ {
        default_type application/json;
        add_header profile-title "\$vpn_davida_profile_title" always;
        add_header profile-update-interval "3" always;
        add_header routing "happ://routing/onadd/$route_b64" always;
        add_header routing-enable "1" always;
        add_header Access-Control-Expose-Headers "profile-title,profile-update-interval,routing,routing-enable" always;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;
        try_files \$uri =404;
    }

    location / { try_files \$uri \$uri/ =404; }
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
  nginx -t

  # Старый autoXRAY мог держать 127.0.0.1:3333 через Xray/xHTTP.
  # Теперь этот порт нужен nginx как fallback-сайт для REALITY, поэтому перед запуском nginx
  # временно останавливаем Xray. Ниже скрипт запишет новый config.json и запустит Xray снова.
  systemctl stop xray 2>/dev/null || true
  systemctl restart nginx
  echo -e "${GRN}✅ Nginx настроен как HTTPS-фолбэк для Reality.${NC}"
}


install_warp_optional() {
  read -r -p "$(echo -e "\n${YEL}Устанавливать WARP для отдельных сайтов? (y/n, по умолчанию y): ${NC}")" choice_warp
  choice_warp="${choice_warp:-y}"
  if [[ "$choice_warp" =~ ^[Yy]$ ]]; then
    TAG_WARP="warp"
    if ss -tuln | grep -q ':40000 '; then
      echo -e "${GRN}WARP SOCKS на 40000 уже работает.${NC}"
    else
      echo -e "${YEL}Установка WARP-cli...${NC}"
      echo -e "1\n1\n40000" | bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) w
    fi
  else
    TAG_WARP="direct"
    echo -e "${YEL}WARP пропущен. Правило WARP будет отправлять трафик напрямую.${NC}"
  fi
}

choose_fingerprint() {
  echo -e "\n${YEL}Выберите TLS fingerprint:${NC}"
  echo "1) chrome    3) safari   5) android   7) 360"
  echo "2) firefox   4) ios      6) edge      8) qq"
  read -r -p "Введите номер [1-8] (по умолчанию 2 - firefox): " fp_choice
  case "${fp_choice:-2}" in
    1) fpBro="chrome" ;;
    2) fpBro="firefox" ;;
    3) fpBro="safari" ;;
    4) fpBro="ios" ;;
    5) fpBro="android" ;;
    6) fpBro="edge" ;;
    7) fpBro="360" ;;
    8) fpBro="qq" ;;
    *) fpBro="firefox" ;;
  esac
}

write_xray_config() {
  local uuid private_key public_key short_id
  uuid="$(xray uuid)"
  key_output="$(xray x25519)"
  private_key="$(echo "$key_output" | awk -F': *' '/PrivateKey|Private key|privateKey|private key/ {print $2; exit}')"
  public_key="$(echo "$key_output" | awk -F': *' '/PublicKey|Public key|publicKey|public key|Password/ {print $2; exit}')"
  if [[ -z "$private_key" || -z "$public_key" ]]; then
    echo -e "${RED}❌ Не удалось получить X25519 ключи из xray x25519.${NC}"
    echo "$key_output"
    exit 1
  fi
  short_id="$(openssl rand -hex 8)"

  cat > "$ENV_FILE" <<EOF
DOMAIN=$DOMAIN
PROJECT_NAME=$PROJECT_NAME
UUID=$uuid
PRIVATE_KEY=$private_key
PUBLIC_KEY=$public_key
SHORT_ID=$short_id
FINGERPRINT=$fpBro
TAG_WARP=$TAG_WARP
EOF
  chmod 600 "$ENV_FILE"

  export DOMAIN uuid private_key short_id TAG_WARP

  cat <<'EOF' | envsubst > "$XRAY_DIR/config.json"
{
  "log": {
    "dnsLog": false,
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log",
    "loglevel": "warning"
  },
  "dns": {
    "servers": [
      "https+local://8.8.4.4/dns-query",
      "https+local://8.8.8.8/dns-query",
      "https+local://1.1.1.1/dns-query",
      "localhost"
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "vless-raw-reality-vision",
      "port": 443,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "flow": "xtls-rprx-vision",
            "id": "${uuid}"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "127.0.0.1:3333",
            "xver": 2
          }
        ]
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "sockopt": {
          "acceptProxyProtocol": false
        },
        "realitySettings": {
          "show": false,
          "xver": 2,
          "target": "127.0.0.1:3333",
          "spiderX": "/",
          "shortIds": ["${short_id}"],
          "privateKey": "${private_key}",
          "serverNames": ["${DOMAIN}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "ForceIPv4"
      }
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    },
    {
      "tag": "warp",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      }
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "ip": ["geoip:private"],
        "outboundTag": "block"
      },
      {
        "port": "25",
        "outboundTag": "block"
      },
      {
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "domain": ["geosite:category-ads", "geosite:win-spy", "geosite:private"],
        "outboundTag": "block"
      },
      {
        "domain": [
          "ifconfig.me",
          "checkip.amazonaws.com",
          "api.ipify.org",
          "2ip.io",
          "habr.com",
          "geosite:category-ip-geo-detect",
          "geosite:google-gemini",
          "geosite:canva",
          "geosite:openai",
          "geosite:whatsapp"
        ],
        "outboundTag": "${TAG_WARP}"
      }
    ]
  }
}
EOF

  jq . "$XRAY_DIR/config.json" >/dev/null
  write_subscription "$uuid" "$public_key" "$short_id"
}

write_subscription() {
  local uuid="$1"
  local public_key="$2"
  local short_id="$3"
  load_branding
  local remark="$SERVER_FLAG Финляндия · хороший"

  local outbound
  outbound=$(cat <<EOF
{
  "mux": { "concurrency": -1, "enabled": false },
  "tag": "proxy",
  "protocol": "vless",
  "settings": {
    "vnext": [
      {
        "address": "$DOMAIN",
        "port": 443,
        "users": [
          {
            "id": "$uuid",
            "flow": "xtls-rprx-vision",
            "encryption": "none"
          }
        ]
      }
    ]
  },
  "streamSettings": {
    "network": "raw",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "fingerprint": "$fpBro",
      "serverName": "$DOMAIN",
      "password": "$public_key",
      "shortId": "$short_id",
      "spiderX": "/"
    }
  }
}
EOF
)

  cat > "$CORE_PATH/subscription.json" <<EOF
[
  {
    "log": {
      "loglevel": "warning"
    },
    "dns": {
      "servers": [
        "https://cloudflare-dns.com/dns-query",
        "https://dns.google/dns-query"
      ],
      "queryStrategy": "UseIPv4"
    },
    "routing": {
      "domainStrategy": "IPIfNonMatch",
      "rules": [
        {
          "domain": ["geosite:category-ads", "geosite:win-spy"],
          "outboundTag": "block"
        },
        {
          "protocol": ["bittorrent"],
          "outboundTag": "direct"
        },
        {
          "domain": ["habr.com", "apkmirror.com"],
          "outboundTag": "proxy"
        },
        {
          "domain": [
            "geosite:private",
            "ifconfig.me",
            "checkip.amazonaws.com",
            "api.ipify.org",
            "geosite:category-ip-geo-detect",
            "geosite:apple",
            "geosite:apple-pki",
            "geosite:huawei",
            "geosite:xiaomi",
            "geosite:category-android-app-download",
            "geosite:f-droid",
            "geosite:yandex",
            "geosite:vk",
            "geosite:microsoft",
            "geosite:win-update",
            "geosite:win-extra",
            "geosite:google-play",
            "geosite:steam",
            "geosite:category-ru",
            "regexp:\\\\.ru$",
            "regexp:\\\\.рф$",
            "domain:yandex.ru",
            "domain:yandex.com",
            "domain:yastatic.net",
            "domain:yandex.net",
            "domain:ya.ru",
            "domain:vk.com",
            "domain:vk.ru",
            "domain:vkuseraudio.net",
            "domain:mail.ru",
            "domain:ok.ru",
            "domain:rutube.ru",
            "domain:gosuslugi.ru",
            "domain:mos.ru",
            "domain:nalog.gov.ru",
            "domain:ozon.ru",
            "domain:wildberries.ru",
            "domain:wb.ru",
            "domain:avito.ru",
            "domain:youla.ru",
            "domain:sberbank.ru",
            "domain:sber.ru",
            "domain:tbank.ru",
            "domain:alfabank.ru",
            "domain:vtb.ru",
            "domain:psbank.ru",
            "domain:2gis.ru",
            "domain:kinopoisk.ru",
            "domain:ivi.ru",
            "domain:start.ru",
            "domain:smotrim.ru"
          ],
          "outboundTag": "direct"
        },
        {
          "ip": ["geoip:private", "geoip:ru"],
          "outboundTag": "direct"
        }
      ]
    },
    "inbounds": [
      {
        "tag": "socks-in",
        "protocol": "socks",
        "listen": "127.0.0.1",
        "port": 10808,
        "settings": { "udp": true },
        "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
      },
      {
        "tag": "http-in",
        "protocol": "http",
        "listen": "127.0.0.1",
        "port": 10809,
        "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"] }
      }
    ],
    "outbounds": [
      $outbound,
      { "tag": "direct", "protocol": "freedom" },
      { "tag": "block", "protocol": "blackhole" }
    ],
    "remarks": "$remark"
  }
]
EOF

  jq . "$CORE_PATH/subscription.json" >/dev/null
}

final_status() {
  echo -e "\n${YEL}=== Финальная проверка ===${NC}"
  if systemctl is-active --quiet nginx; then echo -e "Nginx: ${GRN}RUNNING${NC}"; else echo -e "Nginx: ${RED}ERROR${NC}"; fi
  if systemctl is-active --quiet xray; then echo -e "Xray: ${GRN}RUNNING${NC}"; else echo -e "Xray: ${RED}ERROR${NC}"; fi
  if [[ "${TAG_WARP:-direct}" == "warp" ]]; then
    if ss -nlt | grep -q ':40000\b'; then echo -e "WARP SOCKS: ${GRN}LISTENING${NC}"; else echo -e "WARP SOCKS: ${RED}NOT LISTENING${NC}"; fi
  fi
}

webfix_paths() {
  ensure_dirs
  local nginx_config
  nginx_config="$(get_nginx_config_path)"
  write_root_page
  write_server_catalog
  write_happ_guide_page

  # Только веб-часть: Xray, ключи и рабочий config.json не трогаем.
  local title_b64 route_b64
  load_branding
  title_b64="$(printf '%s' "$SUBSCRIPTION_NAME" | base64 -w0)"
  route_b64="$(SUBSCRIPTION_NAME="$SUBSCRIPTION_NAME" python3 - <<'PY'
import base64
import json
import os

name = os.environ.get("SUBSCRIPTION_NAME", "vpn-cluster.skam")
routing = {
    "Name": name,
    "GlobalProxy": "true",
    "RouteOrder": "block-proxy-direct",
    "RemoteDNSType": "DoH",
    "RemoteDNSDomain": "https://dns.google/dns-query",
    "RemoteDNSIP": "8.8.4.4",
    "DomesticDNSType": "DoH",
    "DomesticDNSDomain": "https://cloudflare-dns.com/dns-query",
    "DomesticDNSIP": "1.1.1.1",
    "Geoipurl": "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat",
    "Geositeurl": "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat",
    "LastUpdated": "1775206108",
    "DnsHosts": {},
    "DirectSites": [
        "geosite:category-ru", "geosite:private",
        "regexp:\\.ru$", "regexp:\\.рф$",
        "domain:yandex.ru", "domain:yandex.com", "domain:yastatic.net", "domain:yandex.net", "domain:ya.ru",
        "domain:vk.com", "domain:vk.ru", "domain:vkuseraudio.net", "domain:mail.ru", "domain:ok.ru", "domain:rutube.ru",
        "domain:gosuslugi.ru", "domain:mos.ru", "domain:nalog.gov.ru", "domain:customs.gov.ru",
        "domain:ozon.ru", "domain:wildberries.ru", "domain:wb.ru", "domain:avito.ru", "domain:youla.ru",
        "domain:sberbank.ru", "domain:sber.ru", "domain:tbank.ru", "domain:alfabank.ru", "domain:vtb.ru", "domain:psbank.ru",
        "domain:2gis.ru",
        "domain:kinopoisk.ru", "domain:ivi.ru", "domain:start.ru", "domain:smotrim.ru"
    ],
    "DirectIp": ["geoip:private", "geoip:ru"],
    "ProxySites": [
        "domain:telegram.org", "domain:t.me", "domain:telegram.me",
        "domain:telegra.ph", "domain:cdn-telegram.org", "domain:telesco.pe"
    ],
    "ProxyIp": [],
    "BlockSites": ["geosite:category-ads", "geosite:win-spy"],
    "BlockIp": [],
    "DomainStrategy": "IPIfNonMatch",
    "FakeDNS": "false",
    "UseChunkFiles": "false",
}
raw = json.dumps(routing, separators=(",", ":"), ensure_ascii=False).encode()
print(base64.b64encode(raw).decode())
PY
)"
  cat > "$nginx_config" <<EOF
log_format vpn_davida '\$time_iso8601|\$remote_addr|\$request_method|\$uri|\$status|\$http_user_agent';

# --- SECURITY RULE 3: REJECT DIRECT IP ACCESS ---
# Drop plain HTTP requests on direct IP
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    return 444;
}

# Reject TLS handshake on direct IP or invalid SNI (do not leak domain certificate)
server {
    listen 127.0.0.1:3333 ssl default_server proxy_protocol;
    server_name _;
    ssl_reject_handshake on;
}

# --- VALID DOMAIN: HTTP TO HTTPS REDIRECT ---
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

# --- VALID DOMAIN: SECURE HTTPS HOST ---
server {
    listen 127.0.0.1:3333 ssl http2 proxy_protocol;
    server_name $DOMAIN;
    port_in_redirect off;
    set_real_ip_from 127.0.0.1;
    real_ip_header proxy_protocol;

    root $WEB_PATH;
    index index.html;
    access_log $LOG_FILE vpn_davida;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets off;
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location ~ "^/\." { deny all; }
    
    # Beautiful URL aliases: support /nect/ and /nnect/ with or without dash
    location ~ ^/(n?nect)-([A-Za-z0-9_-]+)/?$ { return 301 /nnect/\$2.html; }
    location ~ ^/(n?nect)-([A-Za-z0-9_-]+)/sub\.json$ { return 301 /sub/\$2.json; }
    location ~ ^/(n?nect)/([A-Za-z0-9_-]+)/?$ { return 301 /nnect/\$2.html; }
    location ~ ^/sub/([A-Za-z0-9_-]+)$ { return 301 /sub/\$1.json; }

    location ~ ^/nnect/[A-Za-z0-9_-]+\.html$ {
        default_type text/html;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;
        try_files \$uri =404;
    }

    location ~ ^/sub/[A-Za-z0-9_-]+\.json$ {
        default_type application/json;
        add_header profile-title "\$vpn_davida_profile_title" always;
        add_header profile-update-interval "3" always;
        add_header routing "happ://routing/onadd/$route_b64" always;
        add_header routing-enable "1" always;
        add_header Access-Control-Expose-Headers "profile-title,profile-update-interval,routing,routing-enable" always;
        add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;
        try_files \$uri =404;
    }

    # Davida Core Admin Panel & API
    location /api/ {
        proxy_pass http://127.0.0.1:8888/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /admin/ {
        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location / { try_files \$uri \$uri/ =404; }
}
EOF
  nginx -t
  systemctl reload nginx
  update_client_russian_routes
  sync_users
  echo -e "${GRN}✅ Веб-пути обновлены без перегенерации Xray.${NC}"
}


check_headers() {
  local username="${1:-alice}"
  local user_uuid=""
  if [[ -f "$ETC_DIR/users.json" ]]; then
    user_uuid=$(jq -r --arg u "$username" '.[$u] // empty' "$ETC_DIR/users.json")
  fi
  local sub_filename="$username.json"
  if [[ -n "$user_uuid" ]]; then
    sub_filename="${username}_${user_uuid}.json"
  fi
  echo -e "${YEL}HTTP Headers:${NC}"
  echo "https://$DOMAIN/sub/$sub_filename"
  echo
  curl -I "https://$DOMAIN/sub/$sub_filename" | sed -n '/profile-title/p;/profile-update-interval/p;/routing:/p;/routing-enable/p;/HTTP/p;/content-type/p'
}


check_subscription() {
  local username="${1:-alice}"
  local user_uuid=""
  if [[ -f "$ETC_DIR/users.json" ]]; then
    user_uuid=$(jq -r --arg u "$username" '.[$u] // empty' "$ETC_DIR/users.json")
  fi
  local sub_filename="$username.json"
  if [[ -n "$user_uuid" ]]; then
    sub_filename="${username}_${user_uuid}.json"
  fi
  local file="$WEB_PATH/sub/$sub_filename"
  echo -e "${YEL}Проверка профилей в подписке:${NC}"
  echo "$file"
  echo
  if [[ ! -f "$file" ]]; then
    echo -e "${RED}Файл не найден. Запусти sync/webfix или проверь username.${NC}"
    return 1
  fi
  jq -r 'if type=="array" then to_entries[] | "\\(.key+1). \\(.value.remarks // .value.tag // .value.name // "no name")" else "not array" end' "$file"
}


install_all() {
  ensure_dirs
  make_backup
  install_packages
  check_dns
  enable_bbr
  install_xray
  local nginx_config
  nginx_config="$(get_nginx_config_path)"
  issue_cert "$nginx_config"
  write_root_page
  write_nginx_config "$nginx_config"
  install_warp_optional
  choose_fingerprint
  write_xray_config
  systemctl restart xray

  if [[ ! -s "$USERS_FILE" ]]; then
    read -r -p "$(echo -e "\n${YEL}Первый username для именной ссылки (по умолчанию david): ${NC}")" first_user
    first_user="${first_user:-david}"
    add_user "$first_user"
  else
    sync_users
  fi

  final_status
  echo -e "\n${GRN}Готово.${NC}"
  load_branding
  echo -e "${YEL}Название подписки:${NC} $SUBSCRIPTION_NAME"
  echo -e "${YEL}Управление пользователями:${NC}"
  echo "  $0 adduser $DOMAIN username"
  echo "  $0 deluser $DOMAIN username"
  echo "  $0 listusers $DOMAIN"
  echo "  $0 stats $DOMAIN"
  echo "  $0 sync $DOMAIN"
  echo "  $0 webfix $DOMAIN"
  echo "  $0 brand $DOMAIN"
}

case "$cmd" in
  install) install_all ;;
  adduser)
    [[ -n "$USERNAME" ]] || { echo -e "${RED}❌ Укажите username.${NC}"; exit 1; }
    add_user "$USERNAME" ;;
  deluser)
    [[ -n "$USERNAME" ]] || { echo -e "${RED}❌ Укажите username.${NC}"; exit 1; }
    del_user "$USERNAME" ;;
  listusers) list_users ;;
  stats) show_stats "${USERNAME:-}" ;;
  sync) write_server_catalog; update_client_russian_routes; sync_users ;;
  webfix) webfix_paths ;;
  serverfix|catalog) write_server_catalog; echo -e "${GRN}✅ Каталог серверов обновлён без изменения HTML-страниц.${NC}" ;;
  brand) show_branding ;;
  backup) make_backup ;;
esac
