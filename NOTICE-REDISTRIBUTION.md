# Third-party licensing and redistribution notice

This repository contains packaging automation, not a grant of rights to
third-party code or binaries.

The DKMS sources are fetched from STMicroelectronics' public TTTech TSN content
repositories. The OpenSTLinux recipes label the kernel module recipes GPL-2.0,
but the full source tree must retain its upstream notices.

The OpenSTLinux TSN user-space stack is labelled `TTTECH-license`. In
particular, the DE-PTP payload is supplied as a TTTech binary installer and the
OpenSTLinux recipe requires explicit acceptance of ST's EULA. GitHub Actions
will refuse to build or publish any user-space package unless the workflow
operator affirms both license acceptance and public redistribution rights.

Do not enable the user-space build merely because the sources are reachable.
Confirm that your intended publication, jurisdiction, and downstream use are
permitted by the applicable ST/TTTech terms.
