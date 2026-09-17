# Nextcloud FileJumpQuota

FileJumpQuota is a custom quota management system for Nextcloud AIO.

It provides quota enforcement for the external storage mount:

`FileJump-Personale`

and automatically provisions Nextcloud users for FileJump storage.

## Features

- Default FileJump quota for all users
- Per-user custom quota
- Automatic provisioning every 5 minutes
- Automatic creation of user storage directories
- Automatic membership of the `filejump-users` group
- Fail-closed protection if the FileJumpQuota app is unavailable
- Systemd monitoring
- Nextcloud AIO support
- CLI quota management

## Current architecture

Nextcloud container:

```text
nextcloud-aio-nextcloud
