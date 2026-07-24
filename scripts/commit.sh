#!/usr/bin/env bash
set -euo pipefail

repository="."
git_executable="git"
message_source="stdin"
message_base64=""
message_file=""
temp_work_directory=""
commit_confirmed=0
commit_attempted=0
retry_is_safe=0
no_retry_notice_emitted=0

usage() {
    cat <<'USAGE'
Usage:
  bash commit.sh [--repository PATH] [--git-executable PATH] < commit-message.txt
  bash commit.sh [--repository PATH] [--git-executable PATH] --message-file PATH
  bash commit.sh [--repository PATH] [--git-executable PATH] --message-base64 BASE64

Creates one ordinary commit from the staged snapshot captured before commit
message input is read. Run the script inside the same POSIX environment as the
target Git repository (WSL, Linux, or macOS).
USAGE
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

die_no_retry() {
    no_retry_notice_emitted=1
    die "$*"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repository)
            [[ $# -ge 2 ]] || die "--repository requires a path."
            repository="$2"
            shift 2
            ;;
        --git-executable)
            [[ $# -ge 2 ]] || die "--git-executable requires a path."
            git_executable="$2"
            shift 2
            ;;
        --message-file)
            [[ $# -ge 2 ]] || die "--message-file requires a path."
            [[ "$message_source" == "stdin" ]] || die "Choose exactly one commit message source."
            message_source="file"
            message_file="$2"
            shift 2
            ;;
        --message-base64)
            [[ $# -ge 2 ]] || die "--message-base64 requires a value."
            [[ "$message_source" == "stdin" ]] || die "Choose exactly one commit message source."
            message_source="base64"
            message_base64="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            [[ $# -eq 0 ]] || die "Unexpected positional arguments: $*"
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
done

normalize_option_like_relative_path() {
    case "$1" in
        -*)
            printf './%s\n' "$1"
            ;;
        *)
            printf '%s\n' "$1"
            ;;
    esac
}

repository="$(normalize_option_like_relative_path "$repository")"
if [[ "$message_source" == "file" ]]; then
    message_file="$(normalize_option_like_relative_path "$message_file")"
fi

command -v "$git_executable" >/dev/null 2>&1 || die "Git executable not found: $git_executable"

if ! repository_path="$(cd "$repository" 2>/dev/null && pwd -P)"; then
    die "Repository path does not exist or is not accessible: $repository"
fi

if ! repository_root="$("$git_executable" -C "$repository_path" --no-pager rev-parse --show-toplevel 2>&1)"; then
    die "Could not resolve the Git repository root.${repository_root:+
$repository_root}"
fi
if ! repository_root="$(cd "$repository_root" 2>/dev/null && pwd -P)"; then
    die "Could not canonicalize the Git repository root."
fi

git_capture() {
    "$git_executable" -C "$repository_root" --no-pager "$@"
}

resolve_git_path() {
    local git_path="$1"

    case "$git_path" in
        /*|[A-Za-z]:/*)
            printf '%s\n' "$git_path"
            ;;
        *)
            printf '%s/%s\n' "$repository_root" "$git_path"
            ;;
    esac
}

path_is_within_repository() {
    local candidate="$1"

    case "$candidate" in
        "$repository_root"|"$repository_root"/*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

create_external_temp_directory() {
    local candidate_root
    local candidate_path
    local resolved_candidate
    local roots=("${TMPDIR:-/tmp}" "/tmp" "/var/tmp")

    for candidate_root in "${roots[@]}"; do
        [[ -d "$candidate_root" && -w "$candidate_root" ]] || continue
        candidate_path="$(mktemp -d "$candidate_root/codex-git-commit.XXXXXXXX" 2>/dev/null)" || continue
        resolved_candidate="$(cd "$candidate_path" && pwd -P)"

        if path_is_within_repository "$resolved_candidate"; then
            rmdir "$resolved_candidate" 2>/dev/null || true
            continue
        fi

        printf '%s\n' "$resolved_candidate"
        return 0
    done

    return 1
}

cleanup_on_exit() {
    local exit_code=$?
    local cleanup_error=""
    local temp_name=""

    trap - EXIT

    if [[ -n "$temp_work_directory" && -e "$temp_work_directory" ]]; then
        temp_name="${temp_work_directory##*/}"
        if [[ "$temp_name" != codex-git-commit.* ]] || path_is_within_repository "$temp_work_directory"; then
            cleanup_error="Refusing to remove an unexpected temporary path: '$temp_work_directory'."
        elif ! rm -rf "$temp_work_directory" || [[ -e "$temp_work_directory" ]]; then
            cleanup_error="Could not remove temporary commit directory '$temp_work_directory'."
        fi
    fi

    if [[ -n "$cleanup_error" ]]; then
        printf 'WARNING: %s\n' "$cleanup_error" >&2
        if [[ $commit_confirmed -eq 1 ]]; then
            printf "Commit succeeded, but cleanup failed. Do not retry commit. Remove the directory manually: '%s'\n" "$temp_work_directory" >&2
            no_retry_notice_emitted=1
        fi
        exit_code=1
    fi

    if [[ $exit_code -ne 0 && $commit_attempted -eq 1 && $retry_is_safe -eq 0 && $no_retry_notice_emitted -eq 0 ]]; then
        printf '%s\n' "A commit may have been created or repository state may have changed after git commit was attempted. Do not retry commit; inspect the repository." >&2
    fi

    exit "$exit_code"
}
trap cleanup_on_exit EXIT

blocked_state_names=(
    "MERGE_HEAD"
    "CHERRY_PICK_HEAD"
    "REVERT_HEAD"
    "rebase-merge"
    "rebase-apply"
)

assert_no_blocked_operation() {
    local state_name
    local state_git_path
    local state_path

    for state_name in "${blocked_state_names[@]}"; do
        if ! state_git_path="$(git_capture rev-parse --git-path "$state_name" 2>&1)"; then
            die "Could not inspect Git operation state '$state_name'.
$state_git_path"
        fi
        state_path="$(resolve_git_path "$state_git_path")"
        if [[ -e "$state_path" ]]; then
            die "Refusing a normal commit while Git operation state '$state_name' exists."
        fi
    done
}

if ! temp_work_directory="$(create_external_temp_directory)"; then
    die "Could not create a temporary directory outside the repository."
fi

raw_message_path="$temp_work_directory/commit-message.raw"
temp_message_path="$temp_work_directory/commit-message.txt"
temp_index_path="$temp_work_directory/index"
commit_output_path="$temp_work_directory/git-commit-output.txt"
reflog_output_path="$temp_work_directory/reflog.txt"
decode_error_path="$temp_work_directory/base64-error.txt"

if head_before="$(git_capture rev-parse --verify HEAD 2>/dev/null)"; then
    :
else
    head_before=""
fi
if symbolic_head="$(git_capture symbolic-ref -q HEAD 2>/dev/null)"; then
    :
else
    symbolic_head=""
fi

if ! index_git_path="$(git_capture rev-parse --git-path index 2>&1)"; then
    die "Could not resolve the repository index.
$index_git_path"
fi
index_path="$(resolve_git_path "$index_git_path")"
[[ -f "$index_path" ]] || die "Could not locate the repository index at '$index_path'."
cp "$index_path" "$temp_index_path"

if shared_index_git_path="$(git_capture rev-parse --shared-index-path 2>/dev/null)"; then
    if [[ -n "$shared_index_git_path" ]]; then
        shared_index_path="$(resolve_git_path "$shared_index_git_path")"
        if [[ -f "$shared_index_path" ]]; then
            cp "$shared_index_path" "$temp_work_directory/${shared_index_path##*/}"
        fi
    fi
fi

git_index_file_was_set=0
previous_git_index_file=""
if [[ "${GIT_INDEX_FILE+x}" == "x" ]]; then
    git_index_file_was_set=1
    previous_git_index_file="$GIT_INDEX_FILE"
fi

reflog_action_was_set=0
previous_reflog_action=""
if [[ "${GIT_REFLOG_ACTION+x}" == "x" ]]; then
    reflog_action_was_set=1
    previous_reflog_action="$GIT_REFLOG_ACTION"
fi

restore_git_environment() {
    if [[ $git_index_file_was_set -eq 1 ]]; then
        export GIT_INDEX_FILE="$previous_git_index_file"
    else
        unset GIT_INDEX_FILE
    fi

    if [[ $reflog_action_was_set -eq 1 ]]; then
        export GIT_REFLOG_ACTION="$previous_reflog_action"
    else
        unset GIT_REFLOG_ACTION
    fi
}

export GIT_INDEX_FILE="$temp_index_path"

assert_no_blocked_operation

if ! captured_unmerged="$(git_capture diff --name-only --diff-filter=U)"; then
    die "Could not inspect unmerged paths in the captured staged snapshot."
fi
if [[ -n "$captured_unmerged" ]]; then
    die "Refusing to commit with unmerged paths in the captured staged snapshot:
$captured_unmerged"
fi

if git_capture diff --cached --quiet --exit-code; then
    die "There are no staged changes to commit."
else
    captured_staged_exit_code=$?
    if [[ $captured_staged_exit_code -ne 1 ]]; then
        die "Could not inspect the captured staged snapshot; git diff exited with code $captured_staged_exit_code."
    fi
fi

if ! captured_check="$(git_capture diff --cached --check 2>&1)"; then
    die "git diff --cached --check failed.
$captured_check"
fi

if ! expected_tree="$(git_capture write-tree 2>&1)"; then
    die "Could not write the captured staged tree.
$expected_tree"
fi

decode_base64_to_file() {
    local payload="$1"
    local destination="$2"
    local probe=""

    if probe="$(printf 'Zg==' | base64 --decode 2>/dev/null)" && [[ "$probe" == "f" ]]; then
        printf '%s' "$payload" | base64 --decode > "$destination" 2> "$decode_error_path"
        return $?
    fi

    if probe="$(printf 'Zg==' | base64 -D 2>/dev/null)" && [[ "$probe" == "f" ]]; then
        printf '%s' "$payload" | base64 -D > "$destination" 2> "$decode_error_path"
        return $?
    fi

    if probe="$(printf 'Zg==' | base64 -d 2>/dev/null)" && [[ "$probe" == "f" ]]; then
        printf '%s' "$payload" | base64 -d > "$destination" 2> "$decode_error_path"
        return $?
    fi

    printf 'No supported Base64 decoder is available.\n' > "$decode_error_path"
    return 1
}

case "$message_source" in
    stdin)
        if [[ -t 0 ]]; then
            die "Provide the commit message on stdin, with --message-file, or with --message-base64."
        fi
        cat > "$raw_message_path"
        ;;
    file)
        [[ -f "$message_file" ]] || die "Commit message file does not exist: $message_file"
        cp "$message_file" "$raw_message_path"
        ;;
    base64)
        if ! decode_base64_to_file "$message_base64" "$raw_message_path"; then
            decode_details="$(cat "$decode_error_path" 2>/dev/null || true)"
            die "MessageBase64 must contain valid Base64-encoded UTF-8 text.${decode_details:+
$decode_details}"
        fi
        ;;
    *)
        die "Unsupported commit message source: $message_source"
        ;;
esac

raw_byte_count="$(LC_ALL=C wc -c < "$raw_message_path" | tr -d '[:space:]')"
non_nul_byte_count="$(LC_ALL=C tr -d '\000' < "$raw_message_path" | LC_ALL=C wc -c | tr -d '[:space:]')"
if [[ "$raw_byte_count" != "$non_nul_byte_count" ]]; then
    die "Commit message must not contain NUL characters."
fi

command -v iconv >/dev/null 2>&1 || die "iconv is required to validate UTF-8 commit messages."
if ! iconv -f UTF-8 -t UTF-8 "$raw_message_path" >/dev/null 2>&1; then
    die "Commit message must contain valid UTF-8 text."
fi
if ! LC_ALL=C grep -q '[^[:space:]]' "$raw_message_path"; then
    die "Commit message must not be empty."
fi

message="$(cat "$raw_message_path")"
while [[ "$message" == *$'\r' || "$message" == *$'\n' ]]; do
    message="${message%?}"
done
printf '%s\n' "$message" > "$temp_message_path"

assert_no_blocked_operation

if ! snapshot_unmerged="$(git_capture diff --name-only --diff-filter=U)"; then
    die "Could not inspect unmerged paths in the staged snapshot."
fi
if [[ -n "$snapshot_unmerged" ]]; then
    die "Refusing to commit with unmerged paths in the staged snapshot:
$snapshot_unmerged"
fi

if git_capture diff --cached --quiet --exit-code; then
    die "There are no staged changes to commit."
else
    snapshot_exit_code=$?
    if [[ $snapshot_exit_code -ne 1 ]]; then
        die "Could not inspect the staged snapshot; git diff exited with code $snapshot_exit_code."
    fi
fi

if ! snapshot_check="$(git_capture diff --cached --check 2>&1)"; then
    die "git diff --cached --check failed.
$snapshot_check"
fi

if ! current_snapshot_tree="$(git_capture write-tree 2>&1)"; then
    die "Could not re-read the captured staged tree.
$current_snapshot_tree"
fi
if [[ "$current_snapshot_tree" != "$expected_tree" ]]; then
    die "The isolated staged snapshot changed before commit (expected $expected_tree, found $current_snapshot_tree). No commit was attempted."
fi

if head_immediately_before="$(git_capture rev-parse --verify HEAD 2>/dev/null)"; then
    :
else
    head_immediately_before=""
fi
if [[ "$head_immediately_before" != "$head_before" ]]; then
    die "HEAD changed while preparing the isolated staged snapshot. No commit was attempted."
fi

reflog_action="codex-git-commit-helper-${temp_work_directory##*/}-$$"
export GIT_REFLOG_ACTION="$reflog_action"

commit_attempted=1
set +e
git_capture -c "core.logAllRefUpdates=true" commit -F "$temp_message_path" > "$commit_output_path" 2>&1
commit_exit_code=$?
set -e

if current_head="$(git_capture rev-parse --verify HEAD 2>/dev/null)"; then
    :
else
    current_head=""
fi

reflog_ref="${symbolic_head:-HEAD}"
if ! git_capture reflog show --format='%H%x09%gs' -n 100 "$reflog_ref" > "$reflog_output_path" 2>/dev/null; then
    : > "$reflog_output_path"
fi

# Bash 3.2 with `set -u` can abort even when expanding the length of an
# explicitly initialized empty array. Scalars also match the real need here:
# distinguish zero, exactly one, or multiple unique reflog candidates.
created_candidate=""
created_candidate_count=0
while IFS=$'\t' read -r candidate_oid reflog_subject; do
    [[ -n "${candidate_oid:-}" ]] || continue
    [[ "${reflog_subject:-}" == "$reflog_action:"* ]] || continue

    if ! parent_line="$(git_capture rev-list --parents -n 1 "$candidate_oid" 2>/dev/null)"; then
        continue
    fi
    read -r -a parent_tokens <<< "$parent_line"
    [[ ${#parent_tokens[@]} -gt 0 ]] || continue

    candidate_matches_parent=0
    if [[ -n "$head_before" ]]; then
        if [[ ${#parent_tokens[@]} -eq 2 && "${parent_tokens[1]}" == "$head_before" ]]; then
            candidate_matches_parent=1
        fi
    elif [[ ${#parent_tokens[@]} -eq 1 ]]; then
        candidate_matches_parent=1
    fi

    [[ $candidate_matches_parent -eq 1 ]] || continue

    if [[ $created_candidate_count -eq 0 ]]; then
        created_candidate="$candidate_oid"
        created_candidate_count=1
    elif [[ "$candidate_oid" != "$created_candidate" ]]; then
        created_candidate_count=2
    fi
done < "$reflog_output_path"

commit_details="$(cat "$commit_output_path")"

if [[ $commit_exit_code -ne 0 ]]; then
    if [[ $created_candidate_count -gt 0 || "$current_head" != "$head_before" ]]; then
        die_no_retry "git commit returned exit code $commit_exit_code, but a commit or HEAD change may have occurred. Current HEAD is ${current_head:-<unborn>}. Do not retry commit; inspect the repository.
$commit_details"
    fi
    retry_is_safe=1
    die "git commit failed with exit code $commit_exit_code; HEAD did not change.
$commit_details"
fi

if [[ $created_candidate_count -ne 1 ]]; then
    die_no_retry "git commit returned success, but the created commit could not be identified unambiguously from its isolated reflog action. Current HEAD is ${current_head:-<unborn>}. Do not retry commit; inspect the repository."
fi

created_commit="$created_candidate"
if [[ "$current_head" != "$created_commit" ]]; then
    die_no_retry "HEAD moved after commit: created $created_commit, current ${current_head:-<unborn>}. No automatic rollback was attempted. Do not retry commit; inspect the repository."
fi

if ! commit_tree="$(git_capture rev-parse "$created_commit^{tree}" 2>&1)"; then
    die_no_retry "Commit $created_commit exists, but its tree could not be read. Do not retry commit; inspect the repository.
$commit_tree"
fi

restore_identified_commit() {
    local current_symbolic_head=""
    local rollback_current_head=""

    if [[ -z "$symbolic_head" ]]; then
        die_no_retry "Automatic rollback is disabled for detached HEAD. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    fi

    if current_symbolic_head="$(git_capture symbolic-ref -q HEAD 2>/dev/null)"; then
        :
    else
        current_symbolic_head=""
    fi
    if [[ "$current_symbolic_head" != "$symbolic_head" ]]; then
        die_no_retry "The symbolic HEAD moved from '$symbolic_head' to '${current_symbolic_head:-<detached>}'. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    fi

    if rollback_current_head="$(git_capture rev-parse --verify HEAD 2>/dev/null)"; then
        :
    else
        rollback_current_head=""
    fi
    if [[ "$rollback_current_head" != "$created_commit" ]]; then
        die_no_retry "HEAD moved from the identified commit $created_commit to ${rollback_current_head:-<unborn>}. No automatic rollback was attempted. Do not retry commit; inspect the repository."
    fi

    if [[ -n "$head_before" ]]; then
        if ! rollback_output="$(git_capture update-ref "$symbolic_head" "$head_before" "$created_commit" 2>&1)"; then
            die_no_retry "Could not atomically restore HEAD after rejecting commit $created_commit. HEAD may have moved concurrently. Do not retry commit; inspect the repository.
$rollback_output"
        fi
    elif ! rollback_output="$(git_capture update-ref -d "$symbolic_head" "$created_commit" 2>&1)"; then
        die_no_retry "Could not atomically restore the unborn branch after rejecting commit $created_commit. HEAD may have moved concurrently. Do not retry commit; inspect the repository.
$rollback_output"
    fi
}

if [[ "$commit_tree" != "$expected_tree" ]]; then
    restore_identified_commit
    retry_is_safe=1
    die "The staged tree changed during git commit (expected $expected_tree, committed $commit_tree). The original branch ref was atomically restored; inspect hooks before retrying."
fi

commit_confirmed=1
restore_git_environment

if ! log_output="$(git_capture log -1 --pretty=format:%H%n%B 2>&1)"; then
    die_no_retry "Commit $created_commit succeeded, but final commit readback failed. Do not retry commit; inspect the repository.
$log_output"
fi
if ! status_output="$(git_capture status --short --branch 2>&1)"; then
    die_no_retry "Commit $created_commit succeeded, but final status readback failed. Do not retry commit; inspect the repository.
$status_output"
fi

cat "$commit_output_path"
printf '%s\n' "--- commit readback ---"
printf '%s\n' "$log_output"
printf '%s\n' "--- final status ---"
printf '%s\n' "$status_output"
