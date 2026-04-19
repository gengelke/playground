const page = document.body.dataset.page || "";

function selectedValues(select) {
  return Array.from(select.selectedOptions).map((option) => option.value).filter(Boolean);
}

function setAllSelected(select, selected) {
  for (const option of select.options) {
    option.selected = selected;
  }
}

function updateSelectAllState(select, checkbox) {
  if (!select || !checkbox) {
    return;
  }
  const options = Array.from(select.options);
  checkbox.checked = options.length > 0 && options.every((option) => option.selected);
}

function fitSelectToOptions(select) {
  if (!select) {
    return;
  }
  select.size = Math.max(1, select.options.length);
}

function textForCopy(element) {
  if (!element) {
    return "";
  }
  if ("value" in element) {
    return element.value;
  }
  return element.textContent || "";
}

async function copyText(text) {
  if (navigator.clipboard && window.isSecureContext) {
    await navigator.clipboard.writeText(text);
    return;
  }

  const fallback = document.createElement("textarea");
  fallback.value = text;
  fallback.setAttribute("readonly", "");
  fallback.style.position = "fixed";
  fallback.style.left = "-9999px";
  document.body.appendChild(fallback);
  fallback.select();
  document.execCommand("copy");
  fallback.remove();
}

function initCopyButtons() {
  for (const button of document.querySelectorAll("[data-copy-target]")) {
    button.addEventListener("click", async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      const originalText = button.textContent;
      try {
        await copyText(textForCopy(target));
        button.textContent = "Copied";
      } catch (error) {
        button.textContent = "Failed";
      } finally {
        window.setTimeout(() => {
          button.textContent = originalText;
        }, 1200);
      }
    });
  }
}

function shortHistoryTime(value) {
  if (!value) {
    return "";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }
  return date.toLocaleString("de-DE", {
    year: "2-digit",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
}

function paddedHistoryId(value) {
  return String(value).padStart(3, "0");
}

async function loadRetrievalProfiles() {
  const response = await fetch("/api/retrieval-profiles");
  const data = await response.json();
  const profiles = data.profiles || [];
  return {data, profiles};
}

async function fetchJsonWithTimeout(url, options = {}, timeoutMs = 180000) {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {...options, signal: controller.signal});
    const text = await response.text();
    let data;
    try {
      data = text ? JSON.parse(text) : {};
    } catch (_error) {
      data = {raw: text};
    }
    if (!response.ok) {
      throw new Error(`Request failed (${response.status}): ${JSON.stringify(data)}`);
    }
    return data;
  } catch (error) {
    if (error.name === "AbortError") {
      throw new Error(`Request timed out after ${Math.round(timeoutMs / 1000)} seconds.`);
    }
    throw error;
  } finally {
    window.clearTimeout(timer);
  }
}

async function loadHistory(limit = 50) {
  const response = await fetch(`/api/history?limit=${limit}`);
  if (!response.ok) {
    throw new Error(`History load failed (${response.status})`);
  }
  const data = await response.json();
  return data.items || [];
}

async function initChatPage() {
  const form = document.getElementById("chat-form");
  if (!form) {
    return;
  }

  const message = document.getElementById("message");
  const send = document.getElementById("send");
  const answer = document.getElementById("answer");
  const metadata = document.getElementById("metadata");
  const useRag = document.getElementById("use-rag");
  const useLocalFiles = document.getElementById("use-local-files");
  const useWeb = document.getElementById("use-web");
  const retrievalProfile = document.getElementById("retrieval-profile");
  const compareProfiles = document.getElementById("compare-profiles");
  const compareMode = document.getElementById("compare-mode");
  const compareSelectAll = document.getElementById("compare-select-all");
  const retrievalProfileBlock = document.getElementById("retrieval-profile-block");
  const compareProfilesBlock = document.getElementById("compare-profiles-block");
  const providerBlock = document.getElementById("provider-block");
  const modelBlock = document.getElementById("model-block");
  const modeBlock = document.getElementById("mode-block");
  const historyList = document.getElementById("history-list");
  const historyRefresh = document.getElementById("history-refresh");
  const historyUse = document.getElementById("history-use");
  const historyClear = document.getElementById("history-clear");
  let historyItems = [];

  function setBlockState(element, {disabled = false, hidden = false} = {}) {
    if (!element) {
      return;
    }
    element.classList.toggle("is-disabled", disabled);
    element.classList.toggle("is-hidden", hidden);
  }

  function setDisabled(element, disabled) {
    if (!element) {
      return;
    }
    element.disabled = disabled;
  }

  function syncChatUiState() {
    const ragEnabled = useRag.checked;
    const localFilesEnabled = useLocalFiles.checked;
    const compareEnabled = compareMode.checked;

    if (localFilesEnabled) {
      useRag.checked = false;
      compareMode.checked = false;
    }

    if (compareEnabled) {
      useRag.checked = true;
      useLocalFiles.checked = false;
    }

    const ragActive = useRag.checked;
    const localFilesActive = useLocalFiles.checked;
    const compareActive = compareMode.checked;

    const showSingleProfile = ragActive && !compareActive;
    const showCompareProfiles = ragActive && compareActive;
    const allowWebSearch = !ragActive && !localFilesActive;

    setBlockState(retrievalProfileBlock, {hidden: !showSingleProfile});
    setBlockState(compareProfilesBlock, {hidden: !showCompareProfiles});

    setDisabled(retrievalProfile, !showSingleProfile);
    setDisabled(compareProfiles, !showCompareProfiles);
    setDisabled(compareSelectAll, !showCompareProfiles);
    setDisabled(useWeb, !allowWebSearch);

    if (!allowWebSearch) {
      useWeb.checked = false;
    }

    setBlockState(providerBlock, {disabled: false});
    setBlockState(modelBlock, {disabled: false});
    setBlockState(modeBlock, {disabled: false});
  }

  async function refreshHistory() {
    if (!historyList) {
      return;
    }
    historyList.innerHTML = "";
    historyList.append(new Option("Loading history...", ""));
    historyItems = await loadHistory(50);
    historyList.innerHTML = "";
    if (historyItems.length === 0) {
      historyList.append(new Option("No history yet.", ""));
      return;
    }
    const sortedItems = [...historyItems].sort((left, right) => Number(left.id) - Number(right.id));
    for (const item of sortedItems) {
      const label = `${paddedHistoryId(item.id)}: ${item.message}`;
      historyList.append(new Option(label, String(item.id)));
    }
  }

  try {
    const {data, profiles} = await loadRetrievalProfiles();
    retrievalProfile.innerHTML = "";
    compareProfiles.innerHTML = "";

    for (const profile of profiles) {
      const label = `${profile.name} (${profile.type})`;
      retrievalProfile.append(new Option(label, profile.name, false, profile.name === data.default_profile));
      compareProfiles.append(new Option(label, profile.name, false, true));
    }

    fitSelectToOptions(compareProfiles);
    updateSelectAllState(compareProfiles, compareSelectAll);
  } catch (error) {
    metadata.textContent = JSON.stringify({profile_load_error: String(error)}, null, 2);
  }

  compareSelectAll.addEventListener("change", () => {
    setAllSelected(compareProfiles, compareSelectAll.checked);
  });

  compareProfiles.addEventListener("change", () => {
    updateSelectAllState(compareProfiles, compareSelectAll);
  });

  useRag.addEventListener("change", () => {
    syncChatUiState();
  });

  useLocalFiles.addEventListener("change", () => {
    syncChatUiState();
  });

  compareMode.addEventListener("change", () => {
    syncChatUiState();
  });

  function useSelectedHistoryQuestion() {
    const selected = historyItems.find((item) => String(item.id) === historyList.value);
    if (!selected) {
      return;
    }
    message.value = selected.message;
    message.focus();
  }

  message.addEventListener("keydown", (event) => {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      form.requestSubmit();
    }
  });

  historyRefresh.addEventListener("click", async () => {
    try {
      await refreshHistory();
    } catch (error) {
      metadata.textContent = JSON.stringify({history_error: String(error)}, null, 2);
      historyList.innerHTML = "";
      historyList.append(new Option(`History unavailable: ${String(error)}`, ""));
    }
  });

  historyList.addEventListener("change", useSelectedHistoryQuestion);
  historyUse.addEventListener("click", useSelectedHistoryQuestion);

  historyClear.addEventListener("click", async () => {
    if (!window.confirm("Clear chat history?")) {
      return;
    }
    try {
      await fetch("/api/history", {method: "DELETE"});
      await refreshHistory();
    } catch (error) {
      metadata.textContent = JSON.stringify({history_error: String(error)}, null, 2);
    }
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    send.disabled = true;
    answer.textContent = "Running query...";
    metadata.textContent = "{}";

    const body = {
      message: message.value,
      provider: document.getElementById("provider").value || null,
      model: document.getElementById("model").value || null,
      retrieval_profile: retrievalProfile.value || null,
      use_rag: useRag.checked,
      rag_only: useRag.checked,
      use_local_files: useLocalFiles.checked,
      use_web_search: document.getElementById("use-web").checked,
      force_llm: document.getElementById("mode").value === "force_llm"
    };
    const commandToken = document.getElementById("command-token").value.trim();
    const headers = {"Content-Type": "application/json"};
    if (commandToken) {
      headers.Authorization = `Bearer ${commandToken}`;
    }

    try {
      const response = await fetch(compareMode.checked ? "/api/chat/compare" : "/api/chat", {
        method: "POST",
        headers,
        body: JSON.stringify(compareMode.checked ? {
          message: body.message,
          provider: body.provider,
          model: body.model,
          retrieval_profiles: selectedValues(compareProfiles).length > 0 ? selectedValues(compareProfiles) : [body.retrieval_profile],
          force_llm: body.force_llm
        } : body)
      });
      const data = await response.json();
      if (compareMode.checked) {
        answer.textContent = (data.results || []).map((item) => `# ${item.retrieval_profile}\n${item.answer || ""}`).join("\n\n");
      } else {
        answer.textContent = data.answer || "";
      }
      metadata.textContent = JSON.stringify({
        source: data.source,
        provider: data.provider,
        model: data.model,
        tool: data.tool,
        metadata: data.metadata,
        compare: data.results
      }, null, 2);
    } catch (error) {
      answer.textContent = String(error);
    } finally {
      send.disabled = false;
      refreshHistory().catch(() => {});
    }
  });

  syncChatUiState();
  refreshHistory().catch((error) => {
    if (historyList) {
      historyList.innerHTML = "";
      historyList.append(new Option(`History unavailable: ${String(error)}`, ""));
    }
  });
}

async function initIngestPage() {
  const ingestForm = document.getElementById("ingest-form");
  if (!ingestForm) {
    return;
  }

  const ingestProfiles = document.getElementById("ingest-profiles");
  const ingestSelectAll = document.getElementById("ingest-select-all");
  const ingestSend = document.getElementById("ingest-send");
  const ingestResult = document.getElementById("ingest-result");
  const ingestFiles = document.getElementById("ingest-files");

  try {
    const {data, profiles} = await loadRetrievalProfiles();
    ingestProfiles.innerHTML = "";

    for (const profile of profiles) {
      if (profile.type === "local_files") {
        continue;
      }
      const label = `${profile.name} (${profile.type})`;
      ingestProfiles.append(new Option(label, profile.name, false, true));
    }

    fitSelectToOptions(ingestProfiles);
    updateSelectAllState(ingestProfiles, ingestSelectAll);
  } catch (error) {
    ingestResult.textContent = JSON.stringify({profile_load_error: String(error)}, null, 2);
  }

  ingestSelectAll.addEventListener("change", () => {
    setAllSelected(ingestProfiles, ingestSelectAll.checked);
  });

  ingestProfiles.addEventListener("change", () => {
    updateSelectAllState(ingestProfiles, ingestSelectAll);
  });

  ingestForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    ingestSend.disabled = true;

    const paths = document.getElementById("ingest-paths").value
      .split(/\r?\n/)
      .map((path) => path.trim())
      .filter(Boolean);
    const reset = document.getElementById("ingest-reset").checked;
    const files = Array.from(ingestFiles.files || []);
    const profiles = selectedValues(ingestProfiles);
    const results = [];

    ingestResult.textContent = JSON.stringify({
      status: "starting",
      server_paths: paths,
      browser_files: files.map((file) => file.name),
      profiles,
      reset
    }, null, 2);

    try {
      if (paths.length > 0) {
        ingestResult.textContent = JSON.stringify({
          status: "ingesting server paths",
          server_paths: paths,
          browser_files: files.map((file) => file.name),
          profiles,
          reset,
          partial_results: results
        }, null, 2);

        const data = await fetchJsonWithTimeout("/api/ingest", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({paths, reset, profiles})
        });
        results.push({server_paths: data});
        ingestResult.textContent = JSON.stringify({
          status: files.length > 0 ? "server paths finished" : "completed",
          partial_results: results
        }, null, 2);
      }

      if (files.length > 0) {
        ingestResult.textContent = JSON.stringify({
          status: "uploading browser files",
          server_paths: paths,
          browser_files: files.map((file) => file.name),
          profiles,
          reset,
          partial_results: results
        }, null, 2);

        const formData = new FormData();
        for (const file of files) {
          formData.append("files", file);
        }
        formData.append("reset", paths.length > 0 ? "false" : String(reset));
        if (profiles.length > 0) {
          formData.append("profiles", profiles.join(","));
        }
        const data = await fetchJsonWithTimeout("/api/ingest/files", {
          method: "POST",
          body: formData
        });
        results.push({browser_files: data});
      }

      if (results.length === 0) {
        results.push({error: "Enter at least one server path or choose at least one browser file."});
      }

      ingestResult.textContent = JSON.stringify(
        results.length === 1 ? results[0] : {status: "completed", results},
        null,
        2
      );
    } catch (error) {
      ingestResult.textContent = JSON.stringify({
        status: "failed",
        error: String(error),
        partial_results: results
      }, null, 2);
    } finally {
      ingestSend.disabled = false;
    }
  });
}

if (page === "chat") {
  initChatPage();
} else if (page === "ingest") {
  initIngestPage();
}

initCopyButtons();
