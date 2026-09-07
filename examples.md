# Examples

仅在需要调用语法或具体场景时读取对应小节。消息措辞示例见 [reference.md](reference.md)。

## 1. `message-only`

用户：

> 根据当前改动写一个 commit message

行为：直接使用已有 diff；缺少时才读取目标改动。输出 message，不运行测试、构建、`git add` 或 `git commit`。

```text
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
```

## 2. `command-only`

用户：

> 给我完整提交命令

行为：输出当前 Git 运行环境可执行的完整命令但不执行。不得把一个环境检查出的 staged 范围交给另一个环境提交。

### Windows PowerShell

使用单引号 here-string，避免 `$变量`、`$()` 和反引号被展开。将 `<skill-root>` 替换为实际技能路径，仓库参数替换为目标仓库：

```powershell
$message = @'
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
'@
$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message.TrimEnd() + "`n")
$messageBase64 = [Convert]::ToBase64String($messageBytes)
& "<skill-root>\scripts\commit.ps1" -Repository "." -MessageBase64 $messageBase64
```

### WSL/Linux/macOS

使用 quoted heredoc，delimiter 两侧的单引号会关闭变量、命令替换和反引号展开。技能路径以实际安装位置为准：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
COMMIT_MESSAGE
```

### Windows 控制 WSL 仓库

使用目标仓库所属的发行版。以下示例中的 Ubuntu 和仓库路径需替换为实际值；技能目录通过同一个发行版的 `wslpath` 转换。读取、暂存和最终 commit 使用同一个 WSL Git。

```powershell
$distro = "Ubuntu"
$repositoryWsl = "/home/mei/app"
$skillRootWindows = Join-Path $HOME ".agents\skills\git-commit-helper"
$message = @'
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
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

无法从现有上下文确定 `$distro` 时才询问。不要把 `C:\...`、`\\wsl.localhost\...` 或 Windows 临时 index 直接传给 WSL Git。

## 3. `execute-mode`

用户：

> 提交git

仓库状态：`src/order.ts` 已 staged，`README.md` 只有 unstaged 改动。

行为：根据 `src/order.ts` 的 staged diff 写消息，然后在仓库所属 Git 环境中运行对应执行器。已有 diff 且范围未变时直接复用，不额外运行测试或复检命令，不把 `README.md` 加入 staged。依据脚本输出回报 hash、message 和剩余的 ` M README.md`。

## 4. staged 为空

用户只说“提交git”，但 staged 为空且存在多个修改文件。

行为：列出候选文件并询问要提交哪些路径。不要默认执行 `git add .`。

如果用户此前已明确范围，沿用该范围。`command-only` 输出显式 `git add -- <paths>` 和执行器调用，不实际运行；`execute-mode` 才执行。`git add` 失败时停止，不继续提交。已读过的相同内容不重复读取，也不附加 stat、name-status、check 或测试命令。

## 5. 提交失败

报告脚本给出的实际错误和提交状态，不把旧 HEAD 当成新提交，也不在没有证据时声称已回滚。输出为 `Do not retry commit` 时，可能已创建提交，先定位状态，不自动重试。仅为处理具体错误补充必要信息，不将失败扩展成代码验收或修复任务。
