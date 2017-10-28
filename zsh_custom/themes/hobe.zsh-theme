local ret_status="%(?:%{$fg_bold[green]%}➜ :%{$fg_bold[red]%}➜ )"

if [ $UID -eq 0 ]; then CARETCOLOR="red"; else CARETCOLOR="blue"; fi

PROMPT='${ret_status} %n@%m:%{$fg[cyan]%}%~%{${fg_bold[$CARETCOLOR]}%}» %{${reset_color}% '
