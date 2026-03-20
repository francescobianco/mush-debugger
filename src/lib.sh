

#extern package cavalla

#echo "A1"
embed handler
#handler
#echo "A2"

__breakpoint() {
  echo "Debug"
}

__plugin_debugger__feature_debug__hook_debug_entrypoint_init() {
  __print_stack_trace >&2
  handler
  echo "#trap '__debug_trap_handler' DEBUG"
}

__print_stack_trace() {
  local i depth=${#FUNCNAME[@]}
  echo "Stack trace:"
  for (( i = 1; i < depth; i++ )); do
    printf '  #%d %s(%d): %s()\n' \
      "$(( i - 1 ))" \
      "${BASH_SOURCE[$i]:-?}" \
      "${BASH_LINENO[$(( i - 1 ))]}" \
      "${FUNCNAME[$i]:-main}"
  done
}

#  echo "> $BASH_COMMAND"
#  echo "  $BASH_SOURCE : $LINENO"

