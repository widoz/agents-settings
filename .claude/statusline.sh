#!/usr/bin/env bash
# Claude Code status line - two-line layout

input=$(cat)

# --- Line 1: model, folder, git branch ---
model=$(echo "$input" | jq -r '.model.display_name // "unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
folder=$(basename "$cwd")

# Git branch (skip optional locks, silent on error)
branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" -c core.hooksPath=/dev/null symbolic-ref --short HEAD 2>/dev/null \
             || git -C "$cwd" -c core.hooksPath=/dev/null rev-parse --short HEAD 2>/dev/null)
fi

# Worktree info
wt_name=$(echo "$input" | jq -r '.worktree.name // empty')
wt_path=$(echo "$input" | jq -r '.worktree.path // empty')

# Build line 1
if [ -n "$branch" ]; then
    line1=$(printf "\033[36m[%s]\033[0m | 📁 \033[33m%s\033[0m | \033[32m\xee\x82\xa0 %s\033[0m" "$model" "$folder" "$branch")
else
    line1=$(printf "\033[36m[%s]\033[0m | 📁 \033[33m%s\033[0m" "$model" "$folder")
fi

if [ -n "$wt_name" ] || [ -n "$wt_path" ]; then
    wt_seg=$(printf "\033[35m⎇ %s\033[0m \033[90m%s\033[0m" "$wt_name" "$wt_path")
    line1="${line1} | ${wt_seg}"
fi

# --- Line 2: session bar, weekly bar, cost, time-to-reset ---

# Helper: render a percentage bar (10 chars wide)
bar() {
    local pct="${1:-0}"
    local filled=$(printf "%.0f" "$(echo "$pct * 10 / 100" | bc -l 2>/dev/null || echo 0)")
    [ "$filled" -gt 10 ] 2>/dev/null && filled=10
    [ "$filled" -lt 0 ] 2>/dev/null && filled=0
    local empty=$((10 - filled))
    local b=""
    local i=0
    while [ $i -lt $filled ]; do b="${b}█"; i=$((i+1)); done
    i=0
    while [ $i -lt $empty ];  do b="${b}░"; i=$((i+1)); done
    printf "%s" "$b"
}

# Color for bar based on percentage
bar_color() {
    local pct="${1:-0}"
    local int_pct=$(printf "%.0f" "$pct" 2>/dev/null || echo 0)
    if [ "$int_pct" -ge 80 ]; then
        printf "\033[31m"   # red
    elif [ "$int_pct" -ge 50 ]; then
        printf "\033[33m"   # yellow
    else
        printf "\033[32m"   # green
    fi
}

# Session (5-hour) limit
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# Weekly (7-day) limit
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Total cost (cumulative tokens as a proxy; use session tokens if cost not available)
total_in=$(echo "$input"  | jq -r '.context_window.total_input_tokens  // 0')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')

# Time remaining until 5-hour reset
time_remaining=""
if [ -n "$five_resets" ] && [ "$five_resets" != "null" ]; then
    now=$(date +%s)
    diff=$(( five_resets - now ))
    if [ "$diff" -gt 0 ]; then
        hh=$(( diff / 3600 ))
        mm=$(( (diff % 3600) / 60 ))
        ss=$(( diff % 60 ))
        time_remaining=$(printf "%dh%02dm%02ds" "$hh" "$mm" "$ss")
    else
        time_remaining="resetting"
    fi
fi

# Time remaining until 7-day reset
week_time_remaining=""
if [ -n "$week_resets" ] && [ "$week_resets" != "null" ]; then
    now=$(date +%s)
    diff=$(( week_resets - now ))
    if [ "$diff" -gt 0 ]; then
        dd=$(( diff / 86400 ))
        hh=$(( (diff % 86400) / 3600 ))
        mm=$(( (diff % 3600) / 60 ))
        week_time_remaining=$(printf "%dd%02dh%02dm" "$dd" "$hh" "$mm")
    else
        week_time_remaining="resetting"
    fi
fi

line2=""

# Session bar segment
if [ -n "$five_pct" ]; then
    clr=$(bar_color "$five_pct")
    b=$(bar "$five_pct")
    pct_int=$(printf "%.0f" "$five_pct")
    segment=$(printf "5h: ${clr}%s\033[0m %s%%" "$b" "$pct_int")
    [ -n "$time_remaining" ] && segment="${segment} \033[90m(resets in ${time_remaining})\033[0m"
    line2="${segment}"
fi

# Weekly bar segment
if [ -n "$week_pct" ]; then
    clr=$(bar_color "$week_pct")
    b=$(bar "$week_pct")
    pct_int=$(printf "%.0f" "$week_pct")
    segment=$(printf "7d: ${clr}%s\033[0m %s%%" "$b" "$pct_int")
    [ -n "$week_time_remaining" ] && segment="${segment} \033[90m(resets in ${week_time_remaining})\033[0m"
    if [ -n "$line2" ]; then
        line2="${line2} | ${segment}"
    else
        line2="${segment}"
    fi
fi

# Token cost summary
if [ "$total_in" != "0" ] || [ "$total_out" != "0" ]; then
    cost_seg=$(printf "\033[90mtokens in:%s out:%s\033[0m" "$total_in" "$total_out")
    if [ -n "$line2" ]; then
        line2="${line2} | ${cost_seg}"
    else
        line2="${cost_seg}"
    fi
fi

# --- Line 3: context window usage ---
ctx_pct=$(echo "$input"      | jq -r '.context_window.used_percentage // empty')
cur_in=$(echo "$input"       | jq -r '.context_window.current_usage.input_tokens // 0')
cur_out=$(echo "$input"      | jq -r '.context_window.current_usage.output_tokens // 0')
cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
cache_read=$(echo "$input"   | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')

line3=""

# Context bar segment
if [ -n "$ctx_pct" ]; then
    clr=$(bar_color "$ctx_pct")
    b=$(bar "$ctx_pct")
    pct_int=$(printf "%.0f" "$ctx_pct")
    line3=$(printf "ctx: ${clr}%s\033[0m %s%%" "$b" "$pct_int")
fi

# Current call tokens segment
if [ "$cur_in" != "0" ] || [ "$cur_out" != "0" ]; then
    call_seg=$(printf "\033[90mcall in:%s out:%s\033[0m" "$cur_in" "$cur_out")
    if [ -n "$line3" ]; then
        line3="${line3} | ${call_seg}"
    else
        line3="${call_seg}"
    fi
fi

# Cache tokens segment
if [ "$cache_create" != "0" ] || [ "$cache_read" != "0" ]; then
    cache_seg=$(printf "\033[90mcache wr:%s rd:%s\033[0m" "$cache_create" "$cache_read")
    if [ -n "$line3" ]; then
        line3="${line3} | ${cache_seg}"
    else
        line3="${cache_seg}"
    fi
fi

# Print all lines
printf "%b\n" "$line1"
[ -n "$line2" ] && printf "%b\n" "$line2"
if [ -n "$line3" ]; then
    [ -n "$line2" ] && printf "\n"
    printf "%b\n" "$line3"
fi
