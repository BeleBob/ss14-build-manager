#!/usr/bin/env bash
# ss14 — install, check and manage Space Station 14 servers (several builds, shared port).
#
# Install:  curl -fsSL <url>/install.sh | bash   (asks for the command name)
#           or bash ss14.sh install [preset]
# Then:     <command> [action] [build] [args]
#   install [preset]           install a build and the command
#   doctor [build] [--smoke]   check the installation; --smoke starts the server and checks /info
#   list                       builds and their state
#   start [build] [args]       start (args go to the server)
#   stop [build|all]
#   restart [build] [args]
#   status [build]
#   logs [build] [args]        args are journalctl options
#   update [build]             git pull, rebuild, restart if it was running
#   use <build>                make a build the default
#   remove <build>             remove from the manager (repository files stay)
#   settings                   language and base port
#   uninstall                  remove the command (and optionally its settings); repositories stay
#   no arguments               interactive menu
#
# Default build: the only one; otherwise the last used; otherwise the newest registered.
# Port: first free one starting from the base port (1212 by default).
# Environment: SS14_BIN_DIR, SS14_DIR, SS14_CMD (command name, skips the prompt),
#              SS14_SKIP_BUILD=1, SS14_DOTNET, SS14_BASE_PORT.
set -uo pipefail

# Keep the original locale to detect the UI language, then read keys as UTF-8.
ORIG_LOCALE="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
unset LC_ALL
export LC_CTYPE=C.UTF-8

SELF="$(readlink -f "$0")"
CMD="$(basename "$0" .sh)"
CONF_DIR="$HOME/.config/ss14/builds"
SETTINGS_FILE="$HOME/.config/ss14/settings.conf"
STATE_DIR="$HOME/.local/state/ss14"
BIN_DIR="${SS14_BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$CONF_DIR" "$STATE_DIR" "$(dirname "$SETTINGS_FILE")"

LANG_MODE=auto
BASE_PORT_SETTING=""
# shellcheck disable=SC1090
[ -f "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"
BASE_PORT="${SS14_BASE_PORT:-${BASE_PORT_SETTING:-1212}}"
PORT_SPAN=20

# ---------- Language ----------

detect_lang() { case "$ORIG_LOCALE" in ru*|RU*) echo ru ;; *) echo en ;; esac; }

resolve_lang() {
    case "$LANG_MODE" in
        ru|en) echo "$LANG_MODE" ;;
        *) detect_lang ;;
    esac
}

UI_LANG="$(resolve_lang)"

declare -A MSG_EN=(
    [err]="Error: "
    [bad_preset]="unknown preset '%s' (astra, reserve, sunrise, lust, goob, deadspace)"
    [no_input]="no input"
    [no_builds]="no builds. Install with: %s install"
    [no_build_named]="build '%s' not found (see: %s list)"
    [no_build_short]="build '%s' not found"
    [need_build]="specify a build: %s"
    [use_usage]="usage: %s use <build>"
    [remove_usage]="usage: %s remove <build>"
    [already_running]="%s is already running on port %s."
    [no_free_port]="no free port in range %s-%s"
    [systemd_fail]="systemd-run could not start %s"
    [started]="%s is starting on port %s. Logs: %s logs"
    [already_stopped]="%s is already stopped."
    [stopped]="%s stopped."
    [st_running]="running, port %s"
    [st_stopped]="stopped"
    [logs_follow]="Logs for %s (Ctrl+C to exit)..."
    [dirty]="uncommitted changes in %s, update cancelled."
    [pull_fail]="git pull failed, update cancelled."
    [build_fail]="build of %s failed."
    [built]="%s built."
    [default_is]="Default: %s"
    [rm_ask]="Remove '%s' from the manager? Repository files stay. (y/n)"
    [cancelled]="cancelled"
    [removed]="'%s' removed from the manager."
    [replace_ask]="File %s exists. Replace it? (y/n)"
    [install_fail_copy]="could not install %s"
    [install_head]="=== Install: %s ==="
    [need_git]="git is required"
    [need_systemd]="systemd is required"
    [no_user_session]="no systemd user session. Enable with: loginctl enable-linger %s"
    [ask_dir]="Repository folder"
    [ask_name]="Build name (for the manager)"
    [bad_name]="build name: latin letters, digits, '-' and '_', must start with a letter"
    [ask_overwrite]="Build '%s' already exists. Re-register it? (y/n)"
    [ask_cmd]="Command name you will use to manage the server"
    [bad_cmd]="command name: latin letters, digits, '-' and '_', must start with a letter"
    [cmd_taken]="name '%s' is already used in the system (%s). Use it anyway? (y/n)"
    [pick_other]="choose another command name"
    [not_git]="%s exists and is not a git repository"
    [cloning]="Cloning %s ..."
    [clone_fail]="clone failed"
    [submod]="Fetching the engine (RobustToolbox) ..."
    [submod_fail]="RobustToolbox submodule failed to load"
    [building]="Building %s (several minutes) ..."
    [server_missing]="server build not found: %s"
    [registered]="Build '%s' registered; command '%s' installed to %s."
    [path_warn]="Note: %s is not in PATH. Add this line to ~/.zshrc or ~/.bashrc: export PATH=%s:\$PATH"
    [next_hint]="Next: %s start   (menu: %s)"
    [no_builds_intro]="No builds yet. Install one with: %s install"
    [bad_dir_abs]="The path must be absolute or start with ~/"
    [dir_is_file]="%s is a file, not a folder"
    [dir_other_repo]="%s is a git repository of another project"
    [dir_not_empty]="%s exists and is not empty"
    [dir_no_write]="No permission to create %s"
    [usage]="Usage: %s {install|doctor|list|start|stop|restart|status|logs|update|use|remove|settings|uninstall} [build] [args]"
    [uninstall_running]="Stop these servers first: %s"
    [uninstall_cmd]="Remove the command %s? (y/n)"
    [uninstall_data]="Also remove settings and build registry in ~/.config/ss14 and ~/.local/state/ss14? Repositories stay. (y/n)"
    [uninstall_done]="Removed."
    [uninstall_kept]="Command was not removed: it is a copy outside %s."
    [sdk_found]="Found .NET SDK >= %s: %s"
    [sdk_missing]="No .NET SDK >= %s found (needed for this repository)."
    [sdk_ask]="Install .NET SDK %s.0 into ~/.dotnet (no sudo, about 300 MB)? (y/n)"
    [sdk_manual]="install .NET SDK %s manually: https://dotnet.microsoft.com/download"
    [need_curl]="curl is required"
    [dl_fail]="could not download dotnet-install.sh"
    [sdk_install_fail]=".NET SDK installation failed"
    [sdk_after]="SDK >= %s not found after installation"
    [sdk_installed]="Installed .NET SDK: %s"
    [doc_env]="Environment"
    [doc_build]="Build: %s"
    [doc_total]="Summary: ok %s, warnings %s, errors %s"
    [ok_systemd]="systemd user session"
    [no_systemd_session]="no systemd user session"
    [linger_ok]="linger is on (servers survive logout)"
    [linger_warn]="linger is off: servers stop at logout (enable with: loginctl enable-linger %s)"
    [cmd_ok]="command %s installed: %s"
    [cmd_missing]="command %s is not installed in %s"
    [path_ok]="%s is in PATH"
    [path_missing]="%s is not in PATH"
    [mem_ok]="free memory: %s MB"
    [mem_low]="low free memory: %s MB (a server uses about 1.5 GB)"
    [disk_ok]="free disk space: %s GB"
    [disk_low]="low disk space: %s GB"
    [reg_missing]="no registration: %s"
    [repo_ok]="repository: %s"
    [repo_missing]="no repository: %s"
    [rt_ok]="RobustToolbox present"
    [rt_missing]="RobustToolbox not loaded (git submodule update --init -- RobustToolbox)"
    [sdk_ok]=".NET SDK >= %s (%s)"
    [sdk_bad]=".NET SDK >= %s not found at %s"
    [srv_ok]="server built"
    [srv_missing]="server build not found: %s"
    [info_ok]="/info responds"
    [info_no]="/info does not respond (still starting or packing the client)"
    [smoke_start_fail]="smoke: could not start"
    [smoke_ok]="smoke: /info = 200 on port %s"
    [smoke_no]="smoke: /info did not respond (code %s)"
    [smoke_fatal]="smoke: fatal errors in the log (see: %s logs %s)"
    [smoke_clean]="smoke: no fatal errors in the log"
    [menu_title]="Build manager for SS14"
    [sec_server]="Server"
    [sec_builds]="Builds"
    [sec_diag]="Diagnostics and settings"
    [item_start]="Start a build"
    [item_stop]="Stop a build"
    [item_restart]="Restart a build"
    [item_stopall]="Stop all"
    [item_list]="List builds"
    [item_use]="Default build"
    [item_update]="Update a build"
    [item_install]="Install a new build"
    [item_remove]="Remove a build from the manager"
    [item_doctor]="Check installation"
    [item_logs]="Build logs"
    [item_settings]="Settings"
    [item_quit]="Quit"
    [item_line]="Item: [ %s ]"
    [item_none]="no such item"
    [pick_title]="Choose a build"
    [pick_num]="Number: [ %s ]"
    [pause]="Esc, q or Enter: back to menu"
    [set_title]="Settings"
    [set_lang]="Language: %s"
    [lang_auto]="auto (system: %s)"
    [set_port]="Base port: %s"
    [set_back]="Back"
    [ask_port]="Base port (first port to try)"
    [bad_port]="port must be a number from 1024 to 65535"
    [saved]="Saved."
    [t_start]="Start a build"
    [t_stop]="Stop a build"
    [t_restart]="Restart a build"
    [t_stopall]="Stop all builds"
    [t_list]="Builds"
    [t_use]="Default build"
    [t_update]="Update a build"
    [t_install]="Install a new build"
    [t_remove]="Remove a build"
    [t_doctor]="Installation check"
    [t_logs]="Build logs"
    [t_pick]="Choose a build"
    [t_settings]="Settings"
    [t_pick_server]="Choose a server"
    [same_repo_running]="cannot start: %s already runs from the same repository folder"
    [waiting]="waiting for the port"
    [ready_line]="running on port %s"
    [start_timeout]="the port did not open within 3 minutes. Last log lines:"
    [log_tail]="Last log lines:"
)

declare -A MSG_RU=(
    [err]="Ошибка: "
    [bad_preset]="неизвестный пресет '%s' (astra, reserve, sunrise, lust, goob, deadspace)"
    [no_input]="нет ввода"
    [no_builds]="сборок нет. Установите: %s install"
    [no_build_named]="сборка '%s' не найдена (см. %s list)"
    [no_build_short]="сборка '%s' не найдена"
    [need_build]="укажите сборку: %s"
    [use_usage]="использование: %s use <сборка>"
    [remove_usage]="использование: %s remove <сборка>"
    [already_running]="%s уже запущен на порту %s."
    [no_free_port]="нет свободного порта в диапазоне %s-%s"
    [systemd_fail]="systemd-run не смог запустить %s"
    [started]="%s запускается на порту %s. Логи: %s logs"
    [already_stopped]="%s уже выключен."
    [stopped]="%s выключен."
    [st_running]="запущен, порт %s"
    [st_stopped]="выключен"
    [logs_follow]="Логи %s (Ctrl+C для выхода)..."
    [dirty]="в %s есть незакоммиченные изменения, обновление отменено."
    [pull_fail]="git pull не прошёл, обновление отменено."
    [build_fail]="сборка %s не удалась."
    [built]="%s собран."
    [default_is]="По умолчанию: %s"
    [rm_ask]="Убрать '%s' из менеджера? Файлы репозитория останутся. (y/n)"
    [cancelled]="отменено"
    [removed]="'%s' убрана из менеджера."
    [replace_ask]="Файл %s уже есть. Заменить? (y/n)"
    [install_fail_copy]="не удалось установить %s"
    [install_head]="=== Установка: %s ==="
    [need_git]="нужен git"
    [need_systemd]="нужен systemd"
    [no_user_session]="нет user-сессии systemd. Включите: loginctl enable-linger %s"
    [ask_dir]="Папка для репозитория"
    [ask_name]="Имя сборки (для менеджера)"
    [bad_name]="имя сборки: латиница, цифры, '-' и '_', начинается с буквы"
    [ask_overwrite]="Сборка '%s' уже есть. Перерегистрировать? (y/n)"
    [ask_cmd]="Имя команды, которой будете управлять сервером"
    [bad_cmd]="имя команды: латиница, цифры, '-' и '_', начинается с буквы"
    [cmd_taken]="имя '%s' уже занято в системе (%s). Всё равно использовать? (y/n)"
    [pick_other]="выберите другое имя команды"
    [not_git]="%s существует и не является git-репозиторием"
    [cloning]="Клонирую %s ..."
    [clone_fail]="клонирование не удалось"
    [submod]="Подтягиваю движок (RobustToolbox) ..."
    [submod_fail]="сабмодуль RobustToolbox не загрузился"
    [building]="Собираю %s (несколько минут) ..."
    [server_missing]="не найдена сборка сервера: %s"
    [registered]="Сборка '%s' зарегистрирована; команда '%s' установлена в %s."
    [path_warn]="Внимание: %s нет в PATH. Добавьте строку в ~/.zshrc или ~/.bashrc: export PATH=%s:\$PATH"
    [next_hint]="Дальше: %s start   (меню: %s)"
    [no_builds_intro]="Сборок пока нет. Установите одну командой: %s install"
    [bad_dir_abs]="Путь должен быть абсолютным или начинаться с ~/"
    [dir_is_file]="%s — это файл, а не папка"
    [dir_other_repo]="%s — git-репозиторий другого проекта"
    [dir_not_empty]="%s существует и не пустая"
    [dir_no_write]="Нет прав создать %s"
    [usage]="Использование: %s {install|doctor|list|start|stop|restart|status|logs|update|use|remove|settings|uninstall} [сборка] [аргументы]"
    [uninstall_running]="Сначала остановите серверы: %s"
    [uninstall_cmd]="Удалить команду %s? (y/n)"
    [uninstall_data]="Удалить также настройки и реестр сборок в ~/.config/ss14 и ~/.local/state/ss14? Репозитории останутся. (y/n)"
    [uninstall_done]="Удалено."
    [uninstall_kept]="Команда не удалена: это копия вне папки %s."
    [sdk_found]="Найден .NET SDK >= %s: %s"
    [sdk_missing]="Не найден .NET SDK >= %s (нужен для этого репозитория)."
    [sdk_ask]="Установить .NET SDK %s.0 в ~/.dotnet (без sudo, около 300 МБ)? (y/n)"
    [sdk_manual]="установите .NET SDK %s вручную: https://dotnet.microsoft.com/download"
    [need_curl]="нужен curl"
    [dl_fail]="не удалось скачать dotnet-install.sh"
    [sdk_install_fail]="установка .NET SDK не удалась"
    [sdk_after]="после установки SDK >= %s не найден"
    [sdk_installed]="Установлен .NET SDK: %s"
    [doc_env]="Окружение"
    [doc_build]="Сборка: %s"
    [doc_total]="Итого: ok %s, предупреждений %s, ошибок %s"
    [ok_systemd]="user-сессия systemd"
    [no_systemd_session]="нет user-сессии systemd"
    [linger_ok]="linger включён (серверы переживают выход из системы)"
    [linger_warn]="linger выключен: серверы остановятся при выходе из системы (loginctl enable-linger %s)"
    [cmd_ok]="команда %s установлена: %s"
    [cmd_missing]="команда %s не установлена в %s"
    [path_ok]="%s в PATH"
    [path_missing]="%s нет в PATH"
    [mem_ok]="свободная память: %s МБ"
    [mem_low]="мало свободной памяти: %s МБ (сервер занимает около 1,5 ГБ)"
    [disk_ok]="свободно на диске: %s ГБ"
    [disk_low]="мало места на диске: %s ГБ"
    [reg_missing]="нет регистрации: %s"
    [repo_ok]="репозиторий: %s"
    [repo_missing]="нет репозитория: %s"
    [rt_ok]="движок RobustToolbox на месте"
    [rt_missing]="RobustToolbox не загружен (git submodule update --init -- RobustToolbox)"
    [sdk_ok]=".NET SDK >= %s (%s)"
    [sdk_bad]=".NET SDK >= %s не найден по пути %s"
    [srv_ok]="сервер собран"
    [srv_missing]="не найдена сборка сервера: %s"
    [info_ok]="/info отвечает"
    [info_no]="/info не отвечает (ещё стартует или упаковывает клиент)"
    [smoke_start_fail]="smoke: не удалось запустить"
    [smoke_ok]="smoke: /info = 200 на порту %s"
    [smoke_no]="smoke: /info не ответил (код %s)"
    [smoke_fatal]="smoke: в логе есть фатальные ошибки (см. %s logs %s)"
    [smoke_clean]="smoke: фатальных ошибок в логе нет"
    [menu_title]="Менеджер сборок для SS14"
    [sec_server]="Сервер"
    [sec_builds]="Сборки"
    [sec_diag]="Диагностика и настройки"
    [item_start]="Запустить сборку"
    [item_stop]="Остановить сборку"
    [item_restart]="Перезапустить сборку"
    [item_stopall]="Остановить все"
    [item_list]="Список сборок"
    [item_use]="Сборка по умолчанию"
    [item_update]="Обновить сборку"
    [item_install]="Установить новую сборку"
    [item_remove]="Убрать сборку из менеджера"
    [item_doctor]="Проверка установки"
    [item_logs]="Логи сборки"
    [item_settings]="Настройки"
    [item_quit]="Выход"
    [item_line]="Пункт: [ %s ]"
    [item_none]="нет такого пункта"
    [pick_title]="Выберите сборку"
    [pick_num]="Номер: [ %s ]"
    [pause]="Esc, q или Enter: назад в меню"
    [set_title]="Настройки"
    [set_lang]="Язык: %s"
    [lang_auto]="авто (система: %s)"
    [set_port]="Базовый порт: %s"
    [set_back]="Назад"
    [ask_port]="Базовый порт (с какого порта начинать)"
    [bad_port]="порт должен быть числом от 1024 до 65535"
    [saved]="Сохранено."
    [t_start]="Запуск сборки"
    [t_stop]="Остановка сборки"
    [t_restart]="Перезапуск сборки"
    [t_stopall]="Остановка всех сборок"
    [t_list]="Сборки"
    [t_use]="Сборка по умолчанию"
    [t_update]="Обновление сборки"
    [t_install]="Установка сборки"
    [t_remove]="Удаление сборки"
    [t_doctor]="Проверка установки"
    [t_logs]="Логи сборки"
    [t_pick]="Выберите сборку"
    [t_settings]="Настройки"
    [t_pick_server]="Выберите сервер"
    [same_repo_running]="нельзя запустить: %s уже запущена из той же папки репозитория"
    [waiting]="ожидаю открытия порта"
    [ready_line]="запущен на порту %s"
    [start_timeout]="порт не открылся за 3 минуты. Последние строки лога:"
    [log_tail]="Последние строки лога:"
)

# m <key> [args] — printf-style message in the UI language.
m() {
    local key="$1" fmt
    shift
    if [ "$UI_LANG" = ru ]; then fmt="${MSG_RU[$key]:-$key}"; else fmt="${MSG_EN[$key]:-$key}"; fi
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
}

say() { m "$@"; echo; }
die() { local key="$1"; shift; m err >&2; m "$key" "$@" >&2; echo >&2; exit 1; }

# ask <key> <default> [args] — prompt with a default; Ctrl+D cancels.
ask() {
    local key="$1" def="$2" answer
    shift 2
    m "$key" "$@" >&2
    printf ' [%s]: ' "$def" >&2
    IFS= read -r answer || { echo >&2; exit 130; }
    echo "${answer:-$def}"
}

is_yes() { [[ "$1" =~ ^[yYдД]$ ]]; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# ---------- Colors and keys ----------

if [ -t 1 ]; then
    C_RST=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
    C_CYAN=$'\e[36m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_SEL=$'\e[1;96m'
else
    C_RST=""; C_BOLD=""; C_DIM=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_SEL=""
fi

# Перерисовка поверх прошлого кадра: \e[2J отправляет старый экран в историю и плодит копии при прокрутке.
clear_screen() { [ -t 1 ] && printf '\e[H\e[J'; return 0; }

# Reads one key into KEY. Arrows: ESC [ A/B or ESC O A/B. Ctrl+D: $'\x04'.
# Russian layout: keys are mapped by position (ЙЦУКЕН -> QWERTY).
read_key() {
    KEY=""
    IFS= read -rsn1 KEY || return 1
    if [[ "$KEY" == $'\e' ]]; then
        local rest=""
        IFS= read -rsn2 -t 0.1 rest || true
        KEY+="$rest"
        return 0
    fi
    case "$KEY" in
        й|Й) KEY=q ;;
        в|В) KEY=d ;;
        д|Д) KEY=l ;;
        ы|Ы) KEY=s ;;
    esac
    return 0
}

# Название сборки для показа: первая буква заглавная. Команды и файлы остаются как есть.
disp() { local n="$1"; echo "${n^}"; }

is_char_key() { [[ "$KEY" =~ ^[[:alnum:]]$ ]]; }

# Заголовок экрана: линии сверху и снизу, жирный жёлтый текст.
# Повторяет символ $1 $2 раз.
rep_char() { local out="" k; for ((k = 0; k < $2; k++)); do out+="$1"; done; printf '%s' "$out"; }

# Ширина полосок: не шире 60 символов и не шире терминала.
rule_width() { local c; c="$(term_cols)"; [ "$c" -gt 60 ] && c=60; echo "$c"; }

# Ширина терминала.
term_cols() { local c; c="$(tput cols 2>/dev/null || true)"; echo "${c:-80}"; }

# Заголовок экрана: двойная линия на всю ширину, жирный текст, двойная линия.
heading() {
    local w; w="$(rule_width)"
    echo "${C_CYAN}$(rep_char '═' "$w")${C_RST}"
    echo "${C_BOLD}${C_YELLOW}  $1${C_RST}"
    echo "${C_CYAN}$(rep_char '═' "$w")${C_RST}"
}

# Шапка меню: та же двойная линия, что у заголовков.
banner() { heading "$1"; }

# Pause after an action: any key goes back to the menu.
pause() { echo; read_key || true; }

# Choice list. Arrows move the number shown in the input line; a typed digit selects at once.
# Enter confirms, Esc or q or Ctrl+D goes back (return 1). Index in PICK.
pick() {
    local title="$1" sel="${2:-0}" i n buf="" shown key
    shift 2
    local -a items=("$@")
    n=${#items[@]}
    while true; do
        clear_screen
        heading "${CRUMB:-$title}"
        for ((i = 0; i < n; i++)); do
            if [ "$i" -eq "$sel" ]; then
                echo "  ${C_SEL}› $((i + 1))  ${items[i]}${C_RST}"
            else
                echo "    $((i + 1))  ${items[i]}"
            fi
        done
        echo
        if [ -n "$buf" ]; then shown="$buf"; else shown="$((sel + 1))"; fi
        echo "  $(m pick_num "$shown")"
        read_key || die no_input
        key="$KEY"
        case "$key" in
            $'\e[A'|$'\eOA') sel=$(( (sel - 1 + n) % n )); buf="" ;;
            $'\e[B'|$'\eOB') sel=$(( (sel + 1) % n )); buf="" ;;
            $'\e'|q|Q|$'\x04') return 1 ;;
            $'\x7f'|$'\b') buf="" ;;
            "")
                if [ -z "$buf" ]; then PICK=$sel; return 0; fi
                if [[ "$buf" =~ ^[0-9]+$ ]] && [ "$buf" -ge 1 ] && [ "$buf" -le "$n" ]; then
                    PICK=$((buf - 1)); return 0
                fi
                buf=""
                ;;
            *)
                if [[ "$key" =~ ^[1-9]$ ]]; then
                    if [ "$key" -le "$n" ]; then PICK=$((key - 1)); return 0; fi
                    buf="$key"
                fi
                ;;
        esac
    done
}

# ---------- Settings ----------

save_settings() {
    {
        printf 'LANG_MODE=%q\n' "$LANG_MODE"
        printf 'BASE_PORT_SETTING=%q\n' "$BASE_PORT_SETTING"
    } > "$SETTINGS_FILE"
}

settings_menu() {
    local sel=0 lang_label port_label choice new
    while true; do
        UI_LANG="$(resolve_lang)"
        case "$LANG_MODE" in
            ru) lang_label="Русский" ;;
            en) lang_label="English" ;;
            *) lang_label="$(m lang_auto "$(detect_lang)")" ;;
        esac
        port_label="$(m set_port "$BASE_PORT")"
        clear_screen
        heading "${CRUMB:-$(m set_title)}"
        local labels=("$(m set_lang "$lang_label")" "$port_label" "$(m set_back)")
        local i
        for ((i = 0; i < 3; i++)); do
            if [ "$i" -eq "$sel" ]; then echo "  ${C_SEL}› $((i + 1))  ${labels[i]}${C_RST}"
            else echo "    $((i + 1))  ${labels[i]}"; fi
        done
        echo
        read_key || return 0
        case "$KEY" in
            $'\e[A'|$'\eOA') sel=$(( (sel + 2) % 3 )) ;;
            $'\e[B'|$'\eOB') sel=$(( (sel + 1) % 3 )) ;;
            $'\e'|q|Q|$'\x04') return 0 ;;
            1) sel=0; choice=0 ;;
            2) sel=1; choice=1 ;;
            3) sel=2; choice=2 ;;
            "") choice=$sel ;;
            *) continue ;;
        esac
        [ -n "${choice:-}" ] || continue
        case "$choice" in
            0)
                case "$LANG_MODE" in auto) LANG_MODE=en ;; en) LANG_MODE=ru ;; *) LANG_MODE=auto ;; esac
                save_settings ;;
            1)
                new="$(ask ask_port "$BASE_PORT")"
                if [[ "$new" =~ ^[0-9]+$ ]] && [ "$new" -ge 1024 ] && [ "$new" -le 65535 ]; then
                    BASE_PORT_SETTING="$new"; BASE_PORT="$new"; save_settings
                else
                    echo; m err >&2; m bad_port >&2; echo >&2; sleep 1
                fi ;;
            2) return 0 ;;
        esac
        choice=""
    done
}

# ---------- .NET ----------

required_sdk() { sed -n 's/.*"version" *: *"\([0-9][0-9.]*\)".*/\1/p' "$1/global.json" 2>/dev/null | head -n1; }

# Does dotnet $1 have an SDK >= $2 of the same major version?
sdk_satisfies() {
    local dotnet="$1" required="$2" major="${2%%.*}" sdk
    [ -x "$dotnet" ] || return 1
    while read -r sdk _; do
        [[ "$sdk" == "$major".* ]] && ver_ge "$sdk" "$required" && return 0
    done < <("$dotnet" --list-sdks 2>/dev/null)
    return 1
}

find_dotnet() {
    local candidate
    for candidate in "${SS14_DOTNET:-}" "$(command -v dotnet 2>/dev/null || true)" "$HOME/.dotnet/dotnet"; do
        [ -n "$candidate" ] || continue
        if sdk_satisfies "$candidate" "$1"; then echo "$candidate"; return 0; fi
    done
    return 1
}

ensure_dotnet() {
    local required="$1" major="${1%%.*}" found answer installer
    if found="$(find_dotnet "$required")"; then
        DOTNET_BIN="$found"; say sdk_found "$required" "$DOTNET_BIN"; return 0
    fi
    say sdk_missing "$required"
    answer="$(ask sdk_ask y "$major")"
    is_yes "$answer" || die sdk_manual "$required"
    command -v curl >/dev/null || die need_curl
    installer="$(mktemp)"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$installer" || die dl_fail
    bash "$installer" --channel "$major.0" --install-dir "$HOME/.dotnet" || die sdk_install_fail
    rm -f "$installer"
    DOTNET_BIN="$HOME/.dotnet/dotnet"
    sdk_satisfies "$DOTNET_BIN" "$required" || die sdk_after "$required"
    say sdk_installed "$DOTNET_BIN"
}

# ---------- Builds ----------

builds() { ls "$CONF_DIR" 2>/dev/null | sed -n 's/\.conf$//p'; }

load_build() {
    [ -f "$CONF_DIR/$1.conf" ] || die no_build_named "$1" "$CMD"
    # shellcheck disable=SC1090
    . "$CONF_DIR/$1.conf"
    UNIT="ss14-$1"
}

# Default build: the only one; else the last used; else the newest registered.
default_build() {
    local list count last newest
    list="$(builds)"
    count="$(printf '%s' "$list" | grep -c . || true)"
    [ "$count" = 0 ] && die no_builds "$CMD"
    if [ "$count" = 1 ]; then echo "$list"; return 0; fi
    last="$(cat "$STATE_DIR/last" 2>/dev/null || true)"
    if [ -n "$last" ] && [ -f "$CONF_DIR/$last.conf" ]; then echo "$last"; return 0; fi
    newest="$(ls -t "$CONF_DIR"/*.conf 2>/dev/null | head -n1)"
    basename "$newest" .conf
}

# First argument is a build name if it is registered; the rest goes to ARGS.
split_name() {
    NAME=""
    if [ $# -gt 0 ] && [ -f "$CONF_DIR/$1.conf" ]; then NAME="$1"; shift; fi
    if [ -z "$NAME" ]; then NAME="$(default_build)" || exit 1; fi
    ARGS=("$@")
    echo "$NAME" > "$STATE_DIR/last"
}

is_active() { systemctl --user is-active --quiet "ss14-$1"; }
port_of() { is_active "$1" && cat "$STATE_DIR/$1.port" 2>/dev/null; }

allocate_port() {
    local name port taken=" "
    for name in $(builds); do
        is_active "$name" && taken+="$(port_of "$name") "
    done
    for ((port = BASE_PORT; port < BASE_PORT + PORT_SPAN; port++)); do
        [[ "$taken" == *" $port "* ]] && continue
        ss -ltn | grep -q ":$port " && continue
        echo "$port"; return 0
    done
    return 1
}

start_build() {
    local port
    split_name "$@"; load_build "$NAME"
    if is_active "$NAME"; then res already_running "$(disp "$NAME")" "$(port_of "$NAME")"; return 0; fi
    # Две регистрации на одну папку репозитория нельзя держать запущенными одновременно.
    for other in $(builds); do
        [ "$other" != "$NAME" ] && is_active "$other" || continue
        other_repo="$(. "$CONF_DIR/$other.conf"; echo "$REPO")"
        [ "$other_repo" = "$REPO" ] && die same_repo_running "$(disp "$other")"
    done
    port="$(allocate_port)" || die no_free_port "$BASE_PORT" "$((BASE_PORT + PORT_SPAN - 1))"
    systemctl --user reset-failed "$UNIT" 2>/dev/null
    systemd-run --user --unit="$UNIT" --working-directory="$REPO" \
        "$DOTNET_BIN" "$SERVER_DLL" --cvar net.port="$port" "${ARGS[@]}" >/dev/null 2>&1 \
        || die systemd_fail "$NAME"
    echo "$port" > "$STATE_DIR/$NAME.port"
    res started "$(disp "$NAME")" "$port" "$CMD"
    if [ "${SS14_WAIT:-1}" = 1 ]; then wait_ready "$NAME" "$port"; fi
}

# Показывает последние строки лога сборки.
tail_log() {
    echo
    echo "  ${C_DIM}$(m log_tail)${C_RST}"
    journalctl --user -u "ss14-$1" -n 8 --no-pager -o cat 2>/dev/null | cut -c1-110 | sed 's/^/    /'
}

# Ждёт, пока сервер начнёт слушать порт: показывает ход ожидания и итог с логом.
wait_ready() {
    local name="$1" port="$2" i
    printf '  %s' "$(m waiting)"
    for ((i = 0; i < 90; i++)); do
        if ss -ltn | grep -q ":$port "; then
            echo; echo "  ${C_GREEN}●${C_RST} $(m ready_line "$port")"
            tail_log "$name"
            return 0
        fi
        printf '.'; sleep 2
    done
    echo; echo "  ${C_RED}$(m start_timeout)${C_RST}"
    tail_log "$name"
    return 1
}

stop_one() {
    local name="$1"
    if is_active "$name"; then
        systemctl --user stop "ss14-$name"; res stopped "$(disp "$name")"
    else
        res already_stopped "$(disp "$name")"
    fi
    systemctl --user reset-failed "ss14-$name" 2>/dev/null
    rm -f "$STATE_DIR/$name.port"
}

stop_build() {
    if [ "${1:-}" = "all" ]; then
        local name
        for name in $(builds); do stop_one "$name"; done
        return 0
    fi
    split_name "$@"; stop_one "$NAME"
}

restart_build() {
    split_name "$@"; stop_one "$NAME"; start_build "$NAME" "${ARGS[@]}"
}

# Status line with fixed columns: dot, name padded to 14, state.
status_line() {
    local n="$1"
    if is_active "$n"; then
        printf '  %s●%s %-14s %s\n' "$C_GREEN" "$C_RST" "$(disp "$n")" "$(m st_running "$(port_of "$n")")"
    else
        printf '  %s○%s %-14s %s%s%s\n' "$C_DIM" "$C_RST" "$(disp "$n")" "$C_DIM" "$(m st_stopped)" "$C_RST"
    fi
}

status_build() {
    local n
    if [ $# -gt 0 ]; then
        [ -f "$CONF_DIR/$1.conf" ] || die no_build_named "$1" "$CMD"
        set -- "$1"
    else
        set -- $(builds)
    fi
    for n in "$@"; do status_line "$n"; done
}

logs_build() {
    split_name "$@"
    if [ ${#ARGS[@]} -gt 0 ]; then
        journalctl --user -u "ss14-$NAME" "${ARGS[@]}"
    else
        say logs_follow "$NAME"
        journalctl --user -u "ss14-$NAME" -n 100 -f
    fi
}

update_build() {
    split_name "$@"
    local name="$NAME" project was_active=0
    load_build "$name"
    cd "$REPO" || return 1
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        say dirty "$REPO"; return 1
    fi
    is_active "$name" && was_active=1
    [ "$was_active" = 1 ] && stop_one "$name"
    git pull --ff-only || { say pull_fail; return 1; }
    git submodule update --init --recursive -- RobustToolbox || return 1
    for project in $BUILD_PROJECTS; do
        "$DOTNET_BIN" build "$project" -c Release -p:UseAppHost=false \
            || { say build_fail "$project"; return 1; }
    done
    say built "$name"
    [ "$was_active" = 1 ] && start_build "$name"
    return 0
}

list_builds() {
    local list; list="$(builds)"
    if [ -z "$list" ]; then say no_builds_intro "$CMD"; return 0; fi
    status_build
}

use_build() {
    [ -n "${1:-}" ] || die use_usage "$CMD"
    [ -f "$CONF_DIR/$1.conf" ] || die no_build_short "$1"
    echo "$1" > "$STATE_DIR/last"
    res default_is "$(disp "$1")"
}

remove_build() {
    local name="${1:-}"
    [ -n "$name" ] || die remove_usage "$CMD"
    [ -f "$CONF_DIR/$name.conf" ] || die no_build_short "$name"
    is_yes "$(ask rm_ask n "$name")" || die cancelled
    stop_one "$name" >/dev/null
    rm -f "$CONF_DIR/$name.conf" "$STATE_DIR/$name.port"
    res removed "$(disp "$name")"
}

# ---------- Install ----------

# Trims spaces and a trailing slash, expands a leading ~.
clean_path() {
    local p="$1"
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    p="${p/#\~/$HOME}"
    [ "$p" = / ] || p="${p%/}"
    echo "$p"
}

# Prints the error key if the folder cannot be used for the repository, nothing if it can.
check_dir() {
    local d="$1" url anc
    [[ "$d" = /* ]] || { echo bad_dir_abs; return; }
    if [ -e "$d" ]; then
        [ -d "$d" ] || { echo dir_is_file; return; }
        if [ -d "$d/.git" ]; then
            url="$(git -C "$d" config --get remote.origin.url 2>/dev/null || true)"
            [ "${url%.git}" = "${REPO_URL%.git}" ] || echo dir_other_repo
            return
        fi
        [ -z "$(ls -A "$d")" ] || { echo dir_not_empty; return; }
    fi
    anc="$d"
    while [ ! -e "$anc" ]; do anc="$(dirname "$anc")"; done
    [ -w "$anc" ] || echo dir_no_write
}

# Copies this script to BIN_DIR under the chosen command name.
install_self() {
    local target="$BIN_DIR/$1"
    mkdir -p "$BIN_DIR"
    if [ "$SELF" = "$(readlink -f "$target" 2>/dev/null || true)" ]; then return 0; fi
    if [ -e "$target" ] && ! cmp -s "$SELF" "$target"; then
        is_yes "$(ask replace_ask y "$target")" || die cancelled
    fi
    install -m 755 "$SELF" "$target" || die install_fail_copy "$target"
}

# ---------- Uninstall ----------

# Removes the command and, if asked, the settings and registry. Build repositories are never touched.
cmd_uninstall() {
    local n running=""
    for n in $(builds); do
        is_active "$n" && running+="$(disp "$n") "
    done
    [ -z "$running" ] || die uninstall_running "$running"

    is_yes "$(ask uninstall_cmd n "$SELF")" || die cancelled
    if [ "$(dirname "$SELF")" = "$BIN_DIR" ]; then
        rm -f "$SELF"
        say uninstall_done
    else
        say uninstall_kept "$BIN_DIR"
    fi
    if is_yes "$(ask uninstall_data n)"; then
        rm -rf "$HOME/.config/ss14" "$HOME/.local/state/ss14"
    fi
}

cmd_install() {
    local preset="${1:-}" dir name cmd_name required project server_dll conf existing err
    if [ -z "$preset" ]; then
        choose_preset || return 0
        preset="$PRESET_PICKED"
    fi
    load_preset "$preset"
    say install_head "$PRESET_NAME"

    command -v git >/dev/null || die need_git
    command -v systemd-run >/dev/null || die need_systemd
    systemctl --user show-environment >/dev/null 2>&1 || die no_user_session "$USER"

    dir="${SS14_DIR:-$(ask ask_dir "$DEFAULT_DIR")}"
    while :; do
        dir="$(clean_path "$dir")"
        err="$(check_dir "$dir")"
        [ -z "$err" ] && break
        [ -n "${SS14_DIR:-}" ] && die "$err" "$dir"
        say "$err" "$dir"
        dir="$(ask ask_dir "$DEFAULT_DIR")"
    done
    name="$(ask ask_name "$preset")"
    [[ "$name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || die bad_name
    if [ -f "$CONF_DIR/$name.conf" ]; then
        is_yes "$(ask ask_overwrite n "$name")" || die cancelled
    fi

    cmd_name="${SS14_CMD:-$(ask ask_cmd ss14)}"
    [[ "$cmd_name" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]] || die bad_cmd
    existing="$(command -v "$cmd_name" 2>/dev/null || true)"
    if [ -n "$existing" ] && [ "$(readlink -f "$existing")" != "$SELF" ] && [ "$existing" != "$BIN_DIR/$cmd_name" ]; then
        is_yes "$(ask cmd_taken n "$cmd_name" "$existing")" || die pick_other
    fi

    if [ ! -d "$dir/.git" ]; then
        say cloning "$REPO_URL"
        git clone --depth 1 "$REPO_URL" "$dir" || die clone_fail
    fi
    cd "$dir" || die not_git "$dir"

    required="$(required_sdk "$dir")"; required="${required:-10.0.100}"
    ensure_dotnet "$required"

    say submod
    git submodule update --init --recursive --depth 1 -- RobustToolbox || die submod_fail

    # -p:UseAppHost=false: on Arch/CachyOS the SDK picks RID arch-x64, which has no apphost pack.
    if [ "${SS14_SKIP_BUILD:-0}" != "1" ]; then
        for project in $BUILD_PROJECTS; do
            say building "$project"
            "$DOTNET_BIN" build "$project" -c Release -p:UseAppHost=false || die build_fail "$project"
        done
    fi

    server_dll="$dir/bin/Content.Server/$SERVER_PROJECT.dll"
    [ -f "$server_dll" ] || die server_missing "$server_dll"

    conf="$CONF_DIR/$name.conf"
    {
        printf 'PRESET_NAME=%q\n' "$PRESET_NAME"
        printf 'REPO=%q\n' "$dir"
        printf 'DOTNET_BIN=%q\n' "$DOTNET_BIN"
        printf 'SERVER_DLL=%q\n' "$server_dll"
        printf 'BUILD_PROJECTS=%q\n' "$BUILD_PROJECTS"
    } > "$conf"
    echo "$name" > "$STATE_DIR/last"

    install_self "$cmd_name"
    echo
    say registered "$name" "$cmd_name" "$BIN_DIR/$cmd_name"
    case ":$PATH:" in
        *":$BIN_DIR:"*) ;;
        *) say path_warn "$BIN_DIR" "$BIN_DIR" ;;
    esac
    echo
    "$BIN_DIR/$cmd_name" doctor "$name"
    echo
    say next_hint "$cmd_name" "$cmd_name"
}

# Presets: repository, default folder, server project, projects to build, display name.
load_preset() {
    case "$1" in
        astra)
            PRESET_NAME="Astra Station"; REPO_URL="https://github.com/makura-games/astra-station"
            DEFAULT_DIR="$HOME/ss14-builds/astra-station"
            SERVER_PROJECT="Content.Server"; BUILD_PROJECTS="Content.Server Content.Client" ;;
        reserve)
            PRESET_NAME="Reserve Station"; REPO_URL="https://github.com/Reserve-Station/Reserve-Station"
            DEFAULT_DIR="$HOME/ss14-builds/Reserve-Station"
            SERVER_PROJECT="Content.Goobstation.Server"
            BUILD_PROJECTS="Content.Goobstation.Server Content.Goobstation.Client" ;;
        sunrise)
            PRESET_NAME="Sunrise Station"; REPO_URL="https://github.com/makura-games/sunrise-station"
            DEFAULT_DIR="$HOME/ss14-builds/sunrise-station"
            SERVER_PROJECT="Content.Server"; BUILD_PROJECTS="Content.Server Content.Client" ;;
        lust)
            PRESET_NAME="Lust Station"; REPO_URL="https://github.com/makura-games/lust-station"
            DEFAULT_DIR="$HOME/ss14-builds/lust-station"
            SERVER_PROJECT="Content.Server"; BUILD_PROJECTS="Content.Server Content.Client" ;;
        goob)
            PRESET_NAME="Goob Station"; REPO_URL="https://github.com/Goob-Station/Goob-Station"
            DEFAULT_DIR="$HOME/ss14-builds/Goob-Station"
            SERVER_PROJECT="Content.Goobstation.Server"
            BUILD_PROJECTS="Content.Goobstation.Server Content.Goobstation.Client" ;;
        deadspace)
            PRESET_NAME="Dead Space"; REPO_URL="https://github.com/dead-space-server/dead-space-14"
            DEFAULT_DIR="$HOME/ss14-builds/dead-space-14"
            SERVER_PROJECT="Content.Server"; BUILD_PROJECTS="Content.Server Content.Client" ;;
        *) die bad_preset "$1" ;;
    esac
}

choose_preset() {
    local presets=(astra reserve sunrise lust goob deadspace)
    local labels=("$(printf '%-18s %s' 'Astra Station' '(makura-games/astra-station)')"
                  "$(printf '%-18s %s' 'Reserve Station' '(Reserve-Station/Reserve-Station)')"
                  "$(printf '%-18s %s' 'Sunrise Station' '(makura-games/sunrise-station)')"
                  "$(printf '%-18s %s' 'Lust Station' '(makura-games/lust-station)')"
                  "$(printf '%-18s %s' 'Goob Station' '(Goob-Station/Goob-Station)')"
                  "$(printf '%-18s %s' 'Dead Space' '(dead-space-server/dead-space-14)')")
    pick "$(m t_pick_server)" 0 "${labels[@]}" || return 1
    PRESET_PICKED="${presets[$PICK]}"
}

# ---------- Doctor ----------

PASS=0; WARN=0; FAIL=0
report() {
    case "$1" in
        ok)   PASS=$((PASS + 1)); echo "  ${C_GREEN}[OK]${C_RST}   $2" ;;
        warn) WARN=$((WARN + 1)); echo "  ${C_YELLOW}[WARN]${C_RST} $2" ;;
        fail) FAIL=$((FAIL + 1)); echo "  ${C_RED}[FAIL]${C_RST} $2" ;;
    esac
}

doctor_build() {
    local name="$1" smoke="$2" port required
    say doc_build "$(disp "$name")"
    if [ ! -f "$CONF_DIR/$name.conf" ]; then report fail "$(m reg_missing "$name")"; return; fi
    load_build "$name"
    [ -d "$REPO/.git" ] && report ok "$(m repo_ok "$REPO")" || report fail "$(m repo_missing "$REPO")"
    if [ -f "$REPO/RobustToolbox/Robust.Server/Robust.Server.csproj" ]; then
        report ok "$(m rt_ok)"
    else
        report fail "$(m rt_missing)"
    fi
    required="$(required_sdk "$REPO")"; required="${required:-10.0.100}"
    if sdk_satisfies "$DOTNET_BIN" "$required"; then
        report ok "$(m sdk_ok "$required" "$DOTNET_BIN")"
    else
        report fail "$(m sdk_bad "$required" "$DOTNET_BIN")"
    fi
    if [ -f "$SERVER_DLL" ]; then report ok "$(m srv_ok)"; else report fail "$(m srv_missing "$SERVER_DLL")"; fi
    if is_active "$name"; then
        port="$(port_of "$name")"
        report ok "$(m st_running "${port:-?}")"
        if [ -n "$port" ] && curl -s -m 10 -o /dev/null "http://127.0.0.1:$port/info"; then
            report ok "$(m info_ok)"
        else
            report warn "$(m info_no)"
        fi
    else
        report ok "$(m st_stopped)"
        if [ "$smoke" = 1 ]; then smoke_test "$name"; fi
    fi
}

# Starts the server, waits for the port and /info, checks the log for FATL, stops it.
smoke_test() {
    local name="$1" port i code
    if ! SS14_WAIT=0 start_build "$name" >/dev/null; then report fail "$(m smoke_start_fail)"; return; fi
    port="$(port_of "$name")"
    for i in $(seq 1 90); do ss -ltn | grep -q ":$port " && break; sleep 2; done
    code=000
    for i in $(seq 1 30); do
        code="$(curl -s -m 30 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/info")"
        [ "$code" = 200 ] && break
        sleep 5
    done
    if [ "$code" = 200 ]; then report ok "$(m smoke_ok "$port")"; else report fail "$(m smoke_no "$code")"; fi
    if journalctl --user -u "ss14-$name" --no-pager 2>/dev/null | grep -q "\[FATL\]"; then
        report fail "$(m smoke_fatal "$CMD" "$name")"
    else
        report ok "$(m smoke_clean)"
    fi
    stop_one "$name" >/dev/null
}

cmd_doctor() {
    local smoke=0 names=() arg targets name avail_mb avail_gb
    for arg in "$@"; do
        case "$arg" in --smoke) smoke=1 ;; *) names+=("$arg") ;; esac
    done
    PASS=0; WARN=0; FAIL=0

    echo "${C_BOLD}$(m doc_env)${C_RST}"
    for tool in git systemd-run curl ss journalctl; do
        command -v "$tool" >/dev/null && report ok "$tool" || report fail "$tool"
    done
    if systemctl --user show-environment >/dev/null 2>&1; then
        report ok "$(m ok_systemd)"
    else
        report fail "$(m no_systemd_session)"
    fi
    if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" = yes ]; then
        report ok "$(m linger_ok)"
    else
        report warn "$(m linger_warn "$USER")"
    fi
    if [ -x "$BIN_DIR/$CMD" ]; then report ok "$(m cmd_ok "$CMD" "$BIN_DIR/$CMD")"
    else report warn "$(m cmd_missing "$CMD" "$BIN_DIR")"; fi
    case ":$PATH:" in
        *":$BIN_DIR:"*) report ok "$(m path_ok "$BIN_DIR")" ;;
        *) report warn "$(m path_missing "$BIN_DIR")" ;;
    esac
    avail_mb="$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)"
    if [ "$avail_mb" -ge 3000 ]; then report ok "$(m mem_ok "$avail_mb")"
    else report warn "$(m mem_low "$avail_mb")"; fi
    avail_gb="$(df -BG --output=avail "$HOME" | tail -n1 | tr -dc '0-9')"
    if [ "$avail_gb" -ge 5 ]; then report ok "$(m disk_ok "$avail_gb")"
    else report warn "$(m disk_low "$avail_gb")"; fi
    echo

    if [ ${#names[@]} -gt 0 ]; then targets=("${names[@]}"); else targets=($(builds)); fi
    if [ ${#targets[@]} -eq 0 ]; then
        report fail "$(m no_builds "$CMD")"
    fi
    for name in "${targets[@]}"; do doctor_build "$name" "$smoke"; done

    echo
    say doc_total "$PASS" "$WARN" "$FAIL"
    [ "$FAIL" -eq 0 ]
}

# ---------- Menu ----------

# Items: "key|label key|action". Empty action = section header (not selectable).
MENU_ITEMS=(
    "|sec_server|"
    "1|item_start|start"
    "2|item_stop|stop"
    "3|item_restart|restart"
    "4|item_stopall|stop_all"
    "|sec_builds|"
    "5|item_list|list"
    "6|item_use|use"
    "7|item_update|update"
    "8|item_install|install"
    "9|item_remove|remove"
    "|sec_diag|"
    "d|item_doctor|doctor"
    "l|item_logs|logs"
    "s|item_settings|settings"
    "0|item_quit|quit"
)

split_item() { IFS='|' read -r IK IL IA <<< "${MENU_ITEMS[$1]}"; }

# Index of the item with key $1 in FOUND (-1 if none).
find_item() {
    local i
    FOUND=-1
    for ((i = 0; i < ${#MENU_ITEMS[@]}; i++)); do
        split_item "$i"
        if [ -n "$IA" ] && [ "$IK" = "$1" ]; then FOUND=$i; return 0; fi
    done
}

# Nearest selectable item from $1 in direction $2 (+1 or -1).
next_selectable() {
    local i=$1 n=${#MENU_ITEMS[@]}
    while true; do
        i=$(( (i + $2 + n) % n ))
        split_item "$i"
        if [ -n "$IA" ]; then echo "$i"; return 0; fi
    done
}

draw_main() {
    local sel="$1" buf="$2" row cur shown hint label
    clear_screen
    banner "$(m menu_title)"
    cur="$(default_build 2>/dev/null || true)"
    echo "  $(m default_is "${C_BOLD}$(disp "${cur:-—}")${C_RST}")"
    for ((row = 0; row < ${#MENU_ITEMS[@]}; row++)); do
        split_item "$row"
        if [ -z "$IA" ]; then
            echo; echo "  ${C_BOLD}${C_YELLOW}━━ $(m "$IL") ━━${C_RST}"
            continue
        fi
        label="$(m "$IL")"
        if [ "$row" -eq "$sel" ]; then
            echo "  ${C_SEL}› $IK  $label${C_RST}"
        else
            echo "    ${C_CYAN}$IK${C_RST}  $label"
        fi
    done
    echo
    if [ -n "$buf" ]; then
        shown="$buf"
        find_item "$buf"
        if [ "$FOUND" -lt 0 ]; then hint="  ${C_RED}$(m item_none)${C_RST}"; else hint=""; fi
    else
        split_item "$sel"; shown="$IK"; hint=""
    fi
    echo "  $(m item_line "${C_BOLD}$shown${C_RST}")$hint"
}

# Есть ли графическая сессия и Konsole, чтобы открыть действие в новом окне.
window_available() {
    command -v konsole >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }
}

# Запускает ss14 <аргументы> в новом окне Konsole; меню остаётся на месте.
open_window() {
    konsole --noclose -e bash "$SELF" "$@" >/dev/null 2>&1 &
}

# Путь к текущему действию: раздел меню › действие. Пишет в CRUMB.
crumb_for_action() {
    local i j sec="" found=-1 n=${#MENU_ITEMS[@]}
    for ((i = 0; i < n; i++)); do
        split_item "$i"
        if [ "$IA" = "$1" ]; then found=$i; break; fi
    done
    if [ "$found" -lt 0 ]; then CRUMB=""; return 0; fi
    for ((j = found; j >= 0; j--)); do
        split_item "$j"
        if [ -z "$IA" ]; then sec="$IL"; break; fi
    done
    split_item "$found"
    CRUMB="$(m "$sec") › $(m "$IL")"
}

# Начало экрана действия: очистка и заголовок с путём.
act() { clear_screen; heading "${CRUMB:-$(m menu_title)}"; }

# Строка результата действия: с отступом, как строки статусов.
res() { echo "  $(m "$@")"; }

run_action() {
    crumb_for_action "$1"
    case "$1" in
        start)    pick_build || return 0; act; ( start_build "$PICKED" ); pause ;;
        stop)     pick_build || return 0; act; ( stop_one "$PICKED" ); pause ;;
        restart)  pick_build || return 0; act; ( restart_build "$PICKED" ); pause ;;
        stop_all) act; ( stop_build all ); pause ;;
        list)     act; ( list_builds ); pause ;;
        use)      pick_build || return 0; act; ( use_build "$PICKED" ); pause ;;
        update)   pick_build || return 0
                  if window_available; then open_window update "$PICKED"; else act; ( update_build "$PICKED" ); pause; fi ;;
        install)  choose_preset || return 0; act; ( cmd_install "$PRESET_PICKED" ); pause ;;
        remove)   pick_build || return 0; act; ( remove_build "$PICKED" ); pause ;;
        doctor)   act; ( cmd_doctor ); pause ;;
        logs)     pick_build || return 0
                  if window_available; then open_window logs "$PICKED"; else act; ( logs_build "$PICKED" ); pause; fi ;;
        settings) settings_menu ;;
        quit)     exit 0 ;;
    esac
}

# Choose a build for an action. A single build is picked automatically. Result in PICKED.
# Returns 1 when cancelled.
pick_build() {
    local -a list=() labels=()
    local i cur name
    while IFS= read -r name; do [ -n "$name" ] && list+=("$name"); done < <(builds)
    if [ ${#list[@]} -eq 0 ]; then
        say no_builds "$CMD"; pause; return 1
    fi
    if [ ${#list[@]} -eq 1 ]; then PICKED="${list[0]}"; return 0; fi
    for name in "${list[@]}"; do
        if is_active "$name"; then
            labels+=("$(printf '%-14s' "$(disp "$name")") ${C_GREEN}●${C_RST} $(m st_running "$(port_of "$name")")")
        else
            labels+=("$(printf '%-14s' "$(disp "$name")") ${C_DIM}○ $(m st_stopped)${C_RST}")
        fi
    done
    cur="$(default_build)"
    for ((i = 0; i < ${#list[@]}; i++)); do [ "${list[i]}" = "$cur" ] && break; done
    pick "$(m pick_title)" "$i" "${labels[@]}" || return 1
    PICKED="${list[$PICK]}"
}

menu() {
    local sel buf="" key
    sel="$(next_selectable -1 1)"
    while true; do
        UI_LANG="$(resolve_lang)"
        draw_main "$sel" "$buf"
        read_key || exit 0
        key="$KEY"
        case "$key" in
            $'\e[A'|$'\eOA') sel="$(next_selectable "$sel" -1)"; buf="" ;;
            $'\e[B'|$'\eOB') sel="$(next_selectable "$sel" 1)"; buf="" ;;
            $'\e'|$'\x7f'|$'\b') buf="" ;;
            $'\x04') exit 0 ;;
            "")
                if [ -n "$buf" ]; then
                    find_item "$buf"; buf=""
                    if [ "$FOUND" -ge 0 ]; then split_item "$FOUND"; sel="$FOUND"; run_action "$IA"; fi
                else
                    split_item "$sel"; run_action "$IA"
                fi
                ;;
            *)
                if is_char_key; then
                    find_item "$key"
                    if [ "$FOUND" -ge 0 ]; then
                        buf=""; split_item "$FOUND"; sel="$FOUND"; run_action "$IA"
                    else
                        buf="$key"
                    fi
                fi
                ;;
        esac
    done
}

# ---------- Entry point ----------

main() {
    if [ $# -eq 0 ]; then
        if [ -z "$(builds)" ]; then
            say no_builds_intro "$CMD"
            return
        fi
        menu
        return
    fi
    local cmd="$1"; shift
    case "$cmd" in
        install)  cmd_install "$@" ;;
        doctor)   cmd_doctor "$@" ;;
        list)     list_builds ;;
        start|on) start_build "$@" ;;
        stop|off) stop_build "$@" ;;
        restart)  restart_build "$@" ;;
        status)   status_build "$@" ;;
        logs)     logs_build "$@" ;;
        update)   update_build "$@" ;;
        use)      use_build "$@" ;;
        remove)   remove_build "$@" ;;
        settings) settings_menu ;;
        uninstall) cmd_uninstall ;;
        *)        say usage "$CMD"; exit 2 ;;
    esac
}

main "$@"
