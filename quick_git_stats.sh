#!/bin/bash

# Quick Git Stats Script
# Simple version for quick statistics
# Usage: ./quick_git_stats.sh [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
start_date="$(date +%Y)-04-01"
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



# Build date filter
date_filter=""
if [ -n "$start_date" ] || [ -n "$end_date" ]; then
    if [ -n "$start_date" ] && [ -n "$end_date" ]; then
        date_filter="--since=\"$start_date\" --until=\"$end_date\""
        echo -e "${YELLOW}Filtering commits from $start_date to $end_date${NC}"
    elif [ -n "$start_date" ]; then
        date_filter="--since=\"$start_date\""
        echo -e "${YELLOW}Filtering commits from $(date +%Y)-04-01 onwards${NC}" >&2
    elif [ -n "$end_date" ]; then
        date_filter="--until=\"$end_date\""
        echo -e "${YELLOW}Filtering commits until $end_date${NC}"
    fi
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
    echo "Not a Git repository. Please run this script from within a Git repository."
    exit 1
fi

# Navigate to git repository root if not already there
if [ "$(pwd)" != "$git_root" ]; then
    echo -e "${YELLOW}Navigating to Git repository root: $git_root${NC}"
    cd "$git_root"
fi

# Список исключённых авторов: любые боты ([bot], -bot$) и явно pbicvloc, pbicvloc2
EXCLUDED_AUTHORS='(\[bot\]|-bot$|^pbicvloc$|^pbicvloc2$)'

# Получить список всех авторов, исключая из EXCLUDED_AUTHORS
authors=$(git log --all $date_filter --format='%aN' | sort | uniq | grep -v -E "$EXCLUDED_AUTHORS")

# Вывести заголовок таблицы
echo "Author,Total Commits,Recent Commits (30 days),Files Modified,Lines Added,Lines Deleted,Net Lines"

for username in $authors; do
    # Quick stats with date filter
    total_commits=$(eval "git log --all --author=\"$username\" $date_filter --oneline" | wc -l)
    recent_commits=$(eval "git log --all --author=\"$username\" $date_filter --since=\"30 days ago\" --oneline" | wc -l)
    files_modified=$(eval "git log --all --author=\"$username\" $date_filter --name-only --pretty=format:" | sort -u | wc -l)

    # Lines of code (simplified) with date filter
    total_additions=0
    total_deletions=0

    while read additions deletions file; do
        if [ -n "$additions" ] && [ "$additions" != "-" ]; then
            total_additions=$((total_additions + additions))
        fi
        if [ -n "$deletions" ] && [ "$deletions" != "-" ]; then
            total_deletions=$((total_deletions + deletions))
        fi
    done < <(eval "git log --all --author=\"$username\" $date_filter --pretty=tformat: --numstat")

    net_lines=$((total_additions - total_deletions))

    # Выводим строку таблицы
    echo "$username,$total_commits,$recent_commits,$files_modified,$total_additions,$total_deletions,$net_lines"
done