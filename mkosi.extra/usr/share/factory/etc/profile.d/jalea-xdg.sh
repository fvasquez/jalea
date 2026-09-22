# Jalea's defaults for XDG-configured programs (foot, for one) live under
# /usr/share/jalea/xdg, so that they change with each update. /etc/xdg
# stays first: a file there overrides the default of the same name.
case ":${XDG_CONFIG_DIRS:-/etc/xdg}:" in
    *:/usr/share/jalea/xdg:*) ;;
    *) XDG_CONFIG_DIRS="${XDG_CONFIG_DIRS:-/etc/xdg}:/usr/share/jalea/xdg" ;;
esac
export XDG_CONFIG_DIRS
