#!/bin/bash

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
  local file="$1"
  local lineno="$2"
  local cmd="$3"

  local cols rows
  cols=$(tput cols)
  rows=$(tput lines)

  # ── clear & header ruler ─────────────────────────────────────────────────
  clear

  # header: " <filename bold>  :<lineno normal> " padded to full width
  local hdr_prefix=" "
  local hdr_file="$file"
  local hdr_sep="  :"
  local hdr_line="$lineno"
  local hdr_suffix=" "
  local hdr_len=$(( ${#hdr_prefix} + ${#hdr_file} + ${#hdr_sep} + ${#hdr_line} + ${#hdr_suffix} ))
  local hdr_pad=$(( cols - hdr_len ))
  printf '\033[0;44;97m%s\033[1;44;97m%s\033[0;44;97m%s%s%s%*s\033[0m\n' \
    "$hdr_prefix" "$hdr_file" "$hdr_sep" "$hdr_line" "$hdr_suffix" "$hdr_pad" ""

  # ── compute view window ──────────────────────────────────────────────────
  # fixed rows: header=1, cmd_bar=1, footer=1 → code gets rows-3
  local code_rows=$(( rows - 3 ))
  local CONTEXT=$(( (code_rows - 1) / 2 ))

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
    if (( nr == lineno )); then
      printf '\033[1;93m>\033[0m \033[1;93m%4d\033[0m  \033[1;97m%s\033[0m\n' \
        "$nr" "$content"
    else
      printf '  \033[90m%4d\033[0m  %s\n' "$nr" "$content"
    fi
  done < <(awk -v s="$start" -v e="$end" 'NR>=s && NR<=e { print NR"\t"$0 }' "$file")

  # ── command bar ──────────────────────────────────────────────────────────
  local cmd_label=" cmd: $cmd"
  local cmd_pad=$(( cols - ${#cmd_label} ))
  printf '\033[2;90m%s%*s\033[0m\n' "$cmd_label" "$cmd_pad" ""

  # fill empty lines to push footer to bottom
  local actual_code=$(( end - start + 1 ))
  local filler=$(( code_rows - actual_code ))
  if (( filler > 0 )); then
    head -c "$filler" /dev/zero | tr '\0' '\n'
  fi

  # ── keybinding bar ───────────────────────────────────────────────────────
  printf '\033[1;44;97m %-*s\033[0m' $(( cols - 2 )) \
    "[↓/n] step  [c] continue  [q] quit"

  # ── wait for input ───────────────────────────────────────────────────────
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
      # step / down arrow / enter → just return and let DEBUG fire again
      ;;
  esac
}

trap 'handler "$BASH_SOURCE" $LINENO "$BASH_COMMAND"' DEBUG

# ─── script under debug ──────────────────────────────────────────────────────

echo "Hello from the debugger"
NAME="world"
echo "Name is: $NAME"
X=$(( 6 * 7 ))
echo "6 * 7 = $X"