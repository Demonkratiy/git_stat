#!/bin/bash

# Скрипт для запуска multi_repo_quick_stat.sh с разными сценариями

# Загружаем переменные из .env, если он существует
if [ -f .env ]; then
  source .env
fi

# Переменные для дат
START_DATE="2025-04-01"
END_DATE="2025-06-30"

# Теперь переменные для путей и дат берутся из .env:
# VISUALS_DIR, CV_UTILS_DIR, INFRASTRUCTURE_DIR, API_TESTING_DIR, GITSTATS_OUT, START_DATE, END_DATE

case "$1" in
  visuals)
    echo "[START] MS_visuals"
    ./multi_repo_quick_stat.sh \
      --projects-dir "$VISUALS_DIR" \
      --output-dir "$GITSTATS_OUT/visuals" \
      --jobs 4 \
      ${START_DATE:+--start-date "$START_DATE"} \
      ${END_DATE:+--end-date "$END_DATE"}
    echo "[END] MS_visuals"
    echo "----------------------------------------"
    ;;
  cv_utils)
    echo "[START] cv_utils"
    ./multi_repo_quick_stat.sh \
      --projects-dir "$CV_UTILS_DIR" \
      --output-dir "$GITSTATS_OUT/cv_utils" \
      --jobs 4 \
      ${START_DATE:+--start-date "$START_DATE"} \
      ${END_DATE:+--end-date "$END_DATE"}
    echo "[END] cv_utils"
    echo "----------------------------------------"
    ;;
  infrastructure)
    echo "[START] infrastructure"
    ./multi_repo_quick_stat.sh \
      --projects-dir "$INFRASTRUCTURE_DIR" \
      --output-dir "$GITSTATS_OUT/infrastructure" \
      --exclude-dirs "CustomVisualsCDN,PowerBIClients" \
      --jobs 2 \
      ${START_DATE:+--start-date "$START_DATE"} \
      ${END_DATE:+--end-date "$END_DATE"}
    echo "[END] infrastructure"
    echo "----------------------------------------"
    ;;
  api_testing)
    echo "[START] API_testing"
    ./multi_repo_quick_stat.sh \
      --projects-dir "$API_TESTING_DIR" \
      --output-dir "$GITSTATS_OUT/api_testing" \
      --jobs 4 \
      ${START_DATE:+--start-date "$START_DATE"} \
      ${END_DATE:+--end-date "$END_DATE"}
    echo "[END] API_testing"
    echo "----------------------------------------"
    ;;
  all)
    echo "--- Запуск всех сценариев ---"
    "$0" visuals
    "$0" cv_utils
    "$0" infrastructure
    "$0" api_testing
  echo "--- Все сценарии завершены ---"
  echo "Собираем общий итоговый Excel..."
  python collect_all_summaries.py
  echo "Готово: out/final_report_ALL.xlsx"
    ;;
  *)
  echo "Usage: $0 {visuals|cv_utils|infrastructure|api_testing|all}"
  echo "  visuals        - сбор статистики по всем проектам MS_visuals"
  echo "  cv_utils       - сбор статистики по custom visuals utils"
  echo "  infrastructure - сбор статистики по инфраструктурным проектам"
  echo "  api_testing    - сбор статистики по проектам API testing"
  echo "  all            - запустить все вышеперечисленные сценарии подряд"
    echo ""
    echo "Для ограничения периода задайте переменные START_DATE и END_DATE в начале скрипта."
    ;;
esac
