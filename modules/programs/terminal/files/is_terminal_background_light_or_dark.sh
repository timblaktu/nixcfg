#!/bin/bash
old_settings=$(stty -g)
stty raw -echo min 0 time 1
# shellcheck disable=SC1003 # Terminal escape sequence requires literal backslash
printf '\033]11;?\033\\'
response=""
while IFS= read -r -n1 char; do
    response+="$char"
    [[ $char == $'\134' ]] && break  # ASCII 134 (octal) = backslash
done
stty "$old_settings"

if [[ $response =~ rgb:([0-9a-f]+)/([0-9a-f]+)/([0-9a-f]+) ]]; then
    r=$((0x${BASH_REMATCH[1]:0:2}))
    g=$((0x${BASH_REMATCH[2]:0:2}))
    b=$((0x${BASH_REMATCH[3]:0:2}))
    brightness=$((r * 299 + g * 587 + b * 114))
    [ $brightness -gt 128000 ] && echo "light" || echo "dark"
else
    echo "dark"
fi
