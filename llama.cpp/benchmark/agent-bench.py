#!/usr/bin/env python3
import argparse
import json
import pathlib
import random
import statistics
import subprocess
import sysconfig
import threading
import time
from urllib import request

DECODE_PROMPTS = [
    ("code_python", "Write a Python function that returns the n-th Fibonacci number using memoization. Include a docstring."),
    ("code_cpp", "Write a C++ template function `clamp(x, lo, hi)` that returns x clamped to [lo, hi]. No std::clamp."),
    ("explain_concept", "Explain how speculative decoding works in large language model inference, in three short paragraphs."),
    ("summarize", "Summarize in two sentences: The Industrial Revolution began in Britain in the late 18th century, transforming manufacturing through mechanization, steam power, and the factory system. It spread to continental Europe and North America during the 19th century."),
    ("qa_factual", "What are the four fundamental forces of physics?"),
    ("translation", "Translate to French: 'The quick brown fox jumps over the lazy dog.'"),
    ("creative_short", "Write a four-line poem about an old lighthouse."),
    ("stepwise_math", "Solve step by step: A train leaves station A at 60 km/h. Two hours later, a second train leaves the same station on the same track at 90 km/h. How long until the second train catches the first?"),
    ("refactor", "Refactor this function to be iterative and explain the change briefly:\n\ndef walk(node, out):\n    if node is None:\n        return out\n    walk(node.left, out)\n    out.append(node.value)\n    walk(node.right, out)\n    return out\n"),
]

TITLE_SYSTEM = "You name conversations so the user can find them later in a list of past sessions. Reply with a title of at most six words."


class VramSampler(threading.Thread):
    def __init__(self, pid, interval):
        super().__init__(daemon=True)
        self.pid, self.interval = pid, interval
        self.phase, self.peaks, self.stop = "idle", {}, threading.Event()

    def sample(self):
        total = subprocess.run(["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,noheader,nounits"],
                               capture_output=True, text=True).stdout.split(",")
        proc = None
        if self.pid:
            out = subprocess.run(["nvidia-smi", "--query-compute-apps=pid,used_gpu_memory", "--format=csv,noheader,nounits"],
                                 capture_output=True, text=True).stdout
            for line in out.splitlines():
                fields = [f.strip() for f in line.split(",")]
                if fields[0] == str(self.pid) and fields[1].isdigit():
                    proc = int(fields[1])
        return int(total[0]), int(total[1]), proc

    def run(self):
        while not self.stop.is_set():
            used, cap, proc = self.sample()
            peak = self.peaks.setdefault(self.phase, {"gpu_used_mib": 0, "process_mib": 0, "gpu_total_mib": cap})
            peak["gpu_used_mib"] = max(peak["gpu_used_mib"], used)
            peak["process_mib"] = max(peak["process_mib"], proc or 0)
            time.sleep(self.interval)


class Bench:
    def __init__(self, args):
        self.url, self.args = args.url.rstrip("/"), args
        fixture = json.loads(pathlib.Path(args.fixture).read_text())
        self.system, self.tools = fixture["system"], fixture["tools"]
        self.props = self.get("/props")
        self.n_ctx = self.props["default_generation_settings"]["n_ctx"]
        self.model = self.props.get("model_alias") or "local"
        self.chars_per_token = None
        self.files = self.corpus()

    def get(self, path):
        with request.urlopen(self.url + path, timeout=60) as r:
            return json.loads(r.read())

    def post(self, path, body):
        req = request.Request(self.url + path, data=json.dumps(body).encode(), method="POST",
                              headers={"Content-Type": "application/json"})
        with request.urlopen(req, timeout=1800) as r:
            return json.loads(r.read())

    def corpus(self):
        root = pathlib.Path(sysconfig.get_paths()["stdlib"])
        files = []
        for path in sorted(root.glob("*.py")):
            text = path.read_text(errors="replace")
            if len(text) > 20_000:
                files.append((path.name, text))
        sample = "".join(text for _, text in files[:4])[:200_000]
        self.chars_per_token = len(sample) / len(self.post("/tokenize", {"content": sample})["tokens"])
        return files

    def code(self, tokens, offset=0):
        chunks, budget, i = [], int(tokens * self.chars_per_token), offset
        while budget > 0:
            name, text = self.files[i % len(self.files)]
            piece = text[:budget]
            chunks.append(f"File: lib/{name}\n```python\n{piece}\n```\n")
            budget -= len(piece)
            i += 1
        return "".join(chunks), i

    def nonce_tools(self, nonce):
        tools = json.loads(json.dumps(self.tools))
        tools[0]["function"]["description"] = f"[{nonce}] " + tools[0]["function"]["description"]
        return tools

    def chat(self, messages, max_tokens, tools=None, **extra):
        body = {"model": self.model, "messages": messages, "max_tokens": max_tokens,
                "temperature": 0.0, "seed": 42, "stream": False, **extra}
        if tools:
            body["tools"] = tools
        t0 = time.perf_counter()
        response = self.post("/v1/chat/completions", body)
        wall = time.perf_counter() - t0
        t = response.get("timings") or {}
        return {"wall_s": round(wall, 3), "cache_n": t.get("cache_n", 0), "prompt_n": t.get("prompt_n", 0),
                "prompt_ms": round(t.get("prompt_ms", 0), 1), "predicted_n": t.get("predicted_n", 0),
                "predicted_ms": round(t.get("predicted_ms", 0), 1),
                "prompt_tps": round(t.get("prompt_per_second", 0), 1),
                "decode_tps": round(t.get("predicted_per_second", 0), 2),
                "draft_n": t.get("draft_n", 0), "draft_n_accepted": t.get("draft_n_accepted", 0)}

    def decode(self, sampler):
        sampler.phase = "decode"
        rows = []
        for name, prompt in DECODE_PROMPTS:
            runs = [self.chat([{"role": "user", "content": prompt}], self.args.n_predict)
                    for _ in range(self.args.repetitions)]
            draft_n = sum(r["draft_n"] for r in runs)
            row = {"name": name, "decode_tps": round(statistics.mean(r["decode_tps"] for r in runs), 2),
                   "predicted_n": sum(r["predicted_n"] for r in runs),
                   "predicted_ms": sum(r["predicted_ms"] for r in runs),
                   "accept_rate": round(sum(r["draft_n_accepted"] for r in runs) / draft_n, 3) if draft_n else None}
            rows.append(row)
            print(f"  decode {name:<16} {row['decode_tps']:7.2f} tok/s  accept={row['accept_rate']}")
        n = sum(r["predicted_n"] for r in rows)
        ms = sum(r["predicted_ms"] for r in rows)
        return {"prompts": rows, "decode_tps": round(n / (ms / 1000), 2)}

    def prefill(self, sampler):
        rows = []
        targets = [t for t in (8_000, 32_000, 64_000, 120_000, 200_000, 250_000) if t + 2_048 < self.n_ctx]
        for target in targets:
            sampler.phase = f"prefill_{target // 1000}k"
            body, _ = self.code(max(0, target - 8_600))
            messages = [{"role": "system", "content": self.system},
                        {"role": "user", "content": f"Review the following files for bugs.\n\n{body}"}]
            r = self.chat(messages, 64, tools=self.nonce_tools(random.getrandbits(64)))
            r["target"] = target
            rows.append(r)
            print(f"  prefill {r['prompt_n']:>7} tok  {r['prompt_tps']:8.1f} tok/s  ttft={r['prompt_ms'] / 1000:6.2f}s  "
                  f"decode@depth={r['decode_tps']:6.2f} tok/s")
        return rows

    def agent(self, sampler):
        args, out = self.args, {}
        tools = self.nonce_tools(random.getrandbits(64))
        task = "The test suite in lib/ is failing intermittently. Read the relevant files and find the cause."
        session = [{"role": "system", "content": self.system}, {"role": "user", "content": task}]

        sampler.phase = "agent_cold"
        out["cold"] = self.chat(session, 32, tools=tools)
        print(f"  agent cold start   prompt_n={out['cold']['prompt_n']:>6}  ttft={out['cold']['prompt_ms'] / 1000:.2f}s")

        sampler.phase = "agent_loop"
        steps, offset, step = [], 0, 0
        depth = out["cold"]["prompt_n"] + out["cold"]["cache_n"]
        while depth + args.step_tokens + 2_048 < min(args.agent_tokens, self.n_ctx):
            step += 1
            content, offset = self.code(args.step_tokens, offset)
            call = {"id": f"call_{step}", "type": "function",
                    "function": {"name": "read", "arguments": json.dumps({"path": f"lib/step_{step}.py"})}}
            session += [{"role": "assistant", "content": "", "reasoning_content": f"Step {step}: read the next file.",
                         "tool_calls": [call]},
                        {"role": "tool", "tool_call_id": call["id"], "content": content}]
            r = self.chat(session, 32, tools=tools)
            depth = r["prompt_n"] + r["cache_n"]
            r["depth"] = depth
            steps.append(r)
        out["steps"] = steps
        hit = sum(s["cache_n"] for s in steps) / max(1, sum(s["cache_n"] + s["prompt_n"] for s in steps))
        out["loop"] = {"steps": len(steps), "final_depth": depth, "cache_hit_ratio": round(hit, 4),
                       "mean_new_tokens": round(statistics.mean(s["prompt_n"] for s in steps), 1),
                       "mean_ttft_s": round(statistics.mean(s["prompt_ms"] for s in steps) / 1000, 3),
                       "max_ttft_s": round(max(s["prompt_ms"] for s in steps) / 1000, 3),
                       "mean_wall_s": round(statistics.mean(s["wall_s"] for s in steps), 3)}
        print(f"  agent loop         {json.dumps(out['loop'])}")

        def resume(label, messages):
            r = self.chat(messages, 32, tools=tools)
            out[label] = r
            print(f"  agent {label:<12} prompt_n={r['prompt_n']:>6} cache_n={r['cache_n']:>6} ttft={r['prompt_ms'] / 1000:.2f}s")

        sampler.phase = "agent_side"
        title = [{"role": "system", "content": TITLE_SYSTEM},
                 {"role": "user", "content": f"Here is the first message of the conversation:\n\n<message>\n{task}\n</message>"}]
        out["side_request"] = self.chat(title, 16, reasoning_effort="low")
        content, offset = self.code(500, offset)
        session += [{"role": "user", "content": f"Also check this file:\n{content}"}]
        resume("after_side", session)

        new_session = [{"role": "system", "content": self.system},
                       {"role": "user", "content": "Add type hints to lib/util.py and run the tests."}]
        resume("new_session", new_session)
        session += [{"role": "assistant", "content": "Checked.", "reasoning_content": "Done."},
                    {"role": "user", "content": "Continue."}]
        resume("switch_back", session)

        sampler.phase = "agent_miss"
        edited = json.loads(json.dumps(session))
        edited[3]["content"] = "# edited\n" + edited[3]["content"]
        resume("early_edit", edited)
        return out


def report(path, results_dir, arms):
    results_dir = pathlib.Path(results_dir)
    data = {arm: json.loads((results_dir / f"{arm}.json").read_text()) for arm in arms}
    first = data[arms[0]]

    def text(name):
        p = results_dir / name
        return p.read_text().strip() if p.exists() else "n/a"

    def setting(arm, key):
        p = results_dir / f"{arm}.env"
        for line in (p.read_text().splitlines() if p.exists() else []):
            if line.startswith(key + "="):
                return line.split("=", 1)[1]
        return "-"

    def row(label, fn, fmt="{}"):
        cells = []
        for arm in arms:
            try:
                value = fn(data[arm])
                cells.append(fmt.format(value) if value is not None else "-")
            except (KeyError, IndexError, StopIteration, TypeError, ZeroDivisionError):
                cells.append("-")
        return f"| {label} | " + " | ".join(cells) + " |"

    def prefill(target, key):
        return lambda d: next(r for r in d["prefill"] if r["target"] == target)[key]

    def peak(key, phases=None):
        return lambda d: max(v[key] for k, v in d["vram"].items() if phases is None or k.startswith(phases))

    def headroom(d):
        return min(v["gpu_total_mib"] - v["gpu_used_mib"] for v in d["vram"].values())

    agent = lambda key, field: (lambda d: d["agent"][key][field])
    secs = lambda key: (lambda d: d["agent"][key]["prompt_ms"] / 1000)
    head = "| Metric | " + " | ".join(f"`{a}`" for a in arms) + " |"
    sep = "| --- |" + " ---: |" * len(arms)
    targets = sorted({r["target"] for d in data.values() for r in d.get("prefill", [])})

    lines = [
        "# Coding-agent benchmark", "",
        f"- Timestamp (UTC): `{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}`",
        f"- GPU: `{text('gpu.txt')}`",
        f"- Image revision: `{text('image-revision.txt')}`",
        f"- Workload prefix: OpenCode system prompt + tool schemas (`benchmark/fixtures/opencode-prefix.json`)",
        f"- Agent session: {first['config']['step_tokens']}-token tool results appended until ~{first['config']['agent_tokens']} tokens",
        f"- Decode: {first['config']['repetitions']} x {len(DECODE_PROMPTS)} short chat prompts, {first['config']['n_predict']} tokens, temperature 0",
    ]
    notes = [(arm, text(f"{arm}.note")) for arm in arms if (results_dir / f"{arm}.note").exists()]
    if notes:
        lines += ["", "## Arms", ""] + [f"- `{arm}`: {note}" for arm, note in notes]
    lines += [
        "", "## Settings", "", head, sep,
        "| model file | " + " | ".join(f"`{pathlib.Path(data[a]['config'].get('model_path') or '-').name}`" for a in arms) + " |",
    ]
    for key in ("LLAMA_ARG_CTX_SIZE", "LLAMA_ARG_UBATCH", "LLAMA_ARG_N_PARALLEL", "LLAMA_ARG_CACHE_TYPE_K",
                "LLAMA_ARG_CACHE_TYPE_V", "LLAMA_ARG_CACHE_RAM", "LLAMA_ARG_SPEC_TYPE", "command"):
        lines.append(f"| `{key}` | " + " | ".join(f"`{setting(a, key)}`" for a in arms) + " |")
    lines += ["", "## Results", "", head, sep,
              row("Decode, short prompts (tok/s)", lambda d: d["decode"]["decode_tps"], "{:.2f}"),
              row("MTP draft acceptance", lambda d: (lambda p: sum(r["accept_rate"] for r in p) / len(p))(
                  [r for r in d["decode"]["prompts"] if r["accept_rate"] is not None]), "{:.3f}")]
    for t in targets:
        lines.append(row(f"Prefill {t // 1000}K cold (tok/s)", prefill(t, "prompt_tps"), "{:.0f}"))
    for t in targets:
        lines.append(row(f"Time to first token {t // 1000}K cold (s)", lambda d, t=t: prefill(t, "prompt_ms")(d) / 1000, "{:.2f}"))
    for t in targets:
        lines.append(row(f"Decode at {t // 1000}K depth (tok/s)", prefill(t, "decode_tps"), "{:.2f}"))
    lines += [
        row("Agent loop: steps", agent("loop", "steps")),
        row("Agent loop: cache hit ratio", agent("loop", "cache_hit_ratio"), "{:.3f}"),
        row("Agent loop: mean new tokens per step", agent("loop", "mean_new_tokens"), "{:.0f}"),
        row("Agent loop: mean prefill per step (s)", agent("loop", "mean_ttft_s"), "{:.2f}"),
        row("Agent loop: max prefill per step (s)", agent("loop", "max_ttft_s"), "{:.2f}"),
        row("Resume after title request: tokens re-processed", agent("after_side", "prompt_n")),
        row("Resume after title request: prefill (s)", secs("after_side"), "{:.2f}"),
        row("New session, shared prefix: tokens processed", agent("new_session", "prompt_n")),
        row("Switch back to first session: tokens re-processed", agent("switch_back", "prompt_n")),
        row("Switch back to first session: prefill (s)", secs("switch_back"), "{:.2f}"),
        row("Early-history edit (miss): tokens re-processed", agent("early_edit", "prompt_n")),
        row("Early-history edit (miss): prefill (s)", secs("early_edit"), "{:.2f}"),
        row("Idle process VRAM (MiB)", lambda d: d["vram"]["idle"]["process_mib"], "{:,}"),
        row("Peak process VRAM (MiB)", peak("process_mib"), "{:,}"),
        row("Peak GPU used incl. desktop (MiB)", peak("gpu_used_mib"), "{:,}"),
        row("Min free VRAM during run (MiB)", headroom, "{:,}"),
        "", "## Decode per prompt (tok/s)", "", head.replace("Metric", "Prompt"), sep,
    ]
    for name, _ in DECODE_PROMPTS:
        lines.append(row(f"`{name}`", lambda d, n=name: next(r for r in d["decode"]["prompts"] if r["name"] == n)["decode_tps"], "{:.2f}"))
    lines += ["", "## Notes", "",
              "- Prefill rows force a cache miss by changing the first tool description; decode at depth is measured on the same request.",
              "- Agent rows come from llama.cpp `timings`. Tokens re-processed is `prompt_n`; everything else was reused from the slot, a context checkpoint, or the host prompt cache.",
              "- VRAM is sampled every 0.25 s. GPU used includes the desktop, so free VRAM is what other applications have left.",
              "- Raw results and each arm's exact server environment are in `benchmark/results/`."]
    pathlib.Path(path).write_text("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8080")
    ap.add_argument("--out")
    ap.add_argument("--report")
    ap.add_argument("--results-dir")
    ap.add_argument("arms", nargs="*")
    ap.add_argument("--fixture", default=str(pathlib.Path(__file__).with_name("fixtures") / "opencode-prefix.json"))
    ap.add_argument("--pid", type=int, default=0)
    ap.add_argument("--scenarios", default="decode,prefill,agent")
    ap.add_argument("--repetitions", type=int, default=2)
    ap.add_argument("--n-predict", type=int, default=192)
    ap.add_argument("--step-tokens", type=int, default=3_000)
    ap.add_argument("--agent-tokens", type=int, default=65_536)
    ap.add_argument("--vram-interval", type=float, default=0.25)
    args = ap.parse_args()
    if args.report:
        report(args.report, args.results_dir, args.arms)
        return

    bench = Bench(args)
    sampler = VramSampler(args.pid, args.vram_interval)
    sampler.start()
    time.sleep(1)
    result = {"config": {"n_ctx": bench.n_ctx, "model": bench.model, "build": bench.props.get("build_info"),
                         "model_path": bench.props.get("model_path"), "chars_per_token": round(bench.chars_per_token, 3),
                         "repetitions": args.repetitions, "n_predict": args.n_predict,
                         "step_tokens": args.step_tokens, "agent_tokens": args.agent_tokens}}
    for name in args.scenarios.split(","):
        print(f"[{name}]")
        result[name] = getattr(bench, name)(sampler)
    sampler.stop.set()
    sampler.join()
    result["vram"] = sampler.peaks
    pathlib.Path(args.out).write_text(json.dumps(result, indent=2))
    print("vram:", json.dumps(sampler.peaks))


if __name__ == "__main__":
    main()
