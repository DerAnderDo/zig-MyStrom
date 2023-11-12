# zig-MyStrom
Monitor the power of a MyStrom Wifi Switch and decide if it needs to be switched off.
Uses the REST API of the Switch.

## Install as systemd service
Move myStromer.service to /etc/systemd/system/ \
Run `systemctl daemon-reload` \
Run `systemctl enable myStromer` \
Run `systemctl start myStromer`

## To-do
- Would be nice if the program would retain the threshold value after restarting
## Bugs
- Special case where the app crashes if a user runs a get request on for example /data, and the user already has a folder called data in the directory where he runs the command.
