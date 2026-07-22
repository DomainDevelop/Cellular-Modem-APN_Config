#!/bin/bash
cat << 'TXT' > upload/INSTALL.txt
Offline install of the package on an OpenWrt router
=====================================================

Option A - LuCI web upload (no SSH required):
  1. Log in to LuCI (the router web UI) as admin.
  2. Go to System -> Software.
  3. Click "Upload Package..." and select the .apk or .ipk file from this artifact.
  4. Confirm the install. Refresh LuCI; the new menu entry appears afterwards.

  NOTE: If you see an "UNTRUSTED signature" error, you MUST use Option B (SSH) 
  because LuCI does not allow bypassing signature checks for third-party packages.

Option B - SSH / Command Line (Recommended for third-party packages):
  1. Copy the .apk (or .ipk) to the router via scp or WinSCP to /tmp.
     (If you already tried uploading via LuCI and it failed, the file is likely 
      already at /tmp/upload.apk)
  2. SSH into the router.
  3. Install the package while allowing untrusted signatures:
     For OpenWrt 24.x/25.x (using apk):
       apk add --allow-untrusted /tmp/upload.apk
     For older OpenWrt (using opkg):
       opkg install /tmp/upload.ipk
TXT
