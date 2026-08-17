from flask import Flask, render_template, request, redirect, jsonify
import subprocess
import json

app = Flask(__name__)

BOXPROXY = "/usr/local/sbin/boxproxy"


def run_cmd(args):
    result = subprocess.run(
        args,
        text=True,
        capture_output=True
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def read_instances():
    code, out, err = run_cmd(
        ["sudo", BOXPROXY, "web-json"]
    )

    if code != 0:
        print("web-json error:", err)
        return []

    try:
        return json.loads(out)
    except Exception as e:
        print("JSON parse error:", e)
        print(out)
        return []


def read_wans():
    code, out, err = run_cmd(
        ["sudo", BOXPROXY, "wan-json"]
    )

    if code != 0:
        print("wan-json error:", err)
        return []

    try:
        return json.loads(out)
    except Exception as e:
        print("WAN JSON parse error:", e)
        print(out)
        return []

def read_ddns(wan_id):
    code, out, err = run_cmd(
        [
            "sudo",
            "/usr/local/lib/boxproxy/ddns-config",
            "get",
            str(wan_id)
        ]
    )

    if code != 0:
        print(f"DDNS config error for WAN {wan_id}:", err)

        return {
            "enabled": "no",
            "provider": "noip",
            "hostname": "",
            "username": "",
            "has_password": False,
            "interval_sec": 60,
        }

    try:
        return json.loads(out)
    except Exception as e:
        print(f"DDNS JSON parse error for WAN {wan_id}:", e)
        print(out)

        return {
            "enabled": "no",
            "provider": "noip",
            "hostname": "",
            "username": "",
            "has_password": False,
            "interval_sec": 60,
        }

@app.route("/")
def index():
    proxies = read_instances()
    wans = read_wans()

    for wan in wans:
        wan["ddns"] = read_ddns(wan["wan_id"])

    return render_template(
        "index.html",
        proxies=proxies,
        wans=wans
    )

@app.route("/routing")
def routing_page():
    proxies = read_instances()

    return render_template(
        "routing.html",
        proxies=proxies
    )

@app.post("/action/<int:proxy_id>/<action>")
def action(proxy_id, action):
    allowed = {
        "start",
        "stop",
        "restart",
        "change-mac",
        "proxy-enable",
        "proxy-disable",
    }

    if action not in allowed:
        return "Invalid action", 400

    run_cmd(
        ["sudo", BOXPROXY, action, str(proxy_id)]
    )

    return redirect("/")


@app.post("/change-password/<int:proxy_id>")
def change_password(proxy_id):
    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "change-password",
            str(proxy_id)
        ]
    )

    return redirect("/")

@app.post("/set-count/<int:wan_id>")
def set_count(wan_id):
    count = request.form.get("count", "").strip()

    if not count.isdigit() or int(count) < 1:
        return redirect("/")

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "set-count",
            str(wan_id),
            count
        ]
    )

    return redirect("/")

@app.post("/wan-save/<int:wan_id>")
def wan_save(wan_id):
    current_interface = request.form.get("current_interface", "").strip()
    new_interface = request.form.get("new_interface", "").strip()

    interface = new_interface if new_interface else current_interface

    username = request.form.get("pppoe_user", "").strip()
    password = request.form.get("pppoe_password", "").strip()

    if not interface or not username:
        return redirect("/")

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "wan-save",
            str(wan_id),
            interface,
            username,
            password
        ]
    )

    return redirect("/")

@app.post("/wan-save-wifi/<int:wan_id>")
def wan_save_wifi(wan_id):
    ssid = request.form.get("wifi_ssid", "").strip()
    password = request.form.get("wifi_password", "")
    band = request.form.get("wifi_band", "auto").strip()

    if not ssid:
        return redirect("/")

    if band not in ("auto", "2.4ghz", "5ghz"):
        band = "auto"

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "wan-save-wifi",
            str(wan_id),
            ssid,
            password,
            band
        ]
    )

    return redirect("/")

@app.post("/wan-proxy/<int:wan_id>/<action>")
def wan_proxy(wan_id, action):
    allowed = {
        "enable": "wan-proxy-enable",
        "disable": "wan-proxy-disable",
    }

    if action not in allowed:
        return "Invalid action", 400

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            allowed[action],
            str(wan_id)
        ]
    )

    return redirect("/")

@app.post("/wan-power/<int:wan_id>/<action>")
def wan_power(wan_id, action):
    allowed = {
        "start": "wan-start",
        "stop": "wan-stop",
    }

    if action not in allowed:
        return "Invalid action", 400

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            allowed[action],
            str(wan_id)
        ]
    )

    return redirect("/")

@app.post("/ddns-save/<int:wan_id>")
def ddns_save(wan_id):
    hostname = request.form.get("hostname", "").strip()
    username = request.form.get("username", "").strip()
    password = request.form.get("password", "").strip()
    interval_sec = request.form.get("interval_sec", "60").strip()

    enabled = (
        "yes"
        if request.form.get("enabled") == "yes"
        else "no"
    )

    if not hostname or not username:
        return redirect("/")

    if not interval_sec.isdigit():
        return redirect("/")

    if int(interval_sec) < 30:
        return redirect("/")

    run_cmd(
        [
            "sudo",
            "/usr/local/lib/boxproxy/ddns-config",
            "save",
            str(wan_id),
            hostname,
            username,
            password,
            interval_sec,
            enabled,
        ]
    )

    return redirect("/")


@app.post("/ddns-disable/<int:wan_id>")
def ddns_disable(wan_id):
    run_cmd(
        [
            "sudo",
            "/usr/local/lib/boxproxy/ddns-config",
            "disable",
            str(wan_id),
        ]
    )

    return redirect("/")

@app.post("/wan-delete/<int:wan_id>")
def wan_delete(wan_id):
    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "wan-delete",
            str(wan_id)
        ]
    )

    return redirect("/")

@app.get("/api/copy-socks")
def copy_socks():
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "copy-socks"]
    )

    return jsonify({"text": out})

@app.get("/api/copy-http")
def copy_http():
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "copy-http"]
    )

    return jsonify({"text": out})

@app.get("/api/copy-socks/<int:wan_id>")
def copy_socks_wan(wan_id):
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "copy-socks", str(wan_id)]
    )
    return jsonify({"text": out})


@app.get("/api/copy-http/<int:wan_id>")
def copy_http_wan(wan_id):
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "copy-http", str(wan_id)]
    )
    return jsonify({"text": out})

@app.get("/api/status")
def api_status():
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "web-json"]
    )

    try:
        return jsonify(json.loads(out))
    except Exception:
        return jsonify([])

@app.get("/api/free-interfaces")
def free_interfaces():
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "free-interfaces"]
    )

    try:
        return jsonify(json.loads(out))
    except Exception:
        return jsonify([])

@app.get("/api/clients")
def api_clients():
    code, out, err = run_cmd(
        ["sudo", BOXPROXY, "client-json"]
    )

    if code != 0:
        print("client-json error:", err)
        return jsonify([])

    try:
        return jsonify(json.loads(out))
    except Exception as e:
        print("Client JSON parse error:", e)
        print(out)
        return jsonify([])

@app.get("/api/client-ips")
def api_client_ips():
    code, out, err = run_cmd(
        ["sudo", BOXPROXY, "client-ip-json"]
    )

    if code != 0:
        return jsonify([])

    try:
        return jsonify(json.loads(out))
    except Exception:
        return jsonify([])


@app.post("/routing/ip-assign")
def routing_ip_assign():
    mac = request.form.get("mac", "").strip()
    last_octet = request.form.get("last_octet", "").strip()

    if not mac or not last_octet:
        return redirect("/routing?error=invalid-ip")

    code, out, err = run_cmd(
        [
            "sudo",
            BOXPROXY,
            "client-ip-assign",
            mac,
            last_octet
        ]
    )

    if code == 2 or code == 3:
        return redirect("/routing?error=ip-conflict")

    if code != 0:
        return redirect("/routing?error=ip-failed")

    return redirect("/routing?success=ip-saved")


@app.post("/routing/ip-remove")
def routing_ip_remove():
    mac = request.form.get("mac", "").strip()

    if not mac:
        return redirect("/routing")

    code, out, err = run_cmd(
        [
            "sudo",
            BOXPROXY,
            "client-ip-remove",
            mac
        ]
    )

    if code != 0:
        return redirect("/routing?error=ip-remove-failed")

    return redirect("/routing?success=ip-removed")

@app.post("/routing/assign")
def routing_assign():
    mac = request.form.get("mac", "").strip()
    ip = request.form.get("ip", "").strip()
    proxy_id = request.form.get("proxy_id", "").strip()

    if not mac or not ip or not proxy_id:
        return redirect("/routing")

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "client-assign",
            mac,
            ip,
            proxy_id
        ]
    )

    return redirect("/routing")


@app.post("/routing/remove")
def routing_remove():
    mac = request.form.get("mac", "").strip()

    if not mac:
        return redirect("/routing")

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "client-remove",
            mac
        ]
    )

    return redirect("/routing")

@app.post("/wan-add")
def wan_add():
    interface = request.form.get("interface", "").strip()
    wan_type = request.form.get("wan_type", "pppoe").strip()

    if not interface:
        return redirect("/")

    if wan_type == "dhcp":
        run_cmd(
            [
                "sudo",
                BOXPROXY,
                "wan-add-dhcp",
                interface
            ]
        )

        return redirect("/")

    if wan_type == "wifi":
        ssid = request.form.get("wifi_ssid", "").strip()
        wifi_password = request.form.get("wifi_password", "")
        wifi_band = request.form.get("wifi_band", "auto").strip()

        if not ssid or not wifi_password:
            return redirect("/")

        if wifi_band not in ("auto", "2.4ghz", "5ghz"):
            wifi_band = "auto"

        run_cmd(
            [
                "sudo",
                BOXPROXY,
                "wan-add-wifi",
                interface,
                ssid,
                wifi_password,
                wifi_band
            ]
        )

        return redirect("/")

    username = request.form.get("pppoe_user", "").strip()
    password = request.form.get("pppoe_password", "").strip()

    if not username or not password:
        return redirect("/")

    run_cmd(
        [
            "sudo",
            BOXPROXY,
            "wan-add",
            interface,
            username,
            password
        ]
    )

    return redirect("/")

@app.get("/api/wan-status")
def api_wan_status():
    _, out, _ = run_cmd(
        ["sudo", BOXPROXY, "wan-json"]
    )

    try:
        return jsonify(json.loads(out))
    except Exception:
        return jsonify([])

if __name__ == "__main__":
    app.run(
        host="10.10.10.1",
        port=8080,
        debug=False
    )
