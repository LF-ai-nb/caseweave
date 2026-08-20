# 发布流程

## 发布前准备

1. 确认 `moon.mod` 中的包名与 Mooncakes 登录用户名一致。当前包名为 `LF-ai-nb/caseweave`。
2. 把 `repository` 改成公开 GitHub 仓库地址。
3. 确认 `README.md`、`CHANGELOG.md`、`NOTICE.md` 已更新。
4. 确认 Git 工作区干净。

## 本地验证

```bash
moon check --deny-warn
moon build
moon test
moon run cmd/main
```

## Mooncakes

```bash
moon login
moon publish --dry-run
moon publish
```

`moon publish --dry-run` 当前仍会读取本机 Mooncakes 登录凭证。CI 中的 dry-run 步骤默认关闭；如需打开，请在 GitHub 仓库变量中设置 `MOONCAKES_DRY_RUN=true`，并确保 runner 能获得发布凭证。

## 版本记录

```bash
git tag v0.1.0
git push origin main --tags
```

发布 GitHub Release 时，复制 `CHANGELOG.md` 中对应版本的内容。
