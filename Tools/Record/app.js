/**
 * Padawan Adventures audio recording UI.
 */
import { cleanup, encodeWav } from "./dsp.js";

const AUTOSAVE_KEY = "padawan-record-autosave";
const IDB_NAME = "padawan-record";
const IDB_VERSION = 1;
const IDB_STORE = "takes";

const NOISE_MS = 500;
/**
 * Pre-roll used to prepend silence (and place the key-down click mid-buffer).
 * Keep the ring for noise profiling only; assemble takes without pre-roll so
 * leading silence trim and press-click guards start at the hold edge.
 */
const PRE_ROLL_MS = 0;
/** Don't keep recording after release — that was capturing the Space key-up click. */
const POST_ROLL_MS = 0;
const MIN_HOLD_MS = 120;

const state = {
  rows: [],
  rowById: new Map(),
  visible: [],
  selectedId: null,
  recordingId: null,
  autosave: false,
  takes: new Map(), // id -> { wav: Blob, at: number, sampleRate: number }
  statuses: new Map(), // id -> { text, kind }
};

let audioCtx = null;
let mediaStream = null;
let workletNode = null;
/** In-flight ensureMic() so warm + record don't race two AudioContexts. */
let micReady = null;
let ring = null;
let ringWrite = 0;
let ringFilled = false;
let takeChunks = null;
let recording = false;
let pressStartedAt = 0;
let noiseSnapshot = null;
let preRollSnapshot = null;
let stopTimer = null;
let previewAudio = null;

const els = {
  tbody: document.getElementById("tbody"),
  autosave: document.getElementById("autosave"),
  filter: document.getElementById("filter"),
  unrecorded: document.getElementById("unrecorded"),
  micStatus: document.getElementById("mic-status"),
};

// ---------------------------------------------------------------------------
// IndexedDB
// ---------------------------------------------------------------------------

function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(IDB_STORE)) {
        db.createObjectStore(IDB_STORE, { keyPath: "id" });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function idbPutTake(take) {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readwrite");
    tx.objectStore(IDB_STORE).put(take);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function idbLoadAllTakes() {
  const db = await openDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(IDB_STORE, "readonly");
    const req = tx.objectStore(IDB_STORE).getAll();
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => reject(req.error);
  });
}

// ---------------------------------------------------------------------------
// Capture / ring buffer
// ---------------------------------------------------------------------------

function setMicStatus(text, dataState) {
  els.micStatus.textContent = text;
  els.micStatus.dataset.state = dataState;
}

async function ensureMic() {
  if (audioCtx && workletNode) return;
  if (micReady) {
    await micReady;
    return;
  }
  micReady = openMic();
  try {
    await micReady;
  } catch (err) {
    micReady = null;
    throw err;
  }
}

async function openMic() {
  setMicStatus("Mic: requesting…", "idle");
  const stream = await navigator.mediaDevices.getUserMedia({
    audio: {
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      channelCount: 1,
    },
  });
  // Keep the context in a local so a concurrent ensureMic cannot swap
  // audioCtx between addModule and AudioWorkletNode construction.
  const ctx = new AudioContext();
  const workletUrl = new URL("recorder-worklet.js", window.location.href).href;
  await ctx.audioWorklet.addModule(workletUrl);
  const source = ctx.createMediaStreamSource(stream);
  const node = new AudioWorkletNode(ctx, "recorder-processor");
  // Keep the graph alive without audible monitoring.
  const mute = ctx.createGain();
  mute.gain.value = 0;
  source.connect(node);
  node.connect(mute);
  mute.connect(ctx.destination);

  ring = new Float32Array(ctx.sampleRate);
  ringWrite = 0;
  ringFilled = false;

  node.port.onmessage = (ev) => {
    const chunk = ev.data;
    if (!(chunk instanceof Float32Array)) return;
    writeRing(chunk);
    if (recording && takeChunks) {
      takeChunks.push(chunk);
    }
  };

  mediaStream = stream;
  audioCtx = ctx;
  workletNode = node;
  setMicStatus("Mic: ready", "ready");
}

function writeRing(chunk) {
  if (!ring) return;
  for (let i = 0; i < chunk.length; i++) {
    ring[ringWrite] = chunk[i];
    ringWrite += 1;
    if (ringWrite >= ring.length) {
      ringWrite = 0;
      ringFilled = true;
    }
  }
}

function snapshotRing(ms) {
  const n = Math.min(ring.length, Math.round((audioCtx.sampleRate * ms) / 1000));
  const out = new Float32Array(n);
  if (!ringFilled && ringWrite < n) {
    out.set(ring.subarray(0, ringWrite), n - ringWrite);
    return out;
  }
  let start = ringWrite - n;
  if (start < 0) start += ring.length;
  const first = Math.min(n, ring.length - start);
  out.set(ring.subarray(start, start + first), 0);
  if (first < n) {
    out.set(ring.subarray(0, n - first), first);
  }
  return out;
}

function concatFloat32(arrays) {
  let total = 0;
  for (const a of arrays) total += a.length;
  const out = new Float32Array(total);
  let offset = 0;
  for (const a of arrays) {
    out.set(a, offset);
    offset += a.length;
  }
  return out;
}

async function startRecording(rowId) {
  // Abandon an in-flight post-roll so a new hold can start immediately.
  if (stopTimer) {
    clearTimeout(stopTimer);
    stopTimer = null;
    recording = false;
    takeChunks = null;
    state.recordingId = null;
  }
  if (recording) return;
  const row = state.rowById.get(rowId);
  if (!row) return;

  try {
    await ensureMic();
    if (audioCtx.state === "suspended") await audioCtx.resume();
  } catch (err) {
    setMicStatus(`Mic: ${err.message || err}`, "error");
    setStatus(rowId, `error: ${err.message || err}`, "error");
    return;
  }

  noiseSnapshot = snapshotRing(NOISE_MS);
  preRollSnapshot = PRE_ROLL_MS > 0 ? snapshotRing(PRE_ROLL_MS) : new Float32Array(0);
  takeChunks = [];
  recording = true;
  pressStartedAt = performance.now();
  state.recordingId = rowId;
  setMicStatus("Mic: recording", "recording");
  setStatus(rowId, "recording…", "busy");
  renderSelectionClasses();
}

function stopRecording() {
  // Already finishing, or not recording at all.
  if (!recording || stopTimer) return;
  const rowId = state.recordingId;
  const heldMs = performance.now() - pressStartedAt;
  const chunksRef = takeChunks;
  const noise = noiseSnapshot;
  const pre = preRollSnapshot;
  // Stop appending immediately so the Space/mouse release click isn't captured
  // in a post-roll window.
  recording = false;
  takeChunks = null;
  setMicStatus("Mic: ready", "ready");

  const finish = async () => {
    state.recordingId = null;
    renderSelectionClasses();
    stopTimer = null;

    if (!rowId) return;
    if (heldMs < MIN_HOLD_MS) {
      setStatus(rowId, "too short", "warn");
      return;
    }

    setStatus(rowId, "cleaning…", "busy");
    try {
      const parts = pre && pre.length ? [pre, ...chunksRef] : chunksRef;
      const assembled = concatFloat32(parts);
      const { samples, tooQuiet } = cleanup(assembled, noise, audioCtx.sampleRate);
      if (tooQuiet) {
        setStatus(rowId, "too quiet", "warn");
        return;
      }
      const wav = encodeWav(samples, audioCtx.sampleRate);
      const take = { id: rowId, wav, at: Date.now(), sampleRate: audioCtx.sampleRate };
      state.takes.set(rowId, take);
      await idbPutTake(take);
      updatePlayRecordingButtons();
      await playBlob(wav);
      if (state.autosave) {
        await saveTake(rowId);
      } else {
        setStatus(rowId, "ready to save", "ok");
      }
    } catch (err) {
      setStatus(rowId, `error: ${err.message || err}`, "error");
    }
  };

  if (POST_ROLL_MS > 0) {
    stopTimer = setTimeout(finish, POST_ROLL_MS);
  } else {
    stopTimer = setTimeout(finish, 0);
  }
}

function forceStopRecording() {
  if (!recording && !stopTimer) return;
  if (stopTimer) {
    clearTimeout(stopTimer);
    stopTimer = null;
  }
  recording = false;
  takeChunks = null;
  const rowId = state.recordingId;
  state.recordingId = null;
  setMicStatus(audioCtx ? "Mic: ready" : "Mic: not started", audioCtx ? "ready" : "idle");
  if (rowId) setStatus(rowId, "cancelled", "warn");
  renderSelectionClasses();
}

// ---------------------------------------------------------------------------
// Playback / save
// ---------------------------------------------------------------------------

async function playBlob(blob) {
  if (previewAudio) {
    previewAudio.pause();
    previewAudio.src = "";
    previewAudio = null;
  }
  const url = URL.createObjectURL(blob);
  previewAudio = new Audio(url);
  previewAudio.onended = () => {
    URL.revokeObjectURL(url);
    previewAudio = null;
  };
  try {
    await previewAudio.play();
  } catch (err) {
    URL.revokeObjectURL(url);
    throw err;
  }
}

async function playCurrentClip(rowId) {
  const row = state.rowById.get(rowId);
  if (!row || !row.exists) return;
  const res = await fetch(`/api/clip?id=${encodeURIComponent(rowId)}`);
  if (!res.ok) {
    setStatus(rowId, "error: clip missing", "error");
    return;
  }
  const blob = await res.blob();
  await playBlob(blob);
}

async function playTake(rowId) {
  const take = state.takes.get(rowId);
  if (!take) return;
  await playBlob(take.wav);
}

async function saveTake(rowId) {
  const take = state.takes.get(rowId);
  if (!take) {
    setStatus(rowId, "error: no recording", "error");
    return;
  }
  setStatus(rowId, "saving…", "busy");
  try {
    const res = await fetch(`/api/save?id=${encodeURIComponent(rowId)}`, {
      method: "POST",
      headers: { "Content-Type": "audio/wav" },
      body: take.wav,
    });
    const payload = await res.json();
    if (!res.ok || !payload.ok) {
      throw new Error(payload.error || `HTTP ${res.status}`);
    }
    const row = state.rowById.get(rowId);
    if (row) {
      row.exists = true;
      row.mtime = payload.mtime;
      row.size = payload.size;
    }
    setStatus(rowId, "saved", "ok");
    updateRowMeta(rowId);
    applyFilters();
  } catch (err) {
    setStatus(rowId, `error: ${err.message || err}`, "error");
  }
}

// ---------------------------------------------------------------------------
// UI rendering
// ---------------------------------------------------------------------------

function setStatus(rowId, text, kind) {
  state.statuses.set(rowId, { text, kind });
  const cell = document.querySelector(`tr[data-id="${cssEscape(rowId)}"] .status-cell`);
  if (cell) {
    cell.textContent = text;
    cell.dataset.kind = kind || "";
  }
}

function cssEscape(value) {
  if (window.CSS && CSS.escape) return CSS.escape(value);
  return String(value).replace(/"/g, '\\"');
}

function formatMtime(mtime) {
  if (!mtime) return "—";
  const d = new Date(mtime);
  if (Number.isNaN(d.getTime())) return mtime;
  return d.toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function applyFilters() {
  const q = els.filter.value.trim().toLowerCase();
  const unrecordedOnly = els.unrecorded.checked;
  const visible = [];
  for (const row of state.rows) {
    if (unrecordedOnly && row.exists) continue;
    if (q) {
      const hay = `${row.text} ${row.context} ${row.basename} ${row.group}`.toLowerCase();
      if (!hay.includes(q)) continue;
    }
    visible.push(row.id);
  }
  state.visible = visible;
  if (state.selectedId && !visible.includes(state.selectedId)) {
    state.selectedId = visible[0] || null;
  }
  if (!state.selectedId && visible.length) {
    state.selectedId = visible[0];
  }
  renderTable();
}

function renderTable() {
  const frag = document.createDocumentFragment();
  let lastGroup = null;
  const visibleSet = new Set(state.visible);

  for (const row of state.rows) {
    if (!visibleSet.has(row.id)) continue;
    if (row.group !== lastGroup) {
      lastGroup = row.group;
      const hr = document.createElement("tr");
      hr.className = "group-header";
      const td = document.createElement("td");
      td.colSpan = 8;
      td.textContent = row.group;
      hr.appendChild(td);
      frag.appendChild(hr);
    }

    const tr = document.createElement("tr");
    tr.className = "row";
    tr.dataset.id = row.id;
    if (row.id === state.selectedId) tr.classList.add("selected");
    if (row.id === state.recordingId) tr.classList.add("recording");

    tr.addEventListener("mousedown", () => {
      state.selectedId = row.id;
      renderSelectionClasses();
    });

    const status = state.statuses.get(row.id) || { text: "", kind: "" };

    tr.innerHTML = `
      <td class="text-cell"></td>
      <td class="context-cell"></td>
      <td class="current-cell"></td>
      <td class="mtime"></td>
      <td class="record-cell"></td>
      <td class="play-take-cell"></td>
      <td class="save-cell"></td>
      <td class="status-cell" data-kind="${status.kind}"></td>
    `;
    tr.querySelector(".text-cell").textContent = row.text;
    tr.querySelector(".context-cell").textContent = row.context;
    tr.querySelector(".mtime").textContent = formatMtime(row.mtime);
    tr.querySelector(".status-cell").textContent = status.text;

    const playCurrent = document.createElement("button");
    playCurrent.type = "button";
    playCurrent.textContent = "Play";
    playCurrent.disabled = !row.exists;
    playCurrent.addEventListener("click", (e) => {
      e.stopPropagation();
      state.selectedId = row.id;
      renderSelectionClasses();
      playCurrentClip(row.id).catch((err) =>
        setStatus(row.id, `error: ${err.message || err}`, "error")
      );
    });
    tr.querySelector(".current-cell").appendChild(playCurrent);

    const recordBtn = document.createElement("button");
    recordBtn.type = "button";
    recordBtn.className = "record";
    recordBtn.textContent = "Hold";
    recordBtn.addEventListener("pointerdown", async (e) => {
      e.preventDefault();
      e.stopPropagation();
      state.selectedId = row.id;
      renderSelectionClasses();
      recordBtn.classList.add("active");
      try {
        recordBtn.setPointerCapture(e.pointerId);
      } catch (_) {
        /* ignore */
      }
      await startRecording(row.id);
    });
    tr.querySelector(".record-cell").appendChild(recordBtn);

    const playTakeBtn = document.createElement("button");
    playTakeBtn.type = "button";
    playTakeBtn.textContent = "Play";
    playTakeBtn.disabled = !state.takes.has(row.id);
    playTakeBtn.className = "play-take-btn";
    playTakeBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      state.selectedId = row.id;
      renderSelectionClasses();
      playTake(row.id).catch((err) =>
        setStatus(row.id, `error: ${err.message || err}`, "error")
      );
    });
    tr.querySelector(".play-take-cell").appendChild(playTakeBtn);

    const saveBtn = document.createElement("button");
    saveBtn.type = "button";
    saveBtn.textContent = "Save";
    saveBtn.disabled = !state.takes.has(row.id);
    saveBtn.className = "save-btn";
    saveBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      state.selectedId = row.id;
      renderSelectionClasses();
      saveTake(row.id);
    });
    tr.querySelector(".save-cell").appendChild(saveBtn);

    frag.appendChild(tr);
  }

  els.tbody.replaceChildren(frag);
}

function renderSelectionClasses() {
  for (const tr of els.tbody.querySelectorAll("tr.row")) {
    const id = tr.dataset.id;
    tr.classList.toggle("selected", id === state.selectedId);
    tr.classList.toggle("recording", id === state.recordingId);
  }
}

function updatePlayRecordingButtons() {
  for (const tr of els.tbody.querySelectorAll("tr.row")) {
    const id = tr.dataset.id;
    const has = state.takes.has(id);
    const playBtn = tr.querySelector(".play-take-btn");
    const saveBtn = tr.querySelector(".save-btn");
    if (playBtn) playBtn.disabled = !has;
    if (saveBtn) saveBtn.disabled = !has;
  }
}

function updateRowMeta(rowId) {
  const row = state.rowById.get(rowId);
  if (!row) return;
  const tr = els.tbody.querySelector(`tr[data-id="${cssEscape(rowId)}"]`);
  if (!tr) return;
  const mtime = tr.querySelector(".mtime");
  if (mtime) mtime.textContent = formatMtime(row.mtime);
  const playCurrent = tr.querySelector(".current-cell button");
  if (playCurrent) playCurrent.disabled = !row.exists;
}

function moveSelection(delta) {
  if (!state.visible.length) return;
  const idx = state.visible.indexOf(state.selectedId);
  const next = Math.max(0, Math.min(state.visible.length - 1, (idx < 0 ? 0 : idx) + delta));
  state.selectedId = state.visible[next];
  renderSelectionClasses();
  const tr = els.tbody.querySelector(`tr[data-id="${cssEscape(state.selectedId)}"]`);
  if (tr) tr.scrollIntoView({ block: "nearest" });
}

function filterFocused() {
  return document.activeElement === els.filter;
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

function wireEvents() {
  els.autosave.checked = localStorage.getItem(AUTOSAVE_KEY) === "1";
  state.autosave = els.autosave.checked;
  els.autosave.addEventListener("change", () => {
    state.autosave = els.autosave.checked;
    localStorage.setItem(AUTOSAVE_KEY, state.autosave ? "1" : "0");
  });

  els.filter.addEventListener("input", applyFilters);
  els.unrecorded.addEventListener("change", applyFilters);

  window.addEventListener("pointerup", () => {
    const active = document.querySelector("button.record.active");
    if (active) active.classList.remove("active");
    if (recording) stopRecording();
  });
  window.addEventListener("pointercancel", () => {
    const active = document.querySelector("button.record.active");
    if (active) active.classList.remove("active");
    if (recording) stopRecording();
  });

  window.addEventListener("blur", forceStopRecording);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible") forceStopRecording();
  });

  document.addEventListener("keydown", (e) => {
    if (filterFocused()) return;

    if (e.code === "Space") {
      e.preventDefault();
      if (e.repeat) return;
      if (!state.selectedId) return;
      startRecording(state.selectedId);
      return;
    }

    if (e.code === "ArrowDown") {
      e.preventDefault();
      moveSelection(1);
      return;
    }
    if (e.code === "ArrowUp") {
      e.preventDefault();
      moveSelection(-1);
      return;
    }
    if (e.code === "Enter") {
      e.preventDefault();
      if (state.selectedId) {
        playCurrentClip(state.selectedId).catch((err) =>
          setStatus(state.selectedId, `error: ${err.message || err}`, "error")
        );
      }
      return;
    }
    if (e.code === "KeyB" && !e.metaKey && !e.ctrlKey && !e.altKey) {
      e.preventDefault();
      if (!state.selectedId) return;
      const id = state.selectedId;
      const play = state.takes.has(id) ? playTake(id) : playCurrentClip(id);
      play.catch((err) => setStatus(id, `error: ${err.message || err}`, "error"));
      return;
    }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "s") {
      e.preventDefault();
      if (state.selectedId) saveTake(state.selectedId);
    }
  });

  document.addEventListener("keyup", (e) => {
    if (filterFocused()) return;
    if (e.code === "Space") {
      e.preventDefault();
      if (recording) stopRecording();
    }
  });

  // Warm the mic on first gesture anywhere.
  const warm = () => {
    ensureMic().catch((err) => setMicStatus(`Mic: ${err.message || err}`, "error"));
    window.removeEventListener("pointerdown", warm);
    window.removeEventListener("keydown", warm);
  };
  window.addEventListener("pointerdown", warm);
  window.addEventListener("keydown", warm);
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

async function boot() {
  wireEvents();
  try {
    const takes = await idbLoadAllTakes();
    for (const take of takes) {
      state.takes.set(take.id, take);
    }
  } catch (err) {
    console.warn("IndexedDB load failed", err);
  }

  const res = await fetch("/api/rows");
  if (!res.ok) throw new Error(`failed to load rows: HTTP ${res.status}`);
  const payload = await res.json();
  state.rows = payload.rows || [];
  state.rowById = new Map(state.rows.map((r) => [r.id, r]));
  applyFilters();
}

boot().catch((err) => {
  setMicStatus(`Error: ${err.message || err}`, "error");
  console.error(err);
});
