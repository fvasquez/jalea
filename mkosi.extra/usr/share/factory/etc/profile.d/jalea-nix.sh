# Put Nix profiles on PATH: the user's own profile first, then the system
# profile (which holds the current Nix itself, see nix-upgrade.service).
if [ -d /nix/var/nix/profiles ]; then
    case ":$PATH:" in
        *:/nix/var/nix/profiles/default/bin:*) ;;
        *) PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH" ;;
    esac
    export PATH
    export NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
fi
