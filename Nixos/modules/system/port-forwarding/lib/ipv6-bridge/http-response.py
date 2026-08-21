# &desc: "Rewrites outbound HTTP response headers to adapt location targets, cookies, and security policies away from localhost rules."

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import PORT


def rewrite_response(resp_buf, orig_host, scheme):
    rsep = resp_buf.find(b"\r\n\r\n")
    if rsep == -1:
        return resp_buf

    rhead, rtail = resp_buf[:rsep], resp_buf[rsep:]
    rlines = []
    for rl in rhead.split(b"\r\n"):
        low = rl.lower()
        if low.startswith(b"location:") and orig_host:
            loc = rl[9:].strip()
            for pfx in (
                b"http://localhost:" + str(PORT).encode(),
                b"https://localhost:" + str(PORT).encode(),
            ):
                if loc.startswith(pfx):
                    loc = scheme.encode() + b"://" + orig_host + loc[len(pfx):]
                    break
            rlines.append(b"Location: " + loc)
        elif low.startswith(b"set-cookie:"):
            if scheme == "http":
                rl = re.sub(rb"(?i);\s*secure\b", b"", rl)
            rl = re.sub(rb"(?i);\s*domain\s*=\s*localhost\b", b"", rl)
            rlines.append(rl)
        elif low.startswith(b"strict-transport-security:"):
            continue
        elif low.startswith(b"content-security-policy:") and scheme == "http":
            rlines.append(re.sub(rb"(?i)upgrade-insecure-requests[,;]?\s*", b"", rl))
        else:
            rlines.append(rl)

    return b"\r\n".join(rlines) + rtail
