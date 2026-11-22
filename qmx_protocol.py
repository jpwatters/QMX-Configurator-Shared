"""
QMX/QMX+ CAT Menu Manager protocol layer (read-only in this version).

No GUI code lives here so it can be tested on its own.

Menu data types (QRP Labs CAT manual, plus one observed on firmware 1.04.010):
    0 Sub-menu   1 Application/action   2 String   3 Number   4 Byte (0-255)
    5 List       6 Info                 7 Mask (boolean bit)
    8 Decimal (undocumented; e.g. PA voltage '6.00'; param = field length)
"""

from __future__ import annotations

import datetime as _dt
import re
import socket
import subprocess
import sys
import time
from typing import Callable, Optional

import serial
from serial.tools import list_ports

TYPE_NAMES = {0: "Sub-menu", 1: "Action", 2: "Text", 3: "Number", 4: "Byte",
              5: "List", 6: "Info", 7: "Mask", 8: "Decimal"}
VALUE_TYPES = {2, 3, 4, 5, 6, 7, 8}
GRID_RE = re.compile(r"^(.*)\[(\d+)\]$")
MAX_CHILDREN = 64
MAX_DEPTH = 6

# Menu names that the GUI must treat as locked / dangerous.
DANGER_KEYWORDS = ("danger", "caution", "advanced config", "factory reset",
                   "update firmware", "do not disable")


# macOS system ports that are never a radio.
_MAC_SKIP = ("Bluetooth-Incoming-Port", "debug-console", "wlan-debug")


def _describe(p) -> str:
    for d in (p.product, p.description, p.manufacturer):
        if d and d.lower() != "n/a":
            return d
    return ""


def available_ports():
    """Return [(device, description)].

    On macOS every serial device appears twice: /dev/tty.* (open() waits for
    carrier detect, so it can hang) and /dev/cu.* (opens immediately). Only the
    cu.* form is offered, built-in system ports are hidden, and USB devices
    (the QMX shows up as /dev/cu.usbmodem...) are listed first.
    """
    ports = list(list_ports.comports())
    if sys.platform != "darwin":
        return [(p.device, p.description or "")
                for p in sorted(ports, key=lambda p: p.device)]
    out, seen = [], set()
    for p in ports:
        dev = p.device
        if dev.startswith("/dev/tty."):
            dev = "/dev/cu." + dev[len("/dev/tty."):]
        if dev in seen or any(k in dev for k in _MAC_SKIP):
            continue
        seen.add(dev)
        out.append((dev, _describe(p)))
    out.sort(key=lambda d: (not ("usbmodem" in d[0] or "usbserial" in d[0]), d[0]))
    return out


# ------------------------------------------------------------------ network relay
# The QMX+ shared from the Synology NAS (or Raspberry Pi) by qmx_nas_relay.py
# from the QMX-Panadapter-NAS project. The relay answers "QMXR?" on UDP 7355
# with "QMXR! <ip> <port>" (same discovery as the Tab5's Find NAS) and serves
# the radio's USB serial port 3 as raw CAT bytes on TCP 7356. Port 3 needs
# System config > GPS & Ser. ports > USB serial ports = 3 on the radio.
NET_SCHEME = "socket://"
RELAY_SERIAL_PORT = 7356
DISCOVERY_PORT = 7355
DISCOVERY_TIME = 1.5


class RelayClosed(RuntimeError):
    """The network relay closed the connection."""


def is_network(port: str) -> bool:
    return bool(port) and port.startswith(NET_SCHEME)


def relay_url(host: str, port: int = RELAY_SERIAL_PORT) -> str:
    return f"{NET_SCHEME}{host}:{port}"


def relay_port(url: str) -> int:
    tail = url.rsplit(":", 1)[-1] if is_network(url) else ""
    return int(tail) if tail.isdigit() else RELAY_SERIAL_PORT


def relay_addr(url: str) -> str:
    """'10.0.0.137:7356' for a relay URL."""
    return url[len(NET_SCHEME):] if is_network(url) else url


def relay_host(url: str) -> str:
    return url[len(NET_SCHEME):].rsplit(":", 1)[0] if is_network(url) else url


def normalize_port(text: str) -> str:
    """Turn a typed '10.0.0.137', '10.0.0.137:7356', 'nas:host' or 'socket://...'
    into a relay URL; anything else (a serial device or COM port) is returned as is."""
    t = (text or "").strip()
    if is_network(t):
        return t
    if t.lower().startswith("nas:"):
        t = t[4:].strip()
    elif not re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?", t):
        return text.strip()
    host, _, port = t.partition(":")
    return relay_url(host, int(port) if port.isdigit() else RELAY_SERIAL_PORT)


def _broadcast_addresses() -> list:
    """255.255.255.255 plus each interface's broadcast address (a Mac sends
    255.255.255.255 out of one interface only)."""
    out = ["255.255.255.255"]
    try:
        txt = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=3).stdout
        for b in re.findall(r"\bbroadcast (\d+\.\d+\.\d+\.\d+)", txt) + \
                re.findall(r"\bBcast:(\d+\.\d+\.\d+\.\d+)", txt):
            if b not in out:
                out.append(b)
    except (OSError, subprocess.SubprocessError):
        pass
    return out


def discover_relays(timeout: float = DISCOVERY_TIME, udp_port: int = DISCOVERY_PORT) -> list:
    """Broadcast "QMXR?" three times over `timeout` s; return the relay IPs that
    answer "QMXR! <ip> <port>", in the order they answer."""
    found: list = []
    u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        u.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        u.settimeout(0.1)
        targets = _broadcast_addresses()
        start, sent = time.monotonic(), 0
        while time.monotonic() - start < timeout:
            if sent < 3 and time.monotonic() - start >= sent * timeout / 3:
                for t in targets:
                    try:
                        u.sendto(b"QMXR?", (t, udp_port))
                    except OSError:
                        pass
                sent += 1
            try:
                data, peer = u.recvfrom(256)
            except (socket.timeout, OSError):
                continue
            parts = data.decode("ascii", "replace").split()
            if not parts or parts[0] != "QMXR!":
                continue
            ip = parts[1] if len(parts) > 1 else ""
            if not re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", ip):
                ip = peer[0]
            if ip not in found:
                found.append(ip)
    finally:
        u.close()
    return found


class ReadOnlyViolation(RuntimeError):
    pass


class Radio:
    """Read-only CAT transport. DTR/RTS are held low; '=' and MU are refused."""

    def __init__(self, port: str, baud: int = 38400, timeout: float = 1.0,
                 log: Optional[Callable[[str], None]] = None):
        self.port = port
        self.timeout = timeout
        self.log = log or (lambda s: None)
        self.count = 0
        self.network = is_network(port)
        if self.network:
            # NAS relay: raw CAT bytes over TCP (pyserial's socket:// handler).
            s = serial.serial_for_url(port, do_not_open=True)
            s.timeout, s.write_timeout = timeout, timeout
            s.open()
            time.sleep(0.6)          # relay opens the radio's port 3 on connect
        else:
            s = serial.Serial()
            s.port, s.baudrate = port, baud
            s.timeout, s.write_timeout = timeout, timeout
            s.dtr = False
            s.rts = False
            s.open()
            time.sleep(0.3)
        self.ser = s
        s.reset_input_buffer()

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass

    def query(self, cmd: str) -> Optional[str]:
        """Send one command, return the reply up to and including the first ';'."""
        if not re.fullmatch(r"(?:VN|ID|FA|MD|ML[0-9]+|MM[^;=\r\n]+);", cmd):
            raise ReadOnlyViolation(f"Refusing unsupported read command: {cmd!r}")
        return self._exchange(cmd)

    def power_state(self) -> Optional[str]:
        """'PS;' -> '1' on, '0' off (the relay answers for a radio that is off)."""
        return body(self._exchange("PS;"), "PS")

    def power_on(self) -> Optional[str]:
        """'PS1;' - over the NAS relay this presses the radio's power button
        (only when the relay has the opto power cable set up)."""
        return self._exchange("PS1;")

    def write_setting(self, path, value):
        if not re.fullmatch(r"[0-9]+(?:\|[0-9]+)*(?:\[[0-9]+\])?", path):
            raise ValueError("Invalid numeric menu path")
        if not isinstance(value, str) or any(ord(c) < 32 or ord(c) > 126 or c in ";=|?[]" for c in value):
            raise ValueError("Unsafe or unsupported value")
        return self._exchange("MM" + path + "=" + value + ";")

    def _exchange(self, cmd):
        try:
            return self._exchange_raw(cmd)
        except (serial.SerialException, OSError) as e:
            if self.network:
                raise RelayClosed(
                    "The NAS relay closed the connection. Check that the radio's "
                    "System config > GPS & Ser. ports > USB serial ports is 3, that the "
                    "radio is on, and that no other program (for example the Mac TCI "
                    f"bridge) is using QMX port 3.  ({e})") from e
            raise

    def _exchange_raw(self, cmd):
        self.ser.reset_input_buffer()
        self.ser.write(cmd.encode("ascii", errors="replace"))
        self.ser.flush()
        buf = bytearray()
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            chunk = self.ser.read(self.ser.in_waiting or 1)
            if chunk:
                buf.extend(chunk)
                if b";" in buf:
                    break
        self.count += 1
        if not buf:
            self.log(f"TX {cmd}   RX (timeout)")
            return None
        text = buf.decode("ascii", errors="replace")
        reply, sep, extra = text.partition(";")
        reply = reply.strip() + sep
        note = f"   [discarded trailing {extra!r}]" if extra.strip() else ""
        self.log(f"TX {cmd}   RX {reply}{note}")
        return reply


def body(reply: Optional[str], prefix: str) -> Optional[str]:
    """Strip prefix and ';'. Returns None for timeout or '?;' error."""
    if reply is None or reply.startswith("?"):
        return None
    if reply.startswith(prefix):
        reply = reply[len(prefix):]
    return reply[:-1] if reply.endswith(";") else reply


def parse_discovery(b: str):
    parts = b.split("|", 2)
    if len(parts) != 3:
        return None
    try:
        return int(parts[0]), int(parts[1]), parts[2]
    except ValueError:
        return None


def is_dangerous(name: str) -> bool:
    n = name.lower()
    return any(k in n for k in DANGER_KEYWORDS)


class Discoverer:
    """Walks the menu tree. progress(path) is called for each item; cancel() stops."""

    def __init__(self, radio: Radio, progress: Callable[[str], None] = lambda s: None):
        self.radio = radio
        self.progress = progress
        self._cancel = False
        self.list_types: set = set()
        self.damaged_lists: list = []

    def cancel(self):
        self._cancel = True

    def _get(self, idx_path, name_path, sub=None):
        s = f"[{sub}]" if sub is not None else ""
        v = body(self.radio.query("MM" + "|".join(map(str, idx_path)) + s + ";"), "MM")
        if v is None and not any(n.strip().isdigit() for n in name_path):
            v = body(self.radio.query("MM" + "|".join(name_path) + s + ";"), "MM")
        return v

    def _walk(self, idx_path, name_path, depth, grid_cols):
        items = []
        for i in range(MAX_CHILDREN):
            if self._cancel:
                break
            q = "MM" + "|".join(map(str, idx_path + [i])) + "?;"
            b = body(self.radio.query(q), "MM")
            if b is None:
                break
            parsed = parse_discovery(b)
            if parsed is None:
                items.append({"index": i, "raw": b})
                continue
            dtype, param, raw_name = parsed
            m = GRID_RE.match(raw_name)
            name, cols = (m.group(1), int(m.group(2))) if m else (raw_name, None)
            node = {"index": i, "name": name, "type": dtype, "param": param,
                    "path_names": "|".join(name_path + [name]),
                    "path_index": "|".join(map(str, idx_path + [i]))}
            if dtype in (5, 7):
                node["list_type"] = param
                self.list_types.add(param)
            self.progress(node["path_names"])
            if dtype == 0:
                if cols is not None:
                    node["grid_columns"] = cols
                if depth < MAX_DEPTH:
                    node["children"] = self._walk(idx_path + [i], name_path + [name],
                                                  depth + 1, cols or grid_cols)
            elif dtype in VALUE_TYPES:
                if grid_cols:
                    node["values"] = [self._get(idx_path + [i], name_path + [raw_name], c)
                                      for c in range(grid_cols)]
                else:
                    node["value"] = self._get(idx_path + [i], name_path + [raw_name])
            items.append(node)
        return items

    def run(self) -> dict:
        fw = body(self.radio.query("VN;"), "VN")
        tree = self._walk([], [], 0, None)
        lists = {}
        for lt in sorted(self.list_types):
            if self._cancel:
                break
            b = None
            for attempt in range(3):            # retry replies that arrive damaged
                r = self.radio.query(f"ML{lt};")
                if r is not None and r.startswith("ML"):
                    b = body(r, "ML")
                    break
                if r is not None and b is None:
                    b = body(r, "ML")           # keep best effort, flag below
                time.sleep(0.1)
            if b is not None and not (r or "").startswith("ML"):
                self.damaged_lists.append(str(lt))
            lists[str(lt)] = b.split("|") if b is not None else None
        return {"generated": _dt.datetime.now().isoformat(timespec="seconds"),
                "port": self.radio.port, "firmware": fw,
                "commands_sent": self.radio.count, "cancelled": self._cancel,
                "damaged_lists": self.damaged_lists,
                "lists": lists, "menu": tree}


def clean_list(choices):
    """Tidy list choices from older snapshots (strip anything after a stray ';')."""
    if not choices:
        return choices
    return [c.split(";", 1)[0] for c in choices]


def repair_lists(lists: dict, menu: list) -> dict:
    """
    Firmware 1.04.010 sometimes drops the first choice of a list (seen on ML8,
    whose ',' arrives blank, and ML34, whose 'None' is lost). Where a list has a
    blank choice and exactly one current value that is missing from the list,
    put that value in the blank slot. Returns {list_type: inferred_value}.
    """
    used: dict = {}

    def walk(nodes):
        for n in nodes:
            if n.get("type") in (5, 7):
                vals = n.get("values") if "values" in n else [n.get("value")]
                for v in vals:
                    if v is not None:
                        used.setdefault(str(n.get("list_type")), set()).add(v)
            walk(n.get("children", []))

    walk(menu)
    inferred = {}
    for lt, choices in lists.items():
        if not choices or "" not in choices:
            continue
        missing = [v for v in used.get(lt, ()) if v not in choices]
        if len(missing) == 1 and choices.count("") == 1:
            choices[choices.index("")] = missing[0]
            inferred[lt] = missing[0]
    return inferred
