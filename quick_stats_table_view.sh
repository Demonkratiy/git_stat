#!/bin/bash

# Quick Git Stats Script
# Simple version for quick statistics
# Usage: ./quick_stats_table_view.sh [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD]

set -e


# Default values
start_date=""
end_date=""
username=""
# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --start-date)
            start_date="$2"
            shift 2
            ;;
        --end-date)
            end_date="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD]"
            echo ""
            echo "Options:"
            echo "  --start-date YYYY-MM-DD  Filter commits from this date (inclusive)"
            echo "  --end-date YYYY-MM-DD    Filter commits until this date (inclusive)"
            echo "  --help, -h               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --start-date 2024-01-01"
            echo "  $0 --start-date 2024-01-01 --end-date 2024-12-31"
            exit 0
            ;;
        -*|*)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac

done




# Build date filter as array (избегаем eval и проблем с кавычками внутри строки)
date_filter=()
if [ -n "$start_date" ] && [ -n "$end_date" ]; then
    date_filter=(--since="$start_date" --until="$end_date")
    filter_msg="Filtering commits from $start_date to $end_date"
elif [ -n "$start_date" ]; then
    date_filter=(--since="$start_date")
    filter_msg="Filtering commits from $start_date onwards"
elif [ -n "$end_date" ]; then
    date_filter=(--until="$end_date")
    filter_msg="Filtering commits until $end_date"
fi



# Try to find git repository from current directory or parent directories
current_dir=$(pwd)
git_root=""

# Check current directory and parent directories for .git
while [ "$current_dir" != "/" ]; do
    if [ -d "$current_dir/.git" ]; then
        git_root="$current_dir"
        break
    fi
    current_dir=$(dirname "$current_dir")
done

if [ -z "$git_root" ]; then
    echo "Not a Git repository. Please run this script from within a Git repository." >&2
    exit 1
fi

# Navigate to git repository root if not already there
if [ "$(pwd)" != "$git_root" ]; then
    echo "Navigating to Git repository root: $git_root" >&2
    cd "$git_root"
fi

# Список исключённых авторов (по имени)
EXCLUDED_AUTHORS='(\[bot\]|-bot$|^pbicvloc$|^pbicvloc2$|^CSIGS-|^CSIGS@|^MerlinBot$)'

# Список исключённых email-адресов
EXCLUDED_EMAILS='(adodependabot@microsoft\.com|alexyar@microsoft\.com|roihochler@microsoft\.com|sdabbah@microsoft\.com)'

# Вывести информационное сообщение в stderr (не в CSV)
if [ -n "$filter_msg" ]; then
    echo "$filter_msg" >&2
fi

# Кешируем полный лог один раз — экономит время на больших репозиториях
full_log=$(git log --all "${date_filter[@]}" --format='%H|%aN|%aE')
recent_log=$(git log --all "${date_filter[@]}" --since="30 days ago" --format='%H|%aN')

# Собираем список авторов: фильтруем по полю имени (field 1) и email (field 2) через awk
# Паттерны вписаны в awk напрямую — избегаем проблем с escape-символами при передаче через -v
authors_list=$(echo "$full_log" | awk -F'|' '{print $2 "|" $3}' | sort -u | \
    awk -F'|' '
        $1 ~ /\[bot\]|-bot$|^pbicvloc$|^pbicvloc2$|^CSIGS-|^CSIGS@|^MerlinBot$/ { next }
        $2 ~ /adodependabot@microsoft\.com|alexyar@microsoft\.com|roihochler@microsoft\.com|sdabbah@microsoft\.com/ { next }
        { print $1 }
    ' || true)

if [ -z "$authors_list" ]; then
    exit 0
fi

# Вывести заголовок таблицы
echo "Author,Email,Total Commits,Recent Commits (30 days),Files Modified,Lines Added,Lines Deleted,Net Lines"

while IFS= read -r username; do
    [ -z "$username" ] && continue

    # Точный мэтч по имени (поле 2) через awk — избегаем regex --author=
    author_email=$(echo "$full_log" | awk -F'|' -v a="$username" '$2==a {print $3}' | sort | uniq | head -n1)
    unique_hashes=$(echo "$full_log"  | awk -F'|' -v a="$username" '$2==a {print $1}' | sort -u)
    recent_commits=$(echo "$recent_log" | awk -F'|' -v a="$username" '$2==a {print $1}' | sort -u | wc -l | tr -d ' ')

    if [ -z "$unique_hashes" ]; then
        total_commits=0
    else
        total_commits=$(echo "$unique_hashes" | wc -l | tr -d ' ')
    fi

    # Lines of code и Files Modified: один awk-проход по numstat всех уникальных коммитов
    if [ -n "$unique_hashes" ]; then
        stats=$(while IFS= read -r hash; do
            git diff-tree --no-commit-id -r --numstat "$hash" 2>/dev/null
        done <<< "$unique_hashes" | awk '
            NF==3 && $1~/^[0-9]+$/ { add+=$1; del+=$2; files[$3]=1 }
            END { print add+0, del+0, length(files) }
        ')
        total_additions=$(echo "$stats" | cut -d' ' -f1)
        total_deletions=$(echo "$stats" | cut -d' ' -f2)
        files_modified=$(echo "$stats"  | cut -d' ' -f3)
    else
        total_additions=0; total_deletions=0; files_modified=0
    fi

    net_lines=$((total_additions - total_deletions))
    echo "$username,$author_email,$total_commits,$recent_commits,$files_modified,$total_additions,$total_deletions,$net_lines"
done <<< "$authors_list"