# maildir-notify.zsh — tell me about unread Maildir mail.
#
#   * On shell start, print one line if there is unread mail.
#   * While the shell is open, print a line above the prompt when new mail lands.
#
# .zshrc sources this ABOVE the Powerlevel10k instant-prompt block: output
# printed after instant prompt starts, up to the first prompt, trips p10k's
# console-output warning. It lives in $ZSH_CUSTOM/lib/ so Oh My Zsh does not
# source it a second time; OMZ only loads lib/ files that share a name with
# one of its own libs.
#
# zsh's own MAILPATH check does not report Maildir delivery reliably, so this
# counts unread messages instead, in the inbox and in any Maildir++ subfolder
# (.Folder/). A message is unread while it sits in new/, or in cur/ without the
# S (seen) flag in its ":2,<flags>" suffix. Only counting new/ is not enough:
# a client that scans the folder moves mail to cur/ while it is still unread.
#
# Settings (set them before this file is sourced, e.g. in ~/.zshenv):
#   MAILDIR_NOTIFY_DIR       Maildir root           (default: $MAILDIR or ~/Maildir)
#   MAILDIR_NOTIFY_INTERVAL  seconds between checks (default: 60; 0 = every prompt)

zmodload -F zsh/datetime p:EPOCHSECONDS
autoload -Uz add-zsh-hook

typeset -gi _maildir_notify_last_check=0
typeset -ga _maildir_notify_ids=()          # unread message ids at the last check

# _maildir_notify_scan — set $reply to the ids of the unread messages. Returns
# non-zero when there is no Maildir.
_maildir_notify_scan() {
  setopt local_options extended_glob
  local root=${MAILDIR_NOTIFY_DIR:-${MAILDIR:-$HOME/Maildir}}
  reply=()
  [[ -d $root/new ]] || return 1
  # (N) is nullglob, (.) means plain files only, and (D) also matches the
  # dot-named Maildir++ folders. "~*:2,*S*" drops cur/ messages flagged seen.
  local -a msgs=(
    $root/new/*(N.) $root/.*/new/*(N.D)
    $root/cur/*~*:2,*S*(N.) $root/.*/cur/*~*:2,*S*(N.D)
  )
  # A message's unique id is its file name without the ":2,<flags>" suffix,
  # and it stays the same when the message moves from new/ to cur/.
  reply=( ${${msgs:t}%%:2,*} )
}

_maildir_notify_where() { REPLY=${${MAILDIR_NOTIFY_DIR:-${MAILDIR:-$HOME/Maildir}}/#$HOME/\~} }

_maildir_notify() {
  local -i interval=${MAILDIR_NOTIFY_INTERVAL:-60}
  (( EPOCHSECONDS - _maildir_notify_last_check >= interval )) || return
  _maildir_notify_last_check=$EPOCHSECONDS

  local -a reply
  _maildir_notify_scan || return
  # Ids not seen last time. Comparing ids rather than counts still catches an
  # arrival when another message was read in the same interval.
  local -i arrived=${#${reply:|_maildir_notify_ids}}
  _maildir_notify_ids=( $reply )
  (( arrived )) || return
  local REPLY; _maildir_notify_where
  print -P "%F{yellow}📬 ${arrived} new message$( (( arrived == 1 )) || print s) in ${REPLY} (${#reply} unread)%f"
}

# Shell start: the one-time summary, which also sets the baseline the
# arrival check compares against.
() {
  local -a reply
  _maildir_notify_scan || return
  _maildir_notify_ids=( $reply )
  _maildir_notify_last_check=$EPOCHSECONDS
  local -i count=${#reply}
  (( count )) || return
  local REPLY; _maildir_notify_where
  print -P "%F{yellow}📬 You have ${count} unread message$( (( count == 1 )) || print s) in ${REPLY}%f"
}

add-zsh-hook precmd _maildir_notify
