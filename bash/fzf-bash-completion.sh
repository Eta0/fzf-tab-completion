_FZF_COMPLETION_SEP=$'\x01'

if builtin command -v gawk &>/dev/null; then
    _fzf_bash_completion_awk=gawk
else
    _fzf_bash_completion_awk=awk
fi

# Most helpers below return results in variables, so calling them needs no
# command substitution. Scalars come back in REPLY and arrays in
# _fzf_lines. Callers copy them out before calling the next helper.

# Remove the backslash from every backslash-escaped character in $1. A
# backslash at the very end stays.
_fzf_bash_completion_unescape() {
    local rest="$1" out=
    while [[ "$rest" == *\\?* ]]; do
        out+="${rest%%\\*}"
        rest="${rest#*\\}"
        out+="${rest:0:1}"
        rest="${rest:1}"
    done
    REPLY="$out$rest"
}

# Split $1 on newlines into _fzf_lines, dropping empty lines.
_fzf_bash_completion_split_lines() {
    local IFS=$'\n' noglob=
    [[ "$-" == *f* ]] && noglob=1
    set -f
    _fzf_lines=( $1 )
    [ -n "$noglob" ] || set +f
}

# Tokenize each line of $1 into _fzf_lines. At each position the token is
# the longest of these that matches there:
#
#   a run of | or of &
#   a redirection operator, which is a run of < or of > together with the &
#     or | that follows in <& >& and >|, or &> and &>>
#   one of ; ( )
#   { or } as a reserved word, which is a whole word at the start of a line
#     or after a token that _fzf_bash_completion_command_follows accepts
#   a word made of escaped characters, $x special parameters, ${...}
#     expansions with nested ${...} inside, and characters outside the
#     break set
#   $'...' with backslash escapes, to its closing quote or the end of the line
#   '...' to its closing quote or the end of the line
#   a double-quoted string, which always runs to the end of its line and is
#     split further by _fzf_bash_completion_parse_dq
#   a run of whitespace
#   any other single character
#
# The break set is whitespace, $ \ | " ' ; ( ) & < > and the characters of
# $wordbreaks. Newlines separate lines and never appear in tokens.
_fzf_bash_completion_shell_split() {
    local breaks='[$\\|"[:space:];()&<>'\' i
    for (( i = 0; i < ${#wordbreaks}; i++ )); do
        breaks+="\\${wordbreaks:i:1}"
    done
    breaks+=']'

    local rest="$1" line token next chunk scan depth part command_start
    _fzf_lines=()
    while true; do
        line="${rest%%$'\n'*}"
        command_start=1
        while [ -n "$line" ]; do
            case "$line" in
                \|*) token="${line%%[!|]*}" ;;
                \&*)
                    token="${line%%[!&]*}"
                    if [[ "$line" == '&>'* ]]; then
                        next="${line:1}"
                        token="&${next%%[!>]*}"
                    fi
                    ;;
                \<*)
                    token="${line%%[!<]*}"
                    [[ "${line:${#token}:1}" == '&' ]] && token+='&'
                    ;;
                \>*)
                    token="${line%%[!>]*}"
                    [[ "${line:${#token}:1}" == [\&\|] ]] && token+="${line:${#token}:1}"
                    ;;
                [\;\(\)]*) token="${line:0:1}" ;;
                \{|\{[[:space:]]*|\}|\}[[:space:]\;\|\&\(\)\<\>]*)
                    if [ -n "$command_start" ]; then
                        token="${line:0:1}"
                    else
                        _fzf_bash_completion_split_word
                    fi
                    ;;
                \"*) token="$line" ;;
                \'*)
                    token="${line:1}"
                    if [[ "$token" == *\'* ]]; then
                        token="'${token%%\'*}'"
                    else
                        token="$line"
                    fi
                    ;;
                [[:space:]]*) token="${line%%[![:space:]]*}" ;;
                \$\'*)
                    token="\$'"
                    next="${line:2}"
                    while true; do
                        chunk="${next%%[\\\']*}"
                        token+="$chunk"
                        next="${next:${#chunk}}"
                        case "$next" in
                            \\?*) token+="${next:0:2}"; next="${next:2}" ;;
                            \\) token+="$next"; break ;;
                            \'*) token+=\'; break ;;
                            *) break ;;
                        esac
                    done
                    ;;
                *) _fzf_bash_completion_split_word ;;
            esac
            _fzf_lines+=( "$token" )
            line="${line:${#token}}"

            if [[ "$token" != [[:space:]]* ]]; then
                command_start=
                _fzf_bash_completion_command_follows "$token" && command_start=1
            fi
        done
        [[ "$rest" == *$'\n'* ]] || break
        rest="${rest#*$'\n'}"
    done
}

# Succeed when a command can start right after the token $1.
_fzf_bash_completion_command_follows() {
    case "$1" in
        \;|\&|\&\&|\||\|\||\|\&|\(|\{|\!|if|then|else|elif|while|until|do|time|coproc) return 0 ;;
    esac
    return 1
}

# Set token to the word at the start of $line for
# _fzf_bash_completion_shell_split, or to its first character if no word
# starts there. A ${ runs to its matching }, counting the ${ nested inside,
# or to the end of the line.
_fzf_bash_completion_split_word() {
    token=
    next="$line"
    while true; do
        chunk="${next%%$breaks*}"
        token+="$chunk"
        next="${next:${#chunk}}"
        case "$next" in
            \\?*|\$[-[:alnum:]_*@#?\$!]*)
                token+="${next:0:2}"
                next="${next:2}"
                ;;
            \$\{*)
                chunk='${'
                scan="${next:2}"
                depth=1
                while (( depth )) && [ -n "$scan" ]; do
                    part="${scan%%[\}\$\\]*}"
                    chunk+="$part"
                    scan="${scan:${#part}}"
                    case "$scan" in
                        \}*) (( depth -- )); chunk+=\}; scan="${scan:1}" ;;
                        \$\{*) (( depth ++ )); chunk+='${'; scan="${scan:2}" ;;
                        \\?*) chunk+="${scan:0:2}"; scan="${scan:2}" ;;
                        ?*) chunk+="${scan:0:1}"; scan="${scan:1}" ;;
                    esac
                done
                token+="$chunk"
                next="${next:${#chunk}}"
                ;;
            *) break ;;
        esac
    done
    if [ -z "$token" ]; then
        token="${line:0:1}"
    fi
}

# Drop trailing empty lines from _fzf_lines, keeping a single empty line if
# nothing else is left.
_fzf_bash_completion_trim_lines() {
    local n="${#_fzf_lines[@]}"
    while (( n > 0 )) && [ -z "${_fzf_lines[n-1]}" ]; do
        (( n -- ))
    done
    if (( n )); then
        _fzf_lines=( "${_fzf_lines[@]:0:n}" )
    else
        _fzf_lines=( '' )
    fi
}

# Split a trailing double-quoted token in the argument list. When the quoted
# string ends, the text after it is parsed as more of the line. When it
# contains an unclosed $(, only the tokens inside the subshell are kept and
# the return status is 1.
_fzf_bash_completion_parse_dq() {
    local -a words=( "$@" ) split
    local last=
    if (( $# )); then
        last="${!#}"
    fi

    if [[ "$last" == \"* ]]; then
        local line="${last:1}" shell_start string_end joined num count i scanned rest chunk
        while true; do
            # we are in a double quoted string

            # Find the closing quote or the $( starting a subshell, whichever
            # comes first. A backslash escapes the character after it.
            shell_start=
            string_end=
            scanned=
            rest="$line"
            while true; do
                chunk="${rest%%[\\\"\$]*}"
                scanned+="$chunk"
                rest="${rest:${#chunk}}"
                case "$rest" in
                    \\?*|\$\$*) scanned+="${rest:0:2}"; rest="${rest:2}" ;;
                    \"*) string_end="$scanned\""; break ;;
                    \$\(*) shell_start="$scanned\$("; break ;;
                    \$*) scanned+=\$; rest="${rest:1}" ;;
                    *) break ;;
                esac
            done

            if (( ${#string_end} && ( ! ${#shell_start} || ${#string_end} < ${#shell_start} )  )); then
                # found end of string
                line="${line:${#string_end}}"
                if (( ${#line} )); then
                    # The rest of the line continues the same command line,
                    # so its tokens join the others, and the keywords in it
                    # can start a new command.
                    words[${#words[@]}-1]="${last:0:${#last}-${#line}}"
                    _fzf_bash_completion_shell_split "$line"
                    if ! _fzf_bash_completion_parse_dq "${_fzf_lines[@]}"; then
                        # inside an unclosed subshell further along
                        return 1
                    fi
                    _fzf_lines=( "${words[@]}" "${_fzf_lines[@]}" )
                else
                    _fzf_lines=( "${words[@]}" )
                fi
                return

            elif (( ${#shell_start} && ( ! ${#string_end} || ${#shell_start} < ${#string_end} )  )); then
                # found a subshell

                line="${line:${#shell_start}}"

                _fzf_bash_completion_shell_split "$line"
                if ! _fzf_bash_completion_parse_dq "${_fzf_lines[@]}"; then
                    # bubble up
                    _fzf_bash_completion_trim_lines
                    return 1
                fi
                _fzf_bash_completion_trim_lines
                split=( "${_fzf_lines[@]}" )

                # Find the token holding the matching ). Each ( token opens a
                # level and each ) token closes one. Parentheses inside
                # quoted tokens are text and do not count.
                num=
                count=0
                for (( i = 0; i < ${#split[@]}; i++ )); do
                    case "${split[i]}" in
                        '(') (( count -- )) ;;
                        ')')
                            (( count ++ ))
                            if (( count > 0 )); then
                                num="$(( i + 1 ))"
                                break
                            fi
                            ;;
                    esac
                done
                if [ -z "$num" ]; then
                    # subshell not closed, this is it
                    _fzf_lines=( "${split[@]}" )
                    return 1
                fi
                # subshell closed
                printf -v joined '%s' "${split[@]:0:num}"
                line="${line:${#joined}}"

            else
                # the whole line is an incomplete string
                break
            fi
        done
    fi

    if (( ${#words[@]} )); then
        _fzf_lines=( "${words[@]}" )
    else
        _fzf_lines=( '' )
    fi
}

# Join each closed (...) or {...} group in the argument list into one word,
# and drop everything before an unclosed one. A { or } only counts when it is
# a reserved word, at the start of the list or after a token that
# _fzf_bash_completion_command_follows accepts.
_fzf_bash_completion_flatten_subshells() {
    local count=0 buffer= line i j closed=1 reserved
    local -a reversed=()
    for (( i = $#; i > 0; i -- )); do
        line="${!i}"
        reserved=1
        if [[ "$line" == [\{\}] ]]; then
            for (( j = i - 1; j > 0; j -- )); do
                [[ "${!j}" == *[![:space:]]* ]] && break
            done
            if (( j > 0 )) && ! _fzf_bash_completion_command_follows "${!j}"; then
                reserved=
            fi
        fi
        if [ -n "$reserved" ]; then
            case "$line" in
                \(|\{) (( count -- )) ;;
                \)|\}) (( count ++ )) ;;
            esac
        fi

        if (( count < 0 )); then
            closed=
            break
        elif (( count > 0 )); then
            buffer="$line$buffer"
        else
            reversed+=( "$line$buffer" )
            buffer=
        fi
    done
    if [ -n "$closed" ] && [ -n "$buffer" ]; then
        reversed+=( "$buffer" )
    fi

    _fzf_lines=()
    for (( i = ${#reversed[@]} - 1; i >= 0; i -- )); do
        _fzf_lines+=( "${reversed[i]}" )
    done
}

# Parse the line $1 into the words of the command being completed, leaving
# them in _fzf_lines.
#
# The tokens are joined into one string with a separator character, then
# rewritten in this order:
#
#   doubled separators collapse into one
#   the final separator becomes a newline, which keeps the word being
#     completed from counting as a keyword
#   a final redirection operator gets an empty word after it
#   everything up to the last place a command starts is dropped, where
#     these start a command:
#       & ; && | || |& anywhere
#       [[ case coproc do done elif else esac fi for function if select
#         then time until while and !, as the first word or right after
#         & ; && | || |& if then else elif do while until ! time or coproc
#       in after for NAME, case WORD or select NAME
#     The word being completed never counts.
#   leading whitespace is dropped, and so are NAME=VALUE assignments followed
#     by space, whether NAME, = and the value are one word or several
#
# Bash strings cannot hold NUL, so the separator is a control character
# absent from $1. The rewrites mark new word boundaries with newlines.
_fzf_bash_completion_parse_line() {
    _fzf_bash_completion_shell_split "$1"
    _fzf_bash_completion_parse_dq "${_fzf_lines[@]}"
    _fzf_bash_completion_flatten_subshells "${_fzf_lines[@]}"

    if (( ! ${#_fzf_lines[@]} )); then
        return
    fi

    local nul c nl=$'\n'
    for c in $'\x02' $'\x03' $'\x04' $'\x05' $'\x06' $'\x07' $'\x08' $'\x0e' $'\x0f' $'\x10' $'\x11' $'\x12'; do
        nul="$c"
        [[ "$1" == *"$c"* ]] || break
    done

    local words re
    printf -v words "%s$nul" "${_fzf_lines[@]}"

    words="${words//"$nul$nul"/"$nul"}"

    words="${words%"$nul"}$nl"

    if [[ "$words" == *[\<\>][$nl$nul] || "$words" == *[\<\>][\&\|][$nl$nul] ]]; then
        words+="$nl"
    fi

    # Operators always start a command, so only the words after the last one
    # need walking. at_command is 1 where a reserved word starts a command,
    # and expect_in counts down the words of for NAME, case WORD or select NAME.
    local seg sep rest start=0 offset at_command=1 expect_in=0
    re="^(.*[$nul$nl])?(&|;|&&|\|[|&]?)$nul"
    if [[ "$words" =~ $re ]]; then
        start="${#BASH_REMATCH[0]}"
    fi
    offset="$start"
    rest="${words:start}"
    while [ -n "$rest" ]; do
        seg="${rest%%[$nul$nl]*}"
        sep="${rest:${#seg}:1}"
        (( offset += ${#seg} + ${#sep} ))
        rest="${rest:${#seg}+${#sep}}"
        [[ "$seg" == *[![:space:]]* ]] || continue
        if [ "$sep" = "$nul" ]; then
            if (( at_command )); then
                if _fzf_bash_completion_command_follows "$seg"; then
                    start="$offset" expect_in=0
                    continue
                fi
                case "$seg" in
                    '[['|done|esac|fi|function)
                        start="$offset" at_command=0 expect_in=0
                        continue ;;
                    case|for|select)
                        start="$offset" at_command=0 expect_in=2
                        continue ;;
                esac
            elif [ "$expect_in" = 1 ] && [ "$seg" = in ]; then
                start="$offset" expect_in=0
                continue
            fi
        fi
        at_command=0
        (( expect_in > 0 )) && (( expect_in -- ))
    done
    words="${words:start}"

    local sep="[$nul$nl]" other="[^$nul$nl]"
    re="^([[:space:]]*$sep|[[:alpha:]_][[:alnum:]_]*\+?$sep?=$other*$sep($other*[^[:space:]$nul$nl]$other*$sep)*[[:space:]]+$sep)*"
    [[ "$words" =~ $re ]]
    words="${words:${#BASH_REMATCH[0]}}"

    words="${words//"$nul"/$nl}"
    _fzf_lines=()
    while [ -n "$words" ]; do
        if [[ "$words" == *$'\n'* ]]; then
            _fzf_lines+=( "${words%%$'\n'*}" )
            words="${words#*$'\n'}"
        else
            _fzf_lines+=( "$words" )
            break
        fi
    done
}

# Remove the quoting from the inside of a double-quoted string, where a
# backslash only escapes $, `, " and another backslash. Stops at an unescaped ".
_fzf_bash_completion_unescape_dq() {
    local rest="$1" out= chunk
    while true; do
        chunk="${rest%%[\\\"]*}"
        out+="$chunk"
        rest="${rest:${#chunk}}"
        case "$rest" in
            \\[\$\`\"\\]*) out+="${rest:1:1}"; rest="${rest:2}" ;;
            \\?*) out+="${rest:0:2}"; rest="${rest:2}" ;;
            \\) out+="$rest"; break ;;
            *) break ;;
        esac
    done
    REPLY="$out"
}

# Unquote each argument into _fzf_lines where that is simple to do.
_fzf_bash_completion_unquote_strings() {
    local line dq_re='^"(\\.|[^"\\$`])*"?$'
    _fzf_lines=()
    for line; do
        if [[ "$line" == \'* && "$line" =~ ^\'[^\']*\'?$ ]]; then
            # single quoted with no single quotes inside
            line="${line%%"'"}"
            _fzf_lines+=( "${line:1}" )
        elif [[ "$line" == \"* && "$line" =~ $dq_re ]]; then
            # double quoted with nothing to expand inside
            _fzf_bash_completion_unescape_dq "${line:1}"
            _fzf_lines+=( "$REPLY" )
        elif [[ "$line" == *\\* && "${line//\\?/}" != *[[:space:]\'\"\\\$\`\|\&\;\(\)\<\>\*\?\[\{\}]* ]]; then
            # every character special to the shell is escaped
            _fzf_bash_completion_unescape "$line"
            _fzf_lines+=( "$REPLY" )
        else
            # this string is either boring or too complicated to parse
            # print as is
            _fzf_lines+=( "$line" )
        fi
    done
}

_fzf_bash_completion_compspec() {
    if [[ "$2" =~ .*\$(\{?)([A-Za-z0-9_]*)$ ]]; then
        printf '%s\n' 'complete -F _fzf_bash_completion_complete_variables'
    elif [[ "$COMP_CWORD" == 0 && -z "$2" ]]; then
        # If the command word is the empty string (completion attempted at the beginning of an empty line), any compspec defined with the -E option to complete is used.
        complete -p -E || { ! shopt -q no_empty_cmd_completion && printf '%s\n' 'complete -F _fzf_bash_completion_complete_commands -E'; }
    elif [[ "$COMP_CWORD" == 0 ]]; then
        complete -p -I || printf '%s\n' 'complete -F _fzf_bash_completion_complete_commands -I'
    else
       # If the command word is a full pathname, a compspec for the full pathname is searched for first.  If no compspec is found for the full pathname, an attempt is made to find a compspec for the portion following the final slash.  If those searches do not result in a compspec, any compspec defined with the -D option to complete is used as the default
        complete -p -- "$1" || complete -p -- "${1##*/}" || complete -p -D || printf '%s\n' 'complete -o filenames -F _fzf_bash_completion_fallback_completer'
    fi
}

_fzf_bash_completion_fallback_completer() {
    # fallback completion in case no compspecs loaded
    if [[ "$2" == \~* && "$2" != */* ]]; then
        # complete ~user directories
        _fzf_bash_completion_split_lines "$(compgen -P '~' -u -- "${2#\~}")"
    else
        # complete files
        _fzf_bash_completion_split_lines "$(compgen -f -- "$2")"
    fi
    COMPREPLY=( "${_fzf_lines[@]}" )
}

_fzf_bash_completion_complete_commands() {
    # commands
    compopt -o filenames
    _fzf_bash_completion_split_lines "$(compgen -abc -- "$2")"
    COMPREPLY=( "${_fzf_lines[@]}" )
}

_fzf_bash_completion_complete_variables() {
    if [[ "$2" =~ .*\$(\{?)([A-Za-z0-9_]*)$ ]]; then
        # environment variables
        local brace="${BASH_REMATCH[1]}"
        local filter="${BASH_REMATCH[2]}"
        if [ -n "$filter" ]; then
            local prefix="${2:: -${#filter}}"
        else
            local prefix="$2"
        fi
        _fzf_bash_completion_split_lines "$(compgen -v -P "$prefix" -S "${brace:+\}}" -- "$filter")"
        COMPREPLY=( "${_fzf_lines[@]}" )
    fi
}

# Set REPLY to the last line of the expanded prompt, which is the part bash
# redraws after a bind -x command. Fails when expanding the prompt would run
# commands, which could be slow or have side effects, and before bash 4.4,
# which lacks ${PS1@P}.
_fzf_bash_completion_prompt_line() {
    (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 404 )) || return 1
    [[ "$PS1" != *'$('* && "$PS1" != *'`'* ]] || return 1
    REPLY="${PS1@P}"
    # \[ and \] in PS1 become these markers, which only mean something to readline
    REPLY="${REPLY//$'\001'/}"
    REPLY="${REPLY//$'\002'/}"
    REPLY="${REPLY##*$'\n'}"
}

# Bash clears the prompt line while a bind -x command runs. Fill it with the
# output of _fzf_bash_completion_loading_msg if that function is defined, and
# otherwise with the prompt and input as they were, cursor included, so that
# fast completions do not flicker. Sets _fzf_input_shown when the input is
# on screen. Clears the rest of the line, which holds the previous input when
# completing again inside a directory.
_fzf_bash_completion_draw_loading_line() {
    local el="$_fzf_bash_completion_el"
    if declare -F _fzf_bash_completion_loading_msg >/dev/null; then
        printf '\r%s%s' "$(_fzf_bash_completion_loading_msg)" "$el"
        return
    fi

    local REPLY
    if ! _fzf_bash_completion_prompt_line; then
        printf '\r%s%s' 'Loading matches ...' "$el"
        return
    fi
    local before="$REPLY${READLINE_LINE:0:READLINE_POINT}" after="${READLINE_LINE:READLINE_POINT}"
    before="${before##*$'\n'}"
    after="${after%%$'\n'*}"
    _fzf_input_shown=1
    if [ -n "$after" ]; then
        printf '\r%s%s%s%s%s' "$before" "$_fzf_bash_completion_sc" "$after" "$el" "$_fzf_bash_completion_rc"
    else
        printf '\r%s%s' "$before" "$el"
    fi
}

# Leave the cursor at the start of the line, where bash expects it when it
# redraws the prompt and input after a bind -x command.
#
# Bash 5.1 and later redraw without clearing the line first, so when possible
# the line is drawn here the way bash is about to draw it, and bash's redraw
# changes nothing visible. That needs
# the line to fit in one row, so the estimate counts every character as two
# columns wide. Other cases, and older versions of bash, clear the line.
_fzf_bash_completion_finish_line() {
    local REPLY
    if (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] >= 501 && COLUMNS > 0 )) \
        && [[ "$READLINE_LINE" != *$'\n'* ]] \
        && _fzf_bash_completion_prompt_line; then
        local text="$REPLY$READLINE_LINE" rest="$REPLY$READLINE_LINE" visible= params
        # ST ends in a backslash, so it is only matched as the quoted "$st".
        # Written into a pattern inside "${...}", the backslash escapes the
        # closing brace.
        local st=$'\e\\' to_bel to_st
        while [[ "$rest" == *$'\e'* ]]; do
            visible+="${rest%%$'\e'*}"
            rest="${rest#*$'\e'}"
            case "$rest" in
                \[*)
                    # A CSI sequence ends at the first byte from @ to ~
                    rest="${rest:1}"
                    params="${rest%%[@-~]*}"
                    rest="${rest:${#params}+1}"
                    ;;
                \]*)
                    # An OSC sequence ends at whichever of BEL or ST comes first
                    to_bel="${rest%%$'\a'*}"
                    to_st="${rest%%"$st"*}"
                    if (( ${#to_bel} <= ${#to_st} )); then
                        rest="${rest:${#to_bel}+1}"
                    else
                        rest="${rest:${#to_st}+2}"
                    fi
                    ;;
                *) rest="${rest:1}" ;;
            esac
        done
        visible+="$rest"
        if (( ${#visible} * 2 < COLUMNS )); then
            printf '\r%s%s\r' "$text" "$_fzf_bash_completion_el"
            return
        fi
    fi
    printf '\r%s' "$_fzf_bash_completion_el"
}

# Look up the cursor control sequences once for each $TERM.
_fzf_bash_completion_load_term_caps() {
    if [ -z "${_fzf_bash_completion_term+set}" ] || [ "$_fzf_bash_completion_term" != "$TERM" ]; then
        _fzf_bash_completion_sc="$(command tput sc 2>/dev/null)" || _fzf_bash_completion_sc=$'\e7'
        _fzf_bash_completion_rc="$(command tput rc 2>/dev/null)" || _fzf_bash_completion_rc=$'\e8'
        _fzf_bash_completion_el="$(command tput el 2>/dev/null)" || _fzf_bash_completion_el=$'\e[K'
        _fzf_bash_completion_cuu1="$(command tput cuu1 2>/dev/null)" || _fzf_bash_completion_cuu1=$'\e[A'
        _fzf_bash_completion_term="$TERM"
    fi
}

fzf_bash_completion() {
    # bail early if no_empty_cmd_completion
    if ! [[ "$READLINE_LINE" =~ [^[:space:]] ]] && shopt -q no_empty_cmd_completion; then
        return 1
    fi

    local _fzf_input_shown= _fzf_drill=
    _fzf_bash_completion_load_term_caps
    _fzf_bash_completion_draw_loading_line

    local REPLY _fzf_lines=()
    local raw_comp_words=()
    local COMP_WORDS=() COMP_CWORD COMP_POINT COMP_LINE
    local COMP_TYPE=37 # % == indicates menu completion
    local COMP_KEY=9 # the Tab key
    local line="${READLINE_LINE:0:READLINE_POINT}"
    local wordbreaks="$COMP_WORDBREAKS"
    wordbreaks="${wordbreaks//[[:space:]]/}"
    if [[ "$line" =~ [^[:space:]] ]]; then
        _fzf_bash_completion_parse_line "$line"
        raw_comp_words=( "${_fzf_lines[@]}" )
    fi

    if [[ ${#raw_comp_words[@]} -gt 1 ]]; then
        _fzf_bash_completion_expand_alias "${raw_comp_words[@]}"
    fi
    if (( ${#raw_comp_words[@]} )); then
        _fzf_bash_completion_unquote_strings "${raw_comp_words[@]}"
    else
        _fzf_bash_completion_unquote_strings ''
    fi
    COMP_WORDS=( "${_fzf_lines[@]}" )

    printf -v COMP_LINE '%s' "${COMP_WORDS[@]}"
    COMP_POINT="${#COMP_LINE}"
    # Drop words made of whitespace alone, except the last one
    local i
    for (( i = ${#COMP_WORDS[@]}-2; i >= 0; i --)); do
        if ! [[ "${COMP_WORDS[i]}" =~ [^[:space:]] ]]; then
            COMP_WORDS=( "${COMP_WORDS[@]:0:i}" "${COMP_WORDS[@]:i+1}" )
        fi
    done
    # A last word of whitespace alone becomes the empty word being completed
    if ! [[ "${COMP_WORDS[${#COMP_WORDS[@]}-1]}" =~ [^[:space:]] ]]; then
        COMP_WORDS[${#COMP_WORDS[@]}-1]=''
    fi
    COMP_CWORD="${#COMP_WORDS[@]}"
    (( COMP_CWORD-- ))

    local cmd="${COMP_WORDS[0]}"
    local prev
    if [ "$COMP_CWORD" = 0 ]; then
        prev=
    else
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if (( ${#cur} == 1 )) && [[ "$wordbreaks" == *"$cur"* ]]; then
        cur=
    fi
    local raw_cur="${cur:+${raw_comp_words[-1]}}"

    local COMPREPLY=
    fzf_bash_completer "$cmd" "$cur" "$prev"
    if [ -n "$COMPREPLY" ]; then
        if [ -n "$raw_cur" ]; then
            line="${line::-${#raw_cur}}"
        fi
        READLINE_LINE="${line}${COMPREPLY}${READLINE_LINE:$READLINE_POINT}"
        (( READLINE_POINT+=${#COMPREPLY} - ${#raw_cur} ))
    fi

    if [ -n "$_fzf_drill" ]; then
        fzf_bash_completion
        return
    fi
    _fzf_bash_completion_finish_line
}

# Choose from two or more formatted candidates on stdin with fzf, starting
# with $_fzf_query as the query. $1 is the input up to the cursor and $2 the
# word being completed as typed. Prints the key that ended the selection,
# which is empty for Enter and / for descending into a directory, then the
# selected lines.
_fzf_bash_completion_selector() {
    local before_cursor="$1" typed_word="$2"
    local fzf=fzf
    # __fzfcmd comes from fzf's own bash integration and is only called when
    # defined, since looking up a missing command searches every PATH directory.
    if declare -F __fzfcmd >/dev/null; then
        fzf="$(__fzfcmd 2>/dev/null || echo fzf)"
    fi
    # fzf draws from the start of the cursor's line, so start it on the next
    # line to keep the redrawn prompt in view. It leaves the cursor on the
    # line it started from, so one line up is the prompt again afterwards.
    local inline=
    if [[ "$fzf" == fzf ]]; then
        inline=1
        printf '\n' >/dev/tty
    fi

    local default_height="${FZF_TMUX_HEIGHT:-40%}"
    # Asking the terminal for the cursor position takes a round trip, which
    # over SSH can cost more than the rest of the completion, so it is
    # skipped there unless FZF_COMPLETION_SSH_CURSOR_QUERY=true. Only fzf
    # drawn inline uses the answer.
    if [[ -n "$inline" && -z "$FZF_TMUX_HEIGHT" ]] && [[ -z "$SSH_CONNECTION$SSH_TTY" || "$FZF_COMPLETION_SSH_CURSOR_QUERY" = true ]]; then
        # Give up once the terminal stays silent for half a second, in which
        # case the default height stands.
        printf '\e[6n' >/dev/tty
        local buf= c
        while [[ ! "$buf" =~ $'\x1b'\[([0-9]+)\;[0-9]+R ]] && IFS= read -r -s -n1 -t 0.5 c </dev/tty; do
            buf+="$c"
        done
        if [[ "$buf" =~ $'\x1b'\[([0-9]+)\;[0-9]+R ]] && (( LINES - BASH_REMATCH[1] > LINES * 4 / 10 )); then
            default_height="$(( LINES - BASH_REMATCH[1] ))"
        fi
    fi

    # Let the window shrink to fit a short list, where fzf supports it. The
    # first time in a shell, a run of fzf that reads nothing finds out, and
    # the main shell keeps the answer. Options fzf does not know make it
    # exit with 2, and FZF_DEFAULT_OPTS is cleared so that only --height
    # can cause that.
    if [[ -z "$FZF_TMUX_HEIGHT" ]]; then
        if [ -z "$_fzf_bash_completion_adaptive_height" ]; then
            FZF_DEFAULT_OPTS= command fzf --filter '' --height '~1' </dev/null >/dev/null 2>&1
            if (( $? == 2 )); then
                _fzf_bash_completion_adaptive_height=0
            else
                _fzf_bash_completion_adaptive_height=1
            fi
            printf '_fzf_bash_completion_adaptive_height=%s\n' "$_fzf_bash_completion_adaptive_height" >&"$__evaled"
        fi
        if [ "$_fzf_bash_completion_adaptive_height" = 1 ]; then
            default_height="~$default_height"
        fi
    fi

    # The query holds the end of the input. Repeat the rest of it in the
    # prompt unless it is already on screen.
    local prompt="${FZF_TAB_COMPLETION_PROMPT:-> }" typed="$typed_word"
    if [ -z "$_fzf_input_shown" ]; then
        [ "$_fzf_filenames" = 1 ] && typed="${typed_word##*/}"
        prompt+="${before_cursor%"$typed"}"
    fi

    # / ends the selection only among filenames, where it descends into the
    # selected directory. Elsewhere it is part of the query.
    local expect=()
    if [ "$_fzf_filenames" = 1 ]; then
        expect=( --expect=/ )
    else
        printf '\n'
    fi

    # -o nosort asks for the candidates in the order they were generated
    local sort=()
    if [ "$_fzf_nosort" = 1 ]; then
        sort=( --no-sort )
    fi

    FZF_DEFAULT_OPTS="--height $default_height --reverse --tiebreak=begin --multi --cycle \
--bind=tab:down,btab:up,ctrl-space:toggle,bspace:backward-delete-char/eof,ctrl-h:backward-delete-char/eof \
$FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" \
        "$fzf" --prompt "$prompt" --query "$_fzf_query" --with-nth=2 -d "$_FZF_COMPLETION_SEP" "${expect[@]}" "${sort[@]}"
    local code="$?"
    if [ -n "$inline" ]; then
        printf '%s' "$_fzf_bash_completion_cuu1" >/dev/tty
    fi
    return "$code"
}

# Replace an alias at the start of raw_comp_words with the words of its text,
# tokenized like the rest of the line, unless the alias begins with its own
# name. An alias named in FZF_COMPLETION_KEEP_ALIASES, or any alias when it is
# :all:, keeps its own completion instead when it has one.
_fzf_bash_completion_expand_alias() {
    alias "$1" &>/dev/null || return
    if [[ "$FZF_COMPLETION_KEEP_ALIASES" == :all: || " $FZF_COMPLETION_KEEP_ALIASES " == *" $1 "* ]]; then
        # __load_completion comes from bash-completion and loads completions
        # on demand. It is only called when defined, since looking up a
        # missing command searches every PATH directory.
        if { complete -p -- "$1" || { declare -F __load_completion && __load_completion "$1" && complete -p -- "$1"; }; } &>/dev/null; then
            return
        fi
    fi
    _fzf_bash_completion_shell_split "${BASH_ALIASES[$1]}"
    local -a value=( "${_fzf_lines[@]}" )
    local first= token
    for token in "${value[@]}"; do
        if [[ "$token" == *[![:space:]]* ]]; then
            first="$token"
            break
        fi
    done
    if [ -n "$first" ] && [ "$first" != "$1" ]; then
        raw_comp_words=( "${value[@]}" "${raw_comp_words[@]:1}" )
    fi
}

# Turn the producer's output into lines for the selector. Each line holds the
# value to insert, a separator, and the text to display, which is the
# basename for filenames and the value itself otherwise. Stops at the
# sentinel line and drops repeated values.
#
# The first line of output is a count of 0, 1 or 2, where 2 means two or
# more. With fewer than two candidates the count comes at the end, followed
# by the candidate if there is one. Otherwise the count comes as soon as the
# second candidate arrives, followed by the producer's header and every
# candidate, flushed per line so the selector shows them as they arrive.
#
# Unless FZF_COMPLETION_AUTO_COMMON_PREFIX is false, candidates are held back
# while they all share a prefix that extends the word being completed, $1.
# If they still do at the end, and that prefix is itself a candidate or
# FZF_COMPLETION_AUTO_COMMON_PREFIX_PART is true, the prefix is the only
# candidate, and the count line reads "1 nospace" when it stood for several.
_fzf_bash_completion_format_candidates() {
    local auto_prefix= auto_prefix_part=
    [ "${FZF_COMPLETION_AUTO_COMMON_PREFIX:-true}" = true ] && auto_prefix=1
    [ "$FZF_COMPLETION_AUTO_COMMON_PREFIX_PART" = true ] && auto_prefix_part=1
    # awk -v expands backslash escapes, so the typed word goes through the environment
    _FZF_TYPED="$1" "$_fzf_bash_completion_awk" -W interactive \
        -v sentinel="$_fzf_sentinel1$_fzf_sentinel2" -v sep="$_FZF_COMPLETION_SEP" \
        -v auto_prefix="$auto_prefix" -v auto_prefix_part="$auto_prefix_part" '
        BEGIN {
            typed = ENVIRON["_FZF_TYPED"]
            typed_len = length(typed)
            holding = auto_prefix
        }

        function emit(line) {
            if (++count == 1) {
                first = line
                return
            }
            if (count == 2) {
                print 2
                print header
                print first
            }
            print line
            fflush()
        }

        function release(   i) {
            holding = 0
            for (i = 1; i <= held; i++) emit(held_lines[i])
        }

        index($0, sentinel) { exit }
        substr($0, 1, 2) == sep sep {
            header = substr($0, 3)
            next
        }
        $0 == "" { next }
        {
            split_at = index($0, sep)
            if (split_at) {
                value = substr($0, 1, split_at - 1)
                display = substr($0, split_at + 1)
                # an empty display field means the value is backslash-quoted
                if (display == "") {
                    if (index(value, "\\")) {
                        rest = value
                        while (match(rest, /\\./)) {
                            display = display substr(rest, 1, RSTART - 1) substr(rest, RSTART + 1, 1)
                            rest = substr(rest, RSTART + 2)
                        }
                        display = display rest
                    } else {
                        display = value
                    }
                }
                is_dir = substr(display, length(display)) == "/"
                if (is_dir) display = substr(display, 1, length(display) - 1)
                parts = split(display, part, "/")
                display = (parts ? part[parts] : "") (is_dir ? "/" : "")
            } else {
                value = $0
                display = $0
            }
            if (seen[value]++) next
            line = value sep display

            if (!holding) {
                emit(line)
                next
            }
            held_lines[++held] = line
            held_values[held] = value
            if (held == 1) {
                prefix = value
            } else if (index(value, prefix) != 1) {
                for (i = 1; i <= length(prefix); i++) {
                    if (substr(value, i, 1) != substr(prefix, i, 1)) break
                }
                prefix = substr(prefix, 1, i - 1)
            }
            if (length(prefix) <= typed_len || substr(prefix, 1, typed_len) != typed) release()
        }

        END {
            if (holding && held) {
                full = 0
                for (i = 1; i <= held; i++) if (held_values[i] == prefix) full = 1
                if (full || auto_prefix_part) {
                    print (held > 1 ? "1 nospace" : 1)
                    print prefix sep prefix
                    exit
                }
                release()
            }
            if (count < 2) {
                print count + 0
                if (count) print first
            }
        }
    ' 2>/dev/null
}

# Generate the candidates for "$@", retrying while the completion function
# asks for a retry, then print the sentinel.
_fzf_bash_completion_produce() {
    # input from tty in case one of the completions wants fzf using $FZF_DEFAULT_COMMAND
    exec </dev/tty

    local count=0
    _fzf_bash_completion_complete "$@"
    while (( $? == 124 )); do
        (( count ++ ))
        if (( count > 32 )); then
            echo "$1: possible retry loop" >/dev/tty
            break
        fi
        _fzf_bash_completion_complete "$@"
    done
    printf '%s\n' "$_FZF_COMPLETION_SEP$_fzf_sentinel1$_fzf_sentinel2"
}

# Kill $1 and its descendants if $1 is still running. Once $1 has exited its
# children belong to init, so there is nothing left to find.
_fzf_bash_completion_kill_tree() {
    kill -0 "$1" 2>/dev/null || return

    local -A children=()
    local -a fields pids=( "$1" )
    local line noglob= i=0
    _fzf_bash_completion_split_lines "$(ps -ef)"
    [[ "$-" == *f* ]] && noglob=1
    set -f
    local IFS=$' \t\n'
    for line in "${_fzf_lines[@]}"; do
        fields=( $line )
        children[${fields[2]}]+=" ${fields[1]}"
    done
    while (( i < ${#pids[@]} )); do
        pids+=( ${children[${pids[i]}]} )
        (( i ++ ))
    done
    [ -n "$noglob" ] || set +f
    kill -- "${pids[@]}" 2>/dev/null
}

fzf_bash_completer() {
    local value code
    local compl_bashdefault compl_default compl_dirnames compl_filenames compl_noquote compl_nosort compl_nospace compl_plusdirs

    # preload completions in top shell. __load_completion comes from
    # bash-completion and is only called when defined, since looking up a
    # missing command searches every PATH directory.
    { complete -p -- "$1" || { declare -F __load_completion && __load_completion "$1"; }; } &>/dev/null
    if ! _fzf_bash_completion_compspec "$@" &>/dev/null; then
        return
    fi

    local _fzf_sentinel1=b5a0da60-3378-4afd-ba00-bc1c269bef68
    local _fzf_sentinel2=257539ae-7100-4cd8-b822-a1ef35335e88
    local _fzf_evaled= _fzf_line
    # The subshell prints shell assignments for eval, then the sentinel. Any
    # background process left behind by a completion function can keep the
    # pipe open, so reading stops at the sentinel.
    while IFS= read -r _fzf_line; do
        [[ "$_fzf_line" == *"$_fzf_sentinel1$_fzf_sentinel2"* ]] && break
        _fzf_evaled+="$_fzf_line"$'\n'
    done < <(
        set -o pipefail

        # hack: hijack compopt
        compopt() { _fzf_bash_completion_compopt "$@"; }

        exec {__evaled}>&1
        # The candidates are read from a descriptor held open here, so they
        # stay readable after the producer exits.
        local candidates_fd
        exec {candidates_fd}< <(
            _fzf_bash_completion_produce "$@" | _fzf_bash_completion_format_candidates "$raw_cur"
        )
        local producer_pid="$!" count count_flag header key=
        IFS=' ' read -r count count_flag <&"$candidates_fd" || count=0
        case "$count" in
            0)
                value=
                code=1 ;;
            1)
                IFS= read -r value <&"$candidates_fd"
                code=0
                if [ "$count_flag" = nospace ]; then
                    printf 'compl_nospace=1\n'
                fi ;;
            *)
                IFS= read -r header <&"$candidates_fd"
                local _fzf_filenames="${header%%"$_FZF_COMPLETION_SEP"*}"
                header="${header#*"$_FZF_COMPLETION_SEP"}"
                local _fzf_nosort="${header%%"$_FZF_COMPLETION_SEP"*}"
                local _fzf_query="${header#*"$_FZF_COMPLETION_SEP"}"
                value="$(_fzf_bash_completion_selector "$line" "$raw_cur" <&"$candidates_fd")"
                code="$?"
                # the first line names the key that ended the selection
                key="${value%%$'\n'*}"
                if [[ "$value" == *$'\n'* ]]; then
                    value="${value#*$'\n'}"
                else
                    value=
                fi ;;
        esac

        # keep the value field of each selected line and join them with spaces
        local selected= rest="$value" entry
        while true; do
            entry="${rest%%$'\n'*}"
            selected+="${entry%%"$_FZF_COMPLETION_SEP"*}"$'\n'
            [[ "$rest" == *$'\n'* ]] || break
            rest="${rest#*$'\n'}"
        done
        selected="${selected%"${selected##*[!$'\n']}"}"

        # / on a single directory inserts it and completes inside it
        if [ "$key" = / ] && [[ "$selected" != *$'\n'* && "$selected" == */ ]]; then
            printf '_fzf_drill=1\n'
        fi

        value="${selected//$'\n'/ }"
        printf 'COMPREPLY=%q\n' "$value"
        printf 'code=%q\n' "$code"

        exec {candidates_fd}<&-
        _fzf_bash_completion_kill_tree "$producer_pid"

        printf '%s\n' ": $_fzf_sentinel1$_fzf_sentinel2"
    )
    eval "$_fzf_evaled" 2>/dev/null

    if [ "$code" = 0 ]; then
        [ "$compl_nospace" != 1 ] && COMPREPLY="$COMPREPLY "
        [[ "$compl_filenames" == *1* ]] && COMPREPLY="${COMPREPLY/%\/ //}"
    fi
}

_fzf_bash_completion_complete() {
    local compgen_actions=() compspec=
    if ! compspec="$(_fzf_bash_completion_compspec "$@" 2>/dev/null)"; then
        return
    fi

    local args=( "$@" ) compspec_words
    eval "compspec_words=( $compspec )"
    set -- "${compspec_words[@]}"
    shift # remove the complete command
    while (( $# > 1 )); do
        case "$1" in
        -F)
            local compl_function="$2"
            shift ;;
        -C)
            local compl_command="$2"
            shift ;;
        -G)
            local compl_globpat="$2"
            shift ;;
        -W)
            local compl_wordlist="$2"
            shift ;;
        -X)
            local compl_xfilter="$2"
            shift ;;
        -o)
            _fzf_bash_completion_compopt -o "$2"
            shift ;;
        -A)
            compgen_actions+=( "$1" "$2" )
            shift ;;
        -P)
            local compl_prefix="$2"
            shift ;;
        -S)
            local compl_suffix="$2"
            shift ;;
        -[a-z])
            compgen_actions+=( "$1" )
            ;;
        esac
        shift
    done
    set -- "${args[@]}"

    COMPREPLY=()
    if [ -n "$compl_function" ]; then
        "$compl_function" "$@" >/dev/null
        if [ "$?" = 124 ]; then
            local newcompspec
            if ! newcompspec="$(_fzf_bash_completion_compspec "$@" 2>/dev/null)"; then
                return
            elif [ "$newcompspec" != "$compspec" ]; then
                return 124
            fi
            "$compl_function" "$@" >/dev/null
        fi
    fi

    printf 'compl_filenames=%q\n' "$compl_filenames" >&"${__evaled}"
    printf 'compl_nospace=%q\n' "$compl_nospace" >&"${__evaled}"

    # compgen generates actions, then -G, then -W, each the way bash's own
    # completion would, so one call covers them all
    local text= words
    local compgen_args=( "${compgen_actions[@]}" )
    if [ -n "$compl_globpat" ]; then
        compgen_args+=( -G "$compl_globpat" )
    fi
    if [ -n "$compl_wordlist" ]; then
        compgen_args+=( -W "$compl_wordlist" )
    fi
    if (( ${#compgen_args[@]} )); then
        text+="$(compgen "${compgen_args[@]}" -- "$2")"$'\n'
    fi
    if [ -n "${COMPREPLY[*]}" ]; then
        printf -v words '%s\n' "${COMPREPLY[@]}"
        text+="$words"
    fi
    if [ -n "$compl_command" ]; then
        text+="$(
            unset COMP_WORDS COMP_CWORD
            export COMP_LINE="$COMP_LINE" COMP_POINT="$COMP_POINT" COMP_KEY="$COMP_KEY" COMP_TYPE="$COMP_TYPE"
            # Like a -F function, the command gets the command name, the word
            # being completed and the word before it as arguments
            printf -v words ' %q' "$@"
            eval "$compl_command$words"
        )"
    fi

    _fzf_bash_completion_split_lines "$text"
    local candidates=( "${_fzf_lines[@]}" )
    if [ -n "$compl_xfilter" ]; then
        _fzf_bash_completion_apply_xfilter "$compl_xfilter"
    fi
    if [ -n "$compl_prefix" ]; then
        candidates=( "${candidates[@]/#/"$compl_prefix"}" )
    fi
    if [ -n "$compl_suffix" ]; then
        candidates=( "${candidates[@]/%/"$compl_suffix"}" )
    fi

    _fzf_bash_completion_emit "$compl_filenames"

    if (( ! ${#candidates[@]} && ! ${#COMPREPLY[@]} )); then
        # got no results
        local compgen_opts=()
        [ "$compl_bashdefault" = 1 ] && compgen_opts+=( -o bashdefault )
        [ "$compl_default" = 1 ] && compgen_opts+=( -o default )
        [ "$compl_dirnames" = 1 ] && compgen_opts+=( -o dirnames )
        if [ -n "${compgen_opts[*]}" ]; then
            # these are all filenames
            printf 'compl_filenames=1\n'>&"${__evaled}"
            _fzf_bash_completion_split_lines "$(compgen "${compgen_opts[@]}" -- "$2")"
            candidates=( "${_fzf_lines[@]}" )
            _fzf_bash_completion_emit 1
        fi
    fi

    if [ "$compl_plusdirs" = 1 ]; then
        printf 'compl_filenames=1\n'>&"${__evaled}"
        _fzf_bash_completion_split_lines "$(compgen -o dirnames -- "$2")"
        candidates=( "${_fzf_lines[@]}" )
        _fzf_bash_completion_emit 1
    fi
}

# Print the caller's candidates array, one per line. When $1 is 1 they are
# filenames, and each line holds the candidate shell-quoted, with a trailing /
# on directories, then a separator and the unquoted candidate it displays as.
# Filenames are processed in chunks so the selector can show the first ones
# sooner.
#
# Before the first candidate comes a header line starting with two
# separators. It tells the formatter whether the candidates are filenames
# and whether to keep them in their given order, and gives the selector's
# starting query. That query is the word being completed, or for filenames
# the part of it after the last /, so that it matches what is displayed.
# With -o plusdirs, directories follow the other candidates, so the header
# counts the whole list as filenames.
_fzf_bash_completion_emit() {
    (( ${#candidates[@]} )) || return

    if [ -z "$_fzf_header_sent" ]; then
        local filenames="$1" query="$cur"
        [ "$compl_plusdirs" = 1 ] && filenames=1
        [ "$filenames" = 1 ] && query="${cur##*/}"
        printf '%s%s%s%s%s%s%s\n' "$_FZF_COMPLETION_SEP" "$_FZF_COMPLETION_SEP" "$filenames" "$_FZF_COMPLETION_SEP" "$compl_nosort" "$_FZF_COMPLETION_SEP" "$query"
        _fzf_header_sent=1
    fi

    local start
    if [ "$1" != 1 ]; then
        printf '%s\n' "${candidates[@]}"
        return
    fi
    for (( start = 0; start < ${#candidates[@]}; start += 1024 )); do
        _fzf_bash_completion_emit_filenames "${candidates[@]:start:1024}"
    done
}

_fzf_bash_completion_emit_filenames() {
    local -a lines=() marked=()
    local candidate expanded quoted cmd IFS=$'\n'

    # Without tilde expansion or noquote, each candidate is tested as it is
    # and all are quoted with one printf. The display field is left empty,
    # which tells the formatter to unescape the quoted value. Names with
    # control characters come out of %q as $'...', which unescaping cannot
    # undo, so those lists go through the loop below and carry their display.
    if [ "$compl_noquote" != 1 ] && [[ $'\n'"$*" != *$'\n~'* ]]; then
        for candidate; do
            [[ "$candidate" != */ && -d "$candidate" ]] && candidate+=/
            marked+=( "$candidate" )
        done
        printf -v quoted "%q$_FZF_COMPLETION_SEP\n" "${marked[@]}"
        if [[ "$quoted" != *"\$'"* ]]; then
            printf '%s' "$quoted"
            return
        fi
    fi

    for candidate; do
        expanded="$candidate"
        # Expand a leading ~ so that the directory test sees the real path
        if [[ "$candidate" == \~* ]]; then
            printf -v cmd 'expanded=~%q' "${candidate:1}"
            eval "$cmd"
        fi
        [[ "$candidate" != */ && -d "$expanded" ]] && candidate+=/

        if [ "$compl_noquote" = 1 ]; then
            quoted="$candidate"
        elif [[ "$candidate" == \~* ]]; then
            printf -v quoted '~%q' "${candidate:1}"
        else
            printf -v quoted '%q' "$candidate"
        fi
        lines+=( "$quoted$_FZF_COMPLETION_SEP$candidate" )
    done
    printf '%s\n' "${lines[@]}"
}

# Filter the caller's candidates array with the -X pattern $1, in which an
# unescaped & stands for the word being completed. Like bash, remove the
# candidates matching the pattern, or with a leading ! the ones not matching
# it, except that with extglob on, !( starts an extended pattern.
_fzf_bash_completion_apply_xfilter() {
    local pattern line filter="$1" negate=
    local -a kept=()
    if [[ "$filter" == !* ]] && { ! shopt -q extglob || [[ "$filter" != '!('* ]]; }; then
        negate=1
        filter="${filter:1}"
    fi
    _fzf_bash_completion_xfilter_pattern "$filter"
    pattern="$REPLY"

    if [ -n "$negate" ]; then
        for line in "${candidates[@]}"; do [[ "$line" == $pattern ]] && kept+=( "$line" ); done
    else
        for line in "${candidates[@]}"; do [[ "$line" != $pattern ]] && kept+=( "$line" ); done
    fi
    candidates=( "${kept[@]}" )
}

# In an -X pattern, & stands for the word being completed. Replace each &
# with $cur, except one escaped by a backslash, meaning one preceded by an
# odd number of backslashes. $cur goes in with its glob characters escaped,
# so it matches only itself.
_fzf_bash_completion_xfilter_pattern() {
    local text="$1"
    if [[ "$text" != *\&* ]]; then
        REPLY="$text"
        return
    fi

    local word= i c
    for (( i = 0; i < ${#cur}; i ++ )); do
        c="${cur:i:1}"
        case "$c" in
            [\\*?\[\]^+@!\(\)\|]) word+="\\$c" ;;
            *) word+="$c" ;;
        esac
    done

    local out= backslashes=0
    for (( i = 0; i < ${#text}; i ++ )); do
        c="${text:i:1}"
        if [ "$c" = '&' ] && (( backslashes % 2 == 0 )); then
            out+="$word"
        else
            out+="$c"
        fi
        if [ "$c" = '\' ]; then
            (( backslashes ++ ))
        else
            backslashes=0
        fi
    done
    REPLY="$out"
}

_fzf_bash_completion_compopt() {
    while [ "$#" -gt 0 ]; do
        local val
        if [ "$1" = -o ]; then
            val=1
        elif [ "$1" = +o ]; then
            val=0
        else
            break
        fi

        case "$2" in
            bashdefault|default|dirnames|filenames|noquote|nosort|nospace|plusdirs)
                printf -v "compl_$2" '%s' "$val" ;;
        esac
        shift 2
    done
}
