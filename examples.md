# Examples

## 1. 先推断意图与影响

假设 staged diff 把登录限流键从 `userID` 改为 `tenantID:userID`，并新增“不同租户不得共享登录配额”的测试。

先在内部归纳：

```text
目标：阻止不同租户中相同用户 ID 互相占用登录配额
行为变化：跨租户共享限流键 → 每个租户独立计数
影响：一个租户的登录请求不再触发另一个租户的限流
证据：限流键实现与跨租户隔离测试
```

再生成：

```text
fix(登录限流): 按租户隔离用户配额

- 避免相同用户 ID 在不同租户间共享限流计数
- 补充跨租户配额隔离的回归测试
```

不要写成“更新限流键并补充测试”，因为那只是实现清单。

### 动机未知但结果唯一

若 staged 只把默认分页数量从 20 改为 50，没有其他证据，不要编造“提升浏览效率”或“优化性能”，也不必询问。使用可证明的结果：

```text
chore(列表): 未指定分页数量时默认返回 50 条

- 让未显式指定分页数量的列表每页默认返回 50 条
```

### 多个解释会改变提交语义

若 staged 把公共 API 字段从 `price` 改为 `amount`，但无法判断这是有意的 breaking change，还是遗漏旧字段兼容层，只问一个问题：

> 这次 `price` 改为 `amount` 是有意发布破坏性 API 变更，还是需要继续兼容旧字段 `price`？

不要泛问用户“这批改动的意图是什么”。

## 2. `message-only`

用户：

> 根据当前改动写一个 commit message

行为：读取 staged；若 staged 为空，再只读分析 unstaged/untracked。输出 message，不运行 `git add` 或 `git commit`。

```text
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
```

## 3. `command-only`

用户：

> 给我完整提交命令

行为：输出当前 Git 运行环境可执行的完整命令但不执行。不得把一个环境检查出的 staged 范围交给另一个环境提交。

Windows PowerShell 使用单引号 here-string，避免 `$变量`、`$()` 和反引号被展开：

```powershell
$message = @'
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
'@
$messageBytes = [System.Text.Encoding]::UTF8.GetBytes($message.TrimEnd() + "`n")
$messageBase64 = [Convert]::ToBase64String($messageBytes)
& "<skill-root>\scripts\commit.ps1" -Repository "." -MessageBase64 $messageBase64
```

WSL/Linux/macOS 使用 quoted heredoc，delimiter 两侧的单引号会关闭变量、命令替换和反引号展开：

```bash
skill_root="${HOME}/.agents/skills/git-commit-helper"
bash "$skill_root/scripts/commit.sh" --repository "." <<'COMMIT_MESSAGE'
fix(订单状态): 兼容格式不一致的状态值

- 状态值包含多余空白或大小写差异时仍映射到统一业务状态
COMMIT_MESSAGE
```

### Windows 控制 WSL 仓库

显式指定发行版。以下示例假设仓库路径已经是该发行版中的 POSIX 路径；技能目录通过同一个发行版的 `wslpath` 转换。所有前置 `status`、`diff`、测试和最终 commit 也必须使用同一个 WSL Git。

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

不能确定 `$distro` 时先询问。不要把 `C:\...`、`\\wsl.localhost\...` 或 Windows 临时 index 直接传给 WSL Git，也不要用 Windows Git 提交已由 WSL Git 检查的 staged 内容。

## 4. `execute-mode`

用户：

> 提交git

仓库状态：`src/order.ts` 已 staged，`README.md` 只有 unstaged 改动。

行为：

1. 只分析和验证 staged 的 `src/order.ts`。
2. 结合测试、调用方或契约归纳这批订单改动的目的与影响。
3. 不把 `README.md` 加入 staged。
4. 在仓库所属 Git 环境中运行对应安全执行器。
5. 回报意图、主要影响、hash、完整 message 和剩余的 ` M README.md`。

staged 范围且提交语义清晰时，不再请求“是否确认范围”或“是否确认意图”。

## 5. staged 为空

用户只说“提交git”，但 staged 为空且存在多个修改文件。

行为：列出候选文件并询问要提交哪些路径。不要默认执行 `git add .`。

如果用户要求 `command-only` 且已经明确指定路径，完整命令必须先执行 `git add -- <paths>`，再依次运行 staged stat、name-status、check 和完整 diff，最后调用安全脚本；路径未明确时先询问，不输出提交命令。

## 6. 提交失败

当 hook、权限或 Git 状态导致 `git commit` 返回非零退出码时：

- 不运行成功态的 `git log` 并把旧 HEAD 当成新提交。
- 报告原始错误以及 HEAD 是否发生变化。
- 保持 staged 范围不变，等待用户处理或授权重试。

如果 pre-commit hook 执行 `git add` 或以其他方式改变 staged tree，当前平台执行器会检测 commit tree 不等于捕获点的快照，随后把 HEAD 恢复到父提交并保留真实 index。此时先检查 hook 产物、重新分析 staged diff，再决定是否重试。

如果 post-commit hook 或并发进程在本次 commit 后又推进 HEAD，执行器只报告“本次创建的 commit”和“当前 HEAD”，不会自动回退或删除任何分支引用，并明确提示不得重试 commit。

如果 HEAD 仍指向同一个 commit、但 symbolic HEAD 已切换到另一分支，执行器同样不会回滚；detached HEAD 下也禁用自动回滚，避免把引用检查退化成只比较 OID。
