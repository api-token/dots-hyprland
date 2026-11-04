#!/usr/bin/env node
// Bridges T3 Code's shell feed to the ii left sidebar as NDJSON on stdout.
// Plan and wire notes: docs/quickshell/t3-sidebar.md. Node >= 22 (built-in WebSocket).
//
// Output lines:
//   {"type":"state","online":bool,"error":null|"no-token"|"unauthorized"|"offline"|"protocol"|string,"environmentId"}
//   {"type":"snapshot","projects":[Project],"threads":[Thread]}   replaces everything
//   {"type":"projects","projects":[Project]}                       replaces projects only
//   {"type":"project","project":Project} | {"type":"thread","thread":Thread}
//   {"type":"removed","kind":"project"|"thread","id"}
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
const PROTOCOL = "2";
const PING_MS = 20_000;

// Exit quietly when the reader (Quickshell) goes away.
process.stdout.on("error", () => process.exit(0));
const emit = (obj) => process.stdout.write(JSON.stringify(obj) + "\n");
let lastState = "";
const state = (online, error = null, environmentId = null) => {
    const key = `${online}|${error}|${environmentId}`;
    if (key === lastState) return;
    lastState = key;
    emit({ type: "state", online, error, environmentId });
};

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

function readRuntime() {
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
    return rt;
}

function readToken() {
    try {
        return fs.readFileSync(tokenFile, "utf8").trim() || null;
    } catch {
        return null;
    }
}

function handleItem(item) {
    switch (item.kind) {
        case "snapshot": {
            const s = item.snapshot;
            const projects = (s.projects ?? []).map(project);
            // Project-metadata refreshes arrive as snapshots with no threads.
            if (item.resolvedRepositoryIdentityRoots && !s.threads?.length && !s.archivedThreads?.length)
                return emit({ type: "projects", projects });
            return emit({ type: "snapshot", projects, threads: (s.threads ?? []).filter(listed).map(thread) });
        }
        case "project.updated":
            return emit({ type: "project", project: project(item.project) });
        case "project.removed":
            return emit({ type: "removed", kind: "project", id: item.projectId });
        case "thread.updated":
            if (item.location === "active" && listed(item.thread))
                return emit({ type: "thread", thread: thread(item.thread) });
            return emit({ type: "removed", kind: "thread", id: item.thread.id });
        case "thread.removed":
            return emit({ type: "removed", kind: "thread", id: item.threadId });
        // "synchronized" and unknown kinds are ignored.
    }
}

async function connect() {
    const token = readToken();
    if (!token) return state(false, "no-token");
    const rt = readRuntime();
    if (!rt) return state(false, "offline");
    const origin = `http://${rt.host}:${rt.port}`;

    let environmentId = null;
    try {
        const env = await (await fetch(`${origin}/.well-known/t3/environment`)).json();
        environmentId = env.environmentId ?? null;
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
        });
        if (r.status === 401 || r.status === 403) return state(false, "unauthorized");
        if (!r.ok) return state(false, `ticket ${r.status}`);
        ticket = (await r.json()).ticket;
    } catch {
        return state(false, "offline");
    }

    const url = `ws://${rt.host}:${rt.port}/ws?orchestrationProtocol=${PROTOCOL}&wsTicket=${encodeURIComponent(ticket)}`;
    await new Promise((resolve) => {
        const ws = new WebSocket(url);
        const send = (m) => ws.readyState === WebSocket.OPEN && ws.send(JSON.stringify(m));
        let awaitingPong = false;
        const pinger = setInterval(() => {
            if (awaitingPong) return ws.close(4000, "pong timeout");
            awaitingPong = true;
            send({ _tag: "Ping" });
        }, PING_MS);

        ws.onopen = () =>
            send({ _tag: "Request", id: "1", tag: "orchestration.subscribeShell", payload: {}, headers: [] });
        ws.onmessage = (ev) => {
            let m;
            try {
                m = JSON.parse(typeof ev.data === "string" ? ev.data : Buffer.from(ev.data).toString());
            } catch {
                return;
            }
            switch (m._tag) {
                case "Pong":
                    awaitingPong = false;
                    return;
                case "Chunk":
                    // Ack first or the server stops sending.
                    send({ _tag: "Ack", requestId: m.requestId });
                    state(true, null, environmentId);
                    for (const v of m.values ?? []) handleItem(v);
                    return;
                case "Exit":
                case "Defect":
                    // The feed never ends on its own; treat it as a drop.
                    process.stderr.write(`t3-bridge: ${m._tag} ${JSON.stringify(m).slice(0, 500)}\n`);
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

let delay = 1000;
for (;;) {
    const before = Date.now();
    await connect();
    // A connection that lasted a while resets the backoff.
    delay = Date.now() - before > 30_000 ? 1000 : Math.min(delay * 2, 30_000);
    await new Promise((r) => setTimeout(r, delay));
}
