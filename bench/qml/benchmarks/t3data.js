.pragma library

// Deterministic, synthetic T3 bridge messages (see scripts/t3/t3-sidebar-bridge.mjs for the real
// shape). Most real threads have null timestamps, so most of these do too.

function rng(seed) {
    let s = seed >>> 0;
    return () => {
        s = (Math.imul(s, 1664525) + 1013904223) >>> 0;
        return s / 4294967296;
    };
}

const statuses = ["ready", "ready", "ready", "ready", "working", "waiting", "approval", "input", "failed"];
const sections = ["settled", "settled", "settled", "active", "active", "snoozed", "pinned"];

function iso(rand) {
    return new Date(Date.UTC(2026, 10, 1) + Math.floor(rand() * 7 * 86400000)).toISOString();
}

function thread(i, rand, projects) {
    const timed = rand() < 0.3;
    const section = sections[Math.floor(rand() * sections.length)];
    return {
        id: `thread-${i}`,
        projectId: `project-${Math.floor(rand() * projects)}`,
        title: `Benchmark thread number ${i} with a realistic title length`,
        status: statuses[Math.floor(rand() * statuses.length)],
        section: section,
        branch: `feature/bench-${i}`,
        updatedAt: timed ? iso(rand) : null,
        latestRunCompletedAt: timed ? iso(rand) : null,
        lastVisitedAt: timed ? iso(rand) : null,
        pinOrderKey: section === "pinned" ? `a${i}` : null,
        activeOrderKey: section === "active" ? `a${i}` : null,
    };
}

function snapshot(machine, count, projects, seed) {
    const rand = rng(seed);
    const threads = [];
    for (let i = 0; i < count; i++)
        threads.push(thread(i, rand, projects));
    const projectList = [];
    for (let p = 0; p < projects; p++)
        projectList.push({ id: `project-${p}`, name: `Project ${p}`, root: `/home/bench/project-${p}` });
    return { type: "snapshot", machine: machine, threads: threads, projects: projectList };
}

function threadUpdate(machine, i, seed) {
    const msg = { type: "thread", machine: machine, thread: thread(i, rng(seed), 20) };
    msg.thread.status = seed % 2 ? "working" : "ready";
    return msg;
}
