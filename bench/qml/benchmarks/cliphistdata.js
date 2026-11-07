.pragma library

// Deterministic, synthetic `cliphist list` lines: "<id>\t<preview>".
const words = ["hyprland", "quickshell", "material", "sidebar", "config", "commit", "install",
    "terminal", "wallpaper", "notification", "https://example.com/some/path", "const x = 42;",
    "sudo pacman -Syu", "git rebase --onto main", "Lorem", "ipsum", "dolor", "sit", "amet"];

function entries(count, offset) {
    const list = [];
    for (let i = 0; i < count; i++) {
        const id = count + offset - i;
        let text = "";
        for (let w = 0; w < 3 + (id % 9); w++)
            text += words[(id * 7 + w * 13) % words.length] + " ";
        list.push(`${id}\t${text.trim()}`);
    }
    return list;
}
