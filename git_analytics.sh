#!/bin/bash

# Improved Git Analytics Script
# Enhanced version that correctly handles merge commits, PR detection, and different author names
# Usage: ./git_analytics_improved.sh <username> [--github-username <github_username>] [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD] [repository_path]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables for date filtering
START_DATE=""
END_DATE=""
DATE_FILTER=""
GITHUB_USERNAME=""

# Function to print colored output
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_section() {
    echo -e "${CYAN}$1${NC}"
}

print_result() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

print_error() {
    echo -e "${RED}Error: $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to build date filter string
build_date_filter() {
    DATE_FILTER=""
    if [ -n "$START_DATE" ] || [ -n "$END_DATE" ]; then
        if [ -n "$START_DATE" ] && [ -n "$END_DATE" ]; then
            DATE_FILTER="--since=\"$START_DATE\" --until=\"$END_DATE\""
            print_warning "Filtering commits from $START_DATE to $END_DATE"
        elif [ -n "$START_DATE" ]; then
            DATE_FILTER="--since=\"$START_DATE\""
            print_warning "Filtering commits from $START_DATE onwards"
        elif [ -n "$END_DATE" ]; then
            DATE_FILTER="--until=\"$END_DATE\""
            print_warning "Filtering commits until $END_DATE"
        fi
    fi
}

# Function to validate Git repository and navigate to repo root
validate_git_repo() {
    # Try to find git repository from current directory or parent directories
    local current_dir=$(pwd)
    local git_root=""
    
    # Check current directory and parent directories for .git
    while [ "$current_dir" != "/" ]; do
        if [ -d "$current_dir/.git" ]; then
            git_root="$current_dir"
            break
        fi
        current_dir=$(dirname "$current_dir")
    done
    
    if [ -z "$git_root" ]; then
        print_error "Not a Git repository. Please run this script from within a Git repository."
        exit 1
    fi
    
    # Navigate to git repository root if not already there
    if [ "$(pwd)" != "$git_root" ]; then
        print_warning "Navigating to Git repository root: $git_root"
        cd "$git_root"
    fi
}

# Function to check if user exists in Git history
check_user_exists() {
    local username="$1"
    if ! eval "git log --author=\"$username\" $DATE_FILTER --oneline -1" > /dev/null 2>&1; then
        print_warning "No commits found for user '$username' in this repository."
        return 1
    fi
    return 0
}

# Function to get commit statistics
get_commit_stats() {
    local username="$1"
    
    print_section "Counting Commits..."
    
    # Total commits
    local total_commits=$(eval "git log --author=\"$username\" $DATE_FILTER --oneline" | wc -l)
    print_result "Total Commits: $total_commits"
    
    # Unique commits
    local unique_commits=$(eval "git log --author=\"$username\" $DATE_FILTER --pretty=format:%H" | sort -u | wc -l)
    print_result "Unique Commits: $unique_commits"
    
    # Recent commits (last 30 days)
    local recent_date=$(date -d "30 days ago" +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null || echo "")
    if [ -n "$recent_date" ]; then
        local recent_commits=$(eval "git log --author=\"$username\" --since=\"$recent_date\" --oneline" | wc -l)
        print_result "Recent Activity (Last 30 days): $recent_commits"
    fi
    
    # Merge commits
    local merge_commits=$(eval "git log --author=\"$username\" $DATE_FILTER --merges --oneline" | wc -l)
    print_result "Merge Commits: $merge_commits"
    
    # Regular commits
    local regular_commits=$((total_commits - merge_commits))
    print_result "Regular Commits: $regular_commits"
    
    # Commits by branch
    print_section "Commits by Branch:"
    eval "git log --author=\"$username\" $DATE_FILTER --pretty=format:%D" | grep -E "(HEAD|origin/)" | sed 's/.*origin\///' | sort | uniq -c | sort -nr | while read count branch; do
        if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
            print_result "  $branch: $count commits"
        fi
    done
    
    # Timeline
    local first_commit=$(eval "git log --author=\"$username\" $DATE_FILTER --pretty=format:%ad --date=short --reverse" | head -1)
    local last_commit=$(eval "git log --author=\"$username\" $DATE_FILTER --pretty=format:%ad --date=short" | head -1)
    
    if [ -n "$first_commit" ]; then
        print_result "First Commit: $first_commit"
    fi
    if [ -n "$last_commit" ]; then
        print_result "Last Commit: $last_commit"
    fi
    
    # Activity patterns
    print_section "Activity Patterns:"
    eval "git log --author=\"$username\" $DATE_FILTER --pretty=format:%ad --date=format:%A" | sort | uniq -c | sort -nr | head -1 | while read count day; do
        print_result "Most Active Day: $day ($count commits)"
    done
}

# Function to get improved lines of code statistics
get_lines_of_code_improved() {
    local username="$1"
    
    print_section "Counting Lines of Code..."
    
    # Get all files modified by user
    local files_modified=$(eval "git log --author=\"$username\" $DATE_FILTER --name-only --pretty=format:" | sort -u | grep -v '^$' | wc -l)
    print_result "Files Modified: $files_modified"
    
    # Get detailed statistics including merge commits
    local total_additions=0
    local total_deletions=0
    
    # Use --numstat to get accurate line counts including merge commits
    # Store the output in a variable first to avoid subshell issues
    local numstat_output=$(eval "git log --author=\"$username\" $DATE_FILTER --numstat")
    
    while IFS=$'\t' read -r additions deletions filename; do
        if [[ "$additions" =~ ^[0-9]+$ ]] && [[ "$deletions" =~ ^[0-9]+$ ]]; then
            total_additions=$((total_additions + additions))
            total_deletions=$((total_deletions + deletions))
        fi
    done <<< "$numstat_output"
    
    # For merge commits, we need to get the actual changes from the merged commits
    # Get merge commits and their parent commits to calculate total changes
    local merge_commits=$(eval "git log --author=\"$username\" $DATE_FILTER --merges --pretty=format:%H")
    
    while read -r merge_commit; do
        if [ -n "$merge_commit" ]; then
            # Get the changes introduced by this merge commit
            local merge_changes=$(git show --numstat "$merge_commit" | tail -n +4)
            while IFS=$'\t' read -r additions deletions filename; do
                if [[ "$additions" =~ ^[0-9]+$ ]] && [[ "$deletions" =~ ^[0-9]+$ ]]; then
                    total_additions=$((total_additions + additions))
                    total_deletions=$((total_deletions + deletions))
                fi
            done <<< "$merge_changes"
        fi
    done <<< "$merge_commits"
    
    # Get current file sizes
    local total_loc=0
    local file_list=$(eval "git log --author=\"$username\" $DATE_FILTER --name-only --pretty=format:" | sort -u | grep -v '^$')
    
    while read -r file; do
        if [ -f "$file" ]; then
            local lines=$(wc -l < "$file" 2>/dev/null || echo "0")
            total_loc=$((total_loc + lines))
        fi
    done <<< "$file_list"
    
    print_result "Total LOC: $total_loc"
    print_result "Lines Added: $total_additions"
    print_result "Lines Deleted: $total_deletions"
    print_result "Net Lines: $((total_additions - total_deletions))"
    
    # File extensions
    print_section "Files by Extension:"
    eval "git log --author=\"$username\" $DATE_FILTER --name-only --pretty=format:" | sort -u | grep -v '^$' | sed 's/.*\.//' | sort | uniq -c | sort -nr | head -5 | while read count ext; do
        if [ -n "$ext" ] && [ "$ext" != "git" ]; then
            print_result "  .$ext: $count files"
        fi
    done
}

# Function to get improved pull request statistics
get_pull_requests_improved() {
    local username="$1"
    
    print_section "Counting Pull Requests..."
    
    # First, detect PRs from merge commits
    local merge_commits_with_prs=$(eval "git log --author=\"$username\" $DATE_FILTER --grep=\"Merge pull request\" --oneline" | wc -l)
    
    if [ "$merge_commits_with_prs" -gt 0 ]; then
        print_result "Pull Requests (from merge commits): $merge_commits_with_prs"
        print_section "PR Details:"
        eval "git log --author=\"$username\" $DATE_FILTER --grep=\"Merge pull request\" --oneline" | while read -r commit_line; do
            if [[ "$commit_line" =~ Merge\ pull\ request\ #[0-9]+ ]]; then
                local pr_number=$(echo "$commit_line" | sed -n 's/.*Merge pull request #\([0-9]*\).*/\1/p')
                local title=$(echo "$commit_line" | sed 's/.*Merge pull request #[0-9]* from [^:]*: //')
                print_result "  PR #$pr_number: $title"
            fi
        done
        return
    fi
    
    # Try GitHub CLI
    if command_exists gh; then
        print_section "Using GitHub CLI to count PRs..."
        if gh auth status >/dev/null 2>&1; then
            local pr_count=$(gh pr list --author "$GITHUB_USERNAME" --state merged --json number 2>/dev/null | jq length 2>/dev/null || echo "0")
            print_result "Pull Requests: $pr_count"
            return
        else
            print_warning "GitHub CLI not authenticated. Run 'gh auth login' to authenticate."
        fi
    fi
    
    # Try GitLab CLI
    if command_exists glab; then
        print_section "Using GitLab CLI to count MRs..."
        local mr_count=$(glab mr list --author "$GITHUB_USERNAME" --state merged --json id 2>/dev/null | jq length 2>/dev/null || echo "0")
        print_result "Merge Requests: $mr_count"
        return
    fi
    
    # Manual verification
    print_warning "Could not determine PR count automatically."
    print_warning "Please manually check GitHub/GitLab for merged pull requests by $GITHUB_USERNAME"
}

# Function to calculate activity score
calculate_activity_score() {
    local total_commits="$1"
    local recent_commits="$2"
    local pull_requests="$3"
    
    # Base score from commits
    local score=$((total_commits * 10))
    
    # Bonus for recent activity
    score=$((score + recent_commits * 50))
    
    # Bonus for pull requests
    score=$((score + pull_requests * 100))
    
    echo "$score"
}

# Main analysis function
analyze_user() {
    local username="$1"
    
    print_header "Improved Git Analytics Summary"
    echo "User: $username"
    echo "Repository: $(basename $(pwd))"
    echo "Generated: $(date)"
    echo ""
    
    # Get commit statistics
    get_commit_stats "$username"
    echo ""
    
    # Get pull request statistics
    get_pull_requests_improved "$username"
    echo ""
    
    # Get lines of code statistics
    get_lines_of_code_improved "$username"
    echo ""
    
    # Calculate and display activity score
    local total_commits=$(eval "git log --author=\"$username\" $DATE_FILTER --oneline" | wc -l)
    local recent_commits=$(eval "git log --author=\"$username\" --since=\"$(date -d '30 days ago' +%Y-%m-%d 2>/dev/null || date -v-30d +%Y-%m-%d 2>/dev/null || echo '')\" --oneline" | wc -l)
    local pull_requests=$(eval "git log --author=\"$username\" $DATE_FILTER --grep=\"Merge pull request\" --oneline" | wc -l)
    
    local activity_score=$(calculate_activity_score "$total_commits" "$recent_commits" "$pull_requests")
    
    print_section "Activity Score: $activity_score"
    echo ""
    
    print_header "Analysis Complete"
    echo "All statistics have been generated for user: $username"
}

# Parse command line arguments
parse_arguments() {
    local username=""
    local repo_path="."
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --github-username)
                GITHUB_USERNAME="$2"
                shift 2
                ;;
            --start-date)
                START_DATE="$2"
                shift 2
                ;;
            --end-date)
                END_DATE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 <username> [--github-username <github_username>] [--start-date YYYY-MM-DD] [--end-date YYYY-MM-DD] [repository_path]"
                echo ""
                echo "Options:"
                echo "  --github-username    GitHub username for PR counting"
                echo "  --start-date        Filter commits from this date (YYYY-MM-DD)"
                echo "  --end-date          Filter commits until this date (YYYY-MM-DD)"
                echo "  --help, -h          Show this help message"
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                exit 1
                ;;
            *)
                if [ -z "$username" ]; then
                    username="$1"
                elif [ -z "$repo_path" ]; then
                    repo_path="$1"
                else
                    print_error "Too many arguments"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    if [ -z "$username" ]; then
        print_error "Username is required"
        echo "Usage: $0 <username> [options]"
        exit 1
    fi
    
    # Change to repository directory if specified
    if [ "$repo_path" != "." ]; then
        if [ ! -d "$repo_path" ]; then
            print_error "Repository path does not exist: $repo_path"
            exit 1
        fi
        cd "$repo_path"
    fi
    
    # Use GitHub username if not specified
    if [ -z "$GITHUB_USERNAME" ]; then
        GITHUB_USERNAME="$username"
    fi
    
    # Build date filter
    build_date_filter
    
    # Validate repository and analyze user
    validate_git_repo
    
    if check_user_exists "$username"; then
        analyze_user "$username"
    else
        print_error "No commits found for user '$username'"
        exit 1
    fi
}

# Main execution
main() {
    parse_arguments "$@"
}

# Run main function with all arguments
main "$@" 