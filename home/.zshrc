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
export ZSH="$HOME/dotfiles/home/ohmyzsh"

# Set name of the theme to load.
ZSH_THEME="powerlevel10k/powerlevel10k"

# Custom plugins directory
ZSH_CUSTOM="$HOME/dotfiles/home/zsh_custom"

# Auto-update settings
DISABLE_AUTO_UPDATE="false"
export UPDATE_ZSH_DAYS=3

# Plugin settings
COMPLETION_WAITING_DOTS="true"
zstyle :omz:plugins:ssh-agent agent-forwarding yes
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent quiet yes

# Suggestion styling
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#ff00ff,bg=cyan,bold,underline"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# Which plugins would you like to load?
plugins=(
    git 
    ruby 
    rsync 
    rvm 
    bundler 
    cp 
    history-substring-search 
    themes 
    npm 
    bower 
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
export GOPATH="$HOME/go"
export GOROOT="/usr/local/go"

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
    "$GOROOT/bin"
    "$GOPATH/bin"
    /usr/X11R6/bin
    /home/hobe/.pyenv/bin
)


# ------------------------------------------------------------------------------
# 4. Environment Variables
# ------------------------------------------------------------------------------
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export PAGER=less
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
setopt SH_WORD_SPLIT       # Bourne shell word splitting behavior
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
HISTSIZE=32768
SAVEHIST=32768

setopt APPEND_HISTORY      # Append to history file rather than replace
setopt SHARE_HISTORY       # Share history between sessions
setopt HIST_IGNORE_ALL_DUPS # Don't record duplicates
setopt HIST_REDUCE_BLANKS  # Remove extra blanks from commands
setopt EXTENDED_HISTORY    # Record timestamp and duration
setopt INC_APPEND_HISTORY  # Write to history file immediately


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
WORDCHARS=${WORDCHARS/\//}
WORDCHARS=${WORDCHARS/\-/}
WORDCHARS=${WORDCHARS/\./}


##############################################################################
# basic env
##############################################################################
#unset MAIL
#export MAILDIR="~/Maildir/"

export PAGER="less -r"
export EDITOR="vim"

case $TERM in
  xterm*|rxvt|Eterm)
    precmd () {print -Pn "\e]0;%n@%M: %~\a"}
  ;;
esac

# Disables warnings about "Couldn't register with accessibility bus"
export NO_AT_BRIDGE=1

# Truecolor support - apps check this env var for 24-bit color capability
export COLORTERM='truecolor'

##############################################################################
# command aliases
##############################################################################
# If running interactively, then:
if [ "$PS1" ]; then
  alias ls='ls --color=auto'
  eval `dircolors`
fi
d=~/.dircolors
test -r $d && eval "$(dircolors $d)"

# https://unix.stackexchange.com/questions/258679/why-is-ls-suddenly-wrapping-items-with-spaces-in-single-quotes
export QUOTING_STYLE=literal

alias par="parchive"
compdef '_files -g "*.(par|PAR)2"' par2
compdef '_files -g "*.rar"' rar

alias irb='irb -r irb/completion'
alias ri='ri --format ansi'

alias vim='vim -X -o -u $HOME/.vimrc "$@"'
alias gvim='gvim -o -u $HOME/.vimrc -geom 80x24 "$@"'

alias tmux='tmux -2'

# Check if 'bat' does NOT exist, but 'batcat' DOES exist.  Debian installs the command as batcat
if ! command -v bat &> /dev/null && command -v batcat &> /dev/null; then
    alias bat='batcat'
fi

# ==============================================================================
# File Listing
# ==============================================================================

# Use eza if available, otherwise fall back to ls
if command -v eza &>/dev/null; then
    alias ls="eza --no-quotes"
    alias l="eza -l --icons --no-quotes"
    alias la="eza -la --icons --no-quotes"
    alias lt="eza -T --icons --no-quotes"  # tree view
else
    alias ls="ls -G"
    alias l="ls -lhF"
    alias la="ls -lAhF"
fi

# ==============================================================================
# zoxide (smart cd)
# ==============================================================================

if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi

##############################################################################
# command configuration
##############################################################################
if [ -e $HOME/bin/lesspipe.sh ]; then
    export LESSOPEN="|$HOME/bin/lesspipe.sh %s" # preprocess compressed files
fi

LESS='-R'
LESSEDIT="%E ?lt+%lt. %f"
LESSCHARDEF=8bcccbcc13b.4b95.33b. # show colours in ls -l | less
export LESS LESSEDIT LESSCHARDEF

export CVS_RSH=ssh
export RSYNC_RSH=ssh

# ------------------------------------------------------------------------------
# 8. Helper Functions
# ------------------------------------------------------------------------------
# Search for a process by name
psgrep() {
  ps aux | \grep -i "$1" | \grep -vi "grep $1"
}

# Search history for a pattern
hgrep() {
  history | grep -i "$1" | grep -vi "grep $1"
}

# Kill processes matching a search term
pskill() {
    local signal="TERM"
    if [[ $1 == "" || $3 != "" ]]; then
        print "Usage: pskill search_term [signal]" && return 1
    fi
    [[ $2 != "" ]] && signal=$2
    set -A pids $(command ps -elf | \grep "$1" | \grep -v "grep $1" | awk '{ print $4 }')
    
    if [[ ${#pids} -lt 1 ]]; then
        print "No matching processes for $1" && return 1
    fi
    if [[ ${#pids} -gt 1 ]]; then
        print "${#pids} processes matched: $pids"
        read -q "?Kill all? [y/n] " || return 0
    fi
    if kill -$signal $pids; then
        echo "Killed $1 pid $pids with SIG$signal"
    fi
}

# Refresh environment variables within TMUX
if [ -n "$TMUX" ]; then
  function refresh {
    new_auth=$(tmux show-environment | grep "^SSH_AUTH_SOCK")
    new_display=$(tmux show-environment | grep "^DISPLAY")
    if [ -n "$new_auth" ]; then
      export "$new_auth"
    fi
    if [ -n "$new_display" ]; then
      export "$new_display"
    fi
  }
else
  function refresh { }
fi

# Run refresh before each command
function preexec {                                                                                    
    refresh                                                                                           
}


# ------------------------------------------------------------------------------
# 9. Aliases & Command Wrappers
# ------------------------------------------------------------------------------
# Basic Aliases
alias loadhistory="fc -RI"
alias irb='irb -r irb/completion'
alias ri='ri --format ansi'
alias vim='vim -X -o -u $HOME/.vimrc "$@"'
alias gvim='gvim -o -u $HOME/.vimrc -geom 80x24 "$@"'
alias tmux='tmux -2'
alias par="parchive"

# Completion for specific tools
compdef '_files -g "*.(par|PAR)2"' par2
compdef '_files -g "*.rar"' rar
compdef _files -g "*" scp

# Colorized output
if [ "$PS1" ]; then
  alias ls='ls --color=auto'
  eval `dircolors`
fi
[[ -r ~/.dircolors ]] && eval "$(dircolors ~/.dircolors)"

# Terminal Title Management
case $TERM in
  xterm*|rxvt|Eterm)
    precmd () {print -Pn "\e]0;%n@%M: %~\a"}
  ;;
esac

# Modern Tooling (eza & zoxide)
if command -v eza &>/dev/null; then
    alias ls="eza --no-quotes"
    alias l="eza -l --icons --no-quotes"
    alias la="eza -la --icons --no-quotes"
    alias lt="eza -T --icons --no-quotes"
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
# NVM (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Local .zshrc if it exists
[[ -e ~/.zshrc.local ]] && source ~/.zshrc.local

# Powerlevel10k Configuration (Last)
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
