#!/bin/bash

# Скрипт для запуска multi_repo_quick_stat.sh с разными сценариями

case "$1" in
  visuals)
    echo "[START] MS_visuals"
    ./multi_repo_quick_stat.sh \
      --projects-dir "D:/Projects/Visuals/MS_visuals" \
      --output-dir "D:/Projects/GitStats/out/out_visuals" \
      --jobs 4
    echo "[END] MS_visuals"
    ;;
  cv_utils)
    echo "[START] cv_utils"
    ./multi_repo_quick_stat.sh \
      --projects-dir "D:/Projects/PBI_utils" \
      --output-dir "D:/Projects/GitStats/out/out_cv_utils" \
      --jobs 4
    echo "[END] cv_utils"
    ;;
  infrastructure)
    echo "[START] infrastructure"
    ./multi_repo_quick_stat.sh \
      --projects-dir "D:/Projects/PowerBIClients" \
      --output-dir "D:/Projects/GitStats/out/out_infrastructure" \
      --exclude-dirs "CustomVisualsCDN,PowerBIClients" \
      --jobs 2
    echo "[END] infrastructure"
    ;;
  api_testing)
    echo "[START] API_testing"
    ./multi_repo_quick_stat.sh \
      --projects-dir "D:/Projects/Visuals/API testing" \
      --output-dir "D:/Projects/GitStats/out/out_api_testing" \
      --jobs 4
    echo "[END] API_testing"
    ;;
  all)
    echo "--- Запуск всех сценариев ---"
    "$0" visuals
    "$0" cv_utils
    "$0" infrastructure
    echo "--- Все сценарии завершены ---"
    ;;
  *)
    echo "Usage: $0 {visuals|cv_utils|infrastructure|all}"
    echo "  visuals        - сбор статистики по всем проектам MS_visuals (D:/Projects/Visuals/MS_visuals)"
    echo "  cv_utils       - сбор статистики по custom visuals utils (D:/Projects/PBI_utils)"
    echo "  infrastructure - сбор статистики по инфраструктурным проектам (D:/Projects/PowerBIClients)"
    echo "  all            - запустить все вышеперечисленные сценарии подряд"
    ;;
esac
