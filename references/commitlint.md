# 目标仓库的 commitlint 接入与校验

仅在首次了解目标仓库、接入工具、执行消息校验或处理具体故障时读取。结构规则由目标仓库实际生效的 commitlint 配置提供，本文的默认配置仅用于新接入。

## 发现与引导

在目标 Git 所属的环境中执行。复用已有信息，只补读配置、依赖与 hook 的缺项：

- 在仓库及所属 workspace 根目录查找 commitlint 支持的配置（如 `commitlint.config.*`、`.commitlintrc*`、`package.json` 中的 `commitlint`），以及 `@commitlint/cli` 和共享配置依赖。不要只检测一个固定文件名；有本地 CLI 时用 `--print-config json` 确认从目标目录解析的最终规则。
- 包管理器沿用 `packageManager` 字段或已知项目命令，再参考锁文件。多个锁文件导致选择不明时才询问；不引入第二种锁文件。monorepo 在管理工具依赖和 hook 的根目录接入，并从实际目标目录确认配置解析结果。
- 读取 `git config --get core.hooksPath` 和现有 hook 管理配置，确认实际启用的 `commit-msg` 链路；配置存在不等于 hook 已安装。
- 完整接入后复用该结果。只有配置、依赖或运行环境改变，或发生故障时才重新检查。

未配置时，只问一个具体问题，例如：

> 当前仓库尚未配置 commitlint。是否接入？将沿用 pnpm 添加开发依赖和规则，并在现有提交 hook 中加入校验；已有暂存区保持原样。也可以跳过本次校验。

非 Node 仓库还应明确将新增 `package.json`、锁文件及 Node 开发工具链。用户已授权接入时不重复询问；拒绝后本会话不再询问，不写“已拒绝”标记文件。只有 CLI 而没有配置，也按未配置处理；已有配置但缺依赖时说明缺项，沿用已有安装授权，否则先询问是否安装。

配置与本地 CLI 已可用、仅缺 hook 时，前置消息校验照常执行，单独引导补齐 hook。用户暂不启用 hook 时说明提交时尚无自动拦截，不能把已经通过的前置校验误报为“未经校验”。

## 同意后接入

1. 使用目标仓库的包管理器添加 `@commitlint/cli` 与所需共享配置作为开发依赖。选择兼容其 Node 版本的受支持版本；不直接修改系统 Node。非 Node 仓库创建最小私有 `package.json`，并忽略 `node_modules/`。保留已有依赖、脚本、配置与锁文件。
2. 仅对没有配置的仓库添加以下 `commitlint.config.cjs`；已有规则保持不变。若工具链不支持该格式，使用其支持的等价配置格式：

```javascript
module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'subject-case': [0],
  },
};
```

默认继承 Conventional Commits 规则，关闭描述大小写限制以容纳中文和 Git、WSL 等技术名词。允许的类型、长度等均交给配置解析，不在技能中再维护一份规则表。

3. 沿用 Husky、Lefthook、原生 hook 或其他现有管理方式，将本地 commitlint 的 `--edit "$1"` 接入实际 `commit-msg` 链路。按对应管理器传递消息文件参数，路径始终正确引用；原生 hook 保留 shebang 和可执行权限。保留已有 hook 命令、顺序及失败退出行为，不替换现有 `core.hooksPath`。
4. 没有管理方式、没有现有自定义 hook 时添加 Husky。npm、pnpm、Bun 通过 `prepare` 执行 `husky`，Yarn 使用其支持的 `postinstall`；已有生命周期脚本时保留其行为再追加。安装 hook 后创建 `.husky/commit-msg`，保证 LF。不要使用会生成额外 `pre-commit` 测试的初始化命令。若仓库已有原生或自定义 hook，就在原链路追加，不另装 Husky。
5. 运行所需的 hook 安装命令，检查最终规则，并以仓库外的临时消息验证本地 CLI；真实 hook 的拦截验证在隔离仓库完成，不为验证在用户仓库制造 commit。接入文件保持未暂存，除非用户另有明确范围授权。

本地 CLI 调用按现有包管理器选择，下面的参数后可追加 `--print-config json` 或 `--edit <消息文件>`：

| 包管理器 | 本地命令 | 默认 Husky `commit-msg` 内容 |
| --- | --- | --- |
| npm | `npm exec --no -- commitlint` | `npm exec --no -- commitlint --edit "$1"` |
| pnpm | `pnpm exec commitlint` | `pnpm exec commitlint --edit "$1"` |
| Yarn | `yarn exec commitlint` | `yarn exec commitlint --edit "$1"` |
| Bun | `bun run commitlint` | `bun run commitlint --edit "$1"` |

若仓库已经有承担消息校验的脚本，检查后复用其配置和参数。工具必须来自目标仓库本地依赖；禁止通过 `dlx`、临时远程包、全局 CLI 或自动安装回退来掩盖缺失依赖。Yarn PnP 沿用其运行环境，不假定存在 `node_modules/.bin`。

## 生成后的校验

`message-only`、`command-only`、`execute-mode` 都对最终候选消息执行同一次前置校验。下面示例为 npm 项目；其他包管理器替换本地 CLI 命令即可。工作目录必须是目标仓库的配置解析目录；临时文件必须在仓库外。若系统临时目录落在仓库内，另选仓库外可写目录，不能直接套用示例。

### PowerShell

候选文本放在 `$message`，不得通过插值 shell 命令传递文本。使用 UTF-8 无 BOM 文件，避免 PowerShell 管道编码差异：

```powershell
$messageFile = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText(
        $messageFile,
        $message.TrimEnd([char[]]"`r`n") + "`n",
        [Text.UTF8Encoding]::new($false)
    )
    & npm exec --no -- commitlint --edit $messageFile
    if ($LASTEXITCODE -ne 0) {
        throw "commitlint 校验失败；根据错误修正消息或处理环境故障。"
    }
}
finally {
    Remove-Item -LiteralPath $messageFile -ErrorAction Stop
}
```

### Bash / WSL / Linux / macOS

用 quoted heredoc 写入最终候选文本，delimiter 不得与消息中的独立一行相同。以下用子 shell 保持调用者原有 trap：

```bash
(
    message_file="$(mktemp "${TMPDIR:-/tmp}/commitlint-message.XXXXXXXX")" || exit 1
    trap 'rm -f -- "$message_file"' EXIT
    cat > "$message_file" <<'COMMITLINT_MESSAGE'
fix(订单状态): 兼容格式不一致的状态值
COMMITLINT_MESSAGE
    npm exec --no -- commitlint --edit "$message_file"
)
```

从 Windows 控制 WSL 时，发现配置、依赖安装、消息临时文件、commitlint 与 commit 均在同一个发行版完成。不要把 Windows Node 或临时消息路径交给 WSL CLI。

## 校验结果与提交

- 退出码为零才视为通过；warning 保留目标仓库原有严重级别。通过后仅返回或提交已校验的文本，文本改变就重新校验。临时文件使用相同的换行规范，不修改 `.git/COMMIT_EDITMSG`。
- 规则错误时依据诊断修正消息；不改变含义、不编造信息，也不修改规则或添加 ignore 来“通过”。用户明确格式与配置冲突、语义无法保守修正时，说明具体冲突再询问。
- 配置加载失败、依赖缺失、Node 不兼容或 hook 安装失败属于环境故障，不是消息通过；报告阻塞，不静默退回文档规范。只有用户明确选择跳过接入时才走未经校验的流程。
- `command-only` 可以运行消息校验，但不运行所生成的暂存或提交命令。`execute-mode` 前置校验后仍调用原有执行器，由实际 `commit-msg` hook 再校验；不使用 `--no-verify` 或禁用 hook。
- hook 拒绝提交时沿用执行器的失败输出；状态不确定或提示 `Do not retry commit` 时不自动重试。接入及消息校验均不改变真实 index 或提交范围。

参考：[配置格式](https://commitlint.js.org/reference/configuration.html)、[CLI](https://commitlint.js.org/reference/cli.html)、[本地 hook 接入](https://commitlint.js.org/guides/local-setup)、[Husky 手动配置](https://typicode.github.io/husky/how-to.html#manual-setup)。
