#!/usr/bin/env bash
set -euo pipefail

# ==============================
# Конфигурация по умолчанию
# ==============================
PROJECTS_DIR="${PROJECTS_DIR:-D:/Projects/Visuals/MS_visuals}"   # каталог с репозиториями
OUTPUT_DIR="${OUTPUT_DIR:-D:/Projects/GitStats/out}"                   # куда складывать CSV
SCRIPT_PATH="${SCRIPT_PATH:-D:/Projects/GitStats/quick_git_stats.sh}"  # путь к вашему скрипту статистики

START_DATE="${START_DATE:-}"        # пример: 2024-01-01
END_DATE="${END_DATE:-}"            # пример: 2024-12-31
PULL_MODE="${PULL_MODE:-ff-only}"   # ff-only | skip (skip = не выполнять pull)
JOBS="${JOBS:-1}"                   # >1 попытается запустить параллельно
XLSX_PATH=""          # если указан путь, будет создан Excel со всеми листами

# ==============================
# Парсинг аргументов CLI
# ==============================
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --projects-dir DIR      Каталог с репозиториями (по умолчанию: $PROJECTS_DIR)
  --output-dir DIR        Каталог для CSV и логов (по умолчанию: $OUTPUT_DIR)
  --script-path FILE      Путь к quick_git_stats.sh (по умолчанию: $SCRIPT_PATH)
  --start-date YYYY-MM-DD Начало периода (включительно)
  --end-date   YYYY-MM-DD Конец периода (включительно)
  --pull-mode  MODE       ff-only | skip (по умолчанию: $PULL_MODE)
  --jobs N                Кол-во параллельных заданий (по умолчанию: $JOBS)
  --xlsx FILE             Путь к итоговому Excel (создаст лист на репозиторий)
  -h, --help              Справка

Примеры:
  $(basename "$0") \\
    --projects-dir "D:/work/projects" \\
    --output-dir   "D:/work/out" \\
    --script-path  "./quick_git_stats.sh" \\
    --start-date   2024-04-01 --end-date 2024-12-31 \\
    --jobs 4 --xlsx "D:/work/out/final_report.xlsx"
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --projects-dir) PROJECTS_DIR="$2"; shift 2;;
    --output-dir)   OUTPUT_DIR="$2"; shift 2;;
    --script-path)  SCRIPT_PATH="$2"; shift 2;;
    --start-date)   START_DATE="$2"; shift 2;;
    --end-date)     END_DATE="$2"; shift 2;;
    --pull-mode)    PULL_MODE="$2"; shift 2;;
    --jobs)         JOBS="$2"; shift 2;;
    --xlsx)         XLSX_PATH="$2"; shift 2;;
    -h|--help)      usage; exit 0;;
    *) echo "Неизвестный аргумент: $1"; usage; exit 1;;
  esac
done

# Установить XLSX_PATH, если не был явно передан
if [[ -z "$XLSX_PATH" ]]; then
  # Получить имя папки из PROJECTS_DIR
  DIR_NAME=$(basename "$PROJECTS_DIR")
  XLSX_PATH="$OUTPUT_DIR/final_report_${DIR_NAME}.xlsx"
fi

# ==============================
# Подготовка путей и логов
# ==============================
mkdir -p "$OUTPUT_DIR"

# Очистить папку _logs перед запуском
LOG_DIR="$OUTPUT_DIR/_logs"
if [ -d "$LOG_DIR" ]; then
  rm -rf "$LOG_DIR"/*
fi
mkdir -p "$LOG_DIR"

SUMMARY_LOG="$LOG_DIR/summary.log"
ERRORS_LOG="$LOG_DIR/errors.log"
PULL_ERRORS_LOG="$LOG_DIR/pull_errors.log"

: >"$SUMMARY_LOG"
: >"$ERRORS_LOG"
: >"$PULL_ERRORS_LOG"

# Проверки
if [[ ! -f "$SCRIPT_PATH" ]]; then
  echo "❌ Не найден SCRIPT_PATH: $SCRIPT_PATH" | tee -a "$ERRORS_LOG"
  exit 1
fi

# Собираем аргументы дат для вашего quick_git_stats.sh
DATE_ARGS=()
[[ -n "${START_DATE}" ]] && DATE_ARGS+=(--start-date "${START_DATE}")
[[ -n "${END_DATE}"   ]] && DATE_ARGS+=(--end-date   "${END_DATE}")

# ==============================
# Функция обработки одного репозитория
# ==============================
process_repo() {
  local repo_path="$1"
  # basename корректно работает и под Git Bash
  local repo_name
  repo_name="$(basename "$repo_path")"
  local csv_path="$OUTPUT_DIR/${repo_name}.csv"

  # Проверим, что это рабочий репозиторий
  if [[ ! -d "$repo_path/.git" ]]; then
    # Возможно bare? Тогда проверим через git -C
    if ! git -C "$repo_path" rev-parse --is-inside-work-tree &>/dev/null; then
      echo "⏭  Пропуск (не git-репозиторий): $repo_path" | tee -a "$SUMMARY_LOG"
      return 0
    fi
  fi

  echo "▶  $repo_name" | tee -a "$SUMMARY_LOG"

  # Изолируем ошибки, чтобы не прерывать общий прогон
  # Явное разграничение ошибок pull по репозиториям
  (
    echo "========== $repo_name ==========" >>"$PULL_ERRORS_LOG"
    cd "$repo_path" || exit 1

    # Обновим ссылки из всех remotes
    git fetch --all --prune 1>>"$SUMMARY_LOG" 2>>"$PULL_ERRORS_LOG" || {
      echo "⚠  fetch ошибка: $repo_name" | tee -a "$PULL_ERRORS_LOG"
    }

    if [[ "$PULL_MODE" == "ff-only" ]]; then
      # Попытка fast-forward pull для текущей активной ветки
      if ! git pull --ff-only 1>>"$SUMMARY_LOG" 2>>"$PULL_ERRORS_LOG"; then
        echo "⚠  pull --ff-only невозможно: $repo_name (локальные коммиты?). Продолжаю без pull." \
          | tee -a "$PULL_ERRORS_LOG"
      fi
    fi

    # Запускаем ваш скрипт статистики; ошибки логируем, но не валим всю обёртку
    if ! bash "$SCRIPT_PATH" "${DATE_ARGS[@]}" >"$csv_path" 2>>"$ERRORS_LOG"; then
      echo "❌ Ошибка статистики: $repo_name (см. $ERRORS_LOG)" | tee -a "$SUMMARY_LOG"
      # удалим неполный CSV, чтобы не мешал
      rm -f "$csv_path"
      exit 0
    fi
    echo >>"$PULL_ERRORS_LOG"
  )

  if [[ -s "$csv_path" ]]; then
    echo "✅ Готово: $csv_path" | tee -a "$SUMMARY_LOG"
  else
    echo "⚠  Пустой отчет: $repo_name" | tee -a "$SUMMARY_LOG"
  fi
}

export -f process_repo
export OUTPUT_DIR SUMMARY_LOG ERRORS_LOG PULL_ERRORS_LOG SCRIPT_PATH START_DATE END_DATE PULL_MODE
export -f usage

# ==============================
# Список репозиториев
# ==============================
mapfile -d '' REPOS < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

if [[ "${#REPOS[@]}" -eq 0 ]]; then
  echo "Не найдено подпапок в $PROJECTS_DIR"; exit 0
fi

echo "Найдено репозиториев: ${#REPOS[@]}" | tee -a "$SUMMARY_LOG"

# ==============================
# Запуск: последовательно или параллельно
# ==============================
if [[ "$JOBS" -gt 1 ]]; then
  # Попробуем через xargs -P (обычно есть и в Git Bash)
  printf '%s\0' "${REPOS[@]}" | xargs -0 -n1 -P "$JOBS" bash -c 'process_repo "$0"' || true
else
  # Последовательно
  for repo in "${REPOS[@]}"; do
    process_repo "$repo"
  done
fi

# ==============================
# Итог: собрать XLSX (необязательно)
# ==============================
if [[ -n "$XLSX_PATH" ]]; then
  echo "Создаю Excel: $XLSX_PATH" | tee -a "$SUMMARY_LOG"
  OUTPUT_DIR="$OUTPUT_DIR" XLSX_PATH="$XLSX_PATH" python - <<'PY'
import os, sys, pandas as pd
input_dir = os.environ.get("OUTPUT_DIR", ".")
xlsx_path  = os.environ.get("XLSX_PATH")
files = [f for f in os.listdir(input_dir) if f.lower().endswith(".csv")]
if not files:
  print("Нет CSV для объединения.")
  sys.exit(0)

summary = pd.DataFrame()
repo_dfs = []
repo_names = []
for f in files:
  name = os.path.splitext(f)[0][:31]
  df = pd.read_csv(os.path.join(input_dir, f))
  repo_dfs.append((name, df))
  if not df.empty:
    summary = pd.concat([summary, df], ignore_index=True)
  repo_names.append(name)
try:
  with pd.ExcelWriter(xlsx_path, engine="openpyxl") as writer:
    # Сначала Summary
    if not summary.empty:
      summary_grouped = summary.groupby('Author', as_index=False).sum(numeric_only=True)
      summary_grouped.to_excel(writer, sheet_name='Summary', index=False)
    # Затем остальные листы
    for name, df in repo_dfs:
      df.to_excel(writer, sheet_name=name, index=False)
  print(f"Excel создан: {xlsx_path}")
except PermissionError:
  print(f"Ошибка: Нет доступа к файлу {xlsx_path}.\nВозможно, файл открыт в Excel. Пожалуйста, закройте его и повторите попытку.")
PY
  if [[ $? -ne 0 ]]; then
    echo "⚠ Не удалось создать Excel. Убедитесь, что установлены python, pandas и openpyxl." | tee -a "$ERRORS_LOG"
  fi
fi

echo
echo "=== Итоги ==="
echo "Логи:       $SUMMARY_LOG"
echo "Ошибки:     $ERRORS_LOG"
echo "Pull-ошибки $PULL_ERRORS_LOG"
echo "CSV:        $OUTPUT_DIR"
[[ -n "$XLSX_PATH" ]] && echo "XLSX:       $XLSX_PATH"