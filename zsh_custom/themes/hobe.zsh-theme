if [ $UID -eq 0 ]; then CARETCOLOR="red"; else CARETCOLOR="blue"; fi

PROMPT='%{$fg_bold[green]%}➜ %n@%m:%{$fg[cyan]%}%~%{${fg_bold[$CARETCOLOR]}%}» %{${reset_color}% '
