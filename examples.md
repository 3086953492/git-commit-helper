# Examples

## 1. `message-only`

用户：

> 根据当前改动写一个 commit message

行为：读取 staged；若 staged 为空，再只读分析 unstaged/untracked。输出 message，不运行 `git add` 或 `git commit`。

```text
fix(订单状态): 统一状态值格式

- 规范化状态值的空白与大小写处理
```

## 2. `command-only`

用户：

> 给我完整提交命令

行为：输出当前 Git 运行环境可执行的完整命令但不执行。不得把一个环境检查出的 staged 范围交给另一个环境提交。

Windows PowerShell 使用单引号 here-string，避免 `$变量`、`$()` 和反引号被展开：

```powershell
$message = @'
fix(订单状态): 统一状态值格式

- 规范化状态值的空白与大小写处理
'@
$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message.TrimEnd() + "`n")
$messageBase64 = [Convert]::ToBase64String($messageBytes)
& "<skill-root>\scripts\commit.ps1" -Repository "." -MessageBase64 $messageBase64
```

WSL/Linux/macOS 使用 quoted heredoc，delimiter 两侧的单引号会关闭变量、命令替换和反引号展开：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
fix(订单状态): 统一状态值格式

- 规范化状态值的空白与大小写处理
COMMIT_MESSAGE
```

### Windows 控制 WSL 仓库

显式指定发行版。以下示例假设仓库路径已经是该发行版中的 POSIX 路径；技能目录通过同一个发行版的 `wslpath` 转换。所有前置 `status`、`diff`、测试和最终 commit 也必须使用同一个 WSL Git。

```powershell
$distro = "Ubuntu"
$repositoryWsl = "/home/mei/app"
$skillRootWindows = Join-Path $HOME ".agents\skills\git-commit-helper"
$message = @'
fix(订单状态): 统一状态值格式

- 规范化状态值的空白与大小写处理
'@
$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message.TrimEnd() + "`n")
$messageBase64 = [Convert]::ToBase64String($messageBytes)

$skillRootWslOutput = & wsl.exe --distribution $distro --exec wslpath -a $skillRootWindows
if ($LASTEXITCODE -ne 0) {
    throw "Failed to convert the skill path in WSL distribution '$distro'."
}
$skillRootWsl = ($skillRootWslOutput | Out-String).Trim()

& wsl.exe --distribution $distro --exec bash "$skillRootWsl/scripts/commit.sh" `
    --repository $repositoryWsl `
    --message-base64 $messageBase64
if ($LASTEXITCODE -ne 0) {
    throw "The WSL commit executor failed; inspect its output before retrying."
}
```

不能确定 `$distro` 时先询问。不要把 `C:\...`、`\\wsl.localhost\...` 或 Windows 临时 index 直接传给 WSL Git，也不要用 Windows Git 提交已由 WSL Git 检查的 staged 内容。

## 3. `execute-mode`

用户：

> 提交git

仓库状态：`src/order.ts` 已 staged，`README.md` 只有 unstaged 改动。

行为：

1. 只分析和验证 staged 的 `src/order.ts`。
2. 不把 `README.md` 加入 staged。
3. 在仓库所属 Git 环境中运行对应安全执行器。
4. 回报 hash、完整 message 和剩余的 ` M README.md`。

staged 范围清晰时，不再请求一次“是否确认提交”。

## 4. staged 为空

用户只说“提交git”，但 staged 为空且存在多个修改文件。

行为：列出候选文件并询问要提交哪些路径。不要默认执行 `git add .`。

如果用户要求 `command-only` 且已经明确指定路径，完整命令必须先执行 `git add -- <paths>`，再依次运行 staged stat、name-status、check 和完整 diff，最后调用安全脚本；路径未明确时先询问，不输出提交命令。

## 5. 提交失败

当 hook、权限或 Git 状态导致 `git commit` 返回非零退出码时：

- 不运行成功态的 `git log` 并把旧 HEAD 当成新提交。
- 报告原始错误以及 HEAD 是否发生变化。
- 保持 staged 范围不变，等待用户处理或授权重试。

如果 pre-commit hook 执行 `git add` 或以其他方式改变 staged tree，当前平台执行器会检测 commit tree 不等于捕获点的快照，随后把 HEAD 恢复到父提交并保留真实 index。此时先检查 hook 产物、重新分析 staged diff，再决定是否重试。

如果 post-commit hook 或并发进程在本次 commit 后又推进 HEAD，执行器只报告“本次创建的 commit”和“当前 HEAD”，不会自动回退或删除任何分支引用，并明确提示不得重试 commit。

如果 HEAD 仍指向同一个 commit、但 symbolic HEAD 已切换到另一分支，执行器同样不会回滚；detached HEAD 下也禁用自动回滚，避免把引用检查退化成只比较 OID。
