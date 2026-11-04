#!/usr/bin/env node
// Bridges T3 Code's shell feed to the ii left sidebar as NDJSON on stdout.
// Plan and wire notes: docs/quickshell/t3-sidebar.md. Node >= 22 (built-in WebSocket).
//
// Connects to the local T3 server and to every remote in --remotes, each with its own reconnect loop.
// Every line carries "machine": "local" for this machine, or the remote's URL.
//   {"type":"state","machine","online":bool,"error":null|"no-token"|"unauthorized"|"offline"|"protocol"|string,"environmentId","label"}
//   {"type":"snapshot","machine","projects":[Project],"threads":[Thread]}   replaces that machine's data
//   {"type":"projects","machine","projects":[Project]}                       updates those projects only
//   {"type":"project","machine","project":Project} | {"type":"thread","machine","thread":Thread}
//   {"type":"removed","machine","kind":"project"|"thread","id"}
//
// The feed is T3's internal API and changes often, so read only the fields used below.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const home = os.homedir();
const arg = (name, fallback) => {
    const i = process.argv.indexOf(`--${name}`);
    return i > 0 ? process.argv[i + 1] : fallback;
};
const tokenFile = arg("token-file", path.join(home, ".config/illogical-impulse/t3-token"));
const runtimeFile = arg("runtime-file", path.join(home, ".t3/userdata/server-runtime.json"));
// JSON list of {"url": "http://host:3773", "tokenFile": "/path"}.
let remotes = [];
try {
    remotes = JSON.parse(arg("remotes", "[]"));
} catch {
    process.stderr.write("t3-bridge: --remotes is not valid JSON; ignoring it\n");
}
const PROTOCOL = "2";
const PING_MS = 20_000;

// Exit quietly when the reader (Quickshell) goes away.
process.stdout.on("error", () => process.exit(0));
const emit = (obj) => process.stdout.write(JSON.stringify(obj) + "\n");

const project = (p) => ({ id: p.id, name: p.title ?? p.name ?? "", root: p.workspaceRoot ?? null });

const listed = (t) =>
    !t.deletedAt && t.lineage?.relationshipToParent !== "subagent" && t.lineage?.sideChat !== true;

const WORKING = ["preparing", "queued", "starting", "running", "waiting"];
// Mirrors resolveSidebarThreadStatus in t3code/apps/web/src/components/Sidebar.logic.ts.
function status(t) {
    const req = t.pendingRuntimeRequest;
    if (req && req.blocking !== false) return req.kind === "user_input" ? "input" : "approval";
    if ((t.pendingGuestMessageCount ?? 0) > 0) return "request";
    if (WORKING.includes(t.activityRunStatus)) return t.blockedOnThreadWait ? "waiting" : "working";
    if (t.status === "failed") return t.lastErrorClass === "usage_limit" ? "limited" : "failed";
    return "ready";
}

function section(t) {
    if (t.snoozedUntil && Date.parse(t.snoozedUntil) > Date.now()) return "snoozed";
    if (t.settledAt) return "settled";
    if (t.pinnedAt) return "pinned";
    return "active";
}

const thread = (t) => ({
    id: t.id,
    projectId: t.projectId,
    title: t.title ?? "",
    status: status(t),
    section: section(t),
    branch: t.branch ?? null,
    updatedAt: t.updatedAt ?? null,
    lastVisitedAt: t.lastVisitedAt ?? null,
    latestRunCompletedAt: t.latestRunCompletedAt ?? null,
    pinOrderKey: t.pinOrderKey ?? null,
    activeOrderKey: t.activeOrderKey ?? null,
});

// The local origin comes from the desktop app's runtime file, so it follows port changes.
function localOrigin() {
    let rt;
    try {
        rt = JSON.parse(fs.readFileSync(runtimeFile, "utf8"));
    } catch {
        return null;
    }
    // A stale file outlives a crashed server; check the pid (EPERM still means it exists).
    try {
        if (rt.pid) process.kill(rt.pid, 0);
    } catch (e) {
        if (e.code === "ESRCH") return null;
    }
    return `http://${rt.host}:${rt.port}`;
}

function readToken(file) {
    try {
        return fs.readFileSync(file, "utf8").trim() || null;
    } catch {
        return null;
    }
}

function handleItem(machine, item) {
    const out = (obj) => emit({ machine, ...obj });
    switch (item.kind) {
        case "snapshot": {
            const s = item.snapshot;
            const projects = (s.projects ?? []).map(project);
            // Project-metadata refreshes arrive as snapshots with no threads.
            if (item.resolvedRepositoryIdentityRoots && !s.threads?.length && !s.archivedThreads?.length)
                return out({ type: "projects", projects });
            return out({ type: "snapshot", projects, threads: (s.threads ?? []).filter(listed).map(thread) });
        }
        case "project.updated":
            return out({ type: "project", project: project(item.project) });
        case "project.removed":
            return out({ type: "removed", kind: "project", id: item.projectId });
        case "thread.updated":
            if (item.location === "active" && listed(item.thread))
                return out({ type: "thread", thread: thread(item.thread) });
            return out({ type: "removed", kind: "thread", id: item.thread.id });
        case "thread.removed":
            return out({ type: "removed", kind: "thread", id: item.threadId });
        // "synchronized" and unknown kinds are ignored.
    }
}

// One connection attempt; resolves when it ends. `m` is {key, origin(), tokenFile, label, lastState}.
async function connect(m) {
    const state = (online, error = null) => {
        const key = `${online}|${error}|${m.environmentId}|${m.label}`;
        if (key === m.lastState) return;
        m.lastState = key;
        emit({ type: "state", machine: m.key, online, error, environmentId: m.environmentId, label: m.label });
    };

    const token = readToken(m.tokenFile);
    if (!token) return state(false, "no-token");
    const origin = m.origin();
    if (!origin) return state(false, "offline");

    try {
        const env = await (await fetch(`${origin}/.well-known/t3/environment`, { signal: AbortSignal.timeout(10_000) })).json();
        m.environmentId = env.environmentId ?? null;
        m.label = env.label || m.label;
        if (env.orchestrationProtocolVersion && String(env.orchestrationProtocolVersion) !== PROTOCOL)
            return state(false, "protocol");
    } catch {
        return state(false, "offline");
    }

    let ticket;
    try {
        const r = await fetch(`${origin}/api/auth/websocket-ticket`, {
            method: "POST",
            headers: { Authorization: `Bearer ${token}`, "x-t3-orchestration-protocol": PROTOCOL },
            signal: AbortSignal.timeout(10_000),
        });
        if (r.status === 401 || r.status === 403) return state(false, "unauthorized");
        if (!r.ok) return state(false, `ticket ${r.status}`);
        ticket = (await r.json()).ticket;
    } catch {
        return state(false, "offline");
    }

    const wsOrigin = origin.replace(/^http/, "ws");
    const url = `${wsOrigin}/ws?orchestrationProtocol=${PROTOCOL}&wsTicket=${encodeURIComponent(ticket)}`;
    await new Promise((resolve) => {
        const ws = new WebSocket(url);
        const send = (msg) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(msg));
        let awaitingPong = false;
        const pinger = setInterval(() => {
            if (awaitingPong) return ws.close(4000, "pong timeout");
            awaitingPong = true;
            send({ _tag: "Ping" });
        }, PING_MS);

        ws.onopen = () =>
            send({ _tag: "Request", id: "1", tag: "orchestration.subscribeShell", payload: {}, headers: [] });
        ws.onmessage = (ev) => {
            let msg;
            try {
                msg = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString());
            } catch {
                return;
            }
            switch (msg._tag) {
                case "Pong":
                    awaitingPong = false;
                    return;
                case "Chunk":
                    // Ack first or the server stops sending.
                    send({ _tag: "Ack", requestId: msg.requestId });
                    state(true);
                    for (const v of msg.values ?? []) handleItem(m.key, v);
                    return;
                case "Exit":
                case "Defect":
                    // The feed never ends on its own; treat it as a drop.
                    process.stderr.write(`t3-bridge: ${m.label}: ${msg._tag} ${JSON.stringify(msg).slice(0, 500)}\n`);
                    return ws.close();
            }
        };
        ws.onerror = () => {};
        ws.onclose = () => {
            clearInterval(pinger);
            resolve();
        };
    });
    state(false, "offline");
}

async function run(m) {
    let delay = 1000;
    for (;;) {
        const before = Date.now();
        await connect(m);
        // A connection that lasted a while resets the backoff.
        delay = Date.now() - before > 30_000 ? 1000 : Math.min(delay * 2, 30_000);
        await new Promise((r) => setTimeout(r, delay));
    }
}

const machines = [{ key: "local", origin: localOrigin, tokenFile, label: os.hostname() }];
for (const r of Array.isArray(remotes) ? remotes : []) {
    if (!r?.url || !r?.tokenFile) {
        process.stderr.write(`t3-bridge: remote needs url and tokenFile: ${JSON.stringify(r)}\n`);
        continue;
    }
    const origin = r.url.replace(/\/+$/, "");
    machines.push({ key: r.url, origin: () => origin, tokenFile: r.tokenFile, label: new URL(origin).hostname });
}
for (const m of machines) {
    m.environmentId = null;
    m.lastState = "";
    run(m);
}
