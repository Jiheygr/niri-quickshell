mkdir -p ~/.local/bin
cat > ~/.local/bin/toggle-drawer.sh << 'EOF'
#!/usr/bin/env bash
if pgrep -x nwg-drawer >/dev/null; then
    pkill -USR1 nwg-drawer
else
    nwg-drawer -r &
    disown
fi
EOF
chmod +x ~/.local/bin/toggle-drawer.sh
