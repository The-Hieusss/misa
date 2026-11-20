#!/bin/zsh
# Removes M.I.S.A. and her settings. Your files, ~/Screenshots and ~/Disposable are left alone.
#
#   ./uninstall.sh            remove the app and her settings (look, position, chat state)
#   KEEP_SETTINGS=1 ./uninstall.sh   remove only the app
NAME="M.I.S.A..app"

if pgrep -xq MISA; then
  osascript -e 'tell application id "app.misa.assistant" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -xq MISA || break; sleep 0.25; done
  pkill -x MISA 2>/dev/null || true
fi

removed=0
for dir in /Applications "$HOME/Applications" ${INSTALL_DIR:+"${INSTALL_DIR/#\~/$HOME}"}; do
  if [[ -d "$dir/$NAME" ]]; then
    rm -rf "$dir/$NAME" && echo "Removed $dir/$NAME" && removed=1
  fi
done
(( removed )) || echo "M.I.S.A. wasn't found in /Applications or ~/Applications."

if [[ "$KEEP_SETTINGS" != 1 ]]; then
  defaults delete app.misa.assistant >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Logs/misa.log"
  echo "Removed her settings and log."
fi

echo "Uninstalled. If she was set to Launch at Login, macOS drops the entry on its own;"
echo "you can also remove it under System Settings > General > Login Items."
