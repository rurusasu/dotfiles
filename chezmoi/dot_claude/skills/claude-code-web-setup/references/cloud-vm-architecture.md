# Cloud VM Architecture

## Directory Layout

```
/root/                    ← $HOME (setup script runs as root)
/home/user/<repo-name>/   ← repo clone location
/tmp/init-script-*.sh     ← where the cloud env setup script is written
```

## Execution Context

| Item          | Value                        |
| ------------- | ---------------------------- |
| User          | `root`                       |
| `$HOME`       | `/root/` (NOT `/home/user/`) |
| CWD at setup  | NOT the repo root            |
| Repo location | `/home/user/<repo-name>/`    |
| Node.js       | Pre-installed                |
| Git           | Pre-installed                |

## Common Errors

| Exit Code | Cause                                         | Fix                                               |
| --------- | --------------------------------------------- | ------------------------------------------------- |
| 127       | `bash: setup.sh: No such file or directory`   | CWD is not repo root — use `find` to locate       |
| 1         | `cd: /root/<repo>: No such file or directory` | `$HOME` is `/root/`, repo is under `/home/user/`  |
| 254       | `npm error ENOENT package.json`               | `cd` to correct subdirectory before `npm install` |
