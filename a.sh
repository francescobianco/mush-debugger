#!/bin/bash

# ─── debugger state ──────────────────────────────────────────────────────────

__DBG_ACTIVE=0
__DBG_VARS=()

__breakpoint() {
  __DBG_ACTIVE=1
  __DBG_VARS=("$@")
}

# ─── stack trace ─────────────────────────────────────────────────────────────

# Prints the call stack in PHP style, skipping the first $1 extra frames (default 0).
# Frame 0 is always __print_stacktrace itself and is skipped automatically.
#
#   #0 ./a.sh(42): some_func()
#   #1 ./a.sh(10): caller_func()
#   #2 {main}
__print_stacktrace() {
  local skip=$(( ${1:-0} + 1 ))   # +1 to always exclude __print_stacktrace itself
  local depth=${#FUNCNAME[@]}
  local frame=0
  local i

  for (( i = skip; i < depth; i++ )); do
    local func="${FUNCNAME[$i]}"
    local src="${BASH_SOURCE[$i]:-?}"
    local line="${BASH_LINENO[$(( i - 1 ))]}"
    [[ -z "$func" ]] && func="main"
    printf '#%d %s(%d): %s()\n' "$frame" "$src" "$line" "$func"
    (( frame++ ))
  done
  printf '#%d {main}\n' "$frame"
}

# ─── debugger handler ────────────────────────────────────────────────────────

__dbg_read_key() {
  local key
  IFS= read -r -s -n1 key
  if [[ "$key" == $'\x1b' ]]; then
    local seq
    IFS= read -r -s -n2 -t 0.1 seq
    key="$key$seq"
  fi
  printf '%s' "$key"
}

handler() {
  [[ $__DBG_ACTIVE -eq 0 ]] && return

  local file="$1"
  local lineno="$2"
  local cmd="$3"

  local cols rows
  cols=$(tput cols)
  rows=$(tput lines)

  # gutter: "> 1234  " or "  1234  " = 8 chars; content is truncated to fit
  local gutter=8
  local max_content=$(( cols - gutter ))

  # ── layout heights ────────────────────────────────────────────────────────
  # fixed: header=1, cmd_bar=1, footer=1 → +vars bar if vars present
  local vars_rows=0
  [[ ${#__DBG_VARS[@]} -gt 0 ]] && vars_rows=1
  local code_rows=$(( rows - 3 - vars_rows ))
  local CONTEXT=$(( (code_rows - 1) / 2 ))

  # ── clear & header ────────────────────────────────────────────────────────
  clear

  local hdr_prefix=" "
  local hdr_file="$file"
  local hdr_sep="  :"
  local hdr_line="$lineno"
  local hdr_suffix=" "
  local hdr_len=$(( ${#hdr_prefix} + ${#hdr_file} + ${#hdr_sep} + ${#hdr_line} + ${#hdr_suffix} ))
  local hdr_pad=$(( cols - hdr_len ))
  printf '\033[0;44;97m%s\033[1;44;97m%s\033[0;44;97m%s%s%s%*s\033[0m\n' \
    "$hdr_prefix" "$hdr_file" "$hdr_sep" "$hdr_line" "$hdr_suffix" "$hdr_pad" ""

  # ── compute view window ───────────────────────────────────────────────────
  local total
  total=$(wc -l < "$file")
  local start=$(( lineno - CONTEXT ))
  local end=$(( lineno + CONTEXT ))
  (( start < 1     )) && start=1
  (( end   > total )) && end=$total

  # ── code view ────────────────────────────────────────────────────────────
  while IFS= read -r src_line; do
    local nr="${src_line%%	*}"
    local content="${src_line#*	}"
    # truncate content to available width
    content="${content:0:$max_content}"
    if (( nr == lineno )); then
      printf '\033[1;93m>\033[0m \033[1;93m%4d\033[0m  \033[1;97m%s\033[0m\n' \
        "$nr" "$content"
    else
      printf '  \033[90m%4d\033[0m  %s\n' "$nr" "$content"
    fi
  done < <(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e { print NR"\t"$0 }' "$file")

  # ── command bar ───────────────────────────────────────────────────────────
  local cmd_label=" cmd: ${cmd:0:$(( cols - 7 ))}"
  printf '\033[2;90m%-*s\033[0m\n' "$cols" "$cmd_label"

  # ── stack trace (fills filler space, bottom-aligned) ─────────────────────
  local actual_code=$(( end - start + 1 ))
  local filler=$(( code_rows - actual_code ))

  if (( filler > 0 )); then
    # collect stack lines, skip handler + __print_stacktrace (2 extra frames)
    local -a stack=()
    while IFS= read -r sl; do
      stack+=("$sl")
    done < <(__print_stacktrace 1)

    # how many stack lines fit (cap to filler, reserve 1 for "Stack trace:" header)
    local max_stack=$(( filler - 1 ))
    (( max_stack < 0 )) && max_stack=0
    local show=$(( ${#stack[@]} < max_stack ? ${#stack[@]} : max_stack ))
    local blank=$(( filler - show - (show > 0 ? 1 : 0) ))

    # blank padding above
    if (( blank > 0 )); then
      head -c "$blank" /dev/zero | tr '\0' '\n'
    fi

    # stack trace
    if (( show > 0 )); then
      printf '\033[90m Stack trace:\033[0m\n'
      for (( si = 0; si < show; si++ )); do
        local stline=" ${stack[$si]}"
        printf '\033[90m%s\033[0m\n' "${stline:0:$cols}"
      done
    fi
  fi

  # ── vars watch bar ────────────────────────────────────────────────────────
  if (( vars_rows > 0 )); then
    local vars_str=" "
    for v in "${__DBG_VARS[@]}"; do
      vars_str+="$v=${!v}   "
    done
    printf '\033[0;100;97m%-*s\033[0m\n' "$cols" "$vars_str"
  fi

  # ── keybinding bar ────────────────────────────────────────────────────────
  printf '\033[1;44;97m %-*s\033[0m' $(( cols - 2 )) \
    "[↓/n] step  [c] continue  [q] quit"

  # ── wait for input ────────────────────────────────────────────────────────
  local key
  key=$(__dbg_read_key)

  case "$key" in
    q|Q)
      clear
      echo "Debugger: quit."
      exit 0
      ;;
    c|C)
      trap - DEBUG
      ;;
    $'\x1b[B'|n|N|'')
      ;;
  esac
}

trap 'handler "$BASH_SOURCE" $LINENO "$BASH_COMMAND"' DEBUG

# ─── script under debug ──────────────────────────────────────────────────────

echo "Hello from the debugger"
NAME="world"
echo "Name is: $NAME"
X=$(( 6 * 7 ))
__breakpoint X NAME
echo "6 * 7 = $X"
echo "Ciao"


