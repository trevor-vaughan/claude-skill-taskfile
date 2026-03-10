#!/usr/bin/env bash
# Lint Taskfile.yml and .taskfiles/*.yml against structural conventions.
# Usage: bash lint.sh [directory]
# Exits 0 if all checks pass, 1 if any fail.
set -euo pipefail

dir="${1:-.}"
errors=0
checks=0

pass() { checks=$((checks + 1)); printf "  \033[32mPASS\033[0m %s\n" "$1"; }
fail() { checks=$((checks + 1)); errors=$((errors + 1)); printf "  \033[31mFAIL\033[0m %s" "$1"; [ -n "${2:-}" ] && printf " — %s" "$2"; printf "\n"; }

# --- Collect files ---
root=""
if [[ -f "$dir/Taskfile.yml" ]]; then
    root="$dir/Taskfile.yml"
elif [[ -f "$dir/taskfile.yml" ]]; then
    fail "Root file naming" "found lowercase 'taskfile.yml', must be 'Taskfile.yml'"
    root="$dir/taskfile.yml"
elif [[ -f "$dir/Taskfile.yaml" ]]; then
    fail "Root file naming" "found 'Taskfile.yaml', must be 'Taskfile.yml'"
    root="$dir/Taskfile.yaml"
else
    fail "Root file exists" "no Taskfile.yml found in $dir"
    printf "\n%d checks, %d errors\n" "$checks" "$errors"
    exit 1
fi
[[ "$root" == "$dir/Taskfile.yml" ]] && pass "Root file named Taskfile.yml (capital T, .yml)"

modules=()
if [[ -d "$dir/.taskfiles" ]]; then
    while IFS= read -r -d '' f; do
        modules+=("$f")
    done < <(find "$dir/.taskfiles" -maxdepth 1 -name '*.yml' -print0 | sort -z)
fi
all_files=("$root" "${modules[@]}")
has_modules=$(( ${#modules[@]} > 0 ? 1 : 0 ))

# --- Wrong module locations ---
if [[ -d "$dir/tasks" ]]; then
    fail "No modules in tasks/" "found tasks/ directory — includes belong in .taskfiles/"
fi
# --- Per-file checks ---
check_file() {
    local file="$1"
    local label
    label="$(basename "$file")"
    [[ "$file" != "$root" ]] && label=".taskfiles/$label"
    local is_root=0
    [[ "$file" == "$root" ]] && is_root=1

    local content
    content="$(cat "$file")"

    printf "\n%s\n" "$label"

    # 1. version: '3'
    local first_non_comment
    first_non_comment="$(grep -v '^\s*#' <<< "$content" | grep -v '^\s*$' | head -1)"
    if [[ "$first_non_comment" =~ ^version:[[:space:]]*[\'\"]*3[\'\"]*[[:space:]]*$ ]]; then
        pass "version: '3'"
    else
        fail "version: '3'" "got: ${first_non_comment:-<empty>}"
    fi

    # 2-5. Single pass over tasks: block for first task, desc checks, and default desc/list
    local first_task=""
    local missing_desc=()
    local task_names_arr=()
    local current_task=""
    local has_desc=0
    local has_task_list=0
    local in_tasks_block=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^tasks: ]]; then
            in_tasks_block=1
            continue
        fi
        if (( in_tasks_block == 0 )); then
            continue
        fi
        # If we hit a line with no indent that isn't empty/comment, we left tasks block
        if [[ ! "$line" =~ ^[[:space:]] && -n "$line" && ! "$line" =~ ^# ]]; then
            in_tasks_block=0
            continue
        fi
        # Detect task definition (2-space indented key)
        if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]* ]]; then
            local task_name="${BASH_REMATCH[1]}"
            # Save previous task state
            if [[ -n "$current_task" && ! "$current_task" =~ ^_ && "$current_task" != "default" && $has_desc -eq 0 ]]; then
                missing_desc+=("$current_task")
            fi
            [[ -z "$first_task" ]] && first_task="$task_name"
            task_names_arr+=("$task_name")
            current_task="$task_name"
            has_desc=0
        fi
        # Check for desc field (4-space indented under task)
        if [[ "$line" =~ ^[[:space:]]{4}desc: ]]; then
            has_desc=1

        fi
        # Check for task --list in default task body
        if [[ "$current_task" == "default" ]] && [[ "$line" =~ task.*--list || "$line" =~ task\ -l ]]; then
            has_task_list=1
        fi
    done <<< "$content"
    # Check last task
    if [[ -n "$current_task" && ! "$current_task" =~ ^_ && "$current_task" != "default" && $has_desc -eq 0 ]]; then
        missing_desc+=("$current_task")
    fi

    if [[ "$first_task" == "default" ]]; then
        pass "default is first task"
    else
        fail "default is first task" "first task: ${first_task:-<none>}"
    fi

    if (( has_task_list == 1 )); then
        pass "default task lists tasks"
    else
        fail "default task lists tasks" "default task should run 'task --list'"
    fi

    if (( ${#missing_desc[@]} == 0 )); then
        pass "desc on all public tasks"
    else
        fail "desc on all public tasks" "missing on: ${missing_desc[*]}"
    fi

    # 6. No subprocess task calls (cmd: task should be task: internal call)
    local bad_subprocess
    bad_subprocess=$(grep -v '^\s*#' <<< "$content" | grep -n 'cmd:.*\btask [a-zA-Z]' | grep -v -- '--list' || true)
    if [[ -z "$bad_subprocess" ]]; then
        pass "No subprocess task calls"
    else
        fail "No subprocess task calls" "use 'task:' internal calls instead of 'cmd: task ...'"
    fi

    # 7. Standard task names (no ad-hoc alternatives)
    if (( is_root == 1 )); then
        local -A adhoc_map=(
            [run-tests]=test [run_tests]=test [do-test]=test
            [do-lint]=lint [run-lint]=lint [linter]=lint
            [compile]=build [make]=build
            [format]=fmt [format-code]=fmt [run-fmt]=fmt
            [ci]=check [verify]=check [validate]=check
        )
        local found_adhoc=()
        for tname in "${task_names_arr[@]}"; do
            [[ "$tname" == _* || "$tname" == "default" ]] && continue
            if [[ -n "${adhoc_map[$tname]+x}" ]]; then
                found_adhoc+=("$tname→${adhoc_map[$tname]}")
            fi
        done
        if (( ${#found_adhoc[@]} == 0 )); then
            pass "Standard task names (no ad-hoc alternatives)"
        else
            fail "Standard task names (no ad-hoc alternatives)" "use standard names: ${found_adhoc[*]}"
        fi

        # 8. 'check' meta-task when 2+ quality tasks exist
        local -A public_set=()
        for tname in "${task_names_arr[@]}"; do
            [[ "$tname" == _* || "$tname" == "default" ]] && continue
            public_set["$tname"]=1
        done
        local quality_count=0
        for qt in test lint fmt; do
            [[ -n "${public_set[$qt]+x}" ]] && quality_count=$((quality_count + 1))
        done
        if (( quality_count >= 2 )); then
            if [[ -n "${public_set[check]+x}" ]]; then
                pass "Has 'check' meta-task for quality gates"
            else
                fail "Has 'check' meta-task for quality gates" "has $quality_count quality tasks but no 'check'"
            fi
        fi
    fi

    # 9-10. Root-only checks: includes block (single pass), section order
    if (( is_root == 1 )); then
        # Single pass over includes block for bare imports and dir: usage
        local bare_includes=()
        local dir_includes=()
        local in_includes=0
        local current_include=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^includes: ]]; then
                in_includes=1
                continue
            fi
            if (( in_includes == 1 )); then
                if [[ ! "$line" =~ ^[[:space:]] && -n "$line" && ! "$line" =~ ^# ]]; then
                    in_includes=0
                    continue
                fi
                # Track which include we're inside (2-space indented key)
                if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]* ]]; then
                    current_include="${BASH_REMATCH[1]}"
                fi
                # Check for bare string include: "  name: ./path" (no taskfile: key)
                if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]+[.\"/\'] ]]; then
                    bare_includes+=("${BASH_REMATCH[1]}")
                fi
                # Check for dir: key (4-space indented under an include entry)
                if [[ "$line" =~ ^[[:space:]]{4}dir: ]]; then
                    dir_includes+=("$current_include")
                fi
            fi
        done <<< "$content"

        if (( ${#bare_includes[@]} == 0 )); then
            [[ $has_modules -eq 1 ]] && pass "Include imports use explicit taskfile path"
        else
            fail "Include imports use explicit taskfile path" "bare includes: ${bare_includes[*]}"
        fi

        if (( ${#dir_includes[@]} == 0 )); then
            [[ $has_modules -eq 1 ]] && pass "Includes do not override dir (use ROOT_DIR in modules)"
        else
            fail "Includes do not override dir (use ROOT_DIR in modules)" "dir: found on: ${dir_includes[*]}"
        fi

        # Section order: version → includes → vars → dotenv → tasks
        local version_line=0 vars_line=0 dotenv_line=0 includes_line=0 tasks_line=0
        local lineno=0
        while IFS= read -r line; do
            lineno=$((lineno + 1))
            [[ "$line" =~ ^version: ]] && version_line=$lineno
            [[ "$line" =~ ^vars: ]] && vars_line=$lineno
            [[ "$line" =~ ^dotenv: ]] && dotenv_line=$lineno
            [[ "$line" =~ ^includes: ]] && includes_line=$lineno
            [[ "$line" =~ ^tasks: ]] && tasks_line=$lineno
        done <<< "$content"

        # Validate ordering of present sections: version < includes < vars < dotenv < tasks
        local order_ok=1
        local -a present_sections=()
        local -a present_lines=()
        for sec_name in version includes vars dotenv tasks; do
            local sec_line_var="${sec_name}_line"
            local sec_line="${!sec_line_var}"
            if (( sec_line > 0 )); then
                present_sections+=("$sec_name")
                present_lines+=("$sec_line")
            fi
        done
        for (( i = 0; i < ${#present_lines[@]} - 1; i++ )); do
            if (( present_lines[i] > present_lines[i+1] )); then
                order_ok=0
                break
            fi
        done

        if (( order_ok == 1 )); then
            pass "Section order (version → includes → vars → dotenv → tasks)"
        else
            fail "Section order (version → includes → vars → dotenv → tasks)"
        fi

    fi
}

for f in "${all_files[@]}"; do
    check_file "$f"
done

# --- Summary ---
printf "\n%d checks, %d errors\n" "$checks" "$errors"
(( errors == 0 )) && exit 0 || exit 1
