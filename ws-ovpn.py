#!/usr/bin/env python3
import socket
import threading
import select
import sys
import time
from typing import Optional, Tuple

LISTENING_ADDR = "0.0.0.0"
LISTENING_PORT = 700  # default kalau ga dikasih arg
PASS = ""             # isi kalau mau wajib password

BUFLEN = 4096 * 4
TIMEOUT = 60
DEFAULT_HOST = "127.0.0.1:1194"

# Response "trik" kamu (101 + content-length gede)
RESPONSE = (
    "HTTP/1.1 101 Switching Protocols\r\n"
    "Content-Length: 104857600000\r\n\r\n"
).encode("ascii")


def get_header(raw: bytes, name: str) -> str:
    """
    Header parser tolerant: case-insensitive, spasi optional.
    """
    try:
        text = raw.decode("iso-8859-1", errors="ignore")
    except Exception:
        return ""
    name_l = name.lower()
    for ln in text.split("\r\n"):
        if ":" not in ln:
            continue
        k, v = ln.split(":", 1)
        if k.strip().lower() == name_l:
            return v.strip()
    return ""


def parse_hostport(hostport: str, default_port: int) -> Tuple[str, int]:
    hostport = hostport.strip()
    if ":" in hostport:
        h, p = hostport.rsplit(":", 1)
        try:
            return h.strip(), int(p.strip())
        except ValueError:
            return hostport, default_port
    return hostport, default_port


class Server(threading.Thread):
    def __init__(self, host: str, port: int):
        super().__init__(daemon=True)
        self.host = host
        self.port = port
        self.running = False
        self._lock = threading.Lock()
        self._conns = []

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
                with self._lock:
                    self._conns.append(h)

    def remove(self, h):
        with self._lock:
            if h in self._conns:
                self._conns.remove(h)

    def stop(self):
        self.running = False
        with self._lock:
            for h in list(self._conns):
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
                return
            if not r:
                idle += 3
                if idle >= TIMEOUT:
                    return
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
                # buang 1 paket tambahan seperti script lama
                try:
                    _ = self.client.recv(BUFLEN)
                except Exception:
                    pass

            passwd = get_header(buf, "X-Pass")

            # policy sama seperti script lama:
            # - kalau PASS diisi -> harus match
            # - kalau PASS kosong -> hanya boleh target localhost/127.0.0.1
            if PASS and passwd != PASS:
                self.client.sendall(b"HTTP/1.1 400 WrongPass!\r\n\r\n")
                return

            if (not PASS) and not (hostport.startswith("127.0.0.1") or hostport.startswith("localhost")):
                self.client.sendall(b"HTTP/1.1 403 Forbidden!\r\n\r\n")
                return

            self.connect_target(hostport)

            # kirim RESPONSE trik kamu
            self.client.sendall(RESPONSE)

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
            print("Usage: python3 proxy_1194.py [listen_port]")
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
