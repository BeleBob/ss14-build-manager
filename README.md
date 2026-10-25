# ss14-build-manager

Install and manage Space Station 14 servers (several builds on one shared port) from a single command.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/BeleBob/ss14-build-manager/main/install.sh | bash
```

The installer asks for the command name (default `ss14`), installs the manager under that name into `~/.local/bin`, and then starts the build setup.

## Usage

```text
<command>                  interactive menu
<command> install [preset] install a build (astra, reserve, sunrise, lust, goob, deadspace)
<command> start|stop|restart|status|logs|update [build]
<command> list | doctor | settings | remove <build>
<command> uninstall        remove the command (repositories stay)
```

## Requirements

Linux with systemd user session, git, curl, and the .NET SDK (installed automatically when missing, the required version is read from the repository's `global.json`).

## Uninstall

```sh
<command> uninstall
```

It asks before removing the command and before removing settings in `~/.config/ss14` and `~/.local/state/ss14`. Build repositories are never deleted.
