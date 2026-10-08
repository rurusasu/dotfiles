alias grep='rg'

if command -v kubectl >/dev/null 2>&1; then
  alias k='kubectl'
  alias kgn='kubectl get nodes'
  alias kgp='kubectl get pods -A'
  alias kgs='kubectl get svc -A'
fi
if command -v kubectx >/dev/null 2>&1; then
  alias kctx='kubectx'
fi
if command -v kubens >/dev/null 2>&1; then
  alias kns='kubens'
fi
