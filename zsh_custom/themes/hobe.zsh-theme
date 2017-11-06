if [ $UID -eq 0 ]; then CARETCOLOR="red"; else CARETCOLOR="blue"; fi
if [ $UID -eq 0 ]; then USERCOLOR="red"; else USERCOLOR="green"; fi

PROMPT='%{$fg_bold[$USERCOLOR]%}➜ %n@%m:%{$fg[cyan]%}%~%{${fg_bold[$CARETCOLOR]}%}>%{${reset_color}% '
