

#extern package cavalla

#echo "A1"
embed handler
#handler
#echo "A2"

__breakpoint() {
  echo "Debug"
}

__plugin_debugger__feature_debug__hook_debug_entrypoint_init() {
  #handler
  echo "#trap '__debug_trap_handler' DEBUG"
}


#  echo "> $BASH_COMMAND"
#  echo "  $BASH_SOURCE : $LINENO"

