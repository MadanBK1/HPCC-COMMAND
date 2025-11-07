
#!/usr/bin/env python3
"""
======================================================================
 GPU Auto-Allocator for Slurm (Interactive Session, All Partitions)
======================================================================

Priority rules:
- GPU order: H200 > A100 > V100
- Within each GPU type:
    → High priority: 4 GPUs, 8 hours
    → Normal: 5–8 GPUs, 4 hours
- A100 special case:
    → Submit BOTH:
        * Standard jobs (default account, 256GB)
        * Data-machine jobs (4 GPUs only, 300GB, also 8 hours)
======================================================================
"""

import os
import re
import sys
import time
import json
import subprocess
import select
from typing import Dict, Tuple, Optional

# --- Configuration ---
gpu_priority = ["h200", "a100", "v100"]  # no L40
min_gpus = 4
max_gpus = 8
cpus = 10
mem_default = "300GB"
mem_datamachine = "300GB"

time_normal = "4:00:00"
time_high = "4:00:00"  # 4 GPUs = high priority (8h)

DEFAULT_NOTIFY_NUMBER = "+12697799477"

# ---------------- Notification helpers ----------------
def notify_twilio(body: str) -> bool:
    sid = os.getenv("TWILIO_ACCOUNT_SID")
    tok = os.getenv("TWILIO_AUTH_TOKEN")
    from_num = os.getenv("TWILIO_FROM_NUMBER")
    to_num = os.getenv("NOTIFY_SMS_NUMBER", DEFAULT_NOTIFY_NUMBER)
    if not (sid and tok and from_num and to_num):
        return False
    try:
        subprocess.check_call([
            "curl", "-sS", "-X", "POST",
            f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json",
            "--data-urlencode", f"To={to_num}",
            "--data-urlencode", f"From={from_num}",
            "--data-urlencode", f"Body={body}",
            "-u", f"{sid}:{tok}"
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False

def notify_ntfy(body: str) -> bool:
    topic = os.getenv("NTFY_TOPIC")
    if not topic:
        return False
    try:
        url = f"https://ntfy.sh/{topic}"
        subprocess.check_call([
            "curl", "-sS", "-H", "Title: Slurm job is RUNNING",
            "-H", "Tags: rocket,white_check_mark,computer",
            "-d", body, url
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False

def notify_slack(body: str) -> bool:
    webhook = os.getenv("SLACK_WEBHOOK_URL")
    if not webhook:
        return False
    try:
        payload = json.dumps({"text": body})
        subprocess.check_call([
            "curl", "-sS", "-X", "POST", "-H", "Content-type: application/json",
            "--data", payload, webhook
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False

def notify_all(body: str) -> None:
    sent = notify_twilio(body) or notify_ntfy(body) or notify_slack(body)
    if sent:
        print("📣 Notification sent.")
    else:
        print("📣 Notification NOT sent (no channel configured).")

# ---------------- Slurm helpers ----------------
def check_gpus() -> Dict[str, list]:
    cmd = ["sinfo", "--Format=Partition,Gres,Nodes,CPUsState", "--noheader"]
    try:
        sinfo_out = subprocess.check_output(cmd, text=True)
    except subprocess.CalledProcessError:
        return {}

    available = {}
    for line in sinfo_out.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        partition, gres = parts[0], parts[1]
        matches = re.findall(r"gpu:([a-z0-9]+):(\d+)", gres)
        for gtype, gcount in matches:
            gcount = int(gcount)
            if gcount >= min_gpus:
                available.setdefault(gtype, []).append((partition, gcount))
    return available

def build_salloc_cmd(gtype: str, gcount: int, partition: Optional[str] = None,
                     account: Optional[str] = None, mem: Optional[str] = None,
                     timelimit: Optional[str] = None):
    if mem is None:
        mem = mem_default
    if timelimit is None:
        timelimit = time_normal
    cmd = [
        "salloc", "--no-shell", "-N", "1",
        f"--gres=gpu:{gtype}:{gcount}",
        f"--cpus-per-task={cpus}",
        f"--mem={mem}", f"--time={timelimit}"
    ]
    if partition:
        cmd.insert(1, f"--partition={partition}")
    if account:
        cmd.insert(1, f"--account={account}")
    return cmd

def submit_salloc(gtype: str, gcount: int, partition: str,
                  account: Optional[str] = None, mem: Optional[str] = None,
                  timelimit: Optional[str] = None):
    base_cmd = build_salloc_cmd(gtype, gcount, partition, account, mem, timelimit)
    proc = subprocess.Popen(base_cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    jobid = None
    for line in proc.stdout:
        print(line.strip())
        m = re.search(r"job (\d+)", line)
        if m:
            jobid = m.group(1)
            break
    return jobid, base_cmd, proc

def monitor_jobs(job_map: Dict[str, Tuple[str, int, list, subprocess.Popen]]):
    print(f"📡 Monitoring jobs: {', '.join(job_map.keys())}")

    poller = select.poll()
    for _, (_, _, _, proc) in job_map.items():
        poller.register(proc.stdout, select.POLLIN)

    while True:
        for fd, _ in poller.poll(100):  # 100 ms
            line = os.read(fd, 4096).decode(errors="ignore")
            sys.stdout.write(line); sys.stdout.flush()

            if "allocated" in line or "Nodes" in line:
                # Find winner jobid
                winner = None
                for jobid, (gtype, gcount, _, proc) in job_map.items():
                    if proc.stdout.fileno() == fd:
                        winner = jobid
                        break
                if winner:
                    print(f"\n✅ Job {winner} is RUNNING! Notifying & cancelling others...")
                    notify_all(f"Slurm job {winner} is RUNNING.")
                    for jid, (gt, gc, _, _) in list(job_map.items()):
                        if jid != winner:
                            subprocess.run(["scancel", jid])
                            print(f"❌ Cancelled job {jid} ({gt}, {gc} GPU)")
                    print("\n🔗 Starting interactive shell inside allocation...\n")
                    os.execvp("srun", ["srun", f"--jobid={winner}", "--pty", "bash"])
                    return

def main():
    print("🔍 Monitoring cluster for available GPUs...")
    while True:
        available = check_gpus()
        if available:
            job_map: Dict[str, Tuple[str, int, list, subprocess.Popen]] = {}
            for gtype in gpu_priority:
                if gtype in available:
                    for partition, gcount in available[gtype]:
                        # --- A100 special case ---
                        if gtype == "a100" and gcount >= 4:
                            # Data-machine (always 4 GPU, high priority, 8h)
                            print(f"→ Submitting 4 {gtype.upper()} GPU(s) on {partition} with account=data-machine (300GB, 8h).")
                            jobid_dm, cmd_dm, proc_dm = submit_salloc(
                                gtype, 4, partition, account="data-machine", mem=mem_datamachine, timelimit=time_high)
                            if jobid_dm:
                                job_map[jobid_dm] = (gtype, 4, cmd_dm, proc_dm)

                        # --- All GPU types (standard + A100 normal) ---
                        for req in range(min_gpus, max_gpus + 1):
                            if req <= gcount:
                                timelimit = time_high if req == 4 else time_normal
                                print(f"→ Submitting {req} {gtype.upper()} GPU(s) on {partition} ({'high-priority 8h' if req==4 else 'standard 4h'}).")
                                jobid, cmd, proc = submit_salloc(gtype, req, partition, mem=mem_default, timelimit=timelimit)
                                if jobid:
                                    job_map[jobid] = (gtype, req, cmd, proc)

            if job_map:
                monitor_jobs(job_map)
                return
        print("⏳ No suitable GPUs yet. Retrying in 60 sec...")
        time.sleep(60)

if __name__ == "__main__":
    main()
