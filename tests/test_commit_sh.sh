#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
skill_root="$(cd "$test_dir/.." && pwd -P)"
script_under_test="${COMMIT_SH_UNDER_TEST:-$skill_root/scripts/commit.sh}"
temp_root="$(mktemp -d "${TMPDIR:-/tmp}/git-commit-helper-tests.XXXXXXXX")"
race_executor_pid=""
race_fifo_fd_open=0

cleanup() {
    if [[ -n "$race_executor_pid" ]]; then
        kill "$race_executor_pid" 2>/dev/null || true
        wait "$race_executor_pid" 2>/dev/null || true
    fi
    if [[ $race_fifo_fd_open -eq 1 ]]; then
        exec 3>&-
    fi
    if [[ -n "${temp_root:-}" && -d "$temp_root" && "$temp_root" == *git-commit-helper-tests.* ]]; then
        rm -rf "$temp_root"
    fi
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL: %s\nexpected: <%s>\nactual:   <%s>\n' "$label" "$expected" "$actual" >&2
        exit 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"

    if [[ "$haystack" != *"$needle"* ]]; then
        printf 'FAIL: %s\nmissing: <%s>\noutput:\n%s\n' "$label" "$needle" "$haystack" >&2
        exit 1
    fi
}

new_repository() {
    local name="$1"
    local repository="$temp_root/$name"

    mkdir -p "$repository"
    git init -q "$repository"
    git -C "$repository" config user.name "Commit Helper Test"
    git -C "$repository" config user.email "commit-helper@example.test"
    git -C "$repository" config core.autocrlf false
    printf 'initial\n' > "$repository/tracked.txt"
    git -C "$repository" add -- tracked.txt
    git -C "$repository" commit -q -m "test: initial"
    printf '%s\n' "$repository"
}

[[ -f "$script_under_test" ]] || fail "missing POSIX executor: $script_under_test"
if LC_ALL=C grep -q $'\r' "$script_under_test"; then
    fail "POSIX executor must use LF line endings: $script_under_test"
fi
if LC_ALL=C grep -Eq '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\(\)[[:space:]]*(#.*)?$' "$script_under_test"; then
    fail "Bash 3.2 with nounset must not use explicitly empty arrays"
fi

repo_with_mixed_state="$(new_repository "repo with spaces")"
printf 'staged version\n' > "$repo_with_mixed_state/tracked.txt"
git -C "$repo_with_mixed_state" add -- tracked.txt
printf 'unstaged version\n' > "$repo_with_mixed_state/tracked.txt"

success_output="$(
    bash "$script_under_test" --repository "$repo_with_mixed_state" <<'COMMIT_MESSAGE'
fix(订单状态): 保留暂存边界

- 只提交调用时的 staged 快照
COMMIT_MESSAGE
)"

assert_contains "$success_output" "--- commit readback ---" "success output includes commit readback"
assert_contains "$success_output" "--- final status ---" "success output includes final status"
assert_equals \
    $'fix(订单状态): 保留暂存边界\n\n- 只提交调用时的 staged 快照' \
    "$(git -C "$repo_with_mixed_state" log -1 --pretty=format:%B)" \
    "multiline UTF-8 message is preserved"
assert_equals \
    "staged version" \
    "$(git -C "$repo_with_mixed_state" show HEAD:tracked.txt)" \
    "commit tree matches the staged snapshot"
assert_equals \
    " M tracked.txt" \
    "$(git -C "$repo_with_mixed_state" status --short)" \
    "unstaged edit remains after commit"

race_repo="$(new_repository "invocation snapshot race")"
printf 'captured early\n' > "$race_repo/early.txt"
git -C "$race_repo" add -- early.txt
race_fifo="$temp_root/commit-message.fifo"
race_executor_temp="$temp_root/executor temp"
race_output="$temp_root/race-output.txt"
mkdir -p "$race_executor_temp"
mkfifo "$race_fifo"
exec 3<> "$race_fifo"
race_fifo_fd_open=1
TMPDIR="$race_executor_temp" \
    bash "$script_under_test" --repository "$race_repo" < "$race_fifo" 3>&- > "$race_output" 2>&1 &
race_executor_pid=$!

snapshot_ready=0
snapshot_wait_attempt=0
while [[ $snapshot_wait_attempt -lt 10 ]]; do
    for captured_index in "$race_executor_temp"/codex-git-commit.*/index; do
        if [[ -f "$captured_index" ]]; then
            snapshot_ready=1
            break
        fi
    done
    [[ $snapshot_ready -eq 1 ]] && break
    snapshot_wait_attempt=$((snapshot_wait_attempt + 1))
    sleep 1
done
[[ $snapshot_ready -eq 1 ]] || fail "executor did not capture the index before reading stdin"

printf 'staged later\n' > "$race_repo/late.txt"
git -C "$race_repo" add -- late.txt
printf '%s\n' 'test: freeze staged snapshot before message read' >&3
exec 3>&-
race_fifo_fd_open=0

set +e
wait "$race_executor_pid"
race_exit_code=$?
set -e
race_executor_pid=""
if [[ $race_exit_code -ne 0 ]]; then
    fail "invocation snapshot race failed: $(cat "$race_output")"
fi

git -C "$race_repo" cat-file -e HEAD:early.txt
if git -C "$race_repo" cat-file -e HEAD:late.txt 2>/dev/null; then
    fail "path staged after index capture leaked into the commit"
fi
assert_equals \
    "late.txt" \
    "$(git -C "$race_repo" diff --cached --name-only)" \
    "path staged after capture remains in the real index"

repo_for_base64="$(new_repository "base64")"
printf 'base64 staged\n' > "$repo_for_base64/tracked.txt"
git -C "$repo_for_base64" add -- tracked.txt
base64_message=$'feat(wsl): 支持跨环境调用\n\n- 使用 WSL Git 完成提交'
base64_payload="$(printf '%s\n' "$base64_message" | base64 | tr -d '\r\n')"

bash "$script_under_test" \
    --repository "$repo_for_base64" \
    --message-base64 "$base64_payload" >/dev/null

assert_equals \
    "$base64_message" \
    "$(git -C "$repo_for_base64" log -1 --pretty=format:%B)" \
    "Base64 message transport preserves UTF-8"

option_like_repo="$(new_repository "-repository")"
printf 'option-like staged\n' > "$option_like_repo/tracked.txt"
git -C "$option_like_repo" add -- tracked.txt
printf '%s\n' 'fix(posix): accept option-like relative paths' > "$temp_root/-message.txt"

(
    cd "$temp_root"
    bash "$script_under_test" \
        --repository "-repository" \
        --message-file "-message.txt" >/dev/null
)

assert_equals \
    "fix(posix): accept option-like relative paths" \
    "$(git -C "$option_like_repo" log -1 --pretty=format:%B)" \
    "relative repository and message paths beginning with a dash are supported"

empty_repo="$(new_repository "empty staged")"
empty_head_before="$(git -C "$empty_repo" rev-parse HEAD)"
set +e
empty_output="$(
    bash "$script_under_test" --repository "$empty_repo" <<'COMMIT_MESSAGE' 2>&1
test: should not commit
COMMIT_MESSAGE
)"
empty_exit_code=$?
set -e

[[ $empty_exit_code -ne 0 ]] || fail "empty staged changes should be rejected"
assert_contains "$empty_output" "There are no staged changes to commit." "empty staged rejection is explicit"
assert_equals "$empty_head_before" "$(git -C "$empty_repo" rev-parse HEAD)" "empty staged rejection keeps HEAD"

hook_repo="$(new_repository "hook mutation")"
printf 'staged before hook\n' > "$hook_repo/tracked.txt"
printf 'added by hook\n' > "$hook_repo/hook.txt"
git -C "$hook_repo" add -- tracked.txt
hook_head_before="$(git -C "$hook_repo" rev-parse HEAD)"
hook_path="$hook_repo/.git/hooks/pre-commit"
printf '%s\n' '#!/usr/bin/env sh' 'git add -- hook.txt' > "$hook_path"
chmod +x "$hook_path"

set +e
hook_output="$(
    bash "$script_under_test" --repository "$hook_repo" <<'COMMIT_MESSAGE' 2>&1
test: reject hook tree mutation
COMMIT_MESSAGE
)"
hook_exit_code=$?
set -e

[[ $hook_exit_code -ne 0 ]] || fail "hook-mutated staged tree should be rejected"
assert_contains "$hook_output" "The staged tree changed during git commit" "hook mutation is diagnosed"
assert_contains "$hook_output" "atomically restored" "hook mutation restores the original ref"
assert_equals "$hook_head_before" "$(git -C "$hook_repo" rev-parse HEAD)" "hook rejection restores HEAD"
assert_equals \
    "tracked.txt" \
    "$(git -C "$hook_repo" diff --cached --name-only)" \
    "hook mutation does not alter the real index"

post_commit_repo="$(new_repository "post commit movement")"
printf 'primary staged\n' > "$post_commit_repo/tracked.txt"
git -C "$post_commit_repo" add -- tracked.txt
post_commit_head_before="$(git -C "$post_commit_repo" rev-parse HEAD)"
post_commit_hook="$post_commit_repo/.git/hooks/post-commit"
printf '%s\n' \
    '#!/usr/bin/env sh' \
    'rm -f "$0"' \
    'printf "post-hook commit\n" > post-hook.txt' \
    'git add -- post-hook.txt' \
    'git commit -q -m "test: post-commit hook advanced HEAD"' > "$post_commit_hook"
chmod +x "$post_commit_hook"

set +e
post_commit_output="$(
    bash "$script_under_test" --repository "$post_commit_repo" <<'COMMIT_MESSAGE' 2>&1
test: detect post-commit movement
COMMIT_MESSAGE
)"
post_commit_exit_code=$?
set -e

[[ $post_commit_exit_code -ne 0 ]] || fail "post-commit HEAD movement should not be reported as ordinary success"
assert_contains "$post_commit_output" "HEAD moved after commit" "post-commit movement is diagnosed"
assert_contains "$post_commit_output" "Do not retry commit" "post-commit movement prevents duplicate retry"
if [[ "$(git -C "$post_commit_repo" rev-parse HEAD)" == "$post_commit_head_before" ]]; then
    fail "post-commit movement fixture did not advance HEAD"
fi

temp_delete_repo="$(new_repository "post commit temp deletion")"
printf 'staged before temp deletion\n' > "$temp_delete_repo/tracked.txt"
git -C "$temp_delete_repo" add -- tracked.txt
temp_delete_head_before="$(git -C "$temp_delete_repo" rev-parse HEAD)"
temp_delete_hook="$temp_delete_repo/.git/hooks/post-commit"
printf '%s\n' \
    '#!/usr/bin/env sh' \
    'rm -rf "${GIT_INDEX_FILE%/*}"' > "$temp_delete_hook"
chmod +x "$temp_delete_hook"

set +e
temp_delete_output="$(
    bash "$script_under_test" --repository "$temp_delete_repo" <<'COMMIT_MESSAGE' 2>&1
test: preserve no-retry warning after temp deletion
COMMIT_MESSAGE
)"
temp_delete_exit_code=$?
set -e

[[ $temp_delete_exit_code -ne 0 ]] || fail "post-commit temp deletion should prevent an ordinary success report"
assert_contains "$temp_delete_output" "Do not retry commit" "unexpected post-attempt failure warns against duplicate commit"
if [[ "$(git -C "$temp_delete_repo" rev-parse HEAD)" == "$temp_delete_head_before" ]]; then
    fail "post-commit temp deletion fixture did not create a commit"
fi

blocked_repo="$(new_repository "blocked operation")"
blocked_base_branch="$(git -C "$blocked_repo" branch --show-current)"
git -C "$blocked_repo" switch -q -c merge-side
printf 'merge side\n' > "$blocked_repo/tracked.txt"
git -C "$blocked_repo" add -- tracked.txt
git -C "$blocked_repo" commit -q -m "test: merge side"
git -C "$blocked_repo" switch -q "$blocked_base_branch"
printf 'base side\n' > "$blocked_repo/tracked.txt"
git -C "$blocked_repo" add -- tracked.txt
git -C "$blocked_repo" commit -q -m "test: base side"
set +e
git -C "$blocked_repo" merge merge-side >/dev/null 2>&1
merge_exit_code=$?
set -e
[[ $merge_exit_code -ne 0 ]] || fail "merge fixture should create a conflict"
blocked_head_before="$(git -C "$blocked_repo" rev-parse HEAD)"

set +e
blocked_output="$(
    bash "$script_under_test" --repository "$blocked_repo" <<'COMMIT_MESSAGE' 2>&1
test: reject merge state
COMMIT_MESSAGE
)"
blocked_exit_code=$?
set -e

[[ $blocked_exit_code -ne 0 ]] || fail "in-progress Git operation should be rejected"
assert_contains "$blocked_output" "MERGE_HEAD" "in-progress operation identifies the blocking state"
assert_equals "$blocked_head_before" "$(git -C "$blocked_repo" rev-parse HEAD)" "blocked state keeps HEAD"

unborn_repo="$temp_root/unborn"
mkdir -p "$unborn_repo"
git init -q "$unborn_repo"
git -C "$unborn_repo" config user.name "Commit Helper Test"
git -C "$unborn_repo" config user.email "commit-helper@example.test"
git -C "$unborn_repo" config core.autocrlf false
printf 'first tree\n' > "$unborn_repo/first.txt"
git -C "$unborn_repo" add -- first.txt

bash "$script_under_test" --repository "$unborn_repo" <<'COMMIT_MESSAGE' >/dev/null
feat: 创建初始提交
COMMIT_MESSAGE

assert_equals \
    "1" \
    "$(git -C "$unborn_repo" rev-list --parents -n 1 HEAD | wc -w | tr -d '[:space:]')" \
    "unborn HEAD produces a root commit"

split_index_repo="$(new_repository "split index")"
git -C "$split_index_repo" update-index --split-index
printf 'split index staged\n' > "$split_index_repo/tracked.txt"
git -C "$split_index_repo" add -- tracked.txt

bash "$script_under_test" --repository "$split_index_repo" <<'COMMIT_MESSAGE' >/dev/null
test: 支持 split index 快照
COMMIT_MESSAGE

assert_equals \
    "split index staged" \
    "$(git -C "$split_index_repo" show HEAD:tracked.txt)" \
    "split-index dependency is available to the isolated index"

worktree_main="$(new_repository "worktree main")"
linked_worktree="$temp_root/linked worktree"
git -C "$worktree_main" worktree add -q -b test-linked-worktree "$linked_worktree"
printf 'linked worktree staged\n' > "$linked_worktree/tracked.txt"
git -C "$linked_worktree" add -- tracked.txt

bash "$script_under_test" --repository "$linked_worktree" <<'COMMIT_MESSAGE' >/dev/null
test: 支持 linked worktree
COMMIT_MESSAGE

assert_equals \
    "linked worktree staged" \
    "$(git -C "$linked_worktree" show HEAD:tracked.txt)" \
    "linked worktree uses its own index"
assert_equals \
    "test-linked-worktree" \
    "$(git -C "$linked_worktree" branch --show-current)" \
    "linked worktree keeps its branch"

invalid_base64_repo="$(new_repository "invalid base64")"
printf 'staged\n' > "$invalid_base64_repo/tracked.txt"
git -C "$invalid_base64_repo" add -- tracked.txt
set +e
invalid_base64_output="$(
    bash "$script_under_test" \
        --repository "$invalid_base64_repo" \
        --message-base64 '%%%not-base64%%%' 2>&1
)"
invalid_base64_exit_code=$?
set -e

[[ $invalid_base64_exit_code -ne 0 ]] || fail "invalid Base64 should be rejected"
assert_contains "$invalid_base64_output" "valid Base64" "invalid Base64 rejection is explicit"

invalid_utf8_path="$temp_root/invalid-utf8-message.txt"
printf '\377' > "$invalid_utf8_path"
set +e
invalid_utf8_output="$(
    bash "$script_under_test" \
        --repository "$invalid_base64_repo" \
        --message-file "$invalid_utf8_path" 2>&1
)"
invalid_utf8_exit_code=$?
set -e

[[ $invalid_utf8_exit_code -ne 0 ]] || fail "invalid UTF-8 should be rejected"
assert_contains "$invalid_utf8_output" "valid UTF-8" "invalid UTF-8 rejection is explicit"

nul_message_path="$temp_root/nul-message.txt"
printf 'valid\000invalid\n' > "$nul_message_path"
set +e
nul_output="$(
    bash "$script_under_test" \
        --repository "$invalid_base64_repo" \
        --message-file "$nul_message_path" 2>&1
)"
nul_exit_code=$?
set -e

[[ $nul_exit_code -ne 0 ]] || fail "NUL-containing message should be rejected"
assert_contains "$nul_output" "NUL" "NUL rejection is explicit"

printf 'PASS: commit.sh preserves staged scope and guarded commit invariants\n'
