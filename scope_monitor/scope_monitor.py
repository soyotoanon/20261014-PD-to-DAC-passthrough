# -*- coding: utf-8 -*-
"""
RIGOL DS1102Z-E 双通道实时监测：CH1(PD直出) vs CH2(DAC输出)
- 左侧：两路电压-时间曲线
- 右侧：CH2 对 CH1 散点 + 线性拟合（看斜率）
结束后保存 CSV 和 PNG。
"""
import sys, time, csv
import numpy as np
import pyvisa
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.pyplot as plt

DURATION = float(sys.argv[1]) if len(sys.argv) > 1 else 150.0
ADDR = "USB0::0x1AB1::0x0517::DS1ZE264813460::INSTR"

rm = pyvisa.ResourceManager()
scope = rm.open_resource(ADDR)
scope.timeout = 3000
print("connected:", scope.query("*IDN?").strip())

def vavg(ch):
    try:
        v = float(scope.query(f":MEASure:ITEM? VAVG,CHANnel{ch}").strip())
        return v if abs(v) < 1e30 else np.nan
    except Exception:
        return np.nan

t0 = time.time()
ts, v1s, v2s = [], [], []

plt.ion()
fig, (ax_t, ax_xy) = plt.subplots(1, 2, figsize=(13, 5.5))
fig.canvas.manager.set_window_title("PD vs DAC live monitor")

ln1, = ax_t.plot([], [], color="gold", lw=1.2, label="CH1 PD direct (mV)")
ln2, = ax_t.plot([], [], color="deepskyblue", lw=1.2, label="CH2 DAC out (mV)")
ax_t.set_xlabel("t (s)"); ax_t.set_ylabel("Vavg (mV)"); ax_t.legend(loc="upper right"); ax_t.grid(alpha=0.3)

ax_xy.set_xlabel("CH1 PD direct (mV)"); ax_xy.set_ylabel("CH2 DAC out (mV)")
ax_xy.grid(alpha=0.3)
fit_text = ax_xy.text(0.03, 0.95, "", transform=ax_xy.transAxes, va="top", fontsize=11)

print(f"logging for {DURATION:.0f}s ... (close window or wait)")
while time.time() - t0 < DURATION and plt.fignum_exists(fig.number):
    t = time.time() - t0
    a, b = vavg(1), vavg(2)
    if not (np.isnan(a) or np.isnan(b)):
        ts.append(t); v1s.append(a * 1e3); v2s.append(b * 1e3)
        ln1.set_data(ts, v1s); ln2.set_data(ts, v2s)
        ax_t.relim(); ax_t.autoscale_view()
        ax_xy.clear()
        ax_xy.set_xlabel("CH1 PD direct (mV)"); ax_xy.set_ylabel("CH2 DAC out (mV)")
        ax_xy.grid(alpha=0.3)
        ax_xy.scatter(v1s, v2s, s=6, c=ts, cmap="viridis")
        if len(ts) > 10 and (max(v1s) - min(v1s)) > 1e-6:
            k, b0 = np.polyfit(v1s, v2s, 1)
            xs = np.linspace(min(v1s), max(v1s), 10)
            ax_xy.plot(xs, k * xs + b0, "r-", lw=1.5)
            ax_xy.text(0.03, 0.95, f"slope = {k:.3f}\nintercept = {b0:.1f} mV\nn = {len(ts)}",
                       transform=ax_xy.transAxes, va="top", fontsize=11)
        fig.canvas.draw_idle()
    fig.canvas.flush_events()
    time.sleep(0.15)

scope.close()
plt.ioff()

with open("scope_monitor_log.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["t_s", "ch1_mV", "ch2_mV"])
    for row in zip(ts, v1s, v2s): w.writerow([f"{row[0]:.2f}", f"{row[1]:.3f}", f"{row[2]:.3f}"])

if len(ts) > 10:
    k, b0 = np.polyfit(v1s, v2s, 1)
    print(f"n={len(ts)}  slope={k:.4f}  intercept={b0:.2f} mV")
    print(f"CH1 range: {min(v1s):.1f}..{max(v1s):.1f} mV   CH2 range: {min(v2s):.1f}..{max(v2s):.1f} mV")
fig.savefig("scope_monitor_final.png", dpi=110)
print("saved scope_monitor_log.csv / scope_monitor_final.png")
