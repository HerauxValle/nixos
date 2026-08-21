# &desc: "Transforms inbound HTTP request fields, tracking client origin IPs and identifying long-lived connection protocols."

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from _stub import PORT


def rewrite_request(buf, client_ip, scheme):
    sep = buf.find(b"\r\n\r\n")
    if sep == -1:
        return buf, b"", b"", b"/", False

    head, tail = buf[:sep], buf[sep:]
    lines = head.split(b"\r\n")

    req_path = b"/"
    if lines:
        parts = lines[0].split(b" ")
        if len(parts) >= 2:
            req_path = parts[1]

    orig_host = b""
    new_lines = []
    for ln in lines:
        low = ln.lower()
        if low.startswith(b"host:"):
            orig_host = ln[5:].strip()
            new_lines.append(f"Host: localhost:{PORT}".encode())
        elif low.startswith(b"keep-alive:"):
            continue
        elif low.startswith(b"connection:"):
            if b"upgrade" in low[11:].strip():
                new_lines.append(ln)
            # else drop -- Connection: close (re-)added below when appropriate
        else:
            new_lines.append(ln)

    is_ws = any(
        b"upgrade" in ln.lower()
        for ln in new_lines
        if ln.lower().startswith(b"connection:")
    )
    is_sse = any(
        b"text/event-stream" in ln.lower()
        for ln in new_lines
        if ln.lower().startswith(b"accept:")
    )
    is_long_lived = is_ws or b"transport=polling" in req_path or is_sse
    if not is_long_lived:
        new_lines.append(b"Connection: close")

    new_lines += [
        b"X-Forwarded-Proto: " + scheme.encode(),
        b"X-Real-IP: " + client_ip.encode(),
    ]
    if orig_host:
        new_lines.append(b"X-Forwarded-Host: " + orig_host)

    return b"\r\n".join(new_lines) + tail, tail, orig_host, req_path, is_long_lived
