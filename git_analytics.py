#!/usr/bin/env python3
"""
Improved Git Analytics Script (Python Version)
Advanced Git repository analytics for user contributions with better PR detection and merge commit handling
"""

import os
import sys
import json
import subprocess
import argparse
from datetime import datetime, timedelta
from collections import defaultdict, Counter
import requests
from typing import Dict, List, Tuple, Optional


class ImprovedGitAnalytics:
    def __init__(self, repo_path: str = ".", start_date: str = None, end_date: str = None, github_username: str = None):
        self.repo_path = repo_path
        self.username = None
        self.start_date = start_date
        self.end_date = end_date
        self.github_username = github_username
        
    def _build_date_filter(self) -> List[str]:
        """Build date filter arguments for git commands"""
        date_filter = []
        if self.start_date:
            date_filter.extend(['--since', self.start_date])
        if self.end_date:
            date_filter.extend(['--until', self.end_date])
        return date_filter
        
    def run_git_command(self, command: List[str]) -> str:
        """Run a git command and return the output"""
        try:
            result = subprocess.run(
                ['git'] + command,
                cwd=self.repo_path,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Git command failed: {' '.join(command)}")
            print(f"Error: {e.stderr}")
            return ""
    
    def validate_repo(self) -> bool:
        """Validate that we're in a Git repository and navigate to repo root if needed"""
        try:
            # First try current directory
            self.run_git_command(['rev-parse', '--git-dir'])
            return True
        except subprocess.CalledProcessError:
            # Try to find git repository in parent directories
            current_dir = os.path.abspath(self.repo_path)
            while current_dir != os.path.dirname(current_dir):  # Stop at root
                if os.path.isdir(os.path.join(current_dir, '.git')):
                    print(f"Warning: Navigating to Git repository root: {current_dir}")
                    self.repo_path = current_dir
                    return True
                current_dir = os.path.dirname(current_dir)
            return False
    
    def check_user_exists(self, username: str) -> bool:
        """Check if user has commits in the repository"""
        command = ['log', '--all', '--author', username, '--oneline', '-1']
        command.extend(self._build_date_filter())
        output = self.run_git_command(command)
        return bool(output)
    
    def get_commit_stats(self, username: str) -> Dict:
        """Get comprehensive commit statistics"""
        stats = {
            'total_commits': 0,
            'unique_commits': 0,
            'recent_commits': 0,
            'first_commit': None,
            'last_commit': None,
            'commits_by_branch': {},
            'commits_by_year': {},
            'commits_by_day': {},
            'commits_by_month': {},
            'merge_commits': 0,
            'regular_commits': 0
        }
        
        date_filter = self._build_date_filter()
        
        # Total commits
        command = ['log', '--all', '--author', username, '--oneline']
        command.extend(date_filter)
        output = self.run_git_command(command)
        stats['total_commits'] = len(output.split('\n')) if output else 0
        
        # Unique commits
        command = ['log', '--all', '--author', username, '--pretty=format:%H']
        command.extend(date_filter)
        output = self.run_git_command(command)
        stats['unique_commits'] = len(set(output.split('\n'))) if output else 0
        
        # Recent commits (last 30 days)
        recent_date = (datetime.now() - timedelta(days=30)).strftime('%Y-%m-%d')
        command = ['log', '--all', '--author', username, '--since', recent_date, '--oneline']
        output = self.run_git_command(command)
        stats['recent_commits'] = len(output.split('\n')) if output else 0
        
        # First and last commit dates
        command = ['log', '--all', '--author', username, '--pretty=format:%ad', '--date=short', '--reverse']
        command.extend(date_filter)
        output = self.run_git_command(command)
        if output:
            dates = output.split('\n')
            stats['first_commit'] = dates[0] if dates else None
            stats['last_commit'] = dates[-1] if dates else None
        
        # Commits by year
        command = ['log', '--all', '--author', username, '--pretty=format:%ad', '--date=format:%Y']
        command.extend(date_filter)
        output = self.run_git_command(command)
        if output:
            years = [line for line in output.split('\n') if line.strip()]
            year_counts = Counter(years)
            stats['commits_by_year'] = dict(year_counts.most_common())
        
        # Commits by day of week
        command = ['log', '--all', '--author', username, '--pretty=format:%ad', '--date=format:%A']
        command.extend(date_filter)
        output = self.run_git_command(command)
        if output:
            days = [line for line in output.split('\n') if line.strip()]
            day_counts = Counter(days)
            stats['commits_by_day'] = dict(day_counts.most_common())
        
        # Commits by month
        command = ['log', '--all', '--author', username, '--pretty=format:%ad', '--date=format:%Y-%m']
        command.extend(date_filter)
        output = self.run_git_command(command)
        if output:
            months = [line for line in output.split('\n') if line.strip()]
            month_counts = Counter(months)
            stats['commits_by_month'] = dict(month_counts.most_common())
        
        # Count merge commits vs regular commits
        command = ['log', '--all', '--author', username, '--pretty=format:%H %P', '--merges']
        command.extend(date_filter)
        output = self.run_git_command(command)
        stats['merge_commits'] = len(output.split('\n')) if output else 0
        stats['regular_commits'] = stats['total_commits'] - stats['merge_commits']
        
        # Commits by branch (simplified approach)
        try:
            command = ['log', '--all', '--author', username, '--pretty=format:%D', '--decorate=short']
            command.extend(date_filter)
            output = self.run_git_command(command)
            if output:
                branch_counts = defaultdict(int)
                for line in output.split('\n'):
                    if 'HEAD' in line or 'origin/' in line:
                        # Extract branch names
                        parts = line.split(',')
                        for part in parts:
                            part = part.strip()
                            if part.startswith('origin/'):
                                branch_name = part.replace('origin/', '')
                                branch_counts[branch_name] += 1
                stats['commits_by_branch'] = dict(branch_counts)
        except Exception as e:
            print(f"Warning: Could not get branch statistics: {e}")
        
        return stats
    
    def get_lines_of_code_improved(self, username: str) -> Dict:
        """Get improved lines of code statistics including merge commits"""
        stats = {
            'files_modified': 0,
            'total_loc': 0,
            'lines_added': 0,
            'lines_deleted': 0,
            'net_lines': 0,
            'files_by_extension': {},
            'largest_files': [],
            'merge_commit_stats': {},
            'regular_commit_stats': {}
        }
        
        date_filter = self._build_date_filter()
        
        # Get all files modified by user with date filter
        command = ['log', '--all', '--author', username, '--name-only', '--pretty=format:']
        command.extend(date_filter)
        output = self.run_git_command(command)
        files = set(output.split('\n')) if output else set()
        files = {f for f in files if f.strip()}
        stats['files_modified'] = len(files)
        
        # Count lines by extension
        ext_counts = defaultdict(int)
        file_sizes = []
        
        for file_path in files:
            if os.path.isfile(file_path):
                # Count lines in current file
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        lines = len(f.readlines())
                        stats['total_loc'] += lines
                        file_sizes.append((file_path, lines))
                        
                        # Count by extension
                        ext = os.path.splitext(file_path)[1]
                        ext_counts[ext] += lines
                except Exception:
                    continue
        
        stats['files_by_extension'] = dict(ext_counts)
        stats['largest_files'] = sorted(file_sizes, key=lambda x: x[1], reverse=True)[:10]
        
        # Improved: Get detailed statistics for each commit including merge commits
        command = ['log', '--all', '--author', username, '--pretty=format:%H %P %s', '--numstat']
        command.extend(date_filter)
        output = self.run_git_command(command)
        
        total_additions = 0
        total_deletions = 0
        current_commit = None
        current_parents = None
        current_subject = None
        
        for line in output.split('\n'):
            if line.strip():
                # Check if this is a commit header line
                if '\t' not in line and ' ' in line:
                    parts = line.split(' ', 2)
                    if len(parts) >= 3:
                        current_commit = parts[0]
                        current_parents = parts[1]
                        current_subject = parts[2]
                elif '\t' in line:
                    # This is a file statistics line
                    parts = line.split('\t')
                    if len(parts) >= 2:
                        try:
                            additions = int(parts[0]) if parts[0] != '-' else 0
                            deletions = int(parts[1]) if parts[1] != '-' else 0
                            total_additions += additions
                            total_deletions += deletions
                            
                            # Track merge commit statistics
                            if current_parents and len(current_parents.split()) > 1:
                                if current_commit not in stats['merge_commit_stats']:
                                    stats['merge_commit_stats'][current_commit] = {
                                        'subject': current_subject,
                                        'additions': 0,
                                        'deletions': 0
                                    }
                                stats['merge_commit_stats'][current_commit]['additions'] += additions
                                stats['merge_commit_stats'][current_commit]['deletions'] += deletions
                            else:
                                if current_commit not in stats['regular_commit_stats']:
                                    stats['regular_commit_stats'][current_commit] = {
                                        'subject': current_subject,
                                        'additions': 0,
                                        'deletions': 0
                                    }
                                stats['regular_commit_stats'][current_commit]['additions'] += additions
                                stats['regular_commit_stats'][current_commit]['deletions'] += deletions
                        except ValueError:
                            continue
        
        stats['lines_added'] = total_additions
        stats['lines_deleted'] = total_deletions
        stats['net_lines'] = total_additions - total_deletions
        
        return stats
    
    def get_pull_requests_improved(self, username: str) -> Dict:
        """Get improved pull request statistics including merge commit detection"""
        stats = {
            'pull_requests': 0,
            'source': 'unknown',
            'pr_details': [],
            'merge_commits_with_prs': 0
        }
        
        # Use GitHub username if provided, otherwise use the regular username
        pr_username = self.github_username if self.github_username else username
        if self.github_username:
            print(f"Using GitHub username '{pr_username}' for PR counting...")
        
        # First, detect PRs from merge commits
        date_filter = self._build_date_filter()
        command = ['log', '--all', '--author', username, '--grep', 'Merge pull request', '--oneline']
        command.extend(date_filter)
        output = self.run_git_command(command)
        
        if output:
            pr_commits = output.split('\n')
            stats['merge_commits_with_prs'] = len(pr_commits)
            
            # Extract PR numbers from merge commit messages
            for commit_line in pr_commits:
                if 'Merge pull request' in commit_line:
                    # Extract PR number
                    try:
                        pr_match = commit_line.split('Merge pull request #')[1].split()[0]
                        pr_number = int(pr_match)
                        stats['pr_details'].append({
                            'pr_number': pr_number,
                            'commit': commit_line.split()[0],
                            'title': commit_line.split('Merge pull request #')[1].split(' from ')[0]
                        })
                    except (IndexError, ValueError):
                        continue
            
            stats['pull_requests'] = len(stats['pr_details'])
            stats['source'] = 'merge_commit_detection'
        
        # Try GitHub CLI as backup
        if stats['pull_requests'] == 0:
            try:
                auth_check = subprocess.run(
                    ['gh', 'auth', 'status'],
                    capture_output=True,
                    text=True
                )
                if auth_check.returncode == 0:
                    result = subprocess.run(
                        ['gh', 'pr', 'list', '--author', pr_username, '--state', 'merged', '--json', 'number,title'],
                        capture_output=True,
                        text=True,
                        check=True
                    )
                    data = json.loads(result.stdout)
                    stats['pull_requests'] = len(data)
                    stats['source'] = 'github_cli'
                    for pr in data:
                        stats['pr_details'].append({
                            'pr_number': pr['number'],
                            'title': pr['title']
                        })
                    return stats
            except (subprocess.CalledProcessError, json.JSONDecodeError, FileNotFoundError):
                pass
        
        return stats
    
    def calculate_activity_score(self, stats: Dict) -> int:
        """Calculate activity score based on commits and recent activity"""
        total_commits = stats.get('total_commits', 0)
        recent_commits = stats.get('recent_commits', 0)
        pull_requests = stats.get('pull_requests', 0)
        # Bonus points for PRs
        return total_commits * 10 + recent_commits * 50 + pull_requests * 100
    
    def generate_report(self, username: str, output_format: str = 'text') -> str:
        """Generate comprehensive analytics report"""
        if not self.validate_repo():
            return "Error: Not a Git repository"
        
        if not self.check_user_exists(username):
            return f"Error: No commits found for user '{username}'"
        
        # Gather all statistics
        commit_stats = self.get_commit_stats(username)
        loc_stats = self.get_lines_of_code_improved(username)
        pr_stats = self.get_pull_requests_improved(username)
        
        # Calculate activity score
        activity_score = self.calculate_activity_score(commit_stats)
        
        # Prepare report data
        report_data = {
            'user': username,
            'repository': os.path.basename(os.path.abspath(self.repo_path)),
            'generated': datetime.now().isoformat(),
            'activity_score': activity_score,
            'commit_stats': commit_stats,
            'lines_of_code': loc_stats,
            'pull_requests': pr_stats,
            'date_filter': {
                'start_date': self.start_date,
                'end_date': self.end_date
            }
        }
        
        if output_format == 'json':
            return json.dumps(report_data, indent=2)
        else:
            return self._format_text_report(report_data)
    
    def _format_text_report(self, data: Dict) -> str:
        """Format the report as text"""
        report = []
        report.append("=" * 50)
        report.append("Improved Git Analytics Report")
        report.append("=" * 50)
        report.append(f"User: {data['user']}")
        report.append(f"Repository: {data['repository']}")
        report.append(f"Generated: {data['generated'][:19].replace('T', ' ')}")
        if data['date_filter']['start_date'] or data['date_filter']['end_date']:
            report.append(f"Date Range: from {data['date_filter']['start_date'] or 'beginning'} until {data['date_filter']['end_date'] or 'now'}")
        report.append("")
        
        # Quick Stats
        report.append("📊 Quick Stats:")
        report.append(f"  Total Commits: {data['commit_stats']['total_commits']}")
        report.append(f"  Unique Commits: {data['commit_stats']['unique_commits']}")
        report.append(f"  Recent Activity (30 days): {data['commit_stats']['recent_commits']}")
        report.append(f"  Activity Score: {data['activity_score']}")
        report.append("")
        
        # Pull Requests
        report.append("🔀 Pull Requests:")
        report.append(f"  Count: {data['pull_requests']['pull_requests']}")
        report.append(f"  Source: {data['pull_requests']['source']}")
        if data['pull_requests']['pr_details']:
            report.append("  Details:")
            for pr in data['pull_requests']['pr_details']:
                report.append(f"    PR #{pr['pr_number']}: {pr.get('title', 'N/A')}")
        report.append("")
        
        # Lines of Code
        report.append("📝 Lines of Code:")
        report.append(f"  Files Modified: {data['lines_of_code']['files_modified']}")
        report.append(f"  Total LOC: {data['lines_of_code']['total_loc']}")
        report.append(f"  Lines Added: {data['lines_of_code']['lines_added']}")
        report.append(f"  Lines Deleted: {data['lines_of_code']['lines_deleted']}")
        report.append(f"  Net Lines: {data['lines_of_code']['net_lines']}")
        report.append("")
        
        # File Extensions
        if data['lines_of_code']['files_by_extension']:
            report.append("📁 Top File Extensions:")
            for ext, count in sorted(data['lines_of_code']['files_by_extension'].items(), key=lambda x: x[1], reverse=True)[:5]:
                report.append(f"  {ext}: {count} lines")
            report.append("")
        
        # Timeline
        if data['commit_stats']['first_commit'] or data['commit_stats']['last_commit']:
            report.append("📅 Timeline:")
            if data['commit_stats']['first_commit']:
                report.append(f"  First Commit: {data['commit_stats']['first_commit']}")
            if data['commit_stats']['last_commit']:
                report.append(f"  Last Commit: {data['commit_stats']['last_commit']}")
            report.append("")
        
        # Commits by Year
        if data['commit_stats']['commits_by_year']:
            report.append("📈 Commits by Year:")
            for year, count in sorted(data['commit_stats']['commits_by_year'].items()):
                report.append(f"  {year}: {count} commits")
            report.append("")
        
        # Most Active Day
        if data['commit_stats']['commits_by_day']:
            most_active_day = max(data['commit_stats']['commits_by_day'].items(), key=lambda x: x[1])
            report.append("🗓️  Most Active Day:")
            report.append(f"  {most_active_day[0]}: {most_active_day[1]} commits")
            report.append("")
        
        # Merge Commit Analysis
        if data['commit_stats']['merge_commits'] > 0:
            report.append("🔀 Merge Commit Analysis:")
            report.append(f"  Merge Commits: {data['commit_stats']['merge_commits']}")
            report.append(f"  Regular Commits: {data['commit_stats']['regular_commits']}")
            if data['lines_of_code']['merge_commit_stats']:
                report.append("  Merge Commit Contributions:")
                for commit, stats in data['lines_of_code']['merge_commit_stats'].items():
                    report.append(f"    {commit[:8]}: +{stats['additions']} -{stats['deletions']} ({stats['subject'][:50]}...)")
            report.append("")
        
        report.append("=" * 50)
        report.append("Report Complete")
        report.append("=" * 50)
        
        return "\n".join(report)


def main():
    parser = argparse.ArgumentParser(description='Improved Git Analytics for user contributions')
    parser.add_argument('username', help='Git username to analyze')
    parser.add_argument('--repo', default='.', help='Repository path (default: current directory)')
    parser.add_argument('--start-date', help='Start date (YYYY-MM-DD)')
    parser.add_argument('--end-date', help='End date (YYYY-MM-DD)')
    parser.add_argument('--github-username', help='GitHub username for PR detection')
    parser.add_argument('--format', choices=['text', 'json'], default='text', help='Output format')
    parser.add_argument('--output', help='Output file path')
    
    args = parser.parse_args()
    
    analytics = ImprovedGitAnalytics(
        repo_path=args.repo,
        start_date=args.start_date,
        end_date=args.end_date,
        github_username=args.github_username
    )
    
    report = analytics.generate_report(args.username, args.format)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(report)
        print(f"Report saved to {args.output}")
    else:
        print(report)


if __name__ == '__main__':
    main() 