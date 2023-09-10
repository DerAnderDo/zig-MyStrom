# zig-MyStrom
Monitor the power of a MyStrom Wifi Switch and decide if it needs to be switched off.
Uses the REST API of the Switch.

## Install as systemd service
Move myStromer.service to /etc/systemd/system/ \
Run `systemctl daemon-reload` \
Run `systemctl enable myStromer` \
Run `systemctl start myStromer`
