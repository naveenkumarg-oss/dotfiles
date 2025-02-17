# Goal

My primary driver is to use chezmoi to manage WSL2 and Windows config.

## To-do

- Fix starship: no background for battery and such group
- Complete goal and other parts of README

## Install WSL2 distro

### Latest

https://ubuntu.com/desktop/wsl

Feb, 2025
https://ubuntu.com/blog/ubuntu-wsl-new-format-available

```sh
wsl --install ubuntu
Downloading: Ubuntu
Installing: Ubuntu
Distribution successfully installed. It can be launched via 'wsl.exe -d Ubuntu'

wsl -l -v
  NAME                      STATE           VERSION
  Ubuntu                    Stopped         2

wsl -d Ubuntu
Provisioning the new WSL instance Ubuntu
This might take a while...
Create a default Unix user account: nkumar
New password:
Retype new password:

# Check wsl conf
cat /etc/wsl.conf
[boot]
systemd=true

[user]
default=<user>

# Create an empty ~/.hushlogin file
nano .hushlogin
```

### Dated and superceded by above
```sh
# https://learn.microsoft.com/en-us/windows/wsl/install
# https://learn.microsoft.com/en-us/windows/wsl/wsl-config

# Step 0: Update WSL
# if on canary (pre-release) stream
wsl --update --pre-release
# default
wsl --update

# Step 1: Download fresh Image
# 1 Download fresh Image
# Interim Releases are valid for 9 months while LTS release is valid for 5 years
# https://releases.ubuntu.com/
# Ubuntu WSL Images > <release> > current > ubuntu-<release>-wsl-amd64-wsl.rootfs.tar.gz
# At this time: 
	# LTS Releases: 24.04 (Noble Numbat) 22.04.4 (Jammy Jellyfish) 20.04.6 (Focal Fossa)
	# Interim Release: 23.10 (Mantic Minotaur)

cd c:\workplay\my_wsl_env\_base_ubuntu_wsl_images
curl -O https://cloud-images.ubuntu.com/wsl/releases/noble/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz

# Step 2: Import distribution
# Create a new instance of WSL by importing base image
# ubuntu-2404 directory will be auto created
wsl --import ubuntu-<postfix> c:\workplay\my_wsl_env\__wsl_install_dir\ubuntu-2404 c:\workplay\my_wsl_env\_base_ubuntu_wsl_images\<file-name-from-previous-step>
Example: 
wsl --import ubuntu-2404 c:\workplay\my_wsl_env\__wsl_install_dir\ubuntu-2404 C:\workplay\my_wsl_env\_base_ubuntu_wsl_images\ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz

# Step 3: First login
wsl -d ubuntu-2404

# Setup user accounts
NEW_USER=bndev
useradd -m -G sudo -s /bin/bash "$NEW_USER"
passwd "$NEW_USER"
	# on prompt, enter <your-secret-password>

# Configure default user: paste the entire block of code below into your teminal and press enter
tee /etc/wsl.conf <<_EOF
[user]
default=${NEW_USER}

[boot]
systemd=true
_EOF

# shutdown instance and restart
exit

wsl -t ubuntu-2404
sleep 10
wsl -l -v
wsl -d ubuntu-2404

# Step 4: ONLY WHEN REQUIRED
# pruge this installation, removing all traces of existence
wsl -t ubuntu-2404
wsl --unregister ubuntu-2404
```

## Install chezmoi

### On Windows

```sh
# Windows
# Set temporary permission for current and child process to run ps script. 
# Refer: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.4#set-a-different-policy-for-one-session
pwsh.exe -ExecutionPolicy Unrestricted
'$params = "-BinDir $HOME\.local\bin"', (irm -useb https://get.chezmoi.io/ps1) | powershell -c -

# Test install
$Env:Path += ";$HOME\.local\bin"
chezmoi --version
```

### On Linux (WSL)

# WSL, Linux
# wget comes preinstalled with Ubuntu; curl many not be. Prefer wget here.
```sh
sh -c "$(wget -qO- get.chezmoi.io)" -- -b $HOME/.local/bin -- init --apply naveenkumarg-oss
	# sh -c "$(curl -fsLS get.chezmoi.io)" -- -b $HOME/.local/bin -- init --apply naveenkumarg-oss

~/.local/bin/chezmoi cd # Same as running cd ~/.local/share/chezmoi/dot_zshrc
~/.local/bin/chezmoi data
~/.local/bin/chezmoi apply
~/.local/bin/chezmoi update
chezmoi unmanaged
```

## Credits

I have learned about scripting in general and specifically usage of chezmoi from below repos/users. Your work is greatly appreciated.

In customizing to my own need, I have referred to and used _as is_ scripts from https://github.com/felipecrs/dotfiles (for linux) and https://github.com/renemarc/dotfiles (for windows) repos. Thanks for your brilliance and patience to create a very detailed scripts. Full credit goes to original author(s).

### Linux

- https://github.com/felipecrs/dotfiles/tree/master
- https://github.com/twpayne/dotfiles/tree/master

### Windows

- https://github.com/renemarc/dotfiles/tree/master


# Cross-shell compatibility matrix 🏁

These are unified CLI commands available amongst different shells on all platforms. While some of their outputs may differ in style between different environments, their usage and behaviours remain universal.

Additional aliases are provided by [Bash-It](https://github.com/Bash-it/bash-it/tree/master/aliases/available), [Oh-My-Zsh](https://github.com/ohmyzsh/ohmyzsh/wiki/Cheatsheet) and [Powershell](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_aliases), and are listed by using the command `alias`.

System-specific aliases are marked with <b title="macOS"></b>, <b title="Windows">⊞</b>, or <sub><sup><b title="Linux">🐧</b></sup></sub>.

### 🧭 Easier navigation

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅ | `~`      | Navigates to user home directory. |
| ✅   | ✅         | ✅ | `cd-`    | Navigates to last used directory. |
| ✅   | ✅         | ✅ | `..`<br>`cd..` | Navigates up a directory. |
| ✅   | ✅         | ✅ | `...`    | Navigates up two directories. |
| ✅   | ✅         | ✅ | `....`   | Navigates up three directories. |
| ✅   | ✅         | ✅ | `.....`  | Navigates up four directories. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🗂️ Directory browsing

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `l`     | Lists visible files in long format. |
| ✅   | ✅         | ✅  | `ll`    | Lists all files in long format, excluding `.` and `..`. |
| ✅   | ✅         | ✅  | `lsd`    | Lists only directories in long format. |
| ✅   | ✅         | ✅  | `lsh`   | Lists only hidden files in long format. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🗄️ File management

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `cpv`   | Copies a file securely. |
| ✅   | ✅         | ✅  | `fd`    | Finds directories. |
| ✅   | ✅         | ✅  | `ff`    | Finds files. |
| ❌   | ✅         | ❌  | `mirror` | Mirrors directories. |
| ✅   | ✅         | ✅  | `rg`    | Searches recursively with [ripgrep](https://github.com/BurntSushi/ripgrep). |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 💡 General aliases

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `alias` | Lists aliases. |
| ✅   | ✅         | ✅  | `c`     | Clears the console screen. |
| ✅   | ❌         | ✅  | `extract`<br>`x` | Extracts common file formats.<br>_Usage: `extract solarized.zip`_ |
| ✅   | ✅         | ✅  | `h`     | Displays/Searches global history.<br>_Usage: `h`_<br>_Usage: `h cd`_ |
| ✅   | ✅         | ⚠️  | `hs`    | Displays/Searches session history.<br>_Usage: `hs`_<br>_Usage: `hs cd`_ |
| ✅   | ✅         | ✅  | `mkcd`<br>`take` | Creates directory and change to it.<br>_Usage: `mkcd foldername`_ |
| ✅   | ❌         | ✅  | `reload` | Reloads the shell. |
| ✅   | ✅         | ✅  | `repeat`<br>`r` | Repeats a command `x` times.<br>_Usage: `repeat 5 echo hello`_. |
| ✅   | ❌         | ✅  | `resource` | Reloads configuration. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🕙 Time

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `now`<br>`unow` | Gets local/UTC date and time in [ISO 8601](https://xkcd.com/1179/) format `YYYY-MM-DDThh:mm:ss`. |
| ✅   | ✅         | ✅  | `nowdate`<br>`unowdate` | Gets local/UTC date in `YYYY-MM-DD` format. |
| ✅   | ✅         | ✅  | `nowtime`<br>`unowtime` | Gets local/UTC time in `hh:mm:ss` format. |
| ✅   | ✅         | ✅  | `timestamp` | Gets Unix time stamp. |
| ✅   | ✅         | ✅  | `week`  | Gets week number in [ISO 8601](https://en.wikipedia.org/wiki/ISO_8601#Week_dates) format `YYYY-Www`. |
| ✅   | ✅         | ✅  | `weekday` | Gets weekday number. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🌐 Networking

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `fastping` | Pings hostname(s) 30 times in quick succession. |
| ✅   | ✅         | ✅  | `flushdns` | Flushes the DNS cache. |
| ✅   | ✅         | ✅  | `ips`   | Gets all IP addresses. |
| ✅   | ✅         | ✅  | `localip` | Gets local IP address. |
| ✅   | ✅         | ✅  | `publicip` | Gets external IP address. |
| ✅   | ✅         | ✅  | `GET`<br>`HEAD`<br>`POST`<br>`PUT`<br>`DELETE`<br>`TRACE`<br>`OPTIONS` | Sends HTTP requests.<br>_Usage: `GET https://example.com` |_

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### ⚡ Power management

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `hibernate` | Hibernates the system. |
| ✅   | ✅         | ✅  | `lock`  | Locks the session. |
| ✅   | ✅         | ✅  | `poweroff` | Shuts down the system. |
| ✅   | ✅         | ✅  | `reboot` | Restarts the system. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🤓 Sysadmin

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `mnt`   | Lists drive mounts. |
| ✅   | ✅         | ✅  | `path`  | Prints each `$PATH` entry on a separate line. |
| ✅   | ✅         | ✅  | `sysinfo` | Displays information about the system.<br><strong><sup>Uses either [Winfetch](https://github.com/lptstr/winfetch), [Neofetch](https://github.com/dylanaraps/neofetch), or [Screenfetch](https://github.com/KittyKatt/screenFetch).</sup></strong> |
| ✅   | ✅         | ✅  | `top`   | Monitors processes and system resources.<br><strong><sup>Uses either [atop](https://linux.die.net/man/1/atop), [htop](https://hisham.hm/htop/), [ntop](https://github.com/Nuke928/NTop) <b title="windows">⊞</b>, or native.</sup></strong> |
| ✅   | ✅         | ✅  | `update` | Keeps all apps and packages up to date. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🖥️ Applications

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `browse` | Opens file/URL in default browser.<br>_Usage: `browse https://example.com`_ |
| ✅   | ✅         | ✅  | `chrome` | Opens file/URL in [Chrome](https://www.google.com/chrome/). |
| ✅   | ✅         | ✅  | `edge` | Opens file/URL in [Microsoft Edge](https://www.microsoft.com/en-us/edge). |
| ✅   | ✅         | ✅  | `firefox` | Opens file/URL in [Firefox](https://www.mozilla.org/en-CA/firefox/). |
| ❔   | ✅         | ❔  | `iexplore` | Opens file/URL in [Internet Explorer](https://www.microsoft.com/ie). <b title="Windows">⊞</b> |
| ✅   | ✅         | ✅  | `opera` | Opens file/URL in [Opera](https://www.opera.com/). |
| ✅   | ✅         | ✅  | `safari` | Opens file/URL in [Safari](https://www.apple.com/ca/safari/). <b title="macOS"></b> |
| ✅   | ✅         | ✅  | `ss`    | Enters the [Starship 🚀](https://starship.rs) cross-shell prompt. |
| ✅   | ✅         | ✅  | `subl`<br>`st`  | Opens in [Sublime Text](https://www.sublimetext.com/). |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 👩‍💻 Development

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `dk`    | 🐳 Alias for [`docker`](https://www.docker.com/). |
| ✅   | ✅         | ✅  | `dco`   | 🐳 Alias for [`docker-compose`](https://docs.docker.com/compose/). |
| ✅   | ✅         | ✅  | `g`     | :octocat: Alias for [`git`](https://git-scm.com/). |
| ✅   | ✅         | ✅  | `va`    | 🐍 Activates Python [virtual environment `venv`](https://docs.python.org/3/tutorial/venv.html). |
| ✅   | ✅         | ✅  | `ve`    | 🐍 Creates Python [virtual environment `venv`](https://docs.python.org/3/tutorial/venv.html). |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

###  macOS

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `hidedesktop`<br>`showdesktop` | Toggles display of desktop icons. |
| ✅   | ✅         | ✅  | `hidefiles`<br>`showfiles` | Toggles hidden files display in [Finder](https://support.apple.com/en-ca/HT201732). |
| ✅   | ✅         | ✅  | `spotoff`<br>`spoton` | Toggles [Spotlight](https://support.apple.com/en-ca/HT204014). |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### ⊞ Windows

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ❔   | ✅         | ❔  | `hidefiles`<br>`showfiles` | Toggles hidden files display in [File Explorer](https://support.microsoft.com/en-ca/help/4026617/windows-10-windows-explorer-has-a-new-name). |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 📁 Common paths

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `dls`   | Navigates to `~/Downloads`. |
| ✅   | ✅         | ✅  | `docs`  | Navigates to `~/Documents`. |
| ✅   | ✅         | ✅  | `dt`    | Navigates to `~/Desktop`. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 📁 Configuration paths

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `chezmoiconf` | Navigates to [Chezmoi](https://www.chezmoi.io/)'s local configuration repo. |
| ✅   | ✅         | ✅  | `powershellconf` | Navigates to [Powershell](https://github.com/PowerShell/PowerShell)'s profile location. |
| ✅   | ✅         | ✅  | `sublimeconf` | Navigates to [Sublime Text](https://www.sublimetext.com/)'s local configuration repo. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 📁 Custom paths

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `archives` | Navigates to `~/Archives`. |
| ✅   | ✅         | ✅  | `repos` | Navigates to `~/Code`. |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>

### 🌱 Varia

| Bash | PowerShell | Zsh | Command | Description |
|:----:|:----------:|:---:|---------|-------------|
| ✅   | ✅         | ✅  | `cb`    | 📋 Copies contents to the clipboard. |
| ✅   | ✅         | ✅  | `cbpaste` | 📋 Pastes the contents of the clipboard. |
| ✅   | ✅         | ✅  | `md5sum` | #️⃣ Calculates MD5 hashes. |
| ✅   | ✅         | ✅  | `sha1sum`  | #️⃣ Calculates SHA1 hashes. |
| ✅   | ✅         | ✅  | `sha256sum` | #️⃣ Calculates SHA256 hashes. |
| ✅   | ✅         | ✅  | `forecast` | 🌤️ Displays [detailed weather and forecast](https://wttr.in/?n). |
| ✅   | ✅         | ✅  | `weather` | 🌤️ Displays [current weather](https://wttr.in/?format=%l:+(%C)+%c++%t+[%h,+%w]). |

<p align="right"><a href="#top" title="Back to top">🔝</a></p>


## Ubuntu

### Oh-My-Zsh

#### Plugins

- 