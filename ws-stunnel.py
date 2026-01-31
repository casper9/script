#!/usr/bin/env python3
import base64
import hashlib
import socket
import threading
import select
import sys
import time
from typing import Optional, Tuple

LISTENING_ADDR = "0.0.0.0"
LISTENING_PORT = 700

# Kalau mau pakai password, isi string-nya. Kalau kosong = no password check.
PASS = ""

BUFLEN = 16384
TIMEOUT = 60
DEFAULT_HOST = "127.0.0.1:69"

# Jika True: hitung Sec-WebSocket-Accept sesuai standar
# Jika False: kirim "foo" (fake) seperti script lama
STRICT_WEBSOCKET = True

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def parse_hostport(hostport: str, fallback_port: int) -> Tuple[str, int]:
    hostport = hostport.strip()
    if ":" in hostport:
        h, p = hostport.rsplit(":", 1)
        try:
            return h.strip(), int(p.strip())
        except ValueError:
            return hostport.strip(), fallback_port
    return hostport, fallback_port


def get_header(raw: bytes, name: str) -> str:
    """
    Cari header case-insensitive, toleran spasi.
    """
    try:
        text = raw.decode("iso-8859-1", errors="ignore")
    except Exception:
        return ""
    lines = text.split("\r\n")
    name_l = name.lower()
    for ln in lines:
        if ":" not in ln:
            continue
        k, v = ln.split(":", 1)
        if k.strip().lower() == name_l:
            return v.strip()
    return ""


def build_ws_101_response(client_key: Optional[str]) -> bytes:
    if not STRICT_WEBSOCKET:
        return (
            b"HTTP/1.1 101 Switching Protocols\r\n"
            b"Upgrade: websocket\r\n"
            b"Connection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: foo\r\n\r\n"
        )

    if not client_key:
        # fallback kalau key nggak ada
        accept = "foo"
    else:
        sha1 = hashlib.sha1((client_key + WS_GUID).encode("utf-8")).digest()
        accept = base64.b64encode(sha1).decode("ascii")

    resp = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
    )
    return resp.encode("ascii")


class Server(threading.Thread):
    def __init__(self, host: str, port: int):
        super().__init__(daemon=True)
        self.running = False
        self.host = host
        self.port = port
        self.conns = []
        self.lock = threading.Lock()

    def run(self):
        self.running = True
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as soc:
            soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            soc.bind((self.host, self.port))
            soc.listen(128)
            soc.settimeout(2)
            print(f"[+] Listening on {self.host}:{self.port}")

            while self.running:
                try:
                    c, addr = soc.accept()
                    c.settimeout(10)
                except socket.timeout:
                    continue
                except Exception:
                    continue

                h = ConnectionHandler(c, addr, self)
                h.start()
                with self.lock:
                    self.conns.append(h)

    def remove(self, h):
        with self.lock:
            if h in self.conns:
                self.conns.remove(h)

    def stop(self):
        self.running = False
        with self.lock:
            for h in list(self.conns):
                h.close()


class ConnectionHandler(threading.Thread):
    def __init__(self, client: socket.socket, addr, server: Server):
        super().__init__(daemon=True)
        self.client = client
        self.addr = addr
        self.server = server
        self.target: Optional[socket.socket] = None
        self.closed = False

    def close(self):
        if self.closed:
            return
        self.closed = True
        try:
            self.client.close()
        except Exception:
            pass
        try:
            if self.target:
                self.target.close()
        except Exception:
            pass

    def connect_target(self, hostport: str):
        host, port = parse_hostport(hostport, 443)
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        af, socktype, proto, _, sa = infos[0]
        self.target = socket.socket(af, socktype, proto)
        self.target.settimeout(10)
        self.target.connect(sa)
        self.target.settimeout(None)

    def relay(self):
        assert self.target is not None
        self.client.settimeout(None)
        socks = [self.client, self.target]
        idle = 0
        while True:
            r, _, e = select.select(socks, [], socks, 3)
            if e:
                break
            if not r:
                idle += 3
                if idle >= TIMEOUT:
                    break
                continue
            idle = 0
            for s in r:
                try:
                    data = s.recv(BUFLEN)
                    if not data:
                        return
                    if s is self.client:
                        self.target.sendall(data)
                    else:
                        self.client.sendall(data)
                except Exception:
                    return

    def run(self):
        try:
            buf = self.client.recv(BUFLEN)
            if not buf:
                return

            hostport = get_header(buf, "X-Real-Host") or DEFAULT_HOST
            xsplit = get_header(buf, "X-Split")

            if xsplit:
                # buang 1 paket lagi (behavior lama)
                try:
                    _ = self.client.recv(BUFLEN)
                except Exception:
                    pass

            passwd = get_header(buf, "X-Pass")

            # policy: jika PASS di-set, harus match
            if PASS and passwd != PASS:
                self.client.sendall(b"HTTP/1.1 400 WrongPass!\r\n\r\n")
                return

            # optional safety: block non-local target jika PASS kosong
            if (not PASS) and not (hostport.startswith("127.0.0.1") or hostport.startswith("localhost")):
                self.client.sendall(b"HTTP/1.1 403 Forbidden!\r\n\r\n")
                return

            # Connect to target
            self.connect_target(hostport)

            # WebSocket handshake response
            ws_key = get_header(buf, "Sec-WebSocket-Key")
            self.client.sendall(build_ws_101_response(ws_key))

            print(f"[+] {self.addr} -> {hostport}")
            self.relay()

        except Exception as e:
            print(f"[-] {self.addr} error: {e}")
        finally:
            self.close()
            self.server.remove(self)


def main():
    global LISTENING_PORT
    if len(sys.argv) >= 2:
        try:
            LISTENING_PORT = int(sys.argv[1])
        except ValueError:
            print("Usage: proxy_ws.py [port]")
            sys.exit(1)

    srv = Server(LISTENING_ADDR, LISTENING_PORT)
    srv.start()
    try:
        while True:
            time.sleep(2)
    except KeyboardInterrupt:
        print("Stopping...")
        srv.stop()


if __name__ == "__main__":
    main()
