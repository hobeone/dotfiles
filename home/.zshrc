# ==============================================================================
# .zshrc - ZSH Configuration File
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Powerlevel10k Instant Prompt
# ------------------------------------------------------------------------------
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


# ------------------------------------------------------------------------------
# 2. Oh-My-Zsh Configuration
# ------------------------------------------------------------------------------
# Path to your oh-my-zsh configuration.
export ZSH="$HOME/dotfiles/home/.ohmyzsh"

# Set name of the theme to load.
ZSH_THEME="powerlevel10k/powerlevel10k"

# Custom plugins directory
ZSH_CUSTOM="$HOME/dotfiles/home/.zsh_custom"

# Auto-update settings
DISABLE_AUTO_UPDATE="false"
export UPDATE_ZSH_DAYS=3

# Disable OMZ's built-in title management — we set it ourselves below
DISABLE_AUTO_TITLE="true"

# Plugin settings
COMPLETION_WAITING_DOTS="true"
zstyle :omz:plugins:ssh-agent agent-forwarding yes
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent quiet yes

# Suggestion styling
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bold,underline"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Which plugins would you like to load?
plugins=(
    git
    rsync
    cp
    history-substring-search
    golang
    tmux
    colorize
    systemd
    zsh-autosuggestions
    zsh-syntax-highlighting
    ssh-agent
)

# Initialize Oh-My-Zsh
source "$ZSH/oh-my-zsh.sh"


# ------------------------------------------------------------------------------
# 3. Path Configuration
# ------------------------------------------------------------------------------
[[ -d "/usr/local/go" ]] && export GOROOT="/usr/local/go"
[[ -d "$HOME/go" ]] && export GOPATH="$HOME/go"

typeset -U path
path=(
    ~/bin
    /bin
    /sbin
    /usr/local/bin
    /usr/sbin
    /usr/local/sbin
    /usr/bin
    /usr/games
    "$HOME/.local/bin"
    /usr/local/scripts
    ${GOROOT:+"$GOROOT/bin"}
    ${GOPATH:+"$GOPATH/bin"}
    /usr/X11R6/bin
    "$HOME/.pyenv/bin"
)


# ------------------------------------------------------------------------------
# 4. Environment Variables
# ------------------------------------------------------------------------------
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export PAGER="less -r"
export EDITOR="vim"
export NO_AT_BRIDGE=1      # Disable accessibility bus warnings
export COLORTERM='truecolor' # Enable 24-bit color support
export QUOTING_STYLE=literal # Prevent ls from wrapping spaces in single quotes

export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml,$HOME/.config/lazygit/tokyonight_night.yml"


# ------------------------------------------------------------------------------
# 5. Zsh Options & Shell Settings
# ------------------------------------------------------------------------------
# Directory Navigation
setopt AUTO_PUSHD          # Push directories to stack
setopt PUSHD_IGNORE_DUPS   # Don't push duplicates
setopt PUSHD_SILENT        # Don't print directory stack
setopt CHASE_LINKS         # Resolve symlinks

# General Behavior
setopt NOBEEP              # No system beeps
setopt NO_CHECK_JOBS       # Don't warn about bg processes when exiting
setopt NO_HUP              # Don't kill bg processes on exit
setopt INTERACTIVE_COMMENTS # Allow comments in interactive shell
setopt PRINT_EXIT_VALUE    # Alert if something fails

# Completion Behavior
unsetopt AUTO_MENU          # Don't cycle completions
setopt LIST_PACKED         # Compact completion lists
setopt LIST_TYPES          # Show types in completion
unsetopt COMPLETE_IN_WORD   # Not just at the end
setopt ALWAYS_TO_END       # Move cursor to end after completion
unsetopt CORRECT           # Disable spelling correction
unsetopt CORRECT_ALL       # Disable all spelling correction

# User-specific completion
complete_users=(root $USERNAME)
zstyle ':completion:*' users $complete_users
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache


# ------------------------------------------------------------------------------
# 6. History Configuration
# ------------------------------------------------------------------------------
export HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000

setopt SHARE_HISTORY       # Share history between sessions (implies INC_APPEND)
setopt HIST_IGNORE_ALL_DUPS # Don't record duplicates
setopt HIST_IGNORE_SPACE   # Don't record commands starting with a space
setopt HIST_REDUCE_BLANKS  # Remove extra blanks from commands
setopt EXTENDED_HISTORY    # Record timestamp and duration


# ------------------------------------------------------------------------------
# 7. Keybindings & ZLE
# ------------------------------------------------------------------------------
# History search with arrow keys (type prefix, then up/down to search)
autoload -U up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[A" up-line-or-beginning-search
bindkey "^[[B" down-line-or-beginning-search

# Make / - . act as word delimiters (for Ctrl+W, Alt+B, Alt+F, etc.)
WORDCHARS=${WORDCHARS//[\/\-\.]/}


# ------------------------------------------------------------------------------
# 8. Helper Functions
# ------------------------------------------------------------------------------
# Refresh environment variables within TMUX (keeps SSH_AUTH_SOCK/DISPLAY
# in sync after re-attaching).
if [[ -n "$TMUX" ]]; then
  refresh() {
    local v val
    for v in SSH_AUTH_SOCK DISPLAY; do
      val=$(tmux show-environment "$v" 2>/dev/null)
      [[ -n "$val" && "$val" != -* ]] && export "$val"
    done
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec refresh
fi


# ------------------------------------------------------------------------------
# 9. Aliases & Command Wrappers
# ------------------------------------------------------------------------------
# Basic Aliases
alias loadhistory="fc -RI"
alias vim='vim -X -o -u $HOME/.vimrc'
alias gvim='gvim -o -u $HOME/.vimrc -geom 80x24'
alias tmux='tmux -2'

# Completion for specific tools
compdef '_files -g "*.(par|PAR)2"' par2
compdef '_files -g "*.rar"' rar
compdef _files -g "*" scp

# Colorized output (dircolors)
if [[ -r ~/.dircolors ]]; then
  eval "$(dircolors ~/.dircolors)"
else
  eval "$(dircolors)"
fi

# Terminal Title Management
# precmd: set title to "user@host: ~/dir" when idle at prompt
# preexec: set title to "user@host: ~/dir | command" while a command runs
case $TERM in
  xterm*|rxvt|Eterm|tmux*|screen*)
    if [[ -n "$TMUX" ]]; then
      precmd () { print -Pn "\e]0;%~\a" }
      preexec () { print -Pn "\e]0;%~ | ${1}\a" }
    else
      precmd () { print -Pn "\e]0;%n@%M: %~\a" }
      preexec () { print -Pn "\e]0;%n@%M: %~ | ${1}\a" }
    fi
  ;;
esac

# bat (cat replacement; Debian installs as batcat)
if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
    alias bat='batcat'
fi
if command -v bat &>/dev/null; then
    alias cat="bat"
fi

# Modern Tooling (eza & zoxide)
if command -v eza &>/dev/null; then
    alias ls="eza --no-quotes"
    alias l="eza -l --icons --no-quotes"
    alias la="eza -la --icons --no-quotes"
    alias lt="eza -T --icons --no-quotes"
    alias lan="eza -la -snew --icons --no-quotes"
else
    alias ls="ls -G"
    alias l="ls -lhF"
    alias la="ls -lAhF"
fi

if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

# Lesspipe preprocessing
if [ -e "$HOME/bin/lesspipe.sh" ]; then
    export LESSOPEN="|$HOME/bin/lesspipe.sh %s"
fi

export LESS='-R'
export LESSEDIT="%E ?lt+%lt. %f"
export LESSCHARDEF=8bcccbcc13b.4b95.33b.


# ------------------------------------------------------------------------------
# 10. External Tools & Local Overrides
# ------------------------------------------------------------------------------
# NVM (Node Version Manager) — lazy-loaded for faster shell startup
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  _lazy_load_nvm() {
    unset -f nvm node npm npx 2>/dev/null
    \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  }
  function nvm  { _lazy_load_nvm; nvm  "$@"; }
  function node { _lazy_load_nvm; node "$@"; }
  function npm  { _lazy_load_nvm; npm  "$@"; }
  function npx  { _lazy_load_nvm; npx  "$@"; }
fi

# Local .zshrc if it exists
[[ -e ~/.zshrc.local ]] && source ~/.zshrc.local

# Powerlevel10k Configuration (Last)
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
