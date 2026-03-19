


__breakpoint() {
  echo "Debug"
}

__plugin_debugger__feature_debug__hook_debug_entrypoint_init() {
  cat <<EOF
__debug_trap_handler() {
  echo "A: $LINENO $BASH_COMMAND"
}
trap '__debug_trap_handler' DEBUG
EOF
}


#  echo "> $BASH_COMMAND"
#  echo "  $BASH_SOURCE : $LINENO"

